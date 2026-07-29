#ifndef DATASERVICE_H
#define DATASERVICE_H

#include <QObject>
#include <QVariant>
#include <QString>
#include <QStringList>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

// Generic HTTP bridge to the PHP/Oracle backend (foisor.php). Not tied to any
// one screen or client: it just exposes the backend commands as Q_INVOKABLE
// calls and the returned data as bindable properties. QML talks to this object
// (registered as "dataService"), never to the network directly.
class DataService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    // Conexiunea la backend (rezultatul fiecărei cereri + un ping periodic):
    // true = serverul răspunde, false = pierdută. Vezi beculețul din TablesPage.
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    //
    // (Nu există `busy` și `lastError`: au fost expuse, dar niciun ecran nu
    // le-a folosit vreodată. Fiecare pagină își ține propria stare de
    // încărcare, iar mesajul de eroare vine oricum prin requestFailed, care
    // spune ȘI la ce comandă se referă - un `lastError` global n-ar fi putut
    // face asta. Vezi istoricul git dacă e nevoie de ele înapoi.)
    Q_PROPERTY(QVariantList waiters READ waiters NOTIFY waitersChanged)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY categoriesChanged)
    Q_PROPERTY(QVariantList menu READ menu NOTIFY menuChanged)
    Q_PROPERTY(QVariantList paymentTypes READ paymentTypes NOTIFY paymentTypesChanged)
    Q_PROPERTY(QVariantList tables READ tables NOTIFY tablesChanged)
    Q_PROPERTY(QVariantList openOrders READ openOrders NOTIFY openOrdersChanged)
    // Occupation check for SelectTablePage (ALL waiters, not just the current
    // one) - kept separate from `openOrders` on purpose. TablesPage listens to
    // openOrdersChanged and rebuilds its ("Ale mele"/"Toate") list from
    // whatever it last holds, even while off-screen underneath OrderPage; if
    // SelectTablePage reused the same property for its unfiltered query, it
    // would clobber TablesPage's filtered data and flash the wrong list for a
    // moment when popping back.
    Q_PROPERTY(QVariantList tableOccupancy READ tableOccupancy NOTIFY tableOccupancyChanged)
    // Un singur rand: [{ DAY_COUNT, WEEK_COUNT, MONTH_COUNT }] - comenzi
    // achitate (state=3) ale chelnerului curent, pentru ProfilePage.
    Q_PROPERTY(QVariantList waiterStats READ waiterStats NOTIFY waiterStatsChanged)
    Q_PROPERTY(QVariantList paidOrders READ paidOrders NOTIFY paidOrdersChanged)
    Q_PROPERTY(QVariantList orderLines READ orderLines NOTIFY orderLinesChanged)
    // URL-ul catre version.json, pentru verificarea de actualizari (UpdateManager
    // in QML nu are voie sa vorbeasca direct la backend, ca orice alta cerere).
    Q_PROPERTY(QString updateInfoUrl READ updateInfoUrl NOTIFY updateInfoUrlChanged)

public:
    explicit DataService(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &baseUrl);
    bool online() const;
    QVariantList waiters() const;
    QVariantList categories() const;
    QVariantList menu() const;
    QVariantList paymentTypes() const;
    QVariantList tables() const;
    QVariantList openOrders() const;
    QVariantList tableOccupancy() const;
    QVariantList waiterStats() const;
    QVariantList paidOrders() const;
    QVariantList orderLines() const;
    QString updateInfoUrl() const;

    // Reads (GET) -> fill the matching property, emit its *Changed signal.
    Q_INVOKABLE void loadWaiters();
    Q_INVOKABLE void loadCategories();
    Q_INVOKABLE void loadMenu(int category);
    Q_INVOKABLE void loadPaymentTypes();
    Q_INVOKABLE void loadTables();
    Q_INVOKABLE void loadOpenOrders(const QString &waiter = QString());
    // Same backend command as loadOpenOrders, always unfiltered (all waiters) -
    // fills `tableOccupancy` instead of `openOrders`, so SelectTablePage's
    // "is this table taken" check never clobbers TablesPage's filtered list.
    Q_INVOKABLE void loadTableOccupancy();
    // Comenzi achitate azi/săptămâna asta/luna asta (get_waiter_stats) -
    // ProfilePage, "Mese servite".
    Q_INVOKABLE void loadWaiterStats(const QString &waiter);
    // Comenzile achitate (STATE=3) de azi - vezi get_paid_orders. Folosit de
    // AchitatePage, filtrat implicit pe chelnerul logat (waiterOficiant).
    Q_INVOKABLE void loadPaidOrders(const QString &waiter = QString());
    // Liniile reale ale unei comenzi deja trimise (get_order_lines) - sursa de
    // adevăr când OrderPage editează o comandă existentă, în loc de cache-ul
    // local OrdersStore (care poate fi depășit față de ce e cu-adevărat în
    // Oracle, ex. dacă o comandă a fost achitată direct din UAMenu).
    Q_INVOKABLE void loadOrderLines(const QString &nrComand);
    // URL-ul version.json curent (get_update_info) - vezi UpdatePage.qml.
    Q_INVOKABLE void loadUpdateInfo();

    // Verifică imediat conexiunea la server (ping) - folosit când chelnerul
    // deschide dialogul de stare a conexiunii, pentru feedback instant.
    Q_INVOKABLE void checkConnection();

    // Auth (POST): oficiant (POS operator code, chosen from the loadWaiters()
    // list) + 4-digit PIN. The backend accepts it only if the oficiant is in the
    // real waiter roster (VSLRPRM_CALCD_R_502) AND the PIN in uw_waiters matches.
    // On success emits loggedIn(oficiant, name); on bad credentials the failure
    // arrives via requestFailed("log_in", "invalid_credentials").
    Q_INVOKABLE void login(int oficiant, const QString &pin);

    // Self-enrollment (POST): a waiter with no PIN yet (has_pin=0 in loadWaiters)
    // sets one. On success emits pinSet(oficiant); on failure requestFailed(
    // "set_pin", <code>) where code is pin_already_set / not_a_waiter /
    // invalid_pin_format.
    Q_INVOKABLE void setPin(int oficiant, const QString &pin);

    // Writes (POST). Results come back through the signals below rather than a
    // property, since they're one-shot actions, not persistent state.
    // takeaway = comandă LA PACHET, fără masă (DESK NULL în Oracle). Steag
    // explicit, nu "desk gol": pe partea de PHP, empty() e adevărat și pentru 0,
    // și pentru "", deci un desk lipsă dintr-un bug ar fi creat tăcut o comandă
    // la pachet în loc să dea eroare. Când e true, `desk` nici nu se trimite.
    //
    // coment se scrie în TMDB_COMENZ.COMENT și se TIPĂREȘTE pe bon (verificat pe
    // bon real) - acolo punem "La pachet", ca să se distingă în UAMenu de o
    // vânzare obișnuită de la casă.
    Q_INVOKABLE void createOrder(const QString &waiter,
                                 const QString &desk,
                                 const QString &payType = QString(),
                                 const QString &guestCount = QString(),
                                 bool takeaway = false,
                                 const QString &coment = QString());
    Q_INVOKABLE void addOrderLines(const QString &nrComand,
                                   const QVariantList &lines);
    // Mută o comandă deja trimisă pe altă masă (DESK real în Oracle), nu doar
    // în cache-ul local - vezi update_order_desk. Backend-ul respinge mutarea
    // dacă masa țintă are deja altă comandă deschisă, sau dacă bonul comenzii
    // e deja printat la bucătărie (aceleași reguli ca UAMenu însuși).
    // takeaway = scoate comanda de la masă și o face "la pachet" (DESK NULL).
    // Oracle rescrie singur marcajul din COMENT în ambele sensuri - vezi
    // c_takeaway_mark din pachet.
    Q_INVOKABLE void updateOrderDesk(const QString &nrComand, const QString &desk,
                                     bool takeaway = false);
    // Anulează o comandă deja trimisă (STATE=4 în Oracle, prin
    // pg_mobile_web_waiter.cancel_order) - vezi comentariul din
    // OrderPage.deleteOrder() despre bug-ul comenzilor "orfane" (șterse doar
    // local, dar rămase deschise în Oracle). Backend-ul respinge anularea
    // dacă bonul e deja achitat (state=3).
    Q_INVOKABLE void cancelOrder(const QString &nrComand);

    // Închide comanda ca achitată în Oracle (STATE=3), prin
    // pg_mobile_web_waiter.pay_order. Se apelează DOAR după ce bonul fiscal a
    // fost emis pe terminalul SmartOne - bonul e artefactul legal, închiderea
    // comenzii e contabilitate internă care se poate relua în siguranță.
    // payType: 1 = Numerar (`pay` = suma primită), 2 = Card (`pay` ignorat).
    // Backendul e idempotent: o comandă deja achitată întoarce succes, nu
    // eroare, ca o reluare după o pică de rețea să nu blocheze chelnerul.
    Q_INVOKABLE void payOrder(const QString &nrComand,
                              int payType,
                              double pay,
                              const QString &docFiscal,
                              const QString &oficiant);

signals:
    void baseUrlChanged();
    void onlineChanged();
    void waitersChanged();
    void categoriesChanged();
    void menuChanged();
    void paymentTypesChanged();
    void tablesChanged();
    void openOrdersChanged();
    void tableOccupancyChanged();
    void waiterStatsChanged();
    void paidOrdersChanged();
    void orderLinesChanged();
    void updateInfoUrlChanged();

    // One-shot action results.
    void loggedIn(int oficiant, const QString &name);
    void pinSet(int oficiant);
    void orderCreated(int nrComand);
    void orderLinesAdded(int nrComand, const QVariantList &lines);
    void orderDeskUpdated(int nrComand, int desk);
    void orderCancelled(int nrComand);
    void orderPaid(int nrComand, int payType);
    // Fired whenever any command fails (network or backend "error" payload).
    void requestFailed(const QString &command, const QString &error);

private:
    QString buildUrl(const QString &command, const QVariantMap &queryItems = QVariantMap()) const;

    // Motorul comun al tuturor cererilor. Cele trei helper-e de mai jos erau
    // înainte trei copii aproape identice ale aceluiași cod (construire URL,
    // timeout, trimitere, parsare, verificare de formă, raportare de eroare) -
    // difereau doar prin GET vs POST și prin forma așteptată a răspunsului.
    //
    // `params` sunt itemi de query pentru GET și câmpuri de formular pentru
    // POST. `expected` e forma cerută (QVariant::List sau QVariant::Map): un
    // răspuns de altă formă e tratat ca eșec, nu interpretat pe ghicite.
    // `requiredKeys` (doar pentru obiecte) apără împotriva unui răspuns valid
    // dar incomplet, care altfel ar da tăcut zero pe câmpurile lipsă (ex.
    // nrComand=0): dacă vreo cheie lipsește sau e null, cererea eșuează.
    void sendRequest(const QString &command,
                     bool post,
                     const QVariantMap &params,
                     QVariant::Type expected,
                     const QStringList &requiredKeys,
                     const std::function<void(const QVariant &)> &onResult);

    // Cele trei forme concrete, păstrate ca nume proprii: la locul apelului
    // spun dintr-o privire ce se așteaptă înapoi.
    void getArray(const QString &command,
                  const QVariantMap &queryItems,
                  const std::function<void(const QVariantList &)> &onRows);
    void getObject(const QString &command,
                   const QVariantMap &queryItems,
                   const QStringList &requiredKeys,
                   const std::function<void(const QVariantMap &)> &onObject);
    void postObject(const QString &command,
                    const QVariantMap &formFields,
                    const QStringList &requiredKeys,
                    const std::function<void(const QVariantMap &)> &onObject);

    // Întoarce JSON-ul parsat la succes. La un payload {"error":...} de la
    // backend sau la o problemă de parsare, emite requestFailed și pune
    // *ok pe false.
    QVariant parseReply(QNetworkReply *reply, const QString &command, bool *ok);

    void setOnline(bool online);
    // Sondă de conexiune: GET la comanda "ping", actualizează DOAR `online`
    // (nu atinge busy, nu emite requestFailed). Rulează periodic (m_pingTimer)
    // și la schimbarea adresei serverului.
    void sendPing();
    void setWaiters(const QVariantList &rows);
    void setCategories(const QVariantList &rows);
    void setMenu(const QVariantList &rows);
    void setPaymentTypes(const QVariantList &rows);
    void setTables(const QVariantList &rows);
    void setOpenOrders(const QVariantList &rows);
    void setTableOccupancy(const QVariantList &rows);
    void setWaiterStats(const QVariantList &rows);
    void setPaidOrders(const QVariantList &rows);
    void setOrderLines(const QVariantList &rows);
    void setUpdateInfoUrl(const QString &url);

    QNetworkAccessManager *m_network = nullptr;
    QString m_baseUrl;
    QVariantList m_waiters;
    QVariantList m_categories;
    QVariantList m_menu;
    QVariantList m_paymentTypes;
    QVariantList m_tables;
    QVariantList m_openOrders;
    QVariantList m_tableOccupancy;
    QVariantList m_waiterStats;
    QVariantList m_paidOrders;
    QVariantList m_orderLines;
    QString m_updateInfoUrl;
    bool m_online = false;
    bool m_pinging = false; // evită ping-uri suprapuse pe o conexiune moartă
    QTimer *m_pingTimer = nullptr;
};

#endif // DATASERVICE_H
