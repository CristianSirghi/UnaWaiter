#include "translationmanager.h"

#include <QCoreApplication>
#include <QQmlApplicationEngine>

TranslationManager::TranslationManager(QQmlApplicationEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
}

void TranslationManager::setLanguage(const QString &languageCode)
{
    qApp->removeTranslator(&m_translator);

    // Sursa qsTr() e în engleză, deci "en" nu are nevoie de niciun .qm încărcat.
    if (languageCode != QLatin1String("en")) {
        const QString qmFile = QStringLiteral("waiter_%1").arg(languageCode);
        if (m_translator.load(qmFile, QStringLiteral(":/i18n")))
            qApp->installTranslator(&m_translator);
    }

    m_engine->retranslate();
}
