import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

// Setari de aspect, pe care le poate schimba orice chelner (limba, tema,
// marime text). Setarile de sistem (server, imprimanta) sunt pe pagina
// separata Administrare, accesibila din randul de jos.
Page {
    id: root


    // Cerere de deschidere a paginii Administrare (tratata in main.qml).
    signal adminRequested()
    // Cerere de deschidere a paginii Actualizari (tratata in main.qml).
    signal updateRequested()

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 12 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.preferredWidth: 8 }

        Label {
            text: qsTr("Settings")
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
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
                font.pixelSize: 12 * Theme.fontScale
                font.bold: true
                color: Theme.textSecondary
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
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Components.SegmentedControl {
                    Layout.fillWidth: true
                    currentValue: AppSettings.language
                    options: [
                        { label: "Română", value: "ro" },
                        { label: "English", value: "en" },
                        { label: "Русский", value: "ru" }
                    ]
                    onOptionSelected: AppSettings.language = value
                }
            }

            // ----- Tema -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Theme")
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Components.SegmentedControl {
                    Layout.fillWidth: true
                    currentValue: Theme.darkMode ? "dark" : "light"
                    options: [
                        { label: qsTr("Light"), value: "light" },
                        { label: qsTr("Dark"), value: "dark" }
                    ]
                    onOptionSelected: Theme.darkMode = (value === "dark")
                }
            }

            // ----- Marime text -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Text size")
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Components.SegmentedControl {
                    Layout.fillWidth: true
                    currentValue: Theme.fontScale
                    options: [
                        { label: qsTr("Small"), value: 0.9 },
                        { label: qsTr("Medium"), value: 1.0 },
                        { label: qsTr("Large"), value: 1.15 }
                    ]
                    onOptionSelected: Theme.fontScale = value
                }
            }

            // Separator inainte de zona de administrare.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                height: 1
                color: Theme.border
            }

            // Rand de navigare catre pagina Administrare (setari de sistem).
            // Ascuns momentan (2026-07-23, la cererea lui Kristian): aplicatia
            // ruleaza pentru un singur client, iar URL-ul backend-ului are
            // valoare implicita hardcodata in AppSettings.serverUrl - nu e
            // nevoie de UI pentru el. Pagina AdminPage si semnalul
            // adminRequested raman pe loc, doar re-pui visible cand va fi
            // nevoie (ex. mai multi clienti).
            Rectangle {
                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Icons.IconSettings {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        dark: Theme.darkMode
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: qsTr("Administration")
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Label {
                            text: qsTr("Server")
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    Icons.IconChevron {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        color: Theme.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.adminRequested()
                }
            }

            // Rand de navigare catre pagina Actualizari.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Icons.IconSettings {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        dark: Theme.darkMode
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: qsTr("Updates")
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Label {
                            text: appUpdateManager.currentVersion !== "" ? qsTr("Version %1").arg(appUpdateManager.currentVersion) : ""
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    Icons.IconChevron {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        color: Theme.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.updateRequested()
                }
            }
        }
    }
}
