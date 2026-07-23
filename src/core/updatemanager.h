#pragma once

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QTimer>

class QNetworkReply;

// Verifica daca exista o versiune mai noua a aplicatiei (un fisier
// version.json, la un URL primit din backend - vezi DataService::updateInfoUrl)
// si, la cerere, porneste descarcarea + instalarea APK-ului prin Android
// DownloadManager (cod nativ in UpdateHelper.java). Portat din D:\MMOffline
// (Networking/UpdateManager.*), adaptat: aici URL-ul e dat explicit la
// checkForUpdate() in loc de citit dintr-o tabela Settings locala - UnaWaiter
// nu are inca un cache local de settings, doar cere backend-ul direct.
//
// Pe desktop (Windows) verificarea ruleaza, dar instalarea efectiva e
// disponibila doar pe Android.
class UpdateManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY latestVersionChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY latestVersionChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(int downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)

public:
    explicit UpdateManager(QObject *parent = nullptr);

    QString currentVersion() const;
    QString latestVersion() const { return m_latestVersion; }
    QString releaseNotes() const { return m_releaseNotes; }
    bool busy() const { return m_busy; }
    bool checking() const { return m_checking; }
    int downloadProgress() const { return m_downloadProgress; }

    // Descarca versionJsonUrl si compara "version" din el cu currentVersion().
    Q_INVOKABLE void checkForUpdate(const QString &versionJsonUrl);

    // Porneste descarcarea + instalarea ultimei versiuni gasite (necesita checkForUpdate inainte).
    Q_INVOKABLE void downloadAndInstall();

signals:
    void updateAvailable(const QString &version, const QString &notes);
    void upToDate();
    void checkFailed(const QString &error);
    void downloadStarted();
    void downloadFailed(const QString &error);
    void installLaunched();

    void latestVersionChanged();
    void busyChanged();
    void checkingChanged();
    void downloadProgressChanged();

private:
    void setBusy(bool value);
    void setChecking(bool value);
    void setDownloadProgress(int value);
    bool isRemoteNewer(const QString &remote, const QString &local) const;
    void pollDownloadProgress();

    QNetworkAccessManager m_net;
    QTimer m_progressTimer;

    QString m_latestVersion;
    QString m_releaseNotes;
    QString m_apkUrl;

    bool m_busy = false;
    bool m_checking = false;
    int m_downloadProgress = 0;
};
