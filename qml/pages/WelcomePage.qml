import QtQuick 2.15
import QtQuick.Window 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root


    signal authenticateRequested()
    signal settingsRequested()

    background: Rectangle {
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2

                Image {
                    id: unaLogo
                    property real logoHeight: 38 * Theme.fontScale
                    property real logoWidth: logoHeight * (660 / 249)

                    source: "qrc:/icons/una_logo.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    Layout.preferredHeight: logoHeight
                    Layout.preferredWidth: logoWidth
                    sourceSize.width: logoWidth * Screen.devicePixelRatio
                    sourceSize.height: logoHeight * Screen.devicePixelRatio
                }

                Label {
                    text: "UNA.md | HoReCa"
                    font.pixelSize: 11 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }

            Item { Layout.fillWidth: true }

            Icons.IconSettings {
                color: Theme.textPrimary
                dark: Theme.darkMode
                onClicked: root.settingsRequested()
            }
        }

        Item { Layout.preferredHeight: 32 }

        Image {
            property real iconSize: 128 * Theme.fontScale

            source: "qrc:/icons/hand_waiter.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            Layout.preferredWidth: iconSize
            Layout.preferredHeight: iconSize
            Layout.alignment: Qt.AlignHCenter
            sourceSize.width: iconSize * Screen.devicePixelRatio
            sourceSize.height: iconSize * Screen.devicePixelRatio
        }

        Label {
            text: qsTr("Welcome")
            font.pixelSize: 22 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: qsTr("Choose how you'd like to start")
            font.pixelSize: 15 * Theme.fontScale
            color: Theme.textSecondary
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 26
            color: Theme.surface

            Label {
                anchors.centerIn: parent
                text: qsTr("Sign in")
                color: Theme.primary
                font.pixelSize: 16 * Theme.fontScale
                font.bold: true
            }

            Components.TouchArea {
                anchors.fill: parent
                onClicked: root.authenticateRequested()
            }
        }
    }
}
