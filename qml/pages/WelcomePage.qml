import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
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

            Label {
                text: qsTr("Welcome")
                font.pixelSize: 24 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Item { Layout.fillWidth: true }

            Icons.IconSettings {
                color: Theme.textPrimary
                dark: Theme.darkMode
                onClicked: root.settingsRequested()
            }
        }

        Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

        Label {
            text: "🍴"
            font.pixelSize: 56 * Theme.fontScale
            Layout.alignment: Qt.AlignHCenter
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

            MouseArea {
                anchors.fill: parent
                onClicked: root.authenticateRequested()
            }
        }
    }
}
