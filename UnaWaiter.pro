QT += quick qml gui core network
CONFIG += release

# Include paths for C++ headers
INCLUDEPATH += \
    src \
    src/core

HEADERS += \
    src/core/translationmanager.h \
    src/core/dataservice.h \
    src/core/appversion.h \
    src/core/updatemanager.h

SOURCES += \
    src/main.cpp \
    src/core/translationmanager.cpp \
    src/core/dataservice.cpp \
    src/core/updatemanager.cpp

# Sursa unica a versiunii afisate (src/core/appversion.h) - de-acolo se
# completeaza automat versionName/versionCode in AndroidManifest.xml
# (placeholder-ele %%INSERT_VERSION_NAME%%/%%INSERT_VERSION_CODE%%). Bumpuiesti
# versiunea intr-un singur loc: linia "const char VERSION[]" din appversion.h.
APP_VERSION_HEADER = $$PWD/src/core/appversion.h
APP_VERSION_HEADER_LINES = $$cat($$APP_VERSION_HEADER, lines)

for(line, APP_VERSION_HEADER_LINES) {
    contains(line, "^const char VERSION\\[\\] = \".*\";$") {
        APP_DISPLAY_VERSION = $$replace(line, "^const char VERSION\\[\\] = \"([^\"]+)\";$", "\\1")
    }
}

isEmpty(APP_DISPLAY_VERSION): error("Could not read VERSION from src/core/appversion.h")

VERSION = $$APP_DISPLAY_VERSION
ANDROID_VERSION_NAME = $$APP_DISPLAY_VERSION
ANDROID_VERSION_CODE = $$replace(APP_DISPLAY_VERSION, "\\D", "")

RESOURCES += resources/qml.qrc

TRANSLATIONS += \
    translations/waiter_en.ts \
    translations/waiter_ro.ts \
    translations/waiter_ru.ts

# Additional import path used to resolve QML modules in Qt Creator's code model
#QML_IMPORT_PATH =

# Additional import path used to resolve QML modules just for Qt Quick Designer
#QML_DESIGNER_IMPORT_PATH =

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target

android {
    ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
    QT += androidextras
}

DISTFILES += \
    android/AndroidManifest.xml \
    android/build.gradle \
    android/gradle.properties \
    android/gradle/wrapper/gradle-wrapper.jar \
    android/gradle/wrapper/gradle-wrapper.properties \
    android/gradlew \
    android/gradlew.bat \
    android/res/values/libs.xml \
    android/src/org/qtproject/UnaWaiter/UnaWaiterActivity.java \
    android/src/org/qtproject/UnaWaiter/UpdateHelper.java
