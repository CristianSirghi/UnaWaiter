#ifndef PRINTERMANAGER_H
#define PRINTERMANAGER_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVector>

class QTcpSocket;

// Gestionează imprimanta de rețea (LAN, raw TCP pe portul 9100):
//   - descoperirea imprimantelor din rețeaua locală (scanare paralelă),
//   - trimiterea unui bon ZPL la o imprimantă,
//   - testarea conexiunii.
// Partea de descoperire e portată din Una_Prod (PrinterDiscoveryManager) —
// cod deja verificat pe teren. Trimiterea/testul vin din SettingsManager.printWifi.
//
// Nimic din setările utilizatorului (IP/port) nu se ține aici — alea stau în
// QML (AppSettings) și se transmit ca argumente. Aici e doar logica de rețea.
class PrinterManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QVariantList candidates READ candidates NOTIFY candidatesChanged)
    Q_PROPERTY(int scannedHosts READ scannedHosts NOTIFY progressChanged)
    Q_PROPERTY(int totalHosts READ totalHosts NOTIFY progressChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString scanNetwork READ scanNetwork NOTIFY scanNetworkChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit PrinterManager(QObject *parent = nullptr);

    bool scanning() const;
    QVariantList candidates() const;
    int scannedHosts() const;
    int totalHosts() const;
    int progress() const;
    QString scanNetwork() const;
    QString lastError() const;

    // --- Descoperire ---
    Q_INVOKABLE void startScan();
    Q_INVOKABLE void startScanOnPort(int port);
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void clearCandidates();

    // --- Trimitere / test ---
    // Trimite textul ZPL la imprimantă. Blochează scurt (timeout intern), întoarce
    // true dacă tot conținutul a fost scris cu succes în socket.
    Q_INVOKABLE bool printZpl(const QString &ip, int port, const QString &zplData);
    // Verifică dacă se poate deschide o conexiune la imprimantă; rezultatul vine
    // prin semnalul testResult (ca să nu blocheze UI-ul cu un mesaj sincron).
    Q_INVOKABLE void testConnection(const QString &ip, int port);

signals:
    void scanningChanged();
    void candidatesChanged();
    void progressChanged();
    void scanNetworkChanged();
    void lastErrorChanged();
    void scanFinished();
    void testResult(bool success, const QString &message);

private:
    struct NetworkRange
    {
        QString label;
        QVector<QString> hosts;
    };

    NetworkRange currentNetworkRange() const;
    void resetScanState();
    void setScanning(bool scanning);
    void setScanNetwork(const QString &network);
    void setLastError(const QString &error);
    void updateProgress();
    void dispatchNextConnections();
    void finishSocket(QTcpSocket *socket, bool connected);
    void addCandidate(const QString &ip, int port);

    static QString macAddressForIp(const QString &ip);
    static QString macAddressFromNetlinkNeighbor(const QString &ip);
    static QString macAddressFromProcNetArp(const QString &ip);
    static QString manufacturerForMac(const QString &mac);
    static QString normalizeMacAddress(const QString &mac);
    static bool isPrivateIpv4(quint32 address);
    static int prefixLength(quint32 netmask);
    static QString ipv4ToString(quint32 address);

    bool m_scanning = false;
    QVariantList m_candidates;
    int m_scannedHosts = 0;
    int m_totalHosts = 0;
    int m_progress = 0;
    QString m_scanNetwork;
    QString m_lastError;

    int m_port = 9100;
    int m_nextHostIndex = 0;
    int m_maxConcurrentSockets = 32;
    int m_timeoutMs = 550;
    QVector<QString> m_hosts;
    QVector<QTcpSocket *> m_activeSockets;
    QSet<QString> m_seenCandidateKeys;
};

#endif // PRINTERMANAGER_H
