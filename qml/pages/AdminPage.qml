import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Pagina de administrare: setari de sistem (server PHP + imprimanta de retea),
// setate o data de administrator/la instalare. Separata de Setari (Aspect),
// care raman pentru orice chelner (limba/tema/marime text).
Page {
    id: root

    property var theme
    property var settings

    // Mesaj de stare pentru testul/tiparirea imprimantei.
    property string printerStatus: ""
    property color printerStatusColor: theme.textSecondary

    function useCandidate(candidate) {
        settings.printerIp = String(candidate.ip || "")
        var p = parseInt(candidate.port, 10)
        settings.printerPort = (isNaN(p) || p <= 0) ? 9100 : p
        settings.printerName = String(candidate.manufacturer || candidate.displayName || "")
        root.printerStatus = qsTr("Printer selected: %1").arg(settings.printerIp)
        root.printerStatusColor = theme.success
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
            text: qsTr("Administration")
            font.pixelSize: 20 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    // Primeste rezultatul testului de conexiune la imprimanta.
    Connections {
        target: printerManager
        function onTestResult(success, message) {
            root.printerStatus = message
            root.printerStatusColor = success ? theme.success : theme.danger
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
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Server")
                    font.pixelSize: 16 * theme.fontScale
                    font.bold: true
                    color: theme.textPrimary
                }

                Components.TextInputField {
                    Layout.fillWidth: true
                    theme: root.theme
                    text: root.settings.serverUrl
                    placeholder: qsTr("https://server/oracle_waiter.php")
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    onEditingFinished: root.settings.serverUrl = text
                }
            }

            // ----- Imprimanta -----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Printer")
                    font.pixelSize: 16 * theme.fontScale
                    font.bold: true
                    color: theme.textPrimary
                }

                // Rezumatul imprimantei curente.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 12
                    color: theme.surface
                    border.width: 1
                    border.color: theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.preferredHeight: 10
                            radius: 5
                            color: root.settings.printerIp !== "" ? theme.success : theme.border
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: root.settings.printerIp !== ""
                                      ? (root.settings.printerName !== ""
                                         ? root.settings.printerName
                                         : qsTr("Printer"))
                                      : qsTr("No printer selected")
                                color: theme.textPrimary
                                font.pixelSize: 14 * theme.fontScale
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: root.settings.printerIp !== ""
                                text: root.settings.printerIp + ":" + root.settings.printerPort
                                color: theme.textSecondary
                                font.pixelSize: 12 * theme.fontScale
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
                        theme: root.theme
                        text: root.settings.printerIp
                        placeholder: qsTr("Printer IP")
                        inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoAutoUppercase
                        onEditingFinished: root.settings.printerIp = text
                    }

                    Components.TextInputField {
                        Layout.preferredWidth: 90
                        theme: root.theme
                        text: String(root.settings.printerPort)
                        placeholder: qsTr("Port")
                        inputMethodHints: Qt.ImhDigitsOnly
                        onEditingFinished: {
                            var p = parseInt(text, 10)
                            root.settings.printerPort = (isNaN(p) || p <= 0) ? 9100 : p
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
                        color: theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("Search printers")
                            color: "white"
                            font.pixelSize: 15 * theme.fontScale
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
                        color: theme.keyBackground
                        opacity: root.settings.printerIp !== "" ? 1.0 : 0.4

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("Test")
                            color: theme.textPrimary
                            font.pixelSize: 15 * theme.fontScale
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.settings.printerIp !== ""
                            onClicked: {
                                root.printerStatus = qsTr("Testing...")
                                root.printerStatusColor = theme.textSecondary
                                printerManager.testConnection(root.settings.printerIp, root.settings.printerPort)
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
                    color: theme.keyBackground
                    opacity: root.settings.printerIp !== "" ? 1.0 : 0.4

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Print test receipt")
                        color: theme.textPrimary
                        font.pixelSize: 15 * theme.fontScale
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.settings.printerIp !== ""
                        onClicked: {
                            root.printerStatus = qsTr("Printing...")
                            root.printerStatusColor = theme.textSecondary
                            var ok = printerManager.printZpl(root.settings.printerIp, root.settings.printerPort, root.testZplLabel())
                            root.printerStatus = ok
                                ? qsTr("Test receipt sent.")
                                : (printerManager.lastError !== "" ? printerManager.lastError : qsTr("Failed to send data to printer."))
                            root.printerStatusColor = ok ? theme.success : theme.danger
                        }
                    }
                }

                // Mesaj de stare (rezultat test / selectie).
                Label {
                    Layout.fillWidth: true
                    visible: root.printerStatus !== ""
                    text: root.printerStatus
                    color: root.printerStatusColor
                    font.pixelSize: 13 * theme.fontScale
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // Dialogul de cautare imprimante.
    Components.PrinterDiscoveryDialog {
        id: printerDiscoveryDialog
        theme: root.theme
        scanPort: root.settings.printerPort > 0 ? root.settings.printerPort : 9100
        onPrinterSelected: root.useCandidate(candidate)
    }
}
