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

    header: Components.PageHeader {
        title: qsTr("Administration")
        onBackRequested: root.StackView.view.pop()
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

            // ----- Terminal fiscal (SmartOne) -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Fiscal terminal")
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Number of the next fiscal document. The terminal rejects numbers outside its own sequence - if paying fails with \"Invalid docNumber\", set this to the value the terminal expects.")
                    font.pixelSize: 12 * Theme.fontScale
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }

                Components.TextInputField {
                    Layout.fillWidth: true
                    text: String(paymentController.nextPayId)
                    inputMethodHints: Qt.ImhDigitsOnly
                    onEditingFinished: {
                        var v = parseInt(text)
                        if (!isNaN(v) && v > 0)
                            paymentController.nextPayId = v
                        // Reafișăm valoarea acceptată: dacă s-a tastat ceva
                        // invalid, câmpul nu are voie să rămână cu ea pe ecran,
                        // sugerând o setare care nu s-a aplicat.
                        text = String(paymentController.nextPayId)
                    }
                }
            }
        }
    }
}
