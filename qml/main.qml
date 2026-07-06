import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0
import "pages" as Pages

ApplicationWindow {
    id: appWindow
    visible: true
    width: 400
    height: 860
    title: "UnaWaiter"

    readonly property bool isDesktopPlatform: Qt.platform.os === "windows"
        || Qt.platform.os === "osx"
        || Qt.platform.os === "linux"

    visibility: isDesktopPlatform ? Window.AutomaticVisibility : Window.AutomaticVisibility

    Theme {
        id: appTheme
    }

    OrdersStore {
        id: ordersStore
    }

    AppSettings {
        id: appSettings

        // Aplică limba curentă la pornire și de fiecare dată când se schimbă
        // din Setări — translationManager e expus din C++ (main.cpp).
        onLanguageChanged: translationManager.setLanguage(language)
        Component.onCompleted: translationManager.setLanguage(language)
    }

    Settings {
        // Persistă alegerile din Setări (limbă/temă/mărime text/nume chelner) între lansări.
        property alias language: appSettings.language
        property alias darkMode: appTheme.darkMode
        property alias fontScale: appTheme.fontScale
        property alias waiterName: appSettings.waiterName
    }

    background: Rectangle {
        color: appTheme.background
    }

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: Pages.WelcomePage {
            theme: appTheme
            onAuthenticateRequested: stackView.push(loginPageComponent)
            onDemoRequested: stackView.push(loginPageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
        }
    }

    Component {
        id: settingsPageComponent

        Pages.SettingsPage {
            theme: appTheme
            settings: appSettings
        }
    }

    Component {
        id: loginPageComponent

        Pages.LoginPage {
            theme: appTheme
            onLoginConfirmed: stackView.push(tablesPageComponent)
        }
    }

    Component {
        id: tablesPageComponent

        Pages.TablesPage {
            theme: appTheme
            settings: appSettings
            store: ordersStore
            onNewTableRequested: stackView.push(selectTablePageComponent)
            onOrderOpened: stackView.push(orderPageComponent, { zone: zone, tableNumber: tableNumber })
            onProfileRequested: stackView.push(profilePageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
            onStockRequested: stackView.push(stockPageComponent)
        }
    }

    Component {
        id: profilePageComponent

        Pages.ProfilePage {
            theme: appTheme
            settings: appSettings
        }
    }

    Component {
        id: stockPageComponent

        Pages.StockPage {
            theme: appTheme
        }
    }

    Component {
        id: selectTablePageComponent

        Pages.SelectTablePage {
            theme: appTheme
            onTableSelected: function(zone, tableNumber) {
                stackView.push(orderPageComponent, { zone: zone, tableNumber: tableNumber })
            }
        }
    }

    Component {
        id: orderPageComponent

        Pages.OrderPage {
            theme: appTheme
            settings: appSettings
            store: ordersStore
        }
    }
}
