#pragma once

#include <QObject>
#include <QTranslator>

class QQmlApplicationEngine;

// Încarcă/schimbă traducerea aplicației la runtime, apelat din QML
// (AppSettings.language) — fără repornirea aplicației.
class TranslationManager : public QObject
{
    Q_OBJECT

public:
    explicit TranslationManager(QQmlApplicationEngine *engine, QObject *parent = nullptr);

    Q_INVOKABLE void setLanguage(const QString &languageCode);

private:
    QQmlApplicationEngine *m_engine;
    QTranslator m_translator;
};
