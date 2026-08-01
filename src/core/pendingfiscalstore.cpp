#include "pendingfiscalstore.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

QString PendingFiscalStore::filePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/pending_fiscal.json");
}

bool PendingFiscalStore::save(const PendingFiscal &data)
{
    QJsonObject obj;
    obj[QStringLiteral("nrComand")] = data.nrComand;
    obj[QStringLiteral("payId")] = data.payId;
    obj[QStringLiteral("payType")] = data.payType;
    obj[QStringLiteral("total")] = data.total;
    obj[QStringLiteral("paid")] = data.paid;
    obj[QStringLiteral("change")] = data.change;
    obj[QStringLiteral("documentNumber")] = data.documentNumber;
    obj[QStringLiteral("phase")] = data.phase;
    obj[QStringLiteral("oraclePaid")] = data.oraclePaid;
    obj[QStringLiteral("oficiant")] = data.oficiant;
    obj[QStringLiteral("employeeName")] = data.employeeName;
    obj[QStringLiteral("rrn")] = data.rrn;
    obj[QStringLiteral("timestamp")] = data.timestamp.isEmpty()
        ? QDateTime::currentDateTime().toString(Qt::ISODate)
        : data.timestamp;
    obj[QStringLiteral("lines")] = QJsonArray::fromVariantList(data.lines);

    const QByteArray json = QJsonDocument(obj).toJson(QJsonDocument::Compact);

    // Scriem într-un temporar și abia apoi îl mutăm peste cel real: rename-ul
    // e atomic, deci fișierul final e ori complet vechi, ori complet nou -
    // niciodată trunchiat.
    const QString target = filePath();
    const QString tmp = target + QStringLiteral(".tmp");

    QFile f(tmp);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    if (f.write(json) != json.size()) {
        f.close();
        f.remove();
        return false;
    }
    f.flush();
    f.close();

    // QFile::rename nu suprascrie pe Windows, deci ștergem ținta întâi.
    if (QFile::exists(target))
        QFile::remove(target);

    return QFile::rename(tmp, target);
}

bool PendingFiscalStore::load(PendingFiscal &out)
{
    QFile f(filePath());
    if (!f.open(QIODevice::ReadOnly))
        return false;

    const QByteArray raw = f.readAll();
    f.close();

    QJsonParseError err {};
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QJsonObject obj = doc.object();
    out.nrComand = obj.value(QStringLiteral("nrComand")).toInt(-1);
    out.payId = obj.value(QStringLiteral("payId")).toInt(-1);
    out.payType = obj.value(QStringLiteral("payType")).toString();
    out.total = obj.value(QStringLiteral("total")).toDouble();
    out.paid = obj.value(QStringLiteral("paid")).toDouble();
    out.change = obj.value(QStringLiteral("change")).toDouble();
    out.documentNumber = obj.value(QStringLiteral("documentNumber")).toString();
    out.phase = obj.value(QStringLiteral("phase")).toString();
    out.oraclePaid = obj.value(QStringLiteral("oraclePaid")).toBool(false);
    out.oficiant = obj.value(QStringLiteral("oficiant")).toString();
    out.employeeName = obj.value(QStringLiteral("employeeName")).toString();
    out.rrn = obj.value(QStringLiteral("rrn")).toString();
    out.timestamp = obj.value(QStringLiteral("timestamp")).toString();
    out.lines = obj.value(QStringLiteral("lines")).toArray().toVariantList();

    return out.isValid();
}

bool PendingFiscalStore::exists()
{
    return QFile::exists(filePath());
}

void PendingFiscalStore::remove()
{
    QFile::remove(filePath());
}
