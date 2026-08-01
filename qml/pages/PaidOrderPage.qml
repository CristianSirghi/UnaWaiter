import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../app/Format.js" as Format

// Detaliul unei comenzi deja achitate: ce s-a comandat, cum s-a plătit și
// butonul de retipărire a bonului.
//
// Retipărirea trăiește AICI, nu doar în dialogul care apare imediat după o
// tipărire eșuată: dialogul acela se poate închide cu "Renunță", sau poate
// dispărea odată cu procesul omorât de Android, iar atunci bonul devenea
// irecuperabil. Aici e recuperabil oricând cât timp comanda e în listă.
//
// Utilizare (din AchitatePage):
//   stackView.push(paidOrderPage, { nrComand: "382830", ... })
Page {
    id: root

    property string nrComand: ""
    property string tableLabel: ""
    property string waiterName: ""
    property string payTime: ""
    property string totalText: ""
    // Gol = comanda a fost achitată la casă, nu de noi: nu avem numărul
    // documentului, deci n-avem ce retipări.
    property string documentNumber: ""
    property int payType: 0

    property bool linesLoaded: false
    property string loadError: ""
    property bool reprinting: false

    readonly property string payTypeLabel: root.payType === 1
        ? qsTr("Cash")
        : (root.payType === 2 ? qsTr("Card") : qsTr("Unknown"))

    // Nu se poate retipări din două motive: comanda n-are bon al nostru
    // (achitată la casă), sau terminalul n-are memorie fiscală (Android
    // obișnuit). Butonul gri e singurul semn - motivul scris dedesubt a fost
    // scos intenționat. Cine ajunge totuși să apese primește explicația din
    // dialog, pentru că `reprint()` refuză cu mesaj propriu pentru fiecare caz.
    readonly property bool canReprint: root.documentNumber !== ""
        && paymentController.fiscalAvailable
        && !root.reprinting

    function buildLines(rows) {
        root.loadError = ""
        linesModel.clear()
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var qty = parseFloat(r.CANT)
            if (isNaN(qty) || qty <= 0)
                continue
            linesModel.append({
                productName: r.CLCBLIUDAT ? String(r.CLCBLIUDAT).trim() : qsTr("Product"),
                qtyText: Format.amount(qty),
                priceText: Format.money(r.CLCPRETT),
                sumText: Format.money(r.CLCSUMAT)
            })
        }
        root.linesLoaded = true
    }

    Component.onCompleted: {
        if (root.nrComand !== "")
            dataService.loadOrderLines(root.nrComand)
        // Resondăm la deschidere, ca la OrderActionSheet: pe un terminal bun al
        // cărui bridge a pornit după aplicație, un rezultat vechi ar arăta
        // butonul gri degeaba. Răspunsul vine în milisecunde.
        paymentController.probeFiscalService()
    }

    ListModel { id: linesModel }

    Connections {
        target: dataService

        function onOrderLinesChanged() { root.buildLines(dataService.orderLines) }

        function onRequestFailed(command, error) {
            if (command === "get_order_lines") {
                root.loadError = error
                root.linesLoaded = true
            }
        }
    }

    Connections {
        target: paymentController

        // Canal propriu al retipăririi - `paymentFailed` e filtrat pe numărul
        // comenzii, iar la un document vechi starea controller-ului aparține
        // altei plăți, deci filtrul l-ar arunca exact aici.
        function onReprintFinished(ok, reason) {
            root.reprinting = false
            if (ok) {
                resultDialog.title = qsTr("Receipt printed")
                resultDialog.message = qsTr("Receipt %1 was printed again.").arg(root.documentNumber)
            } else {
                resultDialog.title = qsTr("Couldn't print")
                resultDialog.message = reason
            }
            resultDialog.open()
        }
    }

    background: Rectangle { color: Theme.background }

    header: Components.PageHeader {
        title: root.tableLabel !== "" ? root.tableLabel : qsTr("Paid order")
        onBackRequested: root.StackView.view.pop()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // ---- Rezumatul plății ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: summary.implicitHeight + 28
            radius: 14
            color: Theme.surface
            border.width: 1.5
            border.color: Theme.success

            ColumnLayout {
                id: summary
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 8

                Repeater {
                    model: [
                        { k: qsTr("Order"),        v: "#" + root.nrComand },
                        { k: qsTr("Waiter"),       v: root.waiterName },
                        { k: qsTr("Paid at"),      v: root.payTime },
                        { k: qsTr("Payment"),      v: root.payTypeLabel },
                        // Numărul bonului e util cât timp cauți ceva în
                        // raportul Z al aparatului - de-aceea e afișat, nu doar
                        // folosit intern la retipărire.
                        { k: qsTr("Receipt"),      v: root.documentNumber !== ""
                                                      ? root.documentNumber
                                                      : qsTr("closed at the register") }
                    ]

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: String(modelData.v).trim() !== ""

                        Label {
                            text: modelData.k
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: modelData.v
                            font.pixelSize: 13 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.maximumWidth: parent.width * 0.6
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Total")
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: root.totalText
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Products")
            font.pixelSize: 14 * Theme.fontScale
            font.bold: true
            color: Theme.textSecondary
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 1
            clip: true
            model: linesModel
            visible: linesModel.count > 0

            delegate: Rectangle {
                width: ListView.view.width
                height: lineRow.implicitHeight + 20
                color: Theme.surface

                RowLayout {
                    id: lineRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: productName
                            font.pixelSize: 14 * Theme.fontScale
                            color: Theme.textPrimary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            text: qtyText + " × " + priceText
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    Label {
                        text: sumText
                        font.pixelSize: 14 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: linesModel.count === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: root.loadError !== ""
                ? qsTr("Couldn't load the products:\n%1").arg(root.loadError)
                : (root.linesLoaded ? qsTr("This order has no lines.") : qsTr("Loading…"))
            font.pixelSize: 14 * Theme.fontScale
            color: root.loadError !== "" ? Theme.danger : Theme.textSecondary
        }

        // ---- Retipărire ----
        // Vizibil dar inactiv când n-avem document, cu motivul dedesubt -
        // același tipar ca rândul "Achită" din OrderActionSheet: un buton care
        // dispare îl lasă pe chelner să se întrebe unde e.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 12
            color: root.canReprint ? Theme.primary : Theme.border

            Label {
                anchors.centerIn: parent
                text: root.reprinting ? qsTr("Printing…") : qsTr("Print receipt again")
                font.pixelSize: 15 * Theme.fontScale
                font.bold: true
                color: root.canReprint ? "white" : Theme.textSecondary
            }

            Components.TouchArea {
                anchors.fill: parent
                enabled: root.canReprint
                onClicked: {
                    root.reprinting = true
                    paymentController.reprint(root.documentNumber)
                }
            }
        }
    }

    Components.ConfirmDialog {
        id: resultDialog
        confirmText: qsTr("OK")
        infoOnly: true
    }
}
