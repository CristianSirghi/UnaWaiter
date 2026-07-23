#include "updatemanager.h"
#include "appversion.h"

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QStringList>

#ifdef Q_OS_ANDROID
#include <QtAndroid>
#include <QAndroidJniObject>
#include <QAndroidJniEnvironment>
#endif

UpdateManager::UpdateManager(QObject *parent)
    : QObject(parent)
{
    m_progressTimer.setInterval(700);
    connect(&m_progressTimer, &QTimer::timeout, this, &UpdateManager::pollDownloadProgress);
}

QString UpdateManager::currentVersion() const
{
    return appVersionText();
}

void UpdateManager::setBusy(bool value)
{
    if (m_busy == value)
        return;
    m_busy = value;
    emit busyChanged();
}

void UpdateManager::setChecking(bool value)
{
    if (m_checking == value)
        return;
    m_checking = value;
    emit checkingChanged();
}

void UpdateManager::setDownloadProgress(int value)
{
    if (value < 0)
        value = 0;
    if (value > 100)
        value = 100;
    if (m_downloadProgress == value)
        return;
    m_downloadProgress = value;
    emit downloadProgressChanged();
}

// Compara "1.10" vs "1.9" corect (numeric pe segmente, nu lexicografic).
bool UpdateManager::isRemoteNewer(const QString &remote, const QString &local) const
{
    const QStringList r = remote.split('.', Qt::SkipEmptyParts);
    const QStringList l = local.split('.', Qt::SkipEmptyParts);
    const int count = qMax(r.size(), l.size());
    for (int i = 0; i < count; ++i) {
        const int rv = (i < r.size()) ? r.at(i).trimmed().toInt() : 0;
        const int lv = (i < l.size()) ? l.at(i).trimmed().toInt() : 0;
        if (rv > lv)
            return true;
        if (rv < lv)
            return false;
    }
    return false; // egale
}

void UpdateManager::checkForUpdate(const QString &versionJsonUrl)
{
    if (m_checking)
        return;

    if (versionJsonUrl.trimmed().isEmpty()) {
        emit checkFailed(tr("Update check is not configured."));
        return;
    }

    setChecking(true);

    QNetworkRequest request{QUrl(versionJsonUrl)};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = m_net.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        setChecking(false);

        if (reply->error() != QNetworkReply::NoError) {
            emit checkFailed(reply->errorString());
            return;
        }

        const QByteArray body = reply->readAll();
        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
        if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
            emit checkFailed(tr("Invalid response from server."));
            return;
        }

        const QJsonObject obj = doc.object();
        const QString version = obj.value(QStringLiteral("version")).toString().trimmed();
        const QString url = obj.value(QStringLiteral("url")).toString().trimmed();
        const QString notes = obj.value(QStringLiteral("notes")).toString().trimmed();

        if (version.isEmpty() || url.isEmpty()) {
            emit checkFailed(tr("version.json is incomplete (missing version or url)."));
            return;
        }

        m_latestVersion = version;
        m_releaseNotes = notes;
        m_apkUrl = url;
        emit latestVersionChanged();

        if (isRemoteNewer(version, currentVersion()))
            emit updateAvailable(version, notes);
        else
            emit upToDate();
    });
}

void UpdateManager::downloadAndInstall()
{
    if (m_busy)
        return;

    if (m_apkUrl.isEmpty()) {
        emit downloadFailed(tr("No download URL is available."));
        return;
    }

#ifdef Q_OS_ANDROID
    const QString fileName = QStringLiteral("unawaiter_%1.apk").arg(m_latestVersion);

    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid()) {
        emit downloadFailed(tr("Android context is unavailable."));
        return;
    }

    QAndroidJniObject jUrl = QAndroidJniObject::fromString(m_apkUrl);
    QAndroidJniObject jFile = QAndroidJniObject::fromString(fileName);

    QAndroidJniObject::callStaticMethod<void>(
        "org/qtproject/UnaWaiter/UpdateHelper",
        "startUpdate",
        "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V",
        context.object(),
        jUrl.object<jstring>(),
        jFile.object<jstring>());

    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        emit downloadFailed(tr("Could not start the download."));
        return;
    }

    setDownloadProgress(0);
    setBusy(true);
    emit downloadStarted();
    m_progressTimer.start();
#else
    emit downloadFailed(tr("Automatic installation is available only on Android."));
#endif
}

void UpdateManager::pollDownloadProgress()
{
#ifdef Q_OS_ANDROID
    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid())
        return;

    // getProgress: >=0 procent in curs, 100 = gata, -1 = esuat.
    const jint progress = QAndroidJniObject::callStaticMethod<jint>(
        "org/qtproject/UnaWaiter/UpdateHelper",
        "getProgress",
        "(Landroid/content/Context;)I",
        context.object());

    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return;
    }

    if (progress < 0) {
        m_progressTimer.stop();
        setBusy(false);
        emit downloadFailed(tr("Download failed."));
        return;
    }

    setDownloadProgress(progress);

    if (progress >= 100) {
        m_progressTimer.stop();
        setBusy(false);
        // Sistemul Android afiseaza ecranul de instalare (lansat din Java).
        emit installLaunched();
    }
#endif
}
