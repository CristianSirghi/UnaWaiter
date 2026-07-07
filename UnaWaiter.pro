QT += quick qml gui core network
CONFIG += release

# Include paths for C++ headers
INCLUDEPATH += \
    src

HEADERS += \
    src/translationmanager.h \
    src/printermanager.h

SOURCES += \
    src/main.cpp \
    src/translationmanager.cpp \
    src/printermanager.cpp

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
    android/src/org/qtproject/UnaWaiter/UnaWaiterActivity.java
