import QtQuick 2.15
import "../../theme"
import "../../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"

// Meniu lateral (hamburger) — Profil / Setări / Stocuri / Deconectare.
// Folosește Drawer-ul standard Qt Quick Controls (edge-swipe, dimming,
// back-button de închidere — toate incluse), nu ceva desenat manual.
Drawer {
    id: root


    signal profileRequested()
    signal settingsRequested()
    signal stockRequested()
    signal paidOrdersRequested()
    signal signOutRequested()

    width: Math.min(300, (parent ? parent.width : 300) * 0.82)
    height: parent ? parent.height : 0
    edge: Qt.LeftEdge

    background: Rectangle {
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 16

            Rectangle {
                width: 48
                height: 48
                radius: 24
                color: Theme.primary

                Label {
                    anchors.centerIn: parent
                    text: AppSettings.waiterName.length > 0
                        ? AppSettings.waiterName.charAt(0).toUpperCase()
                        : "W"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18 * Theme.fontScale
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: AppSettings.waiterName
                font.pixelSize: 17 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            IconClose {
                color: Theme.textSecondary

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: root.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            height: 1
            color: Theme.border
        }

        // ----- Profil -----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconPerson {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    color: Theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Profile")
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.profileRequested()
                }
            }
        }

        // ----- Setări -----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Theme.darkMode ? "qrc:/icons/settings_white.png" : "qrc:/icons/settings.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    sourceSize.width: width
                    sourceSize.height: height
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Settings")
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.settingsRequested()
                }
            }
        }

        // ----- Stocuri -----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconStock {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    color: Theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Stock")
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.stockRequested()
                }
            }
        }

        // ----- Achitate -----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconCheck {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    color: Theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Paid orders")
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.paidOrdersRequested()
                }
            }
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            height: 1
            color: Theme.border
        }

        // ----- Deconectare -----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconLogout {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    dark: Theme.darkMode
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Sign out")
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.close()
                    root.signOutRequested()
                }
            }
        }
    }
}
