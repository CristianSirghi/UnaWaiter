import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"

// Meniu lateral (hamburger) — Profil / Setări / Stocuri / Deconectare.
// Folosește Drawer-ul standard Qt Quick Controls (edge-swipe, dimming,
// back-button de închidere — toate incluse), nu ceva desenat manual.
Drawer {
    id: root

    property var theme
    property var settings

    signal profileRequested()
    signal settingsRequested()
    signal stockRequested()
    signal signOutRequested()

    width: Math.min(300, (parent ? parent.width : 300) * 0.82)
    height: parent ? parent.height : 0
    edge: Qt.LeftEdge

    background: Rectangle {
        color: root.theme.background
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
                color: root.theme.primary

                Label {
                    anchors.centerIn: parent
                    text: root.settings.waiterName.length > 0
                        ? root.settings.waiterName.charAt(0).toUpperCase()
                        : "W"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18 * root.theme.fontScale
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: root.settings.waiterName
                font.pixelSize: 17 * root.theme.fontScale
                font.bold: true
                color: root.theme.textPrimary
                elide: Text.ElideRight
            }

            IconClose {
                color: root.theme.textSecondary

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
            color: root.theme.border
        }

        // ----- Profil -----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconPerson {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    color: root.theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Profile")
                    font.pixelSize: 15 * root.theme.fontScale
                    color: root.theme.textPrimary
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
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: root.theme.darkMode ? "qrc:/icons/settings_white.png" : "qrc:/icons/settings.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Settings")
                    font.pixelSize: 15 * root.theme.fontScale
                    color: root.theme.textPrimary
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
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconStock {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    color: root.theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Stock")
                    font.pixelSize: 15 * root.theme.fontScale
                    color: root.theme.textPrimary
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

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            height: 1
            color: root.theme.border
        }

        // ----- Deconectare -----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 14

                IconLogout {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    dark: root.theme.darkMode
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Sign out")
                    font.pixelSize: 15 * root.theme.fontScale
                    color: root.theme.textPrimary
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
