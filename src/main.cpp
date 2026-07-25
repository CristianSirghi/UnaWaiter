#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "translationmanager.h"
#include "dataservice.h"
#include "updatemanager.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
#ifdef Q_OS_ANDROID
    // Ascunde "picătura" albastră de selecție text nativă Android (handle-ul
    // QPA peste TextField-urile QML) - trebuie setat înainte de a construi
    // QGuiApplication.
    qputenv("QT_QPA_NO_TEXT_HANDLES", "1");
#endif
    QGuiApplication app(argc, argv);
    // Fara astea, Qt.labs.settings (Theme, AppSettings, OrdersStore) nu poate
    // determina calea de stocare pe Android si esueaza la initializare
    // ("QML Settings: Failed to initialize QSettings instance. Status code is: 1" -
    // vezi logcat). Trebuie setate INAINTE de a construi orice QSettings, deci
    // aici, imediat dupa QGuiApplication.
    QCoreApplication::setOrganizationName(QStringLiteral("Una"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("una.md"));
    QCoreApplication::setApplicationName(QStringLiteral("UnaWaiter"));

    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/"));

    TranslationManager translationManager(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("translationManager"), &translationManager);

    DataService dataService;
    engine.rootContext()->setContextProperty(QStringLiteral("dataService"), &dataService);

    UpdateManager updateManager;
    engine.rootContext()->setContextProperty(QStringLiteral("appUpdateManager"), &updateManager);

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
