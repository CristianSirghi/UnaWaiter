import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components

Page {
    id: root

    property var theme

    signal authenticateRequested()
    signal demoRequested()
    signal settingsRequested()

    background: Rectangle {
        color: theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: qsTr("Welcome")
                font.pixelSize: 24 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Item { Layout.fillWidth: true }

            Components.IconSettings {
                color: theme.textPrimary
                dark: theme.darkMode
                onClicked: root.settingsRequested()
            }
        }

        Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

        Label {
            text: "🍴"
            font.pixelSize: 56 * theme.fontScale
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: qsTr("Welcome")
            font.pixelSize: 22 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: qsTr("Choose how you'd like to start")
            font.pixelSize: 15 * theme.fontScale
            color: theme.textSecondary
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 26
            color: theme.surface

            Label {
                anchors.centerIn: parent
                text: qsTr("Sign in")
                color: theme.primary
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.authenticateRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 26
            color: "transparent"
            border.color: theme.border

            Label {
                anchors.centerIn: parent
                text: qsTr("Demo")
                color: theme.textPrimary
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.demoRequested()
            }
        }
    }
}
