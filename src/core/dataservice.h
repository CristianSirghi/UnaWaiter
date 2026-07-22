#ifndef DATASERVICE_H
#define DATASERVICE_H

#include <QObject>
#include <QVariant>
#include <QString>
#include <QStringList>

class QNetworkAccessManager;
class QNetworkReply;

// Generic HTTP bridge to the PHP/Oracle backend (foisor.php). Not tied to any
// one screen or client: it just exposes the backend commands as Q_INVOKABLE
// calls and the returned data as bindable properties. QML talks to this object
// (registered as "dataService"), never to the network directly.
class DataService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
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

public:
    explicit DataService(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &baseUrl);
    bool busy() const;
    QString lastError() const;
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

    // Auth (POST) against our own uw_waiters roster: username + 4-digit PIN,
    // each row linked to the real vms_univers waiter code (oficiant) used on
    // orders. On success emits loggedIn(oficiant, name, username); on bad
    // credentials the failure arrives via requestFailed("log_in", "invalid_credentials").
    Q_INVOKABLE void login(const QString &username, const QString &password);

    // Writes (POST). Results come back through the signals below rather than a
    // property, since they're one-shot actions, not persistent state.
    Q_INVOKABLE void createOrder(const QString &waiter,
                                 const QString &desk,
                                 const QString &payType = QString(),
                                 const QString &guestCount = QString());
    Q_INVOKABLE void addOrderLines(const QString &nrComand,
                                   const QVariantList &lines);
    // Mută o comandă deja trimisă pe altă masă (DESK real în Oracle), nu doar
    // în cache-ul local - vezi update_order_desk. Backend-ul respinge mutarea
    // dacă masa țintă are deja altă comandă deschisă, sau dacă bonul comenzii
    // e deja printat la bucătărie (aceleași reguli ca UAMenu însuși).
    Q_INVOKABLE void updateOrderDesk(const QString &nrComand, const QString &desk);
    // Actualizează numărul de clienți (barmen/PERSON) al unei comenzi deja
    // trimise - createOrder îl trimite doar o dată, la creare, prin
    // update_guest_count (nou, 2026-07-21).
    Q_INVOKABLE void updateGuestCount(const QString &nrComand, const QString &guestCount);
    // Anulează o comandă deja trimisă (STATE=4 în Oracle, prin
    // pg_mobile_web_waiter.cancel_order) - vezi comentariul din
    // OrderPage.deleteOrder() despre bug-ul comenzilor "orfane" (șterse doar
    // local, dar rămase deschise în Oracle). Backend-ul respinge anularea
    // dacă bonul e deja achitat (state=3).
    Q_INVOKABLE void cancelOrder(const QString &nrComand);

signals:
    void baseUrlChanged();
    void busyChanged();
    void lastErrorChanged();
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

    // One-shot action results.
    void loggedIn(int oficiant, const QString &name, const QString &username);
    void orderCreated(int nrComand);
    void orderLinesAdded(int nrComand, const QVariantList &lines);
    void orderDeskUpdated(int nrComand, int desk);
    void orderGuestCountUpdated(int nrComand, int guestCount);
    void orderCancelled(int nrComand);
    // Fired whenever any command fails (network or backend "error" payload).
    void requestFailed(const QString &command, const QString &error);

private:
    QString buildUrl(const QString &command, const QVariantMap &queryItems = QVariantMap()) const;

    // Fires a GET for `command`; on success parses a JSON array and hands it to
    // `onRows`. On any failure sets lastError and emits requestFailed.
    void getArray(const QString &command,
                  const QVariantMap &queryItems,
                  const std::function<void(const QVariantList &)> &onRows);

    // Fires a POST for `command` with form-encoded `formFields`; on success
    // parses a JSON object and hands it to `onObject`. `requiredKeys` guards
    // against a malformed-but-non-error response silently defaulting missing
    // fields to 0/empty (e.g. nrComand=0): if any key is absent or null,
    // the request is treated as failed instead of calling `onObject`.
    void postObject(const QString &command,
                    const QVariantMap &formFields,
                    const QStringList &requiredKeys,
                    const std::function<void(const QVariantMap &)> &onObject);

    // Returns the parsed JSON on success. On a backend {"error":...} payload or
    // a parse problem, returns false-ish: sets lastError, emits requestFailed,
    // and *ok is set to false.
    QVariant parseReply(QNetworkReply *reply, const QString &command, bool *ok);

    void setBusy(bool busy);
    void setLastError(const QString &error);
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

    QNetworkAccessManager *m_network = nullptr;
    QString m_baseUrl;
    bool m_busy = false;
    QString m_lastError;
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
    int m_pending = 0; // in-flight request count, drives `busy`
};

#endif // DATASERVICE_H
