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
// de SmartOne, deci nu e nevoie de traducere - doar de procent. Pe producție
// apar 'C' (8%, mâncare) și 'A' (20%).
void taxForCode(const QString &code, QString *letter, int *prcX100, double *rate)
{
    const QString c = code.trimmed().toUpper();
    if (c == QLatin1String("0")) {
        *letter = QStringLiteral("0"); *prcX100 = 0;    *rate = 0.00;
    } else if (c == QLatin1String("B")) {
        *letter = QStringLiteral("B"); *prcX100 = 1200; *rate = 0.12;
    } else if (c == QLatin1String("C")) {
        *letter = QStringLiteral("C"); *prcX100 = 800;  *rate = 0.08;
    } else {
        // 'A' și orice necunoscut -> cota standard. Mai bine să declarăm prea
        // mult TVA decât prea puțin dacă apare un cod nou în meniu.
        *letter = QStringLiteral("A"); *prcX100 = 2000; *rate = 0.20;
    }
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
    QNetworkReply *reply = m_network->get(QNetworkRequest(QUrl(QString(kFiscalBase) + "/check-shift")));

    QTimer::singleShot(kProbeTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const bool missing = serviceMissing(reply);
        reply->deleteLater();
        emit fiscalServiceProbed(!missing);
    });
}

void SmartOneClient::probePosService()
{
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
            emit fiscalPrintFailed(tr("The fiscal service is not available on this terminal. "
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
    // docNumber = numărul comenzii: cheie de idempotență naturală. La o reluare
    // după cădere trimitem exact același număr, iar SmartOne răspunde 409
    // ("document deja existent") în loc să emită un al doilea bon.
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
        taxForCode(line.value(QStringLiteral("CODTVA")).toString(), &letter, &prcX100, &rate);

        const int amountBani = toBani(lineTotal);
        const int taxBani = static_cast<int>(qRound(amountBani * rate));

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
            const QString doc = m_lastDocumentNumber.trimmed().isEmpty()
                ? QString::number(payId) : m_lastDocumentNumber;
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
