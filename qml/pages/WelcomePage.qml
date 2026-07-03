import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root

    property var theme

    signal authenticateRequested()
    signal demoRequested()

    background: Rectangle {
        color: theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        Label {
            text: "Bine ați venit"
            font.pixelSize: 24
            font.bold: true
            color: theme.textPrimary
        }

        Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

        Label {
            text: "🍴"
            font.pixelSize: 56
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "Bine ați venit"
            font.pixelSize: 22
            font.bold: true
            color: theme.textPrimary
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "Alegeți cum doriți să începeți"
            font.pixelSize: 15
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
                text: "Autentificare"
                color: theme.primary
                font.pixelSize: 16
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
                text: "Demo"
                color: theme.textPrimary
                font.pixelSize: 16
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.demoRequested()
            }
        }
    }
}
