#include "dataservice.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

// No baked-in default endpoint on purpose: a hardcoded URL from one client's
// deployment would silently point every fresh install (any restaurant) at
// that client's backend until someone remembers to fill in Administrare. With
// `m_baseUrl` starting empty, buildUrl() returns an empty string and every
// call fails loudly via requestFailed("...", "Missing backend address.")
// until the server address is actually configured.
DataService::DataService(QObject *parent)
    : QObject(parent)
    , m_network(new QNetworkAccessManager(this))
{
}

QString DataService::baseUrl() const { return m_baseUrl; }

void DataService::setBaseUrl(const QString &baseUrl)
{
    const QString trimmed = baseUrl.trimmed();
    if (m_baseUrl == trimmed)
        return;
    m_baseUrl = trimmed;
    emit baseUrlChanged();
}

bool DataService::busy() const { return m_busy; }
QString DataService::lastError() const { return m_lastError; }
QVariantList DataService::waiters() const { return m_waiters; }
QVariantList DataService::categories() const { return m_categories; }
QVariantList DataService::menu() const { return m_menu; }
QVariantList DataService::paymentTypes() const { return m_paymentTypes; }
QVariantList DataService::tables() const { return m_tables; }
QVariantList DataService::openOrders() const { return m_openOrders; }
QVariantList DataService::paidOrders() const { return m_paidOrders; }
QVariantList DataService::orderLines() const { return m_orderLines; }

QString DataService::buildUrl(const QString &command, const QVariantMap &queryItems) const
{
    if (m_baseUrl.isEmpty())
        return QString();

    QUrl url(m_baseUrl);
    QUrlQuery query(url);
    query.removeAllQueryItems(QStringLiteral("cmd"));
    query.addQueryItem(QStringLiteral("cmd"), command);

    const auto keys = queryItems.keys();
    for (const QString &key : keys) {
        const QString value = queryItems.value(key).toString().trimmed();
        if (!value.isEmpty())
            query.addQueryItem(key, value);
    }

    url.setQuery(query);
    return url.toString();
}

QVariant DataService::parseReply(QNetworkReply *reply, const QString &command, bool *ok)
{
    *ok = false;

    if (reply->error() != QNetworkReply::NoError) {
        const QString err = reply->errorString();
        setLastError(err);
        emit requestFailed(command, err);
        return QVariant();
    }

    const QByteArray body = reply->readAll();
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        const QString err = tr("Invalid response from server: %1").arg(parseError.errorString());
        setLastError(err);
        emit requestFailed(command, err);
        return QVariant();
    }

    const QVariant value = doc.toVariant();

    // Backend signals problems as {"error": "..."} rather than an HTTP error.
    if (value.type() == QVariant::Map) {
        const QVariantMap map = value.toMap();
        if (map.contains(QStringLiteral("error"))) {
            const QString err = map.value(QStringLiteral("error")).toString();
            setLastError(err);
            emit requestFailed(command, err);
            return QVariant();
        }
    }

    *ok = true;
    return value;
}

void DataService::getArray(const QString &command,
                           const QVariantMap &queryItems,
                           const std::function<void(const QVariantList &)> &onRows)
{
    const QString url = buildUrl(command, queryItems);
    if (url.isEmpty()) {
        const QString err = tr("Missing backend address.");
        setLastError(err);
        emit requestFailed(command, err);
        return;
    }

    setBusy(true);
    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(url)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, command, onRows]() {
        reply->deleteLater();
        bool ok = false;
        const QVariant value = parseReply(reply, command, &ok);
        if (ok)
            onRows(value.toList());
        setBusy(false);
    });
}

void DataService::postObject(const QString &command,
                             const QVariantMap &formFields,
                             const std::function<void(const QVariantMap &)> &onObject)
{
    const QString url = buildUrl(command);
    if (url.isEmpty()) {
        const QString err = tr("Missing backend address.");
        setLastError(err);
        emit requestFailed(command, err);
        return;
    }

    QUrlQuery body;
    const auto keys = formFields.keys();
    for (const QString &key : keys)
        body.addQueryItem(key, formFields.value(key).toString());

    QNetworkRequest request((QUrl(url)));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));

    setBusy(true);
    const QByteArray payload = body.toString(QUrl::FullyEncoded).toUtf8();
    QNetworkReply *reply = m_network->post(request, payload);
    connect(reply, &QNetworkReply::finished, this, [this, reply, command, onObject]() {
        reply->deleteLater();
        bool ok = false;
        const QVariant value = parseReply(reply, command, &ok);
        if (ok)
            onObject(value.toMap());
        setBusy(false);
    });
}

void DataService::loadWaiters()
{
    getArray(QStringLiteral("get_waiters"), QVariantMap(),
             [this](const QVariantList &rows) { setWaiters(rows); });
}

void DataService::loadCategories()
{
    getArray(QStringLiteral("get_categories"), QVariantMap(),
             [this](const QVariantList &rows) { setCategories(rows); });
}

void DataService::loadMenu(int category)
{
    QVariantMap q;
    q.insert(QStringLiteral("category"), category);
    getArray(QStringLiteral("get_menu"), q,
             [this](const QVariantList &rows) { setMenu(rows); });
}

void DataService::loadPaymentTypes()
{
    getArray(QStringLiteral("get_payment_types"), QVariantMap(),
             [this](const QVariantList &rows) { setPaymentTypes(rows); });
}

void DataService::loadTables()
{
    getArray(QStringLiteral("get_tables"), QVariantMap(),
             [this](const QVariantList &rows) { setTables(rows); });
}

void DataService::loadOpenOrders(const QString &waiter)
{
    QVariantMap q;
    if (!waiter.trimmed().isEmpty())
        q.insert(QStringLiteral("waiter"), waiter.trimmed());
    getArray(QStringLiteral("get_open_orders"), q,
             [this](const QVariantList &rows) { setOpenOrders(rows); });
}

void DataService::loadPaidOrders(const QString &waiter)
{
    QVariantMap q;
    if (!waiter.trimmed().isEmpty())
        q.insert(QStringLiteral("waiter"), waiter.trimmed());
    getArray(QStringLiteral("get_paid_orders"), q,
             [this](const QVariantList &rows) { setPaidOrders(rows); });
}

void DataService::loadOrderLines(const QString &nrComand)
{
    QVariantMap q;
    q.insert(QStringLiteral("nrComand"), nrComand);
    getArray(QStringLiteral("get_order_lines"), q,
             [this](const QVariantList &rows) { setOrderLines(rows); });
}

void DataService::login(const QString &username, const QString &password)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("username"), username.trimmed());
    fields.insert(QStringLiteral("password"), password);

    postObject(QStringLiteral("log_in"), fields,
               [this](const QVariantMap &obj) {
                   emit loggedIn(obj.value(QStringLiteral("oficiant")).toInt(),
                                 obj.value(QStringLiteral("name")).toString(),
                                 obj.value(QStringLiteral("username")).toString());
               });
}

void DataService::createOrder(const QString &waiter,
                              const QString &desk,
                              const QString &payType,
                              const QString &guestCount)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("waiter"), waiter);
    fields.insert(QStringLiteral("desk"), desk);
    if (!payType.trimmed().isEmpty())
        fields.insert(QStringLiteral("payType"), payType);
    if (!guestCount.trimmed().isEmpty())
        fields.insert(QStringLiteral("guestCount"), guestCount);

    postObject(QStringLiteral("create_order"), fields,
               [this](const QVariantMap &obj) {
                   emit orderCreated(obj.value(QStringLiteral("nrComand")).toInt());
               });
}

void DataService::addOrderLines(const QString &nrComand, const QVariantList &lines)
{
    // The backend expects `lines` as a JSON array string in the POST body.
    const QByteArray linesJson =
        QJsonDocument(QJsonArray::fromVariantList(lines)).toJson(QJsonDocument::Compact);

    QVariantMap fields;
    fields.insert(QStringLiteral("nrComand"), nrComand);
    fields.insert(QStringLiteral("lines"), QString::fromUtf8(linesJson));

    postObject(QStringLiteral("add_order_lines"), fields,
               [this](const QVariantMap &obj) {
                   emit orderLinesAdded(obj.value(QStringLiteral("nrComand")).toInt(),
                                        obj.value(QStringLiteral("lines")).toList());
               });
}

void DataService::updateOrderDesk(const QString &nrComand, const QString &desk)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("nrComand"), nrComand);
    fields.insert(QStringLiteral("desk"), desk);

    postObject(QStringLiteral("update_order_desk"), fields,
               [this](const QVariantMap &obj) {
                   emit orderDeskUpdated(obj.value(QStringLiteral("nrComand")).toInt(),
                                        obj.value(QStringLiteral("desk")).toInt());
               });
}

void DataService::setBusy(bool busy)
{
    // Reference-count in-flight requests so overlapping calls don't clear
    // `busy` prematurely.
    if (busy) {
        ++m_pending;
    } else if (m_pending > 0) {
        --m_pending;
    }

    const bool newBusy = m_pending > 0;
    if (m_busy == newBusy)
        return;
    m_busy = newBusy;
    emit busyChanged();
}

void DataService::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void DataService::setWaiters(const QVariantList &rows)
{
    m_waiters = rows;
    emit waitersChanged();
}

void DataService::setCategories(const QVariantList &rows)
{
    m_categories = rows;
    emit categoriesChanged();
}

void DataService::setMenu(const QVariantList &rows)
{
    m_menu = rows;
    emit menuChanged();
}

void DataService::setPaymentTypes(const QVariantList &rows)
{
    m_paymentTypes = rows;
    emit paymentTypesChanged();
}

void DataService::setTables(const QVariantList &rows)
{
    m_tables = rows;
    emit tablesChanged();
}

void DataService::setOpenOrders(const QVariantList &rows)
{
    m_openOrders = rows;
    emit openOrdersChanged();
}

void DataService::setPaidOrders(const QVariantList &rows)
{
    m_paidOrders = rows;
    emit paidOrdersChanged();
}

void DataService::setOrderLines(const QVariantList &rows)
{
    m_orderLines = rows;
    emit orderLinesChanged();
}
