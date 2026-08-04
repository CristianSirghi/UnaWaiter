#include "smartoneclient.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrl>
#include <QtMath>

#include <limits>

namespace {

// Adresele bridge-urilor SmartOne. Hardcodate intenționat pe loopback: sunt
// aplicații externe de pe terminal, nu servicii de rețea (vezi antetul).
const char *kFiscalBase = "http://127.0.0.1:8080";
const char *kPosBase = "http://127.0.0.1:8888";

// Cât așteptăm după ce serviciul fiscal a acceptat conexiunea dar nu răspunde.
// Fără el, interfața rămânea blocată cu comanda deschisă și fără nicio acțiune
// clară pentru chelner.
const int kFiscalSaleTimeoutMs = 20000;
const int kCardCheckTimeoutMs = 5000;
// Sondarea serviciului fiscal e o simplă întrebare "ești acolo?": pe loopback
// un refuz de conexiune vine în milisecunde, iar termenul ăsta acoperă doar
// cazul în care ceva ascultă pe port dar nu răspunde.
const int kProbeTimeoutMs = 3000;
// Verificarea turii nu mai poate atârna la nesfârșit (înainte n-avea niciun
// termen: un serviciu care accepta conexiunea dar nu răspundea lăsa chelnerul
// cu ecranul blocat). Larg intenționat - vezi serviceMissing() pentru ce
// tratăm drept "lipsește" și ce nu.
const int kShiftCheckTimeoutMs = 8000;
// Deschiderea turii și tipărirea n-aveau NICIUN termen. Dacă bridge-ul accepta
// conexiunea și apoi tăcea, `finished` nu se mai emitea niciodată, controller-ul
// rămânea în AwaitingFiscal/ClosingOrder, `busy()` rămânea true - și de-atunci
// ORICE altă plată era refuzată până la repornirea aplicației. Nimic nu repara
// asta singur: `appResumed` iese devreme când starea nu e Idle. Valorile sunt
// largi intenționat (aparatul chiar scoate hârtie); rolul lor e să nu atârne la
// infinit, nu să fie strânse.
const int kOpenShiftTimeoutMs = 20000;
const int kPrintCheckTimeoutMs = 20000;

// Nimeni nu ascultă pe port: bridge-ul SmartOne nu e instalat sau nu rulează.
// DOAR erorile de nivel conexiune contează aici - nu și un timeout sau o eroare
// HTTP. Un 404/500 dovedește că serviciul există, iar un timeout înseamnă doar
// că e lent; dacă le-am trata pe toate la fel, un terminal fiscal bun dar
// încet ar rămâne fără achitare. Greșeala trebuie făcută în direcția asta:
// mai bine încercăm o plată care eșuează explicit, decât să blocăm una validă.
bool serviceMissing(QNetworkReply *reply)
{
    const QNetworkReply::NetworkError err = reply->error();
    return err == QNetworkReply::ConnectionRefusedError
        || err == QNetworkReply::HostNotFoundError;
}

int toBani(double amount)
{
    return static_cast<int>(qRound(amount * 100.0));
}

// TVA: literele din UAMenu (VMDB_COMENZD.CODTVA) sunt exact codurile așteptate
// de SmartOne, deci nu e nevoie de traducere - doar de procent.
//
// A=20, B=8, C=6. Verificate în baza de producție 2026-08-03 ȘI pe hârtie.
//
// ⚠️ CE TIPĂREȘTE BONUL NU DEPINDE DE VALORILE ASTEA. Aparatul fiscal SmartOne
// are propriul tabel de taxe programat și îl folosește pe al lui. Dovedit
// definitiv, nu dedus: cu aplicația trimițând C=10.00% (vezi log-ul
// `[SmartOne][TVA]` de mai jos, `tva=436 bani` pe o comandă de 48 lei), bonul a
// ieșit tipărit cu **6%**. Valorile de aici sunt deci ce DECLARĂM, nu ce se
// tipărește - dar tocmai de-aceea trebuie să fie corecte, nu la întâmplare.
//
// De ce 6% pentru C: e ce tipărește aparatul ȘI ce înregistrează UAMenu în
// Oracle (`TVA_C` = 6% din brut pe 8426 din 8426 comenzi achitate de pe
// producție, și pe comenzile încă deschise). Cele două sunt de acord.
//
// ⚠️ CE NU E DE ACORD, și e problema CLIENTULUI, nu a noastră: imprimanta
// fiscală **Tremol** de la casă tipărește pentru aceeași literă **10%**, pentru
// că UAMenu îi trimite `Unirest_Util.vat_percent_by_letter('C') = 10` prin
// pachetul `BON`. Adică același restaurant emite bonuri cu 6% (din aplicație) și
// cu 10% (de la casă), pe același produs. UAMenu contabilizează la 6% dar
// tipărește 10% - se contrazice pe el însuși.
//
// Cele două aparate sunt pur și simplu programate diferit. De ridicat la
// Sandu/Daniela: rapoartele X/Z ale celor două nu au cum să se reconcilieze.
//
// NU lua cota din `Unirest_Util.vat_percent_by_letter`: pare sursa oficială, dar
// întoarce 10 - valoarea care contrazice și aparatul, și contabilitatea. S-a
// încercat (vezi `TVA_PRC` mai jos) și s-a retras exact din motivul ăsta.
//
// Valorile dinainte (B=12%, C=8%) veneau din UNARetail - care e RETAIL, nu
// restaurant. Arătau plauzibil și au trecut nedetectate până la un bon real.
// Nu lua constante de business dintr-un alt proiect fără să le verifici în baza
// deployment-ului curent.
//
// 'B' nu apare deloc pe producție (0 produse, 0 linii). '0' există pe 3
// „produse" care sunt de fapt furnizori, niciodată vândute.
// Întoarce `false` dacă litera nu e una cunoscută și s-a căzut pe cota standard.
// Apelantul are nevoie de distincția asta: pe o literă nerecunoscută n-are voie
// să lipească peste ea cota venită din Oracle, altfel ar ieși perechi
// inventate, gen "TVA A" cu 0%.
bool taxForCode(const QString &code, QString *letter, int *prcX100, double *rate)
{
    const QString c = code.trimmed().toUpper();
    if (c == QLatin1String("0")) {
        *letter = QStringLiteral("0"); *prcX100 = 0;    *rate = 0.00;
    } else if (c == QLatin1String("B")) {
        *letter = QStringLiteral("B"); *prcX100 = 800;  *rate = 0.08;
    } else if (c == QLatin1String("C")) {
        *letter = QStringLiteral("C"); *prcX100 = 600;  *rate = 0.06;
    } else if (c == QLatin1String("A")) {
        *letter = QStringLiteral("A"); *prcX100 = 2000; *rate = 0.20;
    } else {
        // Cod necunoscut -> cota standard. Mai bine să declarăm prea mult TVA
        // decât prea puțin dacă apare un cod nou în meniu.
        *letter = QStringLiteral("A"); *prcX100 = 2000; *rate = 0.20;
        return false;
    }
    return true;
}

// Partea de TVA dintr-o sumă care îl conține DEJA.
//
// În UAMenu prețurile sunt cu TVA inclus, deci taxa nu e `sumă × cotă`, ci
// `sumă × r/(1+r)`. Spre deosebire de cote, aici NU există nicio contradicție:
// aceeași formulă e în `Unirest_Util.sum_tva`, în view-ul de reconciliere, și e
// și ce a tipărit aparatul (5.09 pe 56 lei = 56*0.1/1.1, nu 56*0.1 = 5.60).
// Cu înmulțirea simplă, pe 100 lei la 10% ar ieși 10.00 în loc de 9.09.
int taxFromInclusive(int amountBani, double rate)
{
    return static_cast<int>(qRound(amountBani * rate / (1.0 + rate)));
}

QString paymentName(const QString &payType)
{
    if (payType == QLatin1String("C"))
        return QStringLiteral("Numerar");
    if (payType == QLatin1String("V"))
        return QStringLiteral("Card");
    return QStringLiteral("Necunoscut");
}

} // namespace

SmartOneClient::SmartOneClient(QObject *parent)
    : QObject(parent)
    , m_network(new QNetworkAccessManager(this))
{
}

void SmartOneClient::probeFiscalService()
{
    // Sondarea în curs va raporta oricum, și mai devreme decât una pornită acum.
    if (m_fiscalProbeInFlight)
        return;
    m_fiscalProbeInFlight = true;

    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(QString(kFiscalBase) + "/check-shift")));

    QTimer::singleShot(kProbeTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const bool missing = serviceMissing(reply);
        reply->deleteLater();
        m_fiscalProbeInFlight = false;
        emit fiscalServiceProbed(!missing);
    });
}

void SmartOneClient::probePosService()
{
    if (m_posProbeInFlight)
        return;
    m_posProbeInFlight = true;

    // GET pe rădăcină, nu pe /check: ne interesează exclusiv dacă cineva ascultă
    // pe port, iar /check ar întreba despre o plată anume. Un 404 e un răspuns
    // perfect bun aici - dovedește că bridge-ul e acolo.
    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(QString(kPosBase) + "/")));

    QTimer::singleShot(kProbeTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const bool missing = serviceMissing(reply);
        reply->deleteLater();
        m_posProbeInFlight = false;
        emit posServiceProbed(!missing);
    });
}

void SmartOneClient::ensureShiftOpen(const std::function<void()> &onReady)
{
    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(QString(kFiscalBase) + "/check-shift")));

    QTimer::singleShot(kShiftCheckTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, onReady]() {
        // Nimeni nu ascultă pe loopback: nu are rost să trimitem /sale, ar eșua
        // la fel și chelnerul ar primi drept explicație textul brut al erorii de
        // rețea ("Connection refused"). Ne oprim aici, cu un motiv pe înțeles.
        if (serviceMissing(reply)) {
            reply->deleteLater();
            emit fiscalServiceProbed(false);
            emit fiscalSaleNotSent(tr("The fiscal service is not available on this terminal. "
                                      "The receipt can only be issued on a SmartOne terminal "
                                      "with fiscal memory."));
            return;
        }

        emit fiscalServiceProbed(true);

        const QByteArray response = reply->readAll();
        reply->deleteLater();

        QJsonParseError err {};
        const QJsonDocument doc = QJsonDocument::fromJson(response, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            // Nu blocăm plata dintr-un răspuns neinterpretabil: dacă tura chiar
            // e închisă, /sale va eșua oricum cu un mesaj clar.
            qWarning("[SmartOne] check-shift: raspuns neinterpretabil, continuam");
            onReady();
            return;
        }

        const QJsonObject obj = doc.object();
        const bool open = obj.value(QStringLiteral("shift_open")).toBool(false)
            || obj.value(QStringLiteral("shiftOpen")).toBool(false);

        if (open)
            onReady();
        else
            openShift(onReady);
    });
}

void SmartOneClient::openShift(const std::function<void()> &onOpened)
{
    QNetworkRequest req { QUrl(QString(kFiscalBase) + "/open-shift") };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject body;
    body[QStringLiteral("employeeName")] = QStringLiteral("Casier");

    QNetworkReply *reply = m_network->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    QTimer::singleShot(kOpenShiftTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [reply, onOpened]() {
        const QByteArray response = reply->readAll();
        reply->deleteLater();

        const QJsonObject obj = QJsonDocument::fromJson(response).object();
        const QString status = obj.value(QStringLiteral("status")).toString().toLower();
        const int code = obj.value(QStringLiteral("code")).toInt(0);

        // code -203 = "tura era deja deschisă", ceea ce e succes pentru noi.
        if (status != QLatin1String("success") && code != -203)
            qWarning("[SmartOne] open-shift: raspuns neasteptat");

        onOpened();
    });
}

void SmartOneClient::startCardPayment(int payId, double amount)
{
    QNetworkRequest req { QUrl(QString(kPosBase) + "/sale") };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject body;
    body[QStringLiteral("pay_id")] = payId;
    body[QStringLiteral("currency_name")] = QStringLiteral("MDL");
    body[QStringLiteral("amount")] = toBani(amount);
    // Pachetul nostru: app-ul POS îl folosește ca să readucă UnaWaiter în
    // prim-plan după plată. Trebuie să rămână identic cu `package` din
    // android/AndroidManifest.xml, altfel chelnerul rămâne blocat în app-ul băncii.
    body[QStringLiteral("package_name")] = QStringLiteral("org.qtproject.UnaWaiter");

    // Singurul apel lăsat ANUME fără termen de abandon. Aici o expirare ar fi
    // periculoasă, nu utilă: am raporta "n-a plecat" pentru o cerere care poate
    // a ajuns, exact în timp ce app-ul băncii debitează cardul. Și nici nu e
    // nevoie - dacă cererea atârnă, starea rămâne AwaitingPos, iar revenirea în
    // prim-plan cheamă /check și află rezultatul adevărat de la terminal.
    QNetworkReply *reply = m_network->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const bool missing = serviceMissing(reply);
        const QString detail = ok ? QString::fromUtf8(reply->readAll()) : reply->errorString();
        reply->deleteLater();

        // Un refuz de conexiune spune despre POS exact ce spune și o sondare,
        // doar că mai devreme: actualizăm disponibilitatea fără să mai așteptăm
        // următoarea revenire în prim-plan.
        if (ok || missing)
            emit posServiceProbed(ok);

        emit cardSaleDispatched(ok, detail);
    });
}

void SmartOneClient::checkCardPayment(int payId)
{
    QNetworkRequest req { QUrl(QString(kPosBase) + "/check") };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject body;
    body[QStringLiteral("pay_id")] = payId;

    QNetworkReply *reply = m_network->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    QTimer::singleShot(kCardCheckTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply->error() != QNetworkReply::NoError) {
            reply->deleteLater();
            emit cardCheckNotReady();
            return;
        }

        const QByteArray response = reply->readAll();
        reply->deleteLater();

        const QJsonObject obj = QJsonDocument::fromJson(response).object();
        const QString status = obj.value(QStringLiteral("status")).toString().toLower();
        const QJsonValue data = obj.value(QStringLiteral("data"));

        if (status == QLatin1String("success") && data.isObject() && !data.toObject().isEmpty()) {
            emit cardCheckConfirmed(data.toObject());
        } else if (status == QLatin1String("error")) {
            // Refuz definitiv (anulat de client, fonduri insuficiente): nu are
            // rost să reîncercăm, doar am bloca chelnerul.
            const QJsonObject d = data.toObject();
            QString reason = d.value(QStringLiteral("error")).toString();
            if (reason.isEmpty())
                reason = d.value(QStringLiteral("status")).toString();
            emit cardCheckDeclined(reason);
        } else {
            emit cardCheckNotReady();
        }
    });
}

QJsonObject SmartOneClient::buildSalePayload(int payId,
                                             const QVariantList &lines,
                                             double total,
                                             const QString &payType,
                                             double change,
                                             const QString &employeeName)
{
    QJsonObject root;
    root[QStringLiteral("date")] = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));
    // docNumber = payId, contorul nostru intern (QSettings fiscal/nextPayId),
    // NU numărul comenzii: acela a fost încercat și terminalul îl refuză
    // ("Invalid docNumber '382766'"), validându-l față de propria secvență.
    // Idempotența se păstrează prin pending_fiscal.json, care ține payId-ul: o
    // reluare după cădere retrimite exact același număr, iar SmartOne răspunde
    // 409 ("document deja existent") în loc să emită un al doilea bon.
    //
    // Nu confunda cu numărul întors de /sale (data.document_number, în mii) —
    // ăla e documentul din memoria fiscală, cheia pentru /print_check. Iar pe
    // hârtie aparatul tipărește un al TREILEA număr ("BON # 24"), nedocumentat
    // în contract; dacă ai nevoie de corespondența cu hârtia, întâi află care
    // din ele e (verificat 2026-08-04: 2555 în memoria fiscală ≠ BON # 24).
    root[QStringLiteral("docNumber")] = QString::number(payId);
    root[QStringLiteral("employeeName")] = employeeName.trimmed().isEmpty()
        ? QStringLiteral("Chelner") : employeeName.trimmed();
    root[QStringLiteral("departmentName")] = QStringLiteral("Restaurant");
    root[QStringLiteral("amount")] = toBani(total);
    root[QStringLiteral("currency")] = QStringLiteral("MDL");
    root[QStringLiteral("printFooter")] = QStringLiteral("Multumim pentru vizita!\nuna.md");
    root[QStringLiteral("genPreview")] = false;

    QJsonArray items;
    QMap<QString, QJsonObject> taxSummary;

    for (const QVariant &lineVar : lines) {
        const QVariantMap line = lineVar.toMap();

        const double qty = line.value(QStringLiteral("CANT")).toDouble();
        const double unitPrice = line.value(QStringLiteral("CLCPRETT")).toDouble();
        // Suma liniei vine calculată de Oracle; o folosim ca atare în loc s-o
        // recalculăm, ca bonul fiscal să nu poată diverge de comandă din cauza
        // rotunjirilor.
        const double lineTotal = line.value(QStringLiteral("CLCSUMAT")).toDouble();

        if (qty <= 0.0)
            continue;

        QString letter;
        int prcX100 = 0;
        double rate = 0.0;
        const bool knownLetter =
            taxForCode(line.value(QStringLiteral("CODTVA")).toString(), &letter, &prcX100, &rate);

        // Dacă backend-ul trimite cota (`TVA_PRC`), o preferăm celei din cod -
        // o constantă fiscală compilată în APK e exact ce n-ar trebui să existe.
        //
        // ⚠️ AZI COLOANA NU E TRIMISĂ, INTENȚIONAT. Fusese scrisă în
        // `get_order_lines` ca `Unirest_Util.vat_percent_by_letter(codtva)` și
        // RETRASĂ înainte de compilare: funcția aia întoarce 10 pentru C, adică
        // valoarea care contrazice și aparatul (tipărește 6), și contabilitatea
        // UAMenu (`TVA_C` = 6). O valoare greșită luată din bază e mai rea decât
        // una corectă din cod, pentru că arată autoritară.
        //
        // Codul rămâne aici pentru ziua în care există o sursă în care se poate
        // avea încredere. **Înainte s-o reactivezi, verifică ce întoarce.**
        //
        // Zero e o cotă VALIDĂ (litera '0'), deci se verifică steagul de
        // conversie, nu valoarea: un `dbPrc == 0` aruncat tăcut ar fi exact
        // singurul caz în care coloana chiar spune "fără TVA".
        bool prcOk = false;
        const double dbPrc = line.value(QStringLiteral("TVA_PRC")).toDouble(&prcOk);
        if (knownLetter && prcOk && dbPrc >= 0.0 && dbPrc <= 100.0) {
            prcX100 = static_cast<int>(qRound(dbPrc * 100.0));
            rate = dbPrc / 100.0;
        }

        const int amountBani = toBani(lineTotal);
        const int taxBani = taxFromInclusive(amountBani, rate);

        // Ce declarăm noi pentru TVA, vizibil în logcat. Nu e depanare
        // temporară: fără el nu se poate deosebi "aparatul tipărește ce-i
        // trimitem" de "aparatul are tabelul lui" decât ghicind - iar
        // presupunerea greșită aici înseamnă bonuri cu altă cotă decât comanda.
        // Cu linia asta, un singur bon real răspunde definitiv: compari ce scrie
        // aici cu ce e tipărit pe hârtie.
        qInfo("[SmartOne][TVA] cod=%s litera=%s cota=%d.%02d%% sursa=%s "
              "suma=%d bani tva=%d bani",
              qPrintable(line.value(QStringLiteral("CODTVA")).toString()),
              qPrintable(letter),
              prcX100 / 100, prcX100 % 100,
              (knownLetter && prcOk) ? "ORACLE" : "rezerva-din-cod",
              amountBani, taxBani);

        QJsonObject tax;
        tax[QStringLiteral("taxName")] = QStringLiteral("TVA ") + letter;
        tax[QStringLiteral("taxCode")] = letter;
        tax[QStringLiteral("taxPrc")] = prcX100;
        tax[QStringLiteral("amount")] = amountBani;
        tax[QStringLiteral("taxAmount")] = taxBani;
        tax[QStringLiteral("calcType")] = 1;

        QJsonArray taxes;
        taxes.append(tax);

        QJsonObject item;
        item[QStringLiteral("itemId")] = QStringLiteral("7");
        item[QStringLiteral("itemName")] = line.value(QStringLiteral("CLCBLIUDAT")).toString();
        item[QStringLiteral("itemQty")] = static_cast<int>(qRound(qty * 1000.0));
        item[QStringLiteral("itemPrice")] = toBani(unitPrice);
        item[QStringLiteral("itemAmount")] = amountBani;
        item[QStringLiteral("discount")] = 0;
        item[QStringLiteral("taxes")] = taxes;
        items.append(item);

        // Sumarul global aduna taxele DEJA ROTUNJITE ale liniilor, deci poate
        // sa iasa cu un ban fata de cum ar calcula Oracle (care rotunjeste o
        // singura data, pe totalul cotei). Lasat ASA INTENTIONAT: varianta
        // "corecta" ar face suma taxelor pe linii sa nu mai fie egala cu blocul
        // global, iar daca aparatul verifica exact asta, bonul ar fi respins -
        // si n-avem cum sa testam pe terminal de aici. Se schimba doar cu un
        // aparat real in fata.
        if (!taxSummary.contains(letter)) {
            taxSummary.insert(letter, tax);
        } else {
            QJsonObject &acc = taxSummary[letter];
            acc[QStringLiteral("amount")] = acc.value(QStringLiteral("amount")).toInt() + amountBani;
            acc[QStringLiteral("taxAmount")] = acc.value(QStringLiteral("taxAmount")).toInt() + taxBani;
        }
    }

    root[QStringLiteral("items")] = items;

    QJsonArray globalTaxes;
    for (const QJsonObject &t : taxSummary.values())
        globalTaxes.append(t);
    root[QStringLiteral("taxes")] = globalTaxes;

    QJsonObject payment;
    payment[QStringLiteral("type")] = payType;
    payment[QStringLiteral("name")] = paymentName(payType);
    payment[QStringLiteral("amount")] = toBani(total);
    payment[QStringLiteral("change")] = toBani(change);

    QJsonArray payments;
    payments.append(payment);
    root[QStringLiteral("payments")] = payments;

    return root;
}

void SmartOneClient::fiscalSaleAndPrint(int payId,
                                        const QVariantList &lines,
                                        double total,
                                        const QString &payType,
                                        double change,
                                        const QString &employeeName,
                                        bool printOnConflict)
{
    const QJsonObject root = buildSalePayload(payId, lines, total, payType, change, employeeName);

    QNetworkRequest req { QUrl(QString(kFiscalBase) + "/sale") };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QNetworkReply *reply = m_network->post(req, QJsonDocument(root).toJson(QJsonDocument::Compact));

    QTimer::singleShot(kFiscalSaleTimeoutMs, reply, [reply]() {
        if (reply && reply->isRunning()) {
            reply->setProperty("fiscalSaleTimedOut", true);
            reply->abort();
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, payId, printOnConflict]() {
        const bool timedOut = reply->property("fiscalSaleTimedOut").toBool();
        const QString netError = (reply->error() != QNetworkReply::NoError)
            ? reply->errorString() : QString();
        const QByteArray response = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        // 409 = documentul există deja la SmartOne. Se întâmplă la reluarea
        // unei plăți întrerupte: bonul a fost deja emis, deci îl tratăm ca
        // succes și mergem la tipărire, nu re-emitem.
        if (httpStatus == 409) {
            // Numărul REAL al documentului se caută întâi în corpul răspunsului.
            // `m_lastDocumentNumber` e doar memorie de proces: după o repornire
            // (exact cazul în care ajungem la 409) e gol, iar vechea rezervă
            // scria `payId` - CONTORUL NOSTRU INTERN - drept număr de document
            // fiscal. Ajungea așa în uw_fiscal_receipts: o valoare mică, care nu
            // corespunde niciunui document din memoria fiscală (documentele
            // reale sunt în ordinul miilor) și nu poate fi urmărită.
            QString doc = QJsonDocument::fromJson(response)
                .object().value(QStringLiteral("data")).toObject()
                .value(QStringLiteral("document_number")).toString().trimmed();

            if (doc.isEmpty())
                doc = m_lastDocumentNumber.trimmed();

            if (doc.isEmpty()) {
                // Rezerva rămâne, pentru că `isCommitted()` se sprijină pe un
                // număr nevid: fără el, recuperarea ar crede că vânzarea nu s-a
                // comis și ar retrimite /sale la nesfârșit, primind mereu 409.
                // ⚠️ De verificat pe terminal ce întoarce SmartOne în corpul lui
                // 409 - dacă dă numărul, ramura asta nu se mai atinge niciodată.
                doc = QString::number(payId);
                qWarning("[SmartOne] 409 fara document_number: folosim payId %d "
                         "ca marcaj - numarul fiscal real ramane necunoscut", payId);
            }

            m_lastDocumentNumber = doc;

            if (!printOnConflict) {
                emit fiscalDocumentAlreadyExists(doc);
                return;
            }

            emit fiscalDocumentCommitted(doc);

            QJsonObject printBody;
            printBody[QStringLiteral("document_number")] = doc;
            printBody[QStringLiteral("operation")] = QStringLiteral("sale");
            sendPrintCheck(printBody, true);
            return;
        }

        QJsonParseError perr {};
        const QJsonDocument respDoc = QJsonDocument::fromJson(response, &perr);
        if (perr.error != QJsonParseError::NoError || respDoc.isNull()) {
            QString reason;
            if (timedOut) {
                reason = tr("The payment was confirmed, but the fiscal service did not respond when "
                            "issuing the receipt. Do NOT repeat the payment - the receipt must be reissued.");
            } else {
                reason = netError.isEmpty()
                    ? tr("Invalid response from the fiscal service.") : netError;
            }
            emit fiscalPrintFailed(reason);
            return;
        }

        const QJsonObject rootObj = respDoc.object();
        const QJsonObject dataObj = rootObj.value(QStringLiteral("data")).toObject();
        const QString docNum = dataObj.value(QStringLiteral("document_number")).toString().trimmed();

        if (docNum.isEmpty()) {
            QString msg = rootObj.value(QStringLiteral("message")).toString(
                dataObj.value(QStringLiteral("message")).toString());
            if (msg.trimmed().isEmpty())
                msg = tr("The fiscal service did not return a document number.");
            emit fiscalPrintFailed(msg);
            return;
        }

        // Avem document_number: vânzarea e COMISĂ în memoria fiscală. Din acest
        // punct o eventuală eroare de tipărire se rezolvă prin re-tipărire,
        // niciodată prin re-emitere.
        m_lastDocumentNumber = docNum;
        emit fiscalDocumentCommitted(docNum);

        QJsonObject printBody;
        printBody[QStringLiteral("document_number")] = docNum;
        printBody[QStringLiteral("operation")] = QStringLiteral("sale");

        // Mica pauză înainte de tipărire - preluată din UNARetail, unde
        // /print_check imediat după /sale prindea uneori imprimanta ocupată.
        QTimer::singleShot(1500, this, [this, printBody]() {
            sendPrintCheck(printBody, true);
        });
    });
}

void SmartOneClient::reprintDocument(const QString &documentNumber)
{
    const QString doc = documentNumber.trimmed().isEmpty()
        ? m_lastDocumentNumber.trimmed() : documentNumber.trimmed();

    if (doc.isEmpty()) {
        emit fiscalPrintFailed(tr("There is no document to reprint."));
        return;
    }

    QJsonObject body;
    body[QStringLiteral("document_number")] = doc;
    body[QStringLiteral("operation")] = QStringLiteral("sale");
    sendPrintCheck(body, false);
}

void SmartOneClient::sendPrintCheck(const QJsonObject &body, bool allowRetry)
{
    QNetworkRequest req { QUrl(QString(kFiscalBase) + "/print_check") };
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QNetworkReply *reply = m_network->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    QTimer::singleShot(kPrintCheckTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, body, allowRetry]() {
        const bool netError = (reply->error() != QNetworkReply::NoError);
        const QString errorString = reply->errorString();
        const QByteArray response = reply->readAll();
        reply->deleteLater();

        if (netError) {
            if (allowRetry) {
                // O singură reîncercare: imprimanta poate fi ocupată o clipă.
                QTimer::singleShot(2000, this, [this, body]() {
                    sendPrintCheck(body, false);
                });
                return;
            }
            emit fiscalPrintFailed(errorString.isEmpty()
                ? tr("Network error while printing the receipt.") : errorString);
            return;
        }

        handlePrintResponse(response);
    });
}

void SmartOneClient::handlePrintResponse(const QByteArray &response)
{
    QJsonParseError perr {};
    const QJsonDocument doc = QJsonDocument::fromJson(response, &perr);
    if (perr.error != QJsonParseError::NoError || doc.isNull()) {
        emit fiscalPrintFailed(tr("Invalid response while printing the receipt."));
        return;
    }

    const QJsonObject rootObj = doc.object();
    const QJsonObject dataObj = rootObj.value(QStringLiteral("data")).toObject();

    const int printStatus = dataObj.value(QStringLiteral("printStatus"))
                                .toInt(std::numeric_limits<int>::min());
    const int errorCode = dataObj.value(QStringLiteral("errorCode"))
                              .toInt(rootObj.value(QStringLiteral("errorCode")).toInt(0));
    const QString statusMsg = dataObj.value(QStringLiteral("statusMessage")).toString();
    const QString errorText = dataObj.value(QStringLiteral("errorText")).toString();
    const QString messageStr = rootObj.value(QStringLiteral("message")).toString(
        dataObj.value(QStringLiteral("message")).toString());

    QString reason = statusMsg;
    if (reason.isEmpty())
        reason = errorText;
    if (reason.isEmpty())
        reason = messageStr;

    const bool explicitError = (errorCode > 0)
        || rootObj.value(QStringLiteral("error")).toBool(false)
        || dataObj.value(QStringLiteral("error")).toBool(false)
        || statusMsg.contains(QLatin1String("no paper"), Qt::CaseInsensitive)
        || statusMsg.contains(QLatin1String("fara hartie"), Qt::CaseInsensitive)
        || errorText.contains(QLatin1String("no paper"), Qt::CaseInsensitive)
        || errorText.contains(QLatin1String("fara hartie"), Qt::CaseInsensitive);

    const bool okRoot = rootObj.value(QStringLiteral("ok")).toBool(false)
        || rootObj.value(QStringLiteral("success")).toBool(false);
    const bool okData = dataObj.value(QStringLiteral("ok")).toBool(false)
        || dataObj.value(QStringLiteral("success")).toBool(false)
        || dataObj.value(QStringLiteral("printed")).toBool(false);
    const bool statusOK = (printStatus == 1) || (printStatus == 0);
    const bool messageOK = (messageStr.compare(QLatin1String("OK"), Qt::CaseInsensitive) == 0);
    const bool hasDoc = !dataObj.value(QStringLiteral("document_number")).toString().trimmed().isEmpty();

    if (explicitError) {
        emit fiscalPrintFailed(reason.trimmed().isEmpty()
            ? tr("Printing the receipt failed - check the paper roll.") : reason.trimmed());
        return;
    }

    if (okRoot || okData || statusOK || messageOK || (hasDoc && reason.trimmed().isEmpty())) {
        emit fiscalPrintSuccessful();
        return;
    }

    emit fiscalPrintFailed(reason.trimmed().isEmpty()
        ? tr("Printing the receipt failed - check the paper roll.") : reason.trimmed());
}
