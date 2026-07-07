import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

// Setari de aspect, pe care le poate schimba orice chelner (limba, tema,
// marime text). Setarile de sistem (server, imprimanta) sunt pe pagina
// separata Administrare, accesibila din randul de jos.
Page {
    id: root

    property var theme
    property var settings

    // Cerere de deschidere a paginii Administrare (tratata in main.qml).
    signal adminRequested()

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

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: contentColumn
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 22

            // Titlu de grup pentru setarile de aspect.
            Label {
                text: qsTr("Appearance")
                font.pixelSize: 12 * theme.fontScale
                font.bold: true
                color: theme.textSecondary
                // Litere spatiate, ca eticheta de sectiune.
                font.letterSpacing: 1.5
                font.capitalization: Font.AllUppercase
            }

            // ----- Limba -----
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

            // ----- Tema -----
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

            // ----- Marime text -----
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

            // Separator inainte de zona de administrare.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                height: 1
                color: theme.border
            }

            // Rand de navigare catre pagina Administrare (setari de sistem).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 14
                color: theme.surface
                border.width: 1
                border.color: theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Icons.IconSettings {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        dark: theme.darkMode
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: qsTr("Administration")
                            font.pixelSize: 15 * theme.fontScale
                            font.bold: true
                            color: theme.textPrimary
                        }

                        Label {
                            text: qsTr("Server, printer")
                            font.pixelSize: 12 * theme.fontScale
                            color: theme.textSecondary
                        }
                    }

                    Icons.IconChevron {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        color: theme.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.adminRequested()
                }
            }
        }
    }
}
