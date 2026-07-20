import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Pagina de administrare: setari de sistem (server PHP), setate o data de
// administrator/la instalare. Separata de Setari (Aspect), care raman pentru
// orice chelner (limba/tema/marime text).
Page {
    id: root

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
            text: qsTr("Administration")
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
            spacing: 28

            // ----- Server (backend PHP) -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Server")
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Components.TextInputField {
                    Layout.fillWidth: true
                    text: AppSettings.serverUrl
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    onEditingFinished: AppSettings.serverUrl = text
                }
            }
        }
    }
}
