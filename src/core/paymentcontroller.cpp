#include "paymentcontroller.h"

#include "dataservice.h"
#include "smartoneclient.h"

#include <QDateTime>
#include <QGuiApplication>
#include <QSettings>
#include <QTimer>

namespace {
// Câte reîncercări pentru un rezultat POS încă neclar (terminalul procesează).
const int kMaxCardCheckRetries = 3;
const int kCardCheckRetryMs = 2000;
// Închiderea comenzii în Oracle se reia de câteva ori: bonul e deja tipărit,
// deci a renunța aici ar lăsa masa ocupată cu banii încasați.
const int kMaxOracleRetries = 3;
const int kOracleRetryMs = 3000;

// Contorul de documente fiscale, persistat între porniri.
const char *kPayIdKey = "fiscal/nextPayId";
} // namespace

int PaymentController::nextPayId() const
{
    QSettings settings;
    return qMax(1, settings.value(QLatin1String(kPayIdKey), 1).toInt());
}

void PaymentController::setNextPayId(int value)
{
    const int wanted = qMax(1, value);
    if (wanted == nextPayId())
        return;

    QSettings settings;
    settings.setValue(QLatin1String(kPayIdKey), wanted);
    emit nextPayIdChanged();
}

void PaymentController::advancePayId(int usedPayId)
{
    setNextPayId(qMax(nextPayId(), usedPayId + 1));
}

PaymentController::PaymentController(DataService *dataService, QObject *parent)
    : QObject(parent)
    , m_dataService(dataService)
    , m_client(new SmartOneClient(this))
{
    connect(m_client, &SmartOneClient::fiscalDocumentCommitted,
            this, &PaymentController::onDocumentCommitted);
    connect(m_client, &SmartOneClient::fiscalDocumentAlreadyExists,
            this, &PaymentController::onDocumentAlreadyExists);
    connect(m_client, &SmartOneClient::fiscalPrintSuccessful,
            this, &PaymentController::onPrintSuccessful);
    connect(m_client, &SmartOneClient::fiscalPrintFailed,
            this, &PaymentController::onPrintFailed);
    connect(m_client, &SmartOneClient::cardCheckConfirmed,
            this, &PaymentController::onCardConfirmed);
    connect(m_client, &SmartOneClient::cardCheckDeclined,
            this, &PaymentController::onCardDeclined);
    connect(m_client, &SmartOneClient::cardCheckNotReady,
            this, &PaymentController::onCardNotReady);
    connect(m_client, &SmartOneClient::cardSaleDispatched,
            this, &PaymentController::onCardSaleDispatched);
    connect(m_client, &SmartOneClient::fiscalServiceProbed,
            this, &PaymentController::onFiscalServiceProbed);
    connect(m_client, &SmartOneClient::posServiceProbed,
            this, &PaymentController::onPosServiceProbed);

    if (m_dataService) {
        connect(m_dataService, &DataService::orderPaid,
                this, &PaymentController::onOrderPaid);
        connect(m_dataService, &DataService::requestFailed,
                this, &PaymentController::onRequestFailed);
    }

    // Revenirea în prim-plan e exact momentul în care putem afla rezultatul
    // plății cu cardul (app-ul băncii tocmai a cedat ecranul înapoi), și tot
    // atunci reluăm o plată rămasă neterminată. Legat aici, nu în QML, ca să
    // funcționeze și după ce Android a omorât și repornit procesul.
    if (qGuiApp) {
        connect(qGuiApp, &QGuiApplication::applicationStateChanged,
                this, [this](Qt::ApplicationState state) {
                    if (state == Qt::ApplicationActive)
                        appResumed();
                });
    }

    // Aflăm din start ce știe terminalul să facă, ca butonul de achitare și
    // lista de metode să fie deja corecte când chelnerul ajunge la prima comandă.
    probeFiscalService();
    probePosService();
}

void PaymentController::probeFiscalService()
{
    m_client->probeFiscalService();
}

void PaymentController::probePosService()
{
    m_client->probePosService();
}

void PaymentController::onPosServiceProbed(bool available)
{
    const ServiceStatus wanted = available ? ServiceAvailable : ServiceUnavailable;
    if (m_posStatus == wanted)
        return;

    const bool wasAvailable = posAvailable();
    m_posStatus = wanted;
    if (wasAvailable != posAvailable())
        emit posAvailableChanged();
}

void PaymentController::onFiscalServiceProbed(bool available)
{
    const ServiceStatus wanted = available ? ServiceAvailable : ServiceUnavailable;
    if (m_fiscalStatus != wanted) {
        const bool wasAvailable = fiscalAvailable();
        m_fiscalStatus = wanted;
        if (wasAvailable != fiscalAvailable())
            emit fiscalAvailableChanged();
    }

    // Serviciul tocmai a devenit accesibil (a fost pornit după aplicație, sau
    // asta e prima sondare): abia acum are rost să reluăm o plată rămasă în aer.
    if (available && m_state == Idle)
        recoverIfPending();
}

void PaymentController::setState(State state)
{
    if (m_state == state)
        return;
    const bool wasBusy = busy();
    m_state = state;
    if (wasBusy != busy())
        emit busyChanged();
}

int PaymentController::oraclePayType() const
{
    return (m_pending.payType == QLatin1String("C")) ? 1 : 2;
}

bool PaymentController::preparePending(int nrComand,
                                       const QVariantList &lines,
                                       double total,
                                       double received,
                                       const QString &payType,
                                       const QString &employeeName,
                                       const QString &oficiant)
{
    // Fiecare refuz trebuie să iasă printr-un semnal, niciodată în tăcere:
    // ecranul pune `paying = true` ÎNAINTE de apel și îl coboară doar pe
    // paymentFailed. Un `return false` mut lăsa comanda blocată sub overlay,
    // fără nimic de apăsat. Devine ușor de atins de când sondarea poate porni
    // o recuperare exact când chelnerul deschide meniul comenzii.
    if (busy()) {
        emit paymentFailed(tr("A payment is already in progress on this device. "
                              "Wait for it to finish, then try again."));
        return false;
    }

    if (nrComand <= 0 || lines.isEmpty()) {
        emit paymentFailed(tr("This order cannot be paid: it is missing from the system "
                              "or has no lines."));
        return false;
    }

    // Plasa de siguranță din spatele butonului dezactivat: fără serviciu fiscal
    // nu există bon, iar fără bon nu se încasează. Ne oprim ÎNAINTE de a scrie
    // fișierul de recuperare, ca să nu rămână o plată fantomă pe disc.
    if (m_fiscalStatus == ServiceUnavailable) {
        emit paymentFailed(tr("This terminal has no fiscal memory - the payment can only be "
                              "taken on a SmartOne terminal."));
        return false;
    }

    m_employeeName = employeeName;
    m_oficiant = oficiant;
    m_recovering = false;
    m_cardCheckRetries = 0;
    m_oracleRetries = 0;

    m_pending = PendingFiscal();
    m_pending.nrComand = nrComand;
    // payId e un contor INTERN, mic și crescător - NU numărul comenzii.
    // Terminalul fiscal validează numărul de document față de propria secvență
    // și respinge valorile din afara ei ("Invalid docNumber '382766'"), deci
    // numerele de comandă din Oracle (6 cifre) nu pot fi folosite direct.
    //
    // Idempotența la reluare nu se pierde: payId-ul e salvat în fișierul de
    // recuperare, iar o reluare retrimite exact același număr → 409 de la
    // SmartOne în loc de un al doilea bon.
    m_pending.payId = nextPayId();
    m_pending.payType = payType;
    m_pending.total = total;
    m_pending.paid = (payType == QLatin1String("C") && received > 0.0) ? received : total;
    m_pending.change = qMax(0.0, m_pending.paid - total);
    m_pending.lines = lines;
    m_pending.oficiant = oficiant;
    m_pending.employeeName = employeeName;
    m_pending.timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    return true;
}

void PaymentController::payCash(int nrComand,
                                const QVariantList &lines,
                                double total,
                                double received,
                                const QString &employeeName,
                                const QString &oficiant)
{
    if (!preparePending(nrComand, lines, total, received,
                        QStringLiteral("C"), employeeName, oficiant))
        return;

    beginFiscal(true);
}

void PaymentController::payCardManual(int nrComand,
                                      const QVariantList &lines,
                                      double total,
                                      const QString &employeeName,
                                      const QString &oficiant)
{
    if (!preparePending(nrComand, lines, total, 0.0,
                        QStringLiteral("V"), employeeName, oficiant))
        return;

    beginFiscal(true);
}

void PaymentController::payCardPos(int nrComand,
                                   const QVariantList &lines,
                                   double total,
                                   const QString &employeeName,
                                   const QString &oficiant)
{
    // Pereche a guard-ului fiscal din preparePending, pentru metoda care are
    // nevoie și de POS. Verificat înainte de preparePending, ca o metodă
    // indisponibilă să nu lase starea pregătită degeaba.
    if (m_posStatus == ServiceUnavailable) {
        emit paymentFailed(tr("The built-in card terminal is not available on this device."));
        return;
    }

    if (!preparePending(nrComand, lines, total, 0.0,
                        QStringLiteral("V"), employeeName, oficiant))
        return;

    // Salvăm produsele DIN START, nu doar înainte de partea fiscală: dacă
    // Android omoară procesul cât timp e în față app-ul băncii, la repornire
    // trebuie să putem emite bonul fără să mai știm nimic din sesiunea veche.
    m_pending.phase = QStringLiteral("card");
    PendingFiscalStore::save(m_pending);
    setState(AwaitingPos);
    m_client->startCardPayment(m_pending.payId, total);
}

void PaymentController::beginFiscal(bool printOnConflict)
{
    m_pending.phase = QStringLiteral("fiscal");
    PendingFiscalStore::save(m_pending);
    setState(AwaitingFiscal);

    const PendingFiscal snapshot = m_pending;
    const QString employee = m_employeeName;

    // Vizibil în logcat: dacă terminalul refuză numărul de document, ăsta e
    // primul lucru de verificat (vezi proprietatea nextPayId).
    qInfo("[Payment] comanda %d, docNumber %d, total %.2f, tip %s",
          snapshot.nrComand, snapshot.payId, snapshot.total,
          qPrintable(snapshot.payType));

    m_client->ensureShiftOpen([this, snapshot, employee, printOnConflict]() {
        m_client->fiscalSaleAndPrint(snapshot.payId,
                                     snapshot.lines,
                                     snapshot.total,
                                     snapshot.payType,
                                     snapshot.change,
                                     employee,
                                     printOnConflict);
    });
}

void PaymentController::onDocumentCommitted(const QString &documentNumber)
{
    m_pending.documentNumber = documentNumber;
    PendingFiscalStore::save(m_pending);
    // Numărul e consumat abia acum, când chiar există un document fiscal -
    // dacă am avansa la trimitere, o vânzare eșuată ar lăsa o gaură în serie.
    advancePayId(m_pending.payId);

    // Documentul e în memoria fiscală: banii sunt luați. Închidem comanda.
    closeOrderInOracle();
}

void PaymentController::onDocumentAlreadyExists(const QString &documentNumber)
{
    // Reluare: totul fusese dus la capăt înainte de cădere. Nu retipărim (ar
    // ieși un al doilea bon pe hârtie) și nu deranjăm chelnerul cu dialoguri.
    m_pending.documentNumber = documentNumber;
    PendingFiscalStore::save(m_pending);
    advancePayId(m_pending.payId);

    if (!m_pending.oraclePaid) {
        closeOrderInOracle();
        return;
    }

    PendingFiscalStore::remove();
    setState(Idle);
    m_recovering = false;
}

void PaymentController::closeOrderInOracle()
{
    if (!m_dataService) {
        failAndKeepPending(tr("The data service is not available."));
        return;
    }

    setState(ClosingOrder);
    m_dataService->payOrder(QString::number(m_pending.nrComand),
                            oraclePayType(),
                            m_pending.paid,
                            m_pending.documentNumber,
                            m_oficiant);
}

void PaymentController::onOrderPaid(int nrComand, int payType)
{
    Q_UNUSED(payType)

    if (m_state != ClosingOrder || nrComand != m_pending.nrComand)
        return;

    m_oracleRetries = 0;
    m_pending.oraclePaid = true;
    PendingFiscalStore::save(m_pending);

    emit paymentSucceeded(m_pending.nrComand);

    // Dacă recuperam o plată în care tipărirea reușise deja, nu mai urmează
    // niciun semnal de la imprimantă - încheiem aici.
    if (m_recovering) {
        PendingFiscalStore::remove();
        setState(Idle);
        m_recovering = false;
    }
}

void PaymentController::onRequestFailed(const QString &command, const QString &error)
{
    if (command != QLatin1String("pay_order") || m_state != ClosingOrder)
        return;

    if (m_oracleRetries < kMaxOracleRetries) {
        ++m_oracleRetries;
        QTimer::singleShot(kOracleRetryMs, this, [this]() {
            if (m_state == ClosingOrder)
                closeOrderInOracle();
        });
        return;
    }

    m_oracleRetries = 0;
    // Bonul fiscal E emis - banii sunt încasați. Păstrăm fișierul de recuperare
    // ca următoarea pornire să reia DOAR închiderea comenzii (nu emiterea).
    failAndKeepPending(tr("The receipt was issued, but the order could not be closed: %1\n"
                          "It will be retried automatically when the app restarts.").arg(error));
}

void PaymentController::onPrintSuccessful()
{
    // SINGURUL loc care șterge fișierul de recuperare, și numai după
    // confirmarea pozitivă a tipăririi.
    PendingFiscalStore::remove();
    setState(Idle);
    m_recovering = false;
    emit printConfirmed();
}

void PaymentController::onPrintFailed(const QString &reason)
{
    if (m_pending.isCommitted()) {
        // Vânzarea e finalizată; doar hârtia lipsește. Nu ștergem pending-ul.
        setState(Idle);
        emit printNeedsReprint(m_pending.documentNumber, reason);
        return;
    }

    failAndKeepPending(reason);
}

void PaymentController::onCardConfirmed(const QJsonObject &data)
{
    Q_UNUSED(data)

    if (m_state != AwaitingPos)
        return;

    m_cardCheckRetries = 0;
    beginFiscal(!m_recovering);
}

void PaymentController::onCardDeclined(const QString &reason)
{
    if (m_state != AwaitingPos)
        return;

    // Refuz definitiv: nu s-au luat bani și nu s-a emis niciun bon, deci
    // fișierul de recuperare nu mai are ce recupera.
    PendingFiscalStore::remove();
    m_cardCheckRetries = 0;
    setState(Idle);
    m_recovering = false;
    emit paymentFailed(reason.isEmpty() ? tr("The card payment was declined.") : reason);
}

void PaymentController::onCardNotReady()
{
    if (m_state != AwaitingPos)
        return;

    if (m_cardCheckRetries < kMaxCardCheckRetries) {
        ++m_cardCheckRetries;
        QTimer::singleShot(kCardCheckRetryMs, this, [this]() {
            if (m_state == AwaitingPos)
                m_client->checkCardPayment(m_pending.payId);
        });
        return;
    }

    m_cardCheckRetries = 0;
    // Starea rămâne incertă: păstrăm fișierul, ca reluarea de la următoarea
    // pornire să întrebe din nou terminalul în loc să presupunem un eșec.
    failAndKeepPending(tr("No response from the card terminal. Check whether the payment went "
                          "through before trying again."));
}

void PaymentController::onCardSaleDispatched(bool success, const QString &response)
{
    if (success || m_state != AwaitingPos)
        return;

    // Cererea către app-ul băncii nici n-a plecat (bridge-ul POS nu ascultă).
    // Fără tratarea asta rămâneam în AwaitingPos la nesfârșit: app-ul băncii nu
    // s-a deschis, deci nu urmează nicio revenire în prim-plan care să ne
    // trezească, iar chelnerul rămânea cu ecranul blocat pe "se achită".
    //
    // Păstrăm fișierul de recuperare: dacă cererea a apucat totuși să ajungă la
    // terminal, o verificare ulterioară trebuie să poată afla rezultatul.
    m_cardCheckRetries = 0;
    failAndKeepPending(response.trimmed().isEmpty()
        ? tr("The card terminal could not be reached.")
        : tr("The card terminal could not be reached: %1").arg(response.trimmed()));
}

void PaymentController::failAndKeepPending(const QString &reason)
{
    setState(Idle);
    emit paymentFailed(reason);
}

void PaymentController::reprint()
{
    if (m_pending.documentNumber.trimmed().isEmpty()) {
        emit paymentFailed(tr("There is no receipt to reprint."));
        return;
    }
    setState(AwaitingFiscal);
    m_client->reprintDocument(m_pending.documentNumber);
}

void PaymentController::appResumed()
{
    if (m_state == AwaitingPos) {
        m_client->checkCardPayment(m_pending.payId);
        return;
    }

    // Sondarea reia singură recuperarea dacă serviciul răspunde (vezi
    // onFiscalServiceProbed), deci nu mai chemăm recoverIfPending direct:
    // altfel, pe un terminal fără SmartOne, fiecare revenire în prim-plan
    // scotea un dialog de eroare pentru o plată care oricum nu se poate face.
    if (m_state == Idle) {
        probeFiscalService();
        probePosService();
    }
}

void PaymentController::recoverIfPending()
{
    if (busy() || !PendingFiscalStore::exists())
        return;

    PendingFiscal saved;
    if (!PendingFiscalStore::load(saved)) {
        // Fișier corupt/incomplet: nu avem ce recupera din el.
        PendingFiscalStore::remove();
        return;
    }

    m_pending = saved;
    m_recovering = true;
    // Sesiunea veche a dispărut odată cu procesul; luăm chelnerul din fișier.
    m_oficiant = saved.oficiant;
    m_employeeName = saved.employeeName;

    // Bonul e emis, dar comanda n-a apucat să fie închisă: reluăm DOAR partea
    // Oracle. A retrimite /sale ar fi inutil (și ar da oricum 409).
    //
    // Se face ORICUM, chiar dacă terminalul fiscal e mut: pasul ăsta nu-l
    // atinge deloc (merge prin PHP spre Oracle), iar banii sunt deja încasați.
    // A-l amâna ar ține masa ocupată cu o plată neînregistrată.
    if (m_pending.isCommitted() && !m_pending.oraclePaid) {
        m_oracleRetries = 0;
        closeOrderInOracle();
        return;
    }

    // Tot ce urmează are nevoie de SmartOne. Dacă nu răspunde, ne oprim fără să
    // ștergem nimic: plata poate fi reală, doar terminalul e mut acum, iar
    // reluarea se face la prima sondare reușită. Fără oprirea asta, fiecare
    // revenire în prim-plan scotea un dialog de eroare pentru o plată care
    // oricum nu se poate duce la capăt aici.
    if (m_fiscalStatus == ServiceUnavailable) {
        m_recovering = false;
        return;
    }

    // Așteptam rezultatul terminalului de card când s-a oprit aplicația.
    if (m_pending.isCardPhase()) {
        m_cardCheckRetries = 0;
        setState(AwaitingPos);
        m_client->checkCardPayment(m_pending.payId);
        return;
    }

    // Nu știm dacă bonul a apucat să fie emis. Retrimitem vânzarea cu ACELAȘI
    // docNumber: dacă exista deja, SmartOne răspunde 409 și curățăm tăcut;
    // dacă nu, se emite acum, normal.
    beginFiscal(false);
}
