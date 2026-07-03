import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
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
            onNewTableRequested: stackView.push(selectTablePageComponent)
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
        }
    }
}
