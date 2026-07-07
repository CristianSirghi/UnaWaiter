#include "printermanager.h"

#include <QAbstractSocket>
#include <QByteArray>
#include <QDebug>
#include <QFile>
#include <QHash>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QStringList>
#include <QTcpSocket>
#include <QTextStream>
#include <QTimer>
#include <QtGlobal>
#include <QVariantMap>

#if defined(Q_OS_ANDROID) || defined(Q_OS_LINUX)
#include <arpa/inet.h>
#include <cstring>
#include <errno.h>
#include <linux/neighbour.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

PrinterManager::PrinterManager(QObject *parent)
    : QObject(parent)
{
}

bool PrinterManager::scanning() const
{
    return m_scanning;
}

QVariantList PrinterManager::candidates() const
{
    return m_candidates;
}

int PrinterManager::scannedHosts() const
{
    return m_scannedHosts;
}

int PrinterManager::totalHosts() const
{
    return m_totalHosts;
}

int PrinterManager::progress() const
{
    return m_progress;
}

QString PrinterManager::scanNetwork() const
{
    return m_scanNetwork;
}

QString PrinterManager::lastError() const
{
    return m_lastError;
}

void PrinterManager::startScan()
{
    startScanOnPort(9100);
}

void PrinterManager::startScanOnPort(int port)
{
    if (port <= 0 || port > 65535) {
        setLastError(tr("Invalid printer port."));
        return;
    }

    if (m_scanning) {
        stopScan();
    }

    resetScanState();
    m_port = port;

    const NetworkRange range = currentNetworkRange();
    if (range.hosts.isEmpty()) {
        setLastError(tr("No local Wi-Fi network was found for scanning."));
        emit scanFinished();
        return;
    }

    m_hosts = range.hosts;
    m_totalHosts = m_hosts.size();
    setScanNetwork(range.label);
    updateProgress();
    setScanning(true);
    dispatchNextConnections();
}

void PrinterManager::stopScan()
{
    if (!m_scanning && m_activeSockets.isEmpty()) {
        return;
    }

    for (QTcpSocket *socket : m_activeSockets) {
        if (socket) {
            socket->abort();
            socket->deleteLater();
        }
    }

    m_activeSockets.clear();
    m_hosts.clear();
    m_nextHostIndex = 0;
    setScanning(false);
    emit scanFinished();
}

void PrinterManager::clearCandidates()
{
    if (m_candidates.isEmpty() && m_seenCandidateKeys.isEmpty()) {
        return;
    }

    m_candidates.clear();
    m_seenCandidateKeys.clear();
    emit candidatesChanged();
}

PrinterManager::NetworkRange PrinterManager::currentNetworkRange() const
{
    QNetworkAddressEntry selectedEntry;
    bool hasSelectedEntry = false;

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &networkInterface : interfaces) {
        const QNetworkInterface::InterfaceFlags flags = networkInterface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp)
                || !flags.testFlag(QNetworkInterface::IsRunning)
                || flags.testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }

        const QList<QNetworkAddressEntry> entries = networkInterface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries) {
            const QHostAddress ip = entry.ip();
            const quint32 ipv4 = ip.toIPv4Address();
            if (ip.protocol() != QAbstractSocket::IPv4Protocol
                    || ((ipv4 >> 24) & 0xFF) == 127) {
                continue;
            }

            if (!hasSelectedEntry || isPrivateIpv4(ipv4)) {
                selectedEntry = entry;
                hasSelectedEntry = true;
            }

            if (isPrivateIpv4(ipv4)) {
                break;
            }
        }

        if (hasSelectedEntry && isPrivateIpv4(selectedEntry.ip().toIPv4Address())) {
            break;
        }
    }

    NetworkRange range;
    if (!hasSelectedEntry) {
        return range;
    }

    const quint32 localIp = selectedEntry.ip().toIPv4Address();
    quint32 netmask = selectedEntry.netmask().toIPv4Address();
    int prefix = prefixLength(netmask);

    // Ținem prima versiune conservatoare: scanăm /24-ul local. Unele rețele
    // raportează o mască mai largă, iar scanarea a mii de host-uri de pe o
    // tabletă ar fi prea grea pentru funcția asta.
    if (prefix < 24 || prefix > 30) {
        netmask = 0xFFFFFF00u;
        prefix = 24;
    }

    const quint32 network = localIp & netmask;
    const quint32 broadcast = network | ~netmask;
    const quint32 firstHost = network + 1;
    const quint32 lastHost = broadcast - 1;

    range.label = QStringLiteral("%1/%2").arg(ipv4ToString(network), QString::number(prefix));
    for (quint32 address = firstHost; address <= lastHost; ++address) {
        if (address == localIp) {
            continue;
        }
        range.hosts.append(ipv4ToString(address));
    }

    return range;
}

void PrinterManager::resetScanState()
{
    for (QTcpSocket *socket : m_activeSockets) {
        if (socket) {
            socket->abort();
            socket->deleteLater();
        }
    }

    m_activeSockets.clear();
    m_hosts.clear();
    m_nextHostIndex = 0;
    m_scannedHosts = 0;
    m_totalHosts = 0;
    m_progress = 0;
    clearCandidates();
    setScanNetwork(QString());
    setLastError(QString());
    updateProgress();
}

void PrinterManager::setScanning(bool scanning)
{
    if (m_scanning == scanning) {
        return;
    }

    m_scanning = scanning;
    emit scanningChanged();
}

void PrinterManager::setScanNetwork(const QString &network)
{
    if (m_scanNetwork == network) {
        return;
    }

    m_scanNetwork = network;
    emit scanNetworkChanged();
}

void PrinterManager::setLastError(const QString &error)
{
    if (m_lastError == error) {
        return;
    }

    m_lastError = error;
    emit lastErrorChanged();
}

void PrinterManager::updateProgress()
{
    const int nextProgress = m_totalHosts > 0
        ? qBound(0, (m_scannedHosts * 100) / m_totalHosts, 100)
        : 0;

    if (m_progress == nextProgress) {
        emit progressChanged();
        return;
    }

    m_progress = nextProgress;
    emit progressChanged();
}

void PrinterManager::dispatchNextConnections()
{
    if (!m_scanning) {
        return;
    }

    while (m_activeSockets.size() < m_maxConcurrentSockets
           && m_nextHostIndex < m_hosts.size()) {
        const QString host = m_hosts.at(m_nextHostIndex++);
        QTcpSocket *socket = new QTcpSocket(this);
        socket->setProperty("scanHost", host);
        socket->setProperty("scanFinished", false);
        m_activeSockets.append(socket);

        connect(socket, &QTcpSocket::connected, this, [this, socket]() {
            finishSocket(socket, true);
        });

#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
        connect(socket, &QAbstractSocket::errorOccurred, this,
                [this, socket](QAbstractSocket::SocketError) {
            finishSocket(socket, false);
        });
#else
        connect(socket, QOverload<QAbstractSocket::SocketError>::of(&QAbstractSocket::error),
                this, [this, socket](QAbstractSocket::SocketError) {
            finishSocket(socket, false);
        });
#endif

        QTimer::singleShot(m_timeoutMs, socket, [this, socket]() {
            finishSocket(socket, false);
        });

        socket->connectToHost(host, m_port);
    }

    if (m_nextHostIndex >= m_hosts.size() && m_activeSockets.isEmpty()) {
        setScanning(false);
        emit scanFinished();
    }
}

void PrinterManager::finishSocket(QTcpSocket *socket, bool connected)
{
    if (!socket || socket->property("scanFinished").toBool()) {
        return;
    }

    socket->setProperty("scanFinished", true);
    const QString host = socket->property("scanHost").toString();
    m_activeSockets.removeAll(socket);

    if (connected) {
        addCandidate(host, m_port);
    }

    socket->abort();
    socket->deleteLater();

    ++m_scannedHosts;
    updateProgress();
    dispatchNextConnections();
}

void PrinterManager::addCandidate(const QString &ip, int port)
{
    const QString key = QStringLiteral("%1:%2").arg(ip, QString::number(port));
    if (m_seenCandidateKeys.contains(key)) {
        return;
    }

    m_seenCandidateKeys.insert(key);

    const QString mac = macAddressForIp(ip);
    const QString manufacturer = manufacturerForMac(mac);

    QVariantMap candidate;
    candidate.insert(QStringLiteral("ip"), ip);
    candidate.insert(QStringLiteral("port"), port);
    candidate.insert(QStringLiteral("protocol"), QStringLiteral("raw"));
    candidate.insert(QStringLiteral("displayName"),
                     manufacturer.isEmpty()
                         ? tr("Raw printer candidate %1:%2").arg(ip, QString::number(port))
                         : tr("%1 %2:%3").arg(manufacturer, ip, QString::number(port)));
    candidate.insert(QStringLiteral("confidence"), manufacturer.isEmpty()
                     ? QStringLiteral("medium")
                     : QStringLiteral("high"));
    candidate.insert(QStringLiteral("mac"), mac);
    candidate.insert(QStringLiteral("manufacturer"), manufacturer);

    m_candidates.append(candidate);
    emit candidatesChanged();
}

// --- Trimitere / test ---------------------------------------------------------

bool PrinterManager::printZpl(const QString &ip, int port, const QString &zplData)
{
    const QString host = ip.trimmed();
    if (host.isEmpty()) {
        qWarning() << "printZpl: IP address is empty";
        setLastError(tr("Printer IP address is not set."));
        return false;
    }
    if (zplData.isEmpty()) {
        qWarning() << "printZpl: ZPL data is empty";
        return false;
    }

    const int usePort = (port > 0 && port <= 65535) ? port : 9100;
    const QByteArray data = zplData.toUtf8();

    QTcpSocket socket;
    socket.setSocketOption(QAbstractSocket::LowDelayOption, 1);
    socket.connectToHost(host, usePort);
    if (!socket.waitForConnected(3000)) {
        qWarning() << "printZpl: could not connect to" << host << usePort
                   << socket.errorString();
        setLastError(tr("Could not connect to printer %1:%2.").arg(host, QString::number(usePort)));
        return false;
    }

    qint64 written = 0;
    while (written < data.size()) {
        const qint64 chunk = socket.write(data.constData() + written, data.size() - written);
        if (chunk <= 0) {
            qWarning() << "printZpl: socket write returned" << chunk << socket.errorString();
            setLastError(tr("Failed to send data to printer."));
            return false;
        }
        written += chunk;
    }

    while (socket.bytesToWrite() > 0) {
        if (!socket.waitForBytesWritten(3000)) {
            qWarning() << "printZpl: bytes not written, pending:" << socket.bytesToWrite()
                       << "error:" << socket.errorString();
            setLastError(tr("Failed to send data to printer."));
            return false;
        }
    }

    socket.disconnectFromHost();
    return true;
}

void PrinterManager::testConnection(const QString &ip, int port)
{
    const QString host = ip.trimmed();
    if (host.isEmpty()) {
        emit testResult(false, tr("IP address is empty."));
        return;
    }

    const int usePort = (port > 0 && port <= 65535) ? port : 9100;

    QTcpSocket socket;
    socket.connectToHost(host, usePort);
    const bool ok = socket.waitForConnected(3000);
    socket.disconnectFromHost();

    emit testResult(ok,
        ok ? tr("Printer connected successfully.")
           : tr("Could not connect to printer. Check IP and network."));
}

// --- MAC / producător (best-effort, doar pe Linux/Android) --------------------

QString PrinterManager::macAddressForIp(const QString &ip)
{
    const QString netlinkMac = macAddressFromNetlinkNeighbor(ip);
    if (!netlinkMac.isEmpty()) {
        return netlinkMac;
    }

    const QString arpMac = macAddressFromProcNetArp(ip);
    if (!arpMac.isEmpty()) {
        return arpMac;
    }

    return QString();
}

QString PrinterManager::macAddressFromNetlinkNeighbor(const QString &ip)
{
#if defined(Q_OS_ANDROID) || defined(Q_OS_LINUX)
    in_addr targetAddress;
    const QByteArray ipBytes = ip.toLatin1();
    if (::inet_pton(AF_INET, ipBytes.constData(), &targetAddress) != 1) {
        return QString();
    }

    const int socketFd = ::socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (socketFd < 0) {
        return QString();
    }

    timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 450000;
    ::setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    sockaddr_nl kernelAddress;
    memset(&kernelAddress, 0, sizeof(kernelAddress));
    kernelAddress.nl_family = AF_NETLINK;

    struct Request
    {
        nlmsghdr header;
        ndmsg neighbor;
    };

    Request request;
    memset(&request, 0, sizeof(request));
    request.header.nlmsg_len = NLMSG_LENGTH(sizeof(ndmsg));
    request.header.nlmsg_type = RTM_GETNEIGH;
    request.header.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    request.header.nlmsg_seq = 1;
    request.neighbor.ndm_family = AF_INET;

    const ssize_t sent = ::sendto(socketFd,
                                  &request,
                                  request.header.nlmsg_len,
                                  0,
                                  reinterpret_cast<sockaddr *>(&kernelAddress),
                                  sizeof(kernelAddress));
    if (sent < 0) {
        ::close(socketFd);
        return QString();
    }

    QString foundMac;
    char buffer[8192];
    bool done = false;

    while (!done) {
        const ssize_t received = ::recv(socketFd, buffer, sizeof(buffer), 0);
        if (received <= 0) {
            break;
        }

        int remaining = static_cast<int>(received);
        for (nlmsghdr *message = reinterpret_cast<nlmsghdr *>(buffer);
             NLMSG_OK(message, remaining);
             message = NLMSG_NEXT(message, remaining)) {
            if (message->nlmsg_type == NLMSG_DONE) {
                done = true;
                break;
            }
            if (message->nlmsg_type == NLMSG_ERROR) {
                done = true;
                break;
            }
            if (message->nlmsg_type != RTM_NEWNEIGH) {
                continue;
            }

            const ndmsg *neighbor = reinterpret_cast<ndmsg *>(NLMSG_DATA(message));
            if (neighbor->ndm_family != AF_INET) {
                continue;
            }

            QString mac;
            bool addressMatches = false;
            int payloadLength = message->nlmsg_len - NLMSG_LENGTH(sizeof(ndmsg));
            rtattr *firstAttribute = reinterpret_cast<rtattr *>(
                reinterpret_cast<char *>(const_cast<ndmsg *>(neighbor))
                + NLMSG_ALIGN(sizeof(ndmsg)));
            for (rtattr *attribute = firstAttribute;
                 RTA_OK(attribute, payloadLength);
                 attribute = RTA_NEXT(attribute, payloadLength)) {
                if (attribute->rta_type == NDA_DST
                        && RTA_PAYLOAD(attribute) >= static_cast<int>(sizeof(in_addr))) {
                    const in_addr *candidateAddress =
                        reinterpret_cast<const in_addr *>(RTA_DATA(attribute));
                    addressMatches = candidateAddress->s_addr == targetAddress.s_addr;
                } else if (attribute->rta_type == NDA_LLADDR
                           && RTA_PAYLOAD(attribute) >= 6) {
                    const unsigned char *bytes =
                        reinterpret_cast<const unsigned char *>(RTA_DATA(attribute));
                    QStringList parts;
                    for (int i = 0; i < 6; ++i) {
                        parts.append(QStringLiteral("%1")
                                         .arg(bytes[i], 2, 16, QLatin1Char('0'))
                                         .toUpper());
                    }
                    mac = parts.join(QLatin1Char(':'));
                }
            }

            if (addressMatches && !mac.isEmpty()) {
                foundMac = normalizeMacAddress(mac);
                done = true;
                break;
            }
        }
    }

    ::close(socketFd);
    return foundMac;
#else
    Q_UNUSED(ip)
    return QString();
#endif
}

QString PrinterManager::macAddressFromProcNetArp(const QString &ip)
{
    QFile arpFile(QStringLiteral("/proc/net/arp"));
    if (!arpFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    QTextStream stream(&arpFile);
    bool firstLine = true;
    while (!stream.atEnd()) {
        const QString line = stream.readLine().simplified();
        if (firstLine) {
            firstLine = false;
            continue;
        }

        const QStringList columns = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (columns.size() < 4 || columns.at(0) != ip) {
            continue;
        }

        const QString mac = normalizeMacAddress(columns.at(3));
        if (!mac.isEmpty() && mac != QStringLiteral("00:00:00:00:00:00")) {
            return mac;
        }
    }

    return QString();
}

QString PrinterManager::manufacturerForMac(const QString &mac)
{
    const QString normalizedMac = normalizeMacAddress(mac);
    if (normalizedMac.length() < 8) {
        return QString();
    }

    static const QHash<QString, QString> manufacturers = {
        { QStringLiteral("6C:C1:47"), QStringLiteral("Xiamen Hanin Electronic Technology Co., Ltd") },
        { QStringLiteral("C8:2B:96"), QStringLiteral("Espressif Inc.") },
        { QStringLiteral("BC:DD:C2"), QStringLiteral("Espressif Inc.") },
        { QStringLiteral("00:0C:42"), QStringLiteral("Routerboard.com") },
        { QStringLiteral("70:EE:50"), QStringLiteral("Netatmo") },
        { QStringLiteral("B0:60:88"), QStringLiteral("Intel Corporate") },
        { QStringLiteral("24:94:94"), QStringLiteral("Hong Kong Buffalo Lab Limited") },
        { QStringLiteral("C0:18:50"), QStringLiteral("Quanta Computer Inc.") },
        { QStringLiteral("90:E8:68"), QStringLiteral("AzureWave Technology Inc.") },
        { QStringLiteral("00:E0:4C"), QStringLiteral("REALTEK SEMICONDUCTOR CORP.") },
        { QStringLiteral("40:A2:DB"), QStringLiteral("Amazon Technologies Inc.") }
    };

    return manufacturers.value(normalizedMac.left(8), QString());
}

QString PrinterManager::normalizeMacAddress(const QString &mac)
{
    QString value = mac.trimmed().toUpper();
    value.replace(QLatin1Char('-'), QLatin1Char(':'));

    const QStringList parts = value.split(QLatin1Char(':'), Qt::SkipEmptyParts);
    if (parts.size() != 6) {
        return QString();
    }

    QStringList normalizedParts;
    for (const QString &part : parts) {
        if (part.isEmpty() || part.size() > 2) {
            return QString();
        }

        for (const QChar &character : part) {
            if (!character.isDigit()
                    && (character < QLatin1Char('A') || character > QLatin1Char('F'))) {
                return QString();
            }
        }

        normalizedParts.append(part.rightJustified(2, QLatin1Char('0')));
    }

    return normalizedParts.join(QLatin1Char(':'));
}

bool PrinterManager::isPrivateIpv4(quint32 address)
{
    const quint8 first = (address >> 24) & 0xFF;
    const quint8 second = (address >> 16) & 0xFF;

    return first == 10
        || (first == 172 && second >= 16 && second <= 31)
        || (first == 192 && second == 168);
}

int PrinterManager::prefixLength(quint32 netmask)
{
    int prefix = 0;
    bool foundZero = false;

    for (int bit = 31; bit >= 0; --bit) {
        const bool set = (netmask & (1u << bit)) != 0;
        if (set && foundZero) {
            return -1;
        }
        if (set) {
            ++prefix;
        } else {
            foundZero = true;
        }
    }

    return prefix;
}

QString PrinterManager::ipv4ToString(quint32 address)
{
    return QStringLiteral("%1.%2.%3.%4")
        .arg((address >> 24) & 0xFF)
        .arg((address >> 16) & 0xFF)
        .arg((address >> 8) & 0xFF)
        .arg(address & 0xFF);
}
