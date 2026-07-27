#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "translationmanager.h"
#include "dataservice.h"
#include "updatemanager.h"
#include "paymentcontroller.h"

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

    // ORDINEA DE DECLARARE CONTEAZĂ. Variabilele locale se distrug în ordine
    // INVERSĂ, iar motorul QML își demontează tot arborele de obiecte abia la
    // distrugerea lui. Dacă motorul ar fi declarat primul, s-ar distruge ULTIMUL
    // - adică QML-ul ar fi demontat după ce dataService/updateManager/
    // translationManager au dispărut deja, iar orice binding sau handler care
    // le atinge în acel moment ar citi memorie eliberată.
    //
    // Așa: serviciile trăiesc pe tot parcursul, motorul stă într-un bloc propriu
    // și moare la ieșirea din el, cât timp ele sunt încă vii.
    TranslationManager translationManager;
    DataService dataService;
    UpdateManager updateManager;
    // Declarat DUPĂ dataService: se distruge înaintea lui, deci nu ajunge
    // niciodată să-l atingă după ce a dispărut.
    PaymentController paymentController(&dataService);

    int exitCode = 0;
    {
        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral("qrc:/"));
        translationManager.setEngine(&engine);

        QQmlContext *ctx = engine.rootContext();
        ctx->setContextProperty(QStringLiteral("translationManager"), &translationManager);
        ctx->setContextProperty(QStringLiteral("dataService"), &dataService);
        ctx->setContextProperty(QStringLiteral("appUpdateManager"), &updateManager);
        ctx->setContextProperty(QStringLiteral("paymentController"), &paymentController);

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

        exitCode = app.exec();
    }

    return exitCode;
}
