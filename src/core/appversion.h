#pragma once

#include <QString>

// Single source of truth for the app's display version. UnaWaiter.pro parses
// this exact line (regex) to fill in AndroidManifest.xml's versionName /
// versionCode at build time (see D:\MMOffline for the same pattern) - so bump
// the version by editing ONLY this line, nowhere else.
const char VERSION[] = "0.1";

inline QString appVersionText()
{
    return QString::fromLatin1(VERSION);
}
