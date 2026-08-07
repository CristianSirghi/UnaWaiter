#include "dataservice.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>

// No baked-in default endpoint on purpose: a hardcoded URL from one client's
// deployment would silently point every fresh install (any restaurant) at
// that client's backend until someone remembers to fill in Administrare. With
// `m_baseUrl` starting empty, buildUrl() returns an empty string and every
// call fails loudly via requestFailed("...", "Missing backend address.")
// until the server address is actually configured.
DataService::DataService(QObject *parent)
    : QObject(parent)
    , m_network(new QNetworkAccessManager(this))
    , m_pingTimer(new QTimer(this))
{
    // Ping periodic de conexiune, ca beculețul din TablesPage să reflecte
    // pierderea/revenirea legăturii chiar și când aplicația stă degeaba (fără
    // vreo cerere declanșată de chelner). Fiecare cerere reală actualizează la
    // rândul ei `online` prin parseReply, deci pierderea se vede și mai repede.
    m_pingTimer->setInterval(8000);
    connect(m_pingTimer, &QTimer::timeout, this, &DataService::sendPing);
    m_pingTimer->start();
}

namespace {
// Stalled request safety net so a dead connection can't hold `busy` forever.
constexpr int kRequestTimeoutMs = 15000;
}

QString DataService::baseUrl() const { return m_baseUrl; }

void DataService::setBaseUrl(const QString &baseUrl)
{
    const QString trimmed = baseUrl.trimmed();
    if (m_baseUrl == trimmed)
        return;
    m_baseUrl = trimmed;
    emit baseUrlChanged();
    // Adresa serverului tocmai s-a schimbat - verificăm imediat noua legătură.
    sendPing();
}

int DataService::restaurant() const { return m_restaurant; }

void DataService::setRestaurant(int restaurant)
{
    if (m_restaurant == restaurant)
        return;
    m_restaurant = restaurant;
    emit restaurantChanged();
}

QVariantList DataService::restaurants() const { return m_restaurants; }

bool DataService::online() const { return m_online; }

void DataService::setOnline(bool online)
{
    if (m_online == online)
        return;
    m_online = online;
    emit onlineChanged();
}

void DataService::checkConnection()
{
    sendPing();
}

// Sondă ușoară de conexiune: un GET la comanda "ping" (backend întoarce
// {"status":"ok"}). Actualizează DOAR `online`, în funcție de dacă am reușit
// să contactăm serverul - nu atinge busy și nu emite requestFailed, ca să nu
// polueze UI-ul cu erori la fiecare tick.
// Traduce codurile de eroare ale backendului în text pentru chelner.
//
// DOAR cele care privesc RESTAURANTUL. Codurile de logare
// (`invalid_credentials`, `pin_already_set`, `not_a_waiter`) și
// `registry_unavailable` sunt comparate ca ȘIRURI BRUTE în LoginPage și
// SelectRestaurantPage — traduse aici, comparațiile alea ar cădea tăcut și
// chelnerul ar primi mesajul greșit la PIN greșit. De aceea lista e scurtă și
// orice altceva trece nemodificat.
//
// Aici, și nu în pagini, pentru că un restaurant nepregătit poate lovi ORICE
// comandă — e verificat înainte de fiecare, în pâlnia comună din PHP.
QString DataService::friendlyBackendError(const QString &code)
{
    if (code == QLatin1String("restaurant_not_ready")) {
        // Se întâmplă la lansarea pe rând: primul restaurant e instalat,
        // celelalte încă nu. Înainte, chelnerul primea "ORA-06550 ... PLS-00201".
        return tr("UnaWaiter is not activated at this restaurant yet.");
    }
    if (code == QLatin1String("restaurant_unreachable")) {
        return tr("Can't reach this restaurant's system. Try again, or pick "
                  "another restaurant.");
    }
    if (code == QLatin1String("unknown_restaurant")) {
        return tr("This restaurant is no longer available. Pick another one in "
                  "Settings.");
    }
    if (code == QLatin1String("no_restaurant")) {
        return tr("No restaurant selected. Pick one in Settings.");
    }
    // --- Editarea meselor din aplicație (add_table / set_table_active) ---
    if (code == QLatin1String("not_allowed")) {
        return tr("You don't have permission to change tables.");
    }
    if (code == QLatin1String("invalid_table_no")) {
        return tr("The table number must be a whole number greater than zero.");
    }
    if (code == QLatin1String("unknown_zone")) {
        return tr("That zone no longer exists. Reload the tables and try again.");
    }
    if (code == QLatin1String("table_exists")) {
        // Numărul e unic pe TOT restaurantul, nu pe zonă - deci "n-o văd
        // nicăieri" înseamnă de obicei că e în altă zonă. Răspunsul lui Oracle
        // spune și care, dar aici nu mai avem obiectul, doar codul.
        return tr("A table with this number already exists at this restaurant. "
                  "Check the other zones too.");
    }
    if (code == QLatin1String("table_busy")) {
        return tr("This table has an open order. Close it first.");
    }
    if (code == QLatin1String("unknown_table")) {
        return tr("This table no longer exists.");
    }
    return code;
}

void DataService::sendPing()
{
    if (m_pinging)
        return;

    const QString url = buildUrl(QStringLiteral("ping"));
    if (url.isEmpty()) {
        setOnline(false);
        return;
    }

    m_pinging = true;
    QNetworkRequest request((QUrl(url)));
    request.setTransferTimeout(kRequestTimeoutMs);
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_pinging = false;
        setOnline(reply->error() == QNetworkReply::NoError);
    });
}
QVariantList DataService::waiters() const { return m_waiters; }
QVariantList DataService::categories() const { return m_categories; }
QVariantList DataService::menu() const { return m_menu; }
QVariantList DataService::paymentTypes() const { return m_paymentTypes; }
QVariantList DataService::tables() const { return m_tables; }
QVariantList DataService::openOrders() const { return m_openOrders; }
QVariantList DataService::tableOccupancy() const { return m_tableOccupancy; }
QVariantList DataService::waiterStats() const { return m_waiterStats; }
QVariantList DataService::paidOrders() const { return m_paidOrders; }
QVariantList DataService::orderLines() const { return m_orderLines; }
QString DataService::updateInfoUrl() const { return m_updateInfoUrl; }

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
        setOnline(false);
        emit requestFailed(command, reply->errorString());
        return QVariant();
    }

    // Am primit un răspuns HTTP de la server - suntem conectați, chiar dacă
    // corpul se dovedește mai jos a fi un {"error":...} de la backend.
    setOnline(true);

    const QByteArray body = reply->readAll();
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        emit requestFailed(command,
                           tr("Invalid response from server: %1").arg(parseError.errorString()));
        return QVariant();
    }

    const QVariant value = doc.toVariant();

    // Backend signals problems as {"error": "..."} rather than an HTTP error.
    if (value.type() == QVariant::Map) {
        const QVariantMap map = value.toMap();
        if (map.contains(QStringLiteral("error"))) {
            emit requestFailed(command,
                               friendlyBackendError(map.value(QStringLiteral("error")).toString()));
            return QVariant();
        }
    }

    *ok = true;
    return value;
}

void DataService::sendRequest(const QString &command,
                              bool post,
                              const QVariantMap &params,
                              QVariant::Type expected,
                              const QStringList &requiredKeys,
                              const std::function<void(const QVariant &)> &onResult)
{
    // Restaurantul se adaugă AICI, în pâlnia comună, nu în fiecare load*/
    // acțiune în parte: e singurul loc prin care trec toate comenzile, și GET,
    // și POST. Adăugat în fiecare metodă separat, ar fi fost o chestiune de
    // timp până când una nouă l-ar fi uitat - iar o comandă fără restaurant nu
    // dă eroare vizibilă la chelner, ci ajunge în restaurantul greșit.
    //
    // `get_restaurants` și `ping` sunt scutite: prima tocmai aduce lista din
    // care se alege restaurantul, a doua e doar sonda de conexiune.
    QVariantMap effectiveParams = params;
    const bool needsRestaurant = (command != QStringLiteral("get_restaurants")
                                  && command != QStringLiteral("ping"));
    if (needsRestaurant) {
        if (m_restaurant <= 0) {
            emit requestFailed(command, tr("No restaurant selected."));
            return;
        }
        effectiveParams.insert(QStringLiteral("restaurant"), m_restaurant);
    }

    // La POST parametrii merg în corp, deci URL-ul poartă doar comanda.
    const QString url = post ? buildUrl(command) : buildUrl(command, effectiveParams);
    if (url.isEmpty()) {
        emit requestFailed(command, tr("Missing backend address."));
        return;
    }

    QNetworkRequest request((QUrl(url)));
    request.setTransferTimeout(kRequestTimeoutMs);

    QNetworkReply *reply = nullptr;
    if (post) {
        QUrlQuery body;
        const auto keys = effectiveParams.keys();
        for (const QString &key : keys)
            body.addQueryItem(key, effectiveParams.value(key).toString());

        request.setHeader(QNetworkRequest::ContentTypeHeader,
                          QStringLiteral("application/x-www-form-urlencoded"));
        reply = m_network->post(request, body.toString(QUrl::FullyEncoded).toUtf8());
    } else {
        reply = m_network->get(request);
    }

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, command, expected, requiredKeys, onResult]() {
        reply->deleteLater();

        bool ok = false;
        const QVariant value = parseReply(reply, command, &ok);
        if (!ok)
            return;

        if (value.type() != expected) {
            emit requestFailed(command, tr("Unexpected response shape from server."));
            return;
        }

        if (!requiredKeys.isEmpty()) {
            const QVariantMap obj = value.toMap();
            for (const QString &key : requiredKeys) {
                if (!obj.contains(key) || obj.value(key).isNull()) {
                    emit requestFailed(command, tr("Incomplete response from server."));
                    return;
                }
            }
        }

        onResult(value);
    });
}

void DataService::getArray(const QString &command,
                           const QVariantMap &queryItems,
                           const std::function<void(const QVariantList &)> &onRows)
{
    sendRequest(command, false, queryItems, QVariant::List, QStringList(),
                [onRows](const QVariant &value) { onRows(value.toList()); });
}

void DataService::getObject(const QString &command,
                            const QVariantMap &queryItems,
                            const QStringList &requiredKeys,
                            const std::function<void(const QVariantMap &)> &onObject)
{
    sendRequest(command, false, queryItems, QVariant::Map, requiredKeys,
                [onObject](const QVariant &value) { onObject(value.toMap()); });
}

void DataService::postObject(const QString &command,
                             const QVariantMap &formFields,
                             const QStringList &requiredKeys,
                             const std::function<void(const QVariantMap &)> &onObject)
{
    sendRequest(command, true, formFields, QVariant::Map, requiredKeys,
                [onObject](const QVariant &value) { onObject(value.toMap()); });
}

void DataService::loadRestaurants()
{
    // Emitem NECONDIȚIONAT, ca toate celelalte setări din fișier: semnalul
    // înseamnă "a sosit răspunsul", nu "s-a schimbat valoarea". Paginile îl
    // folosesc ca să iasă din starea de încărcare, iar lista de restaurante e
    // aproape mereu identică de la o încărcare la alta - o comparație aici
    // lăsa ecranul blocat pe "Se încarcă…" la a doua intrare.
    getArray(QStringLiteral("get_restaurants"), QVariantMap(),
             [this](const QVariantList &rows) {
                 m_restaurants = rows;
                 emit restaurantsChanged();
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

void DataService::loadTableOccupancy()
{
    getArray(QStringLiteral("get_open_orders"), QVariantMap(),
             [this](const QVariantList &rows) { setTableOccupancy(rows); });
}

void DataService::loadWaiterStats(const QString &waiter)
{
    QVariantMap q;
    q.insert(QStringLiteral("waiter"), waiter.trimmed());
    getArray(QStringLiteral("get_waiter_stats"), q,
             [this](const QVariantList &rows) { setWaiterStats(rows); });
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

void DataService::loadUpdateInfo()
{
    getObject(QStringLiteral("get_update_info"), QVariantMap(),
              {QStringLiteral("url")},
              [this](const QVariantMap &obj) {
                  setUpdateInfoUrl(obj.value(QStringLiteral("url")).toString());
              });
}

void DataService::login(int oficiant, const QString &pin)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("oficiant"), oficiant);
    fields.insert(QStringLiteral("pin"), pin);

    // can_edit_tables NU e în requiredKeys, deși log_in îl trimite mereu de la
    // 2026-08-07: cerut obligatoriu, un APK nou pus peste un backend încă
    // neactualizat ar face logarea să eșueze cu totul. Așa, lipsa lui înseamnă
    // doar "fără drept" - butonul nu apare, restul aplicației merge.
    postObject(QStringLiteral("log_in"), fields,
               {QStringLiteral("oficiant"), QStringLiteral("name")},
               [this](const QVariantMap &obj) {
                   emit loggedIn(obj.value(QStringLiteral("oficiant")).toInt(),
                                 obj.value(QStringLiteral("name")).toString(),
                                 obj.value(QStringLiteral("can_edit_tables")).toInt() == 1);
               });
}

void DataService::setPin(int oficiant, const QString &pin)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("oficiant"), oficiant);
    fields.insert(QStringLiteral("pin"), pin);

    postObject(QStringLiteral("set_pin"), fields,
               {QStringLiteral("ok")},
               [this, oficiant](const QVariantMap &) {
                   emit pinSet(oficiant);
               });
}

void DataService::addTable(const QString &waiter, int tableNo, const QString &zone)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("waiter"), waiter);
    fields.insert(QStringLiteral("tableNo"), tableNo);
    fields.insert(QStringLiteral("zone"), zone);

    postObject(QStringLiteral("add_table"), fields,
               {QStringLiteral("ok")},
               [this, tableNo](const QVariantMap &obj) {
                   emit tableAdded(tableNo,
                                   obj.value(QStringLiteral("reactivated")).toInt() == 1);
               });
}

void DataService::setTableActive(const QString &waiter, int tableNo, bool active)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("waiter"), waiter);
    fields.insert(QStringLiteral("tableNo"), tableNo);
    // "1"/"0" ca text, nu bool: corpul POST se construiește cu
    // QVariant::toString(), iar un bool ar pleca drept "true"/"false" - text
    // nenumeric, pe care Oracle l-ar respinge abia la bind, cu o eroare din care
    // nu se înțelege nimic.
    fields.insert(QStringLiteral("active"),
                  active ? QStringLiteral("1") : QStringLiteral("0"));

    postObject(QStringLiteral("set_table_active"), fields,
               {QStringLiteral("ok")},
               [this, tableNo, active](const QVariantMap &) {
                   emit tableActiveSet(tableNo, active);
               });
}

void DataService::createOrder(const QString &waiter,
                              const QString &desk,
                              const QString &payType,
                              const QString &guestCount,
                              bool takeaway,
                              const QString &coment)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("waiter"), waiter);
    if (takeaway) {
        // Fără `desk` deloc: backend-ul îl ignoră oricum când takeaway=1, dar
        // trimițându-l am lăsa în trafic un număr de masă care nu înseamnă
        // nimic pentru comanda asta.
        fields.insert(QStringLiteral("takeaway"), QStringLiteral("1"));
    } else {
        fields.insert(QStringLiteral("desk"), desk);
    }
    if (!coment.trimmed().isEmpty())
        fields.insert(QStringLiteral("coment"), coment);
    if (!payType.trimmed().isEmpty())
        fields.insert(QStringLiteral("payType"), payType);
    if (!guestCount.trimmed().isEmpty())
        fields.insert(QStringLiteral("guestCount"), guestCount);

    postObject(QStringLiteral("create_order"), fields,
               {QStringLiteral("nrComand")},
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
               {QStringLiteral("nrComand"), QStringLiteral("lines")},
               [this](const QVariantMap &obj) {
                   emit orderLinesAdded(obj.value(QStringLiteral("nrComand")).toInt(),
                                        obj.value(QStringLiteral("lines")).toList());
               });
}

void DataService::updateOrderDesk(const QString &nrComand, const QString &desk, bool takeaway)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("nrComand"), nrComand);
    if (takeaway)
        fields.insert(QStringLiteral("takeaway"), QStringLiteral("1"));
    else
        fields.insert(QStringLiteral("desk"), desk);

    postObject(QStringLiteral("update_order_desk"), fields,
               {QStringLiteral("nrComand"), QStringLiteral("desk")},
               [this](const QVariantMap &obj) {
                   emit orderDeskUpdated(obj.value(QStringLiteral("nrComand")).toInt(),
                                        obj.value(QStringLiteral("desk")).toInt());
               });
}

void DataService::cancelOrder(const QString &nrComand)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("nrComand"), nrComand);

    postObject(QStringLiteral("cancel_order"), fields,
               {QStringLiteral("nrComand")},
               [this](const QVariantMap &obj) {
                   emit orderCancelled(obj.value(QStringLiteral("nrComand")).toInt());
               });
}

void DataService::payOrder(const QString &nrComand,
                           int payType,
                           double pay,
                           const QString &docFiscal,
                           const QString &oficiant,
                           double amount,
                           const QString &rrn)
{
    QVariantMap fields;
    fields.insert(QStringLiteral("nrComand"), nrComand);
    fields.insert(QStringLiteral("payType"), QString::number(payType));
    // La card suma merge în SUMA_TERMINAL pe partea Oracle, nu în PAY, deci
    // trimitem `pay` doar pentru numerar (unde e suma primită de la client).
    if (payType == 1)
        fields.insert(QStringLiteral("pay"), QString::number(pay, 'f', 2));
    // Se trimite pentru AMBELE metode: bonul are un total indiferent cum s-a
    // plătit, iar el trebuie să corespundă comenzii.
    if (amount > 0.0)
        fields.insert(QStringLiteral("amount"), QString::number(amount, 'f', 2));
    // Doar plata "RRN Manual" produce așa ceva; la celelalte rămâne gol și nu
    // se trimite, iar Oracle păstrează NULL.
    if (!rrn.isEmpty())
        fields.insert(QStringLiteral("rrn"), rrn);
    if (!docFiscal.isEmpty())
        fields.insert(QStringLiteral("docFiscal"), docFiscal);
    if (!oficiant.isEmpty())
        fields.insert(QStringLiteral("oficiant"), oficiant);

    postObject(QStringLiteral("pay_order"), fields,
               {QStringLiteral("nrComand"), QStringLiteral("payType")},
               [this](const QVariantMap &obj) {
                   emit orderPaid(obj.value(QStringLiteral("nrComand")).toInt(),
                                  obj.value(QStringLiteral("payType")).toInt());
               });
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

void DataService::setTableOccupancy(const QVariantList &rows)
{
    m_tableOccupancy = rows;
    emit tableOccupancyChanged();
}

void DataService::setWaiterStats(const QVariantList &rows)
{
    m_waiterStats = rows;
    emit waiterStatsChanged();
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

void DataService::setUpdateInfoUrl(const QString &url)
{
    // Unlike the other setters, this always emits (no equality guard): every
    // loadUpdateInfo() call should re-trigger UpdatePage's checkForUpdate()
    // chain, even when the URL happens to be unchanged from last time.
    m_updateInfoUrl = url;
    emit updateInfoUrlChanged();
}
