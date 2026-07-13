#ifndef DATASERVICE_H
#define DATASERVICE_H

#include <QObject>
#include <QVariant>
#include <QString>

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

    // Reads (GET) -> fill the matching property, emit its *Changed signal.
    Q_INVOKABLE void loadWaiters();
    Q_INVOKABLE void loadCategories();
    Q_INVOKABLE void loadMenu(int category);
    Q_INVOKABLE void loadPaymentTypes();
    Q_INVOKABLE void loadTables();
    Q_INVOKABLE void loadOpenOrders(const QString &waiter = QString());

    // Auth (POST) against UAMenu's own TMS_CASIR login (USER_ID/USER_PASSWORD -
    // not a PIN). On success emits loggedIn(oficiant, name, username); on bad
    // credentials the failure arrives via requestFailed("log_in", "invalid_credentials")
    // or requestFailed("log_in", "no_oficiant_linked") if the account has no
    // vms_univers code linked yet (DEP column, set from UAMenu's Users screen).
    Q_INVOKABLE void login(const QString &username, const QString &password);

    // Writes (POST). Results come back through the signals below rather than a
    // property, since they're one-shot actions, not persistent state.
    Q_INVOKABLE void createOrder(const QString &waiter,
                                 const QString &desk,
                                 const QString &payType = QString());
    Q_INVOKABLE void addOrderLines(const QString &nrComand,
                                   const QVariantList &lines);

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

    // One-shot action results.
    void loggedIn(int oficiant, const QString &name, const QString &username);
    void orderCreated(int nrComand);
    void orderLinesAdded(int nrComand, const QVariantList &lines);
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
    // parses a JSON object and hands it to `onObject`.
    void postObject(const QString &command,
                    const QVariantMap &formFields,
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
    int m_pending = 0; // in-flight request count, drives `busy`
};

#endif // DATASERVICE_H
