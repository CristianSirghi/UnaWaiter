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
    // Motorul se dă separat de constructor (setEngine), NU în el: main.cpp are
    // nevoie ca acest obiect să fie declarat ÎNAINTEA motorului QML, ca să se
    // distrugă DUPĂ el. Vezi comentariul despre ordinea de distrugere din
    // main.cpp - la ieșire, obiectele expuse în QML trebuie să fie încă vii cât
    // timp motorul își demontează arborele.
    explicit TranslationManager(QObject *parent = nullptr);

    void setEngine(QQmlApplicationEngine *engine);

    Q_INVOKABLE void setLanguage(const QString &languageCode);

private:
    QQmlApplicationEngine *m_engine = nullptr;
    QTranslator m_translator;
};
