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
    // false = pe terminalul ăsta NU se poate emite bon fiscal (bridge-ul
    // SmartOne lipsește - e un Android obișnuit, fără memorie fiscală).
    // Interfața dezactivează achitarea, iar preparePending o refuză și dacă
    // totuși se ajunge acolo. Cât timp sondarea n-a răspuns încă, proprietatea
    // e true: presupunem terminalul bun și dezactivăm doar pe un "nu" confirmat.
    Q_PROPERTY(bool fiscalAvailable READ fiscalAvailable NOTIFY fiscalAvailableChanged)
    // false = bridge-ul POS de pe :8888 nu ascultă, deci plata cu cardul prin
    // POS-ul integrat nu are cum să pornească. Interfața scoate metoda din
    // listă; celelalte două (numerar, card pe terminal separat) rămân, pentru
    // că nu depind de el.
    Q_PROPERTY(bool posAvailable READ posAvailable NOTIFY posAvailableChanged)

public:
    explicit PaymentController(DataService *dataService, QObject *parent = nullptr);

    bool busy() const { return m_state != Idle; }
    bool fiscalAvailable() const { return m_fiscalStatus != ServiceUnavailable; }
    bool posAvailable() const { return m_posStatus != ServiceUnavailable; }
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

    // Re-tipărește un bon deja emis (rola s-a terminat etc.). Numărul vine de
    // la apelant, nu din starea curentă: dialogul de retipărire trăiește în
    // main.qml și poate rămâne deschis peste alte plăți, timp în care
    // `m_pending` se schimbă - fără parametru s-ar tipări alt document.
    // Gol = ultimul document al plății curente.
    Q_INVOKABLE void reprint(const QString &documentNumber);

    // De chemat când aplicația revine în prim-plan: dacă așteptam rezultatul
    // POS-ului, îl verificăm acum.
    Q_INVOKABLE void appResumed();

    // De chemat la pornire: duce la capăt o plată întreruptă de o cădere.
    Q_INVOKABLE void recoverIfPending();

    // Reîntreabă serviciul fiscal dacă e prezent. Se cheamă singură la pornire
    // și la fiecare revenire în prim-plan; expusă pentru cazul în care
    // bridge-ul SmartOne e pornit după aplicație.
    Q_INVOKABLE void probeFiscalService();

    // Reîntreabă bridge-ul POS. Ca și cea fiscală, se cheamă singură la pornire
    // și la fiecare revenire în prim-plan.
    Q_INVOKABLE void probePosService();

signals:
    void busyChanged();
    void nextPayIdChanged();
    void fiscalAvailableChanged();
    void posAvailableChanged();
    // Comanda e închisă în Oracle: plata s-a încheiat cu succes.
    void paymentSucceeded(int nrComand);
    // Eșecul unei plăți CERUTE ACUM de chelner. Poartă numărul comenzii pentru
    // că ecranul trebuie să arate dialogul doar pentru comanda lui - altfel o
    // recuperare de fundal pentru altă masă scotea o eroare peste comanda
    // deschisă, fără nicio legătură cu ea.
    void paymentFailed(int nrComand, const QString &reason);
    // Eșecul unei recuperări pornite singură (după o cădere sau după revenirea
    // serviciului). Nu-l cere nimeni și nu-i corespunde nicio pagină deschisă,
    // deci îl arată main.qml, numind comanda ca să se înțeleagă despre ce e
    // vorba. Canal separat, ca să nu fie nici ascuns, nici confundat cu plata
    // pe care chelnerul tocmai o încearcă.
    void backgroundPaymentFailed(int nrComand, const QString &reason);
    // Bonul e emis, dar tipărirea a eșuat. Vânzarea E finalizată - interfața
    // oferă re-tipărirea, nu reluarea plății.
    void printNeedsReprint(const QString &documentNumber, const QString &reason);
    void printConfirmed();

private:
    enum State { Idle, AwaitingPos, AwaitingFiscal, ClosingOrder };
    // Trei stări, nu un bool: "încă nu știu" trebuie deosebit de "nu există",
    // altfel prima secundă de după pornire ar arăta achitarea ca imposibilă
    // pe un terminal perfect bun. Folosit pentru ambele bridge-uri SmartOne.
    enum ServiceStatus { ServiceUnknown, ServiceAvailable, ServiceUnavailable };

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
    // Trimite eșecul pe canalul potrivit: `background` = recuperare pornită
    // singură, deci nu are pagină care s-o aștepte.
    void emitFailure(int nrComand, const QString &reason, bool background);

    void onDocumentCommitted(const QString &documentNumber);
    void onDocumentAlreadyExists(const QString &documentNumber);
    void onPrintSuccessful();
    void onPrintFailed(const QString &reason);
    void onCardConfirmed(const QJsonObject &data);
    void onCardDeclined(const QString &reason);
    void onCardNotReady();
    void onCardSaleDispatched(bool success, const QString &response);
    void onFiscalSaleNotSent(const QString &reason);
    // Închide o plată despre care ȘTIM că n-a atins terminalul: șterge fișierul
    // de recuperare (dar niciodată în timpul unei recuperări - acolo el poate
    // descrie o încercare anterioară care chiar a ajuns) și raportează eșecul.
    void failWithoutPending(const QString &reason);
    void onFiscalServiceProbed(bool available);
    void onPosServiceProbed(bool available);
    void onOrderPaid(int nrComand, int payType);
    void onRequestFailed(const QString &command, const QString &error);

    int oraclePayType() const;

    DataService *m_dataService = nullptr;
    SmartOneClient *m_client = nullptr;
    State m_state = Idle;
    ServiceStatus m_fiscalStatus = ServiceUnknown;
    ServiceStatus m_posStatus = ServiceUnknown;
    PendingFiscal m_pending;
    QString m_employeeName;
    QString m_oficiant;
    int m_cardCheckRetries = 0;
    int m_oracleRetries = 0;
    // Suntem într-o reluare după cădere: schimbă ce facem la 409 și ne ferește
    // să arătăm dialoguri de eroare pentru o plată care de fapt reușise.
    bool m_recovering = false;
    // POS-ul a confirmat debitarea cardului pentru plata curentă. NU se
    // persistă intenționat: contează doar cât ține procesul, iar după o
    // repornire suntem oricum în recuperare, unde fișierul nu se șterge nicicum.
    // Fără el, un serviciu fiscal picat DUPĂ debitare ducea la ștergerea
    // fișierului - bani luați de bancă, fără bon, fără urmă și cu risc de dublă
    // debitare dacă chelnerul relua plata.
    bool m_cardCharged = false;
    // Retipărim un document care NU e al plății din `m_pending` (dialogul a
    // rămas deschis peste o plată ulterioară). Atunci reușita tipăririi nu are
    // voie să șteargă fișierul de recuperare - el aparține altei plăți.
    bool m_reprintOnly = false;
};

#endif // PAYMENTCONTROLLER_H
