#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "translationmanager.h"
#include "printermanager.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/"));

    TranslationManager translationManager(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("translationManager"), &translationManager);

    PrinterManager printerManager;
    engine.rootContext()->setContextProperty(QStringLiteral("printerManager"), &printerManager);

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
