import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components

Page {
    id: root

    property var theme
    property var settings

    background: Rectangle {
        color: theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 12 }

        Components.BackButton {
            color: theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.preferredWidth: 8 }

        Label {
            text: qsTr("Settings")
            font.pixelSize: 20 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 28

        // ----- Limbă -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: qsTr("Language")
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Components.SegmentedControl {
                Layout.fillWidth: true
                theme: root.theme
                currentValue: root.settings.language
                options: [
                    { label: "Română", value: "ro" },
                    { label: "English", value: "en" },
                    { label: "Русский", value: "ru" }
                ]
                onOptionSelected: root.settings.language = value
            }
        }

        // ----- Temă -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: qsTr("Theme")
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Components.SegmentedControl {
                Layout.fillWidth: true
                theme: root.theme
                currentValue: root.theme.darkMode ? "dark" : "light"
                options: [
                    { label: qsTr("Light"), value: "light" },
                    { label: qsTr("Dark"), value: "dark" }
                ]
                onOptionSelected: root.theme.darkMode = (value === "dark")
            }
        }

        // ----- Mărime text -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: qsTr("Text size")
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Components.SegmentedControl {
                Layout.fillWidth: true
                theme: root.theme
                currentValue: root.theme.fontScale
                options: [
                    { label: qsTr("Small"), value: 0.9 },
                    { label: qsTr("Medium"), value: 1.0 },
                    { label: qsTr("Large"), value: 1.15 }
                ]
                onOptionSelected: root.theme.fontScale = value
            }
        }

        Item { Layout.fillHeight: true }
    }
}
