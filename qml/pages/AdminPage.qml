import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Pagina de administrare: setari de sistem (server PHP, imprimanta de retea,
// terminal fiscal), setate o data de administrator/la instalare. Separata de
// Setari (Aspect), care raman pentru orice chelner (limba/tema/marime text).
Page {
    id: root

    // Mesaj de stare pentru testul/tiparirea imprimantei.
    property string printerStatus: ""
    property color printerStatusColor: Theme.textSecondary

    function useCandidate(candidate) {
        AppSettings.printerIp = String(candidate.ip || "")
        var p = parseInt(candidate.port, 10)
        AppSettings.printerPort = (isNaN(p) || p <= 0) ? 9100 : p
        AppSettings.printerName = String(candidate.manufacturer || candidate.displayName || "")
        root.printerStatus = qsTr("Printer selected: %1").arg(AppSettings.printerIp)
        root.printerStatusColor = Theme.success
    }

    // ZPL de test, doar ca sa confirmam ca imprimanta tipareste ce trimitem.
    // Foloseste acelasi antet de setari (media + cantitate) ca Una_Prod -
    // Godex-ul intelege ZPL, dar fara ^PW/^LL/^PQ nu scoate nimic pe hartie.
    function testZplLabel() {
        var now = new Date()
        var dt = now.toLocaleString(Qt.locale(), "dd.MM.yyyy HH:mm")
        return "^XA\n"
            + "^CI28\n"        // encoding UTF-8
            + "^PW800\n"       // latime imprimare (dots)
            + "^LL640\n"       // lungime eticheta
            + "^LH0,0\n"
            + "^PR5\n"         // viteza
            + "^MD15\n"        // intensitate
            + "^MMT\n"         // mod tear-off
            + "^FO40,40^A0N,50,50^FDUnaWaiter^FS\n"
            + "^FO40,110^A0N,34,34^FDBon de test^FS\n"
            + "^FO40,160^A0N,30,30^FD" + dt + "^FS\n"
            + "^FO40,210^GB720,3,3^FS\n"
            + "^PQ1,0,1,Y\n"   // tipareste 1 exemplar
            + "^XZ\n"
    }

    background: Rectangle {
        color: Theme.background
    }

    header: Components.PageHeader {
        title: qsTr("Administration")
        onBackRequested: root.StackView.view.pop()
    }

    // Primeste rezultatul testului de conexiune la imprimanta.
    Connections {
        target: printerManager
        function onTestResult(success, message) {
            root.printerStatus = message
            root.printerStatusColor = success ? Theme.success : Theme.danger
        }
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
            // Ascuns (2026-08-05): URL-ul are valoare implicita hardcodata in
            // AppSettings.serverUrl si nu se schimba la un singur client, dar
            // e singurul camp de-aici care, gresit completat, lasa aplicatia
            // complet fara backend. Campul si legatura raman pe loc - se
            // re-afiseaza punand visible: true, fara alta modificare.
            ColumnLayout {
                visible: false
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

            // ----- Imprimanta -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Printer")
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                // Rezumatul imprimantei curente.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 12
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.preferredHeight: 10
                            radius: 5
                            color: AppSettings.printerIp !== "" ? Theme.success : Theme.border
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: AppSettings.printerIp !== ""
                                      ? (AppSettings.printerName !== ""
                                         ? AppSettings.printerName
                                         : qsTr("Printer"))
                                      : qsTr("No printer selected")
                                color: Theme.textPrimary
                                font.pixelSize: 14 * Theme.fontScale
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: AppSettings.printerIp !== ""
                                text: AppSettings.printerIp + ":" + AppSettings.printerPort
                                color: Theme.textSecondary
                                font.pixelSize: 12 * Theme.fontScale
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // IP + port (editabile manual).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Components.TextInputField {
                        Layout.fillWidth: true
                        text: AppSettings.printerIp
                        placeholder: qsTr("Printer IP")
                        inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoAutoUppercase
                        onEditingFinished: AppSettings.printerIp = text
                    }

                    Components.TextInputField {
                        Layout.preferredWidth: 90
                        text: String(AppSettings.printerPort)
                        placeholder: qsTr("Port")
                        inputMethodHints: Qt.ImhDigitsOnly
                        onEditingFinished: {
                            var p = parseInt(text, 10)
                            AppSettings.printerPort = (isNaN(p) || p <= 0) ? 9100 : p
                            // Reafisam valoarea acceptata, ca sa nu ramana pe
                            // ecran un port invalid care n-a fost salvat.
                            text = String(AppSettings.printerPort)
                        }
                    }
                }

                // Butoane: Cauta + Test.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 14
                        color: Theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("Search printers")
                            color: "white"
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: printerDiscoveryDialog.openAndScan()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 48
                        radius: 14
                        color: Theme.keyBackground
                        opacity: AppSettings.printerIp !== "" ? 1.0 : 0.4

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("Test")
                            color: Theme.textPrimary
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: AppSettings.printerIp !== ""
                            onClicked: {
                                root.printerStatus = qsTr("Testing...")
                                root.printerStatusColor = Theme.textSecondary
                                printerManager.testConnection(AppSettings.printerIp, AppSettings.printerPort)
                            }
                        }
                    }
                }

                // Buton separat: trimite un bon ZPL real la imprimanta (nu doar
                // testeaza soclul TCP, ca butonul de mai sus).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 14
                    color: Theme.keyBackground
                    opacity: AppSettings.printerIp !== "" ? 1.0 : 0.4

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Print test receipt")
                        color: Theme.textPrimary
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: AppSettings.printerIp !== ""
                        onClicked: {
                            root.printerStatus = qsTr("Printing...")
                            root.printerStatusColor = Theme.textSecondary
                            var ok = printerManager.printZpl(AppSettings.printerIp, AppSettings.printerPort, root.testZplLabel())
                            root.printerStatus = ok
                                ? qsTr("Test receipt sent.")
                                : (printerManager.lastError !== "" ? printerManager.lastError : qsTr("Failed to send data to printer."))
                            root.printerStatusColor = ok ? Theme.success : Theme.danger
                        }
                    }
                }

                // Mesaj de stare (rezultat test / selectie).
                Label {
                    Layout.fillWidth: true
                    visible: root.printerStatus !== ""
                    text: root.printerStatus
                    color: root.printerStatusColor
                    font.pixelSize: 13 * Theme.fontScale
                    wrapMode: Text.WordWrap
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

    // Dialogul de cautare imprimante.
    Components.PrinterDiscoveryDialog {
        id: printerDiscoveryDialog
        scanPort: AppSettings.printerPort > 0 ? AppSettings.printerPort : 9100
        onPrinterSelected: root.useCandidate(candidate)
    }
}
