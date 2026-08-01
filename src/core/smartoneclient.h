#ifndef SMARTONECLIENT_H
#define SMARTONECLIENT_H

#include <QJsonObject>
#include <QObject>
#include <QVariantList>

#include <functional>

class QNetworkAccessManager;

// Vorbește cu terminalul SmartOne. Portat din D:\UNARetail
// (widgets/VanzariBranch/Fiscal/) - vezi SMARTONE_CONTRACT.md de acolo pentru
// contractul complet și cele 6 invariante de bani.
//
// Trei canale, TOATE pe localhost, pentru că bridge-urile sunt aplicații
// externe instalate pe terminal și ascultă doar pe loopback. De aceea aplicația
// TREBUIE să ruleze pe terminalul SmartOne - un telefon obișnuit nu le vede.
//   :8080 - fiscal (emitere + tipărire bon)
//   :8888 - POS card (app-ul băncii)
//   JNI   - imprimantă non-fiscală, prin SDK-ul Java
class SmartOneClient : public QObject
{
    Q_OBJECT

public:
    explicit SmartOneClient(QObject *parent = nullptr);

    // Întreabă serviciul fiscal dacă e acolo, fără să atingă nimic. Răspunsul
    // vine prin fiscalServiceProbed. Există pentru că aplicația poate ajunge pe
    // un Android obișnuit, fără bridge-urile SmartOne: acolo nu se poate emite
    // bon, iar asta trebuie știut ÎNAINTE ca chelnerul să apese "Achită".
    void probeFiscalService();

    // Aceeași întrebare, pusă bridge-ului POS de pe :8888. Separată de cea
    // fiscală pentru că sunt două aplicații distincte: pe un terminal bun,
    // POS-ul poate lipsi singur, iar atunci doar plata cu cardul integrat
    // trebuie ascunsă, nu toată achitarea.
    void probePosService();

    // Tura fiscală trebuie deschisă înainte de orice bon. Dacă e deja
    // deschisă, callback-ul se cheamă direct.
    void ensureShiftOpen(const std::function<void()> &onReady);

    // Pornește plata cu cardul: aplicația trece în fundal spre app-ul băncii.
    void startCardPayment(int payId, double amount);
    // Verifică rezultatul plății după revenirea în prim-plan.
    void checkCardPayment(int payId);

    // Emite bonul fiscal și îl tipărește. `lines` sunt rândurile din
    // get_order_lines (chei CLCBLIUDAT / CANT / CLCPRETT / CLCSUMAT / CODTVA).
    // payType: "C" = numerar, "V" = card.
    // `printOnConflict` distinge cele două situații în care SmartOne răspunde
    // 409 ("document deja existent"):
    //   true  - plată normală: documentul tocmai s-a creat, mergem la tipărire.
    //   false - RECUPERARE după cădere: bonul a fost deja emis ȘI tipărit
    //           înainte, deci retipărirea ar scoate un al doilea bon pe hârtie.
    //           Emitem fiscalDocumentAlreadyExists ca apelantul să curețe tăcut.
    void fiscalSaleAndPrint(int payId,
                            const QVariantList &lines,
                            double total,
                            const QString &payType,
                            double change,
                            const QString &employeeName,
                            bool printOnConflict = true);

    // Re-tipărește un document deja emis. NU re-emite vânzarea: documentul e
    // deja în memoria fiscală, o a doua /sale ar produce bon dublu.
    void reprintDocument(const QString &documentNumber);

    // Construiește corpul cererii /sale. Public și fără efecte secundare
    // anume ca să poată fi verificat direct în teste: conversiile (lei ->
    // bani, cantități ×1000) și însumarea pe cote de TVA sunt partea cel mai
    // ușor de greșit din toată integrarea, și cea mai scumpă dacă e greșită.
    static QJsonObject buildSalePayload(int payId,
                                        const QVariantList &lines,
                                        double total,
                                        const QString &payType,
                                        double change,
                                        const QString &employeeName);

    QString lastDocumentNumber() const { return m_lastDocumentNumber; }

signals:
    // Rezultatul 8888/check:
    //   confirmed = plată aprobată
    //   declined  = anulată/refuzată -> eșec DEFINITIV, fără retry
    //   notReady  = tranzitoriu (POS încă procesează) -> se reîncearcă
    void cardCheckConfirmed(const QJsonObject &data);
    void cardCheckDeclined(const QString &reason);
    void cardCheckNotReady();
    void cardSaleDispatched(bool success, const QString &response);

    // Documentul fiscal e COMIS în memoria SmartOne (răspuns /sale cu
    // document_number). Punct de non-retur: de aici doar re-tipărire.
    void fiscalDocumentCommitted(const QString &documentNumber);
    // Documentul exista deja (409) într-o reluare: totul fusese dus la capăt
    // înainte de cădere. Nu urmează nicio tipărire.
    void fiscalDocumentAlreadyExists(const QString &documentNumber);
    void fiscalPrintSuccessful();
    void fiscalPrintFailed(const QString &reason);

    // Serviciul fiscal a răspuns (true) sau nici măcar nu ascultă pe loopback
    // (false). Emis atât de probeFiscalService, cât și de ensureShiftOpen -
    // orice atingere a serviciului e o ocazie de a afla adevărul.
    void fiscalServiceProbed(bool available);
    // La fel, pentru bridge-ul POS. Emis de probePosService și de
    // startCardPayment (o cerere refuzată e tot un răspuns despre disponibilitate).
    void posServiceProbed(bool available);

private:
    void openShift(const std::function<void()> &onOpened);
    void sendPrintCheck(const QJsonObject &body, bool allowRetry);
    // Interpretează răspunsul /print_check. Adunată într-un loc pentru că
    // bridge-ul raportează succesul în mai multe forme (ok/success/printStatus/
    // message), iar originalul avea trei copii aproape identice ale logicii.
    void handlePrintResponse(const QByteArray &response);

    QNetworkAccessManager *m_network = nullptr;
    QString m_lastDocumentNumber;
};

#endif // SMARTONECLIENT_H
