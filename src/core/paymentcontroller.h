#ifndef PAYMENTCONTROLLER_H
#define PAYMENTCONTROLLER_H

#include <QJsonObject>
#include <QObject>
#include <QVariantList>

#include "pendingfiscalstore.h"

class DataService;
class SmartOneClient;

// Creierul achitării, separat de interfață: QML îi cere o plată și ascultă
// semnalele, controller-ul nu atinge niciodată butoane sau dialoguri.
//
// ORDINEA OPERAȚIILOR (decisă în analiză): bonul fiscal ÎNTÂI, închiderea
// comenzii în Oracle DUPĂ. Bonul e artefactul legal și e protejat de duplicare
// (409 de la SmartOne); închiderea comenzii e contabilitate internă, reluabilă
// în siguranță. Invers, comanda ar dispărea din listă ca "achitată" fără ca
// clientul să aibă bon.
//
// Reguli de aur (SMARTONE_CONTRACT.md din D:\UNARetail):
//   - `pending_fiscal.json` se șterge într-UN SINGUR loc, doar după confirmarea
//     pozitivă a tipăririi.
//   - După ce SmartOne a întors document_number, vânzarea e COMISĂ: o eroare
//     de tipărire se rezolvă prin re-tipărire, NICIODATĂ prin re-emitere.
class PaymentController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Numărul de document trimis terminalului la următoarea vânzare. E un
    // contor INTERN al nostru (SmartOne își dă propriul `document_number`
    // înapoi), persistat între porniri și avansat după fiecare document comis.
    //
    // Expus ca proprietate pentru că terminalul fiscal poate refuza un număr în
    // afara secvenței lui ("Invalid docNumber") - atunci trebuie potrivit cu ce
    // așteaptă aparatul, fără reinstalarea aplicației.
    Q_PROPERTY(int nextPayId READ nextPayId WRITE setNextPayId NOTIFY nextPayIdChanged)

public:
    explicit PaymentController(DataService *dataService, QObject *parent = nullptr);

    bool busy() const { return m_state != Idle; }
    int nextPayId() const;
    void setNextPayId(int value);

    // Numerar: `received` e suma dată de client (restul se calculează).
    Q_INVOKABLE void payCash(int nrComand,
                             const QVariantList &lines,
                             double total,
                             double received,
                             const QString &employeeName,
                             const QString &oficiant);

    // Card trecut pe un terminal bancar SEPARAT: sărim peste pasul POS și
    // emitem doar bonul fiscal.
    Q_INVOKABLE void payCardManual(int nrComand,
                                   const QVariantList &lines,
                                   double total,
                                   const QString &employeeName,
                                   const QString &oficiant);

    // Card prin POS-ul integrat al terminalului: aplicația trece în fundal
    // spre app-ul băncii și revine cu rezultatul.
    Q_INVOKABLE void payCardPos(int nrComand,
                                const QVariantList &lines,
                                double total,
                                const QString &employeeName,
                                const QString &oficiant);

    // Re-tipărește ultimul bon emis (rola s-a terminat etc.).
    Q_INVOKABLE void reprint();

    // De chemat când aplicația revine în prim-plan: dacă așteptam rezultatul
    // POS-ului, îl verificăm acum.
    Q_INVOKABLE void appResumed();

    // De chemat la pornire: duce la capăt o plată întreruptă de o cădere.
    Q_INVOKABLE void recoverIfPending();

signals:
    void busyChanged();
    void nextPayIdChanged();
    // Comanda e închisă în Oracle: plata s-a încheiat cu succes.
    void paymentSucceeded(int nrComand);
    void paymentFailed(const QString &reason);
    // Bonul e emis, dar tipărirea a eșuat. Vânzarea E finalizată - interfața
    // oferă re-tipărirea, nu reluarea plății.
    void printNeedsReprint(const QString &documentNumber, const QString &reason);
    void printConfirmed();

private:
    enum State { Idle, AwaitingPos, AwaitingFiscal, ClosingOrder };

    void setState(State state);
    // Pregătește starea comună celor trei metode de plată. Întoarce false dacă
    // o plată e deja în curs sau datele sunt goale.
    bool preparePending(int nrComand,
                        const QVariantList &lines,
                        double total,
                        double received,
                        const QString &payType,
                        const QString &employeeName,
                        const QString &oficiant);
    void beginFiscal(bool printOnConflict);
    // Avansează contorul după ce documentul a fost comis, ca vânzarea următoare
    // să nu reia același număr (ar primi 409 și ar fi luată drept "deja emisă").
    void advancePayId(int usedPayId);
    void closeOrderInOracle();
    void finishWithSuccess();
    void failAndKeepPending(const QString &reason);

    void onDocumentCommitted(const QString &documentNumber);
    void onDocumentAlreadyExists(const QString &documentNumber);
    void onPrintSuccessful();
    void onPrintFailed(const QString &reason);
    void onCardConfirmed(const QJsonObject &data);
    void onCardDeclined(const QString &reason);
    void onCardNotReady();
    void onOrderPaid(int nrComand, int payType);
    void onRequestFailed(const QString &command, const QString &error);

    int oraclePayType() const;

    DataService *m_dataService = nullptr;
    SmartOneClient *m_client = nullptr;
    State m_state = Idle;
    PendingFiscal m_pending;
    QString m_employeeName;
    QString m_oficiant;
    int m_cardCheckRetries = 0;
    int m_oracleRetries = 0;
    // Suntem într-o reluare după cădere: schimbă ce facem la 409 și ne ferește
    // să arătăm dialoguri de eroare pentru o plată care de fapt reușise.
    bool m_recovering = false;
};

#endif // PAYMENTCONTROLLER_H
