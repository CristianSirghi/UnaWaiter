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
            text: "Setări"
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
                text: "Limbă"
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

            Label {
                Layout.fillWidth: true
                text: "Traducerile complete vor fi adăugate ulterior."
                font.pixelSize: 12 * theme.fontScale
                color: theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        // ----- Temă -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: "Temă"
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Components.SegmentedControl {
                Layout.fillWidth: true
                theme: root.theme
                currentValue: "light"
                options: [
                    { label: "Light", value: "light" },
                    { label: "Dark · în curând", value: "dark", enabled: false }
                ]
                onOptionSelected: {}
            }
        }

        // ----- Mărime text -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: "Mărime text"
                font.pixelSize: 16 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Components.SegmentedControl {
                Layout.fillWidth: true
                theme: root.theme
                currentValue: root.theme.fontScale
                options: [
                    { label: "Mic", value: 0.9 },
                    { label: "Mediu", value: 1.0 },
                    { label: "Mare", value: 1.15 }
                ]
                onOptionSelected: root.theme.fontScale = value
            }
        }

        Item { Layout.fillHeight: true }
    }
}
