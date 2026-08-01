import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"
import "../../app/Format.js" as Format

// Alegerea metodei de plată, înainte de emiterea bonului fiscal pe terminalul
// SmartOne. Nu vorbește cu terminalul și nu ține starea comenzii: emite doar
// ce a ales chelnerul, iar pagina cheamă paymentController.
//
// Utilizare:
//   PaymentSheet {
//       id: paymentSheet
//       onPayRequested: root.pay(method, received)
//   }
//   ...
//   paymentSheet.openWith(88.0)
Popup {
    id: root

    property real total: 0

    // method: "cash" | "cardPos" | "cardManual"
    // received: suma primită de la client (doar la numerar; 0 în rest)
    signal payRequested(string method, real received)

    // false = terminalul n-are POS integrat (bridge-ul de pe :8888 nu ascultă),
    // deci metoda "Card (POS încorporat)" dispare din listă. E o proprietate, nu
    // o citire directă din paymentController: sheet-ul nu vorbește cu terminalul,
    // pagina îi spune ce se poate (vezi antetul).
    property bool posAvailable: true

    // Metodele arătate chelnerului, în ordinea din listă. Filtrate, nu doar
    // dezactivate: o plată cu cardul pe un POS inexistent n-are nicio variantă
    // de rezolvare pe loc, deci un rând gri n-ar spune nimic util.
    readonly property var methods: {
        var all = [
            { key: "cash",       label: qsTr("Cash"),                     hint: qsTr("Receipt printed on the terminal") },
            { key: "cardPos",    label: qsTr("Card (built-in POS)"),      hint: qsTr("Opens the bank app on this terminal") },
            { key: "cardManual", label: qsTr("Card (separate terminal)"), hint: qsTr("Card already charged elsewhere") }
        ]
        var out = []
        for (var i = 0; i < all.length; ++i) {
            if (all[i].key !== "cardPos" || root.posAvailable)
                out.push(all[i])
        }
        return out
    }

    property string selectedMethod: "cash"
    // Ce a tastat/ales chelnerul. 0 = "suma exactă" (fără rest).
    property real receivedAmount: 0

    readonly property real changeDue: (selectedMethod === "cash" && receivedAmount > total)
        ? (receivedAmount - total) : 0
    readonly property bool canConfirm: total > 0
        && (selectedMethod !== "cash" || receivedAmount === 0 || receivedAmount >= total)

    // Sheet-ul poate fi deschis chiar când o sondare descoperă că POS-ul a
    // dispărut. Fără asta, selecția ar rămâne pe un rând care nu mai e afișat.
    onMethodsChanged: {
        for (var i = 0; i < root.methods.length; ++i) {
            if (root.methods[i].key === root.selectedMethod)
                return
        }
        root.selectedMethod = "cash"
    }

    function openWith(orderTotal) {
        root.total = orderTotal
        root.selectedMethod = "cash"
        root.receivedAmount = 0
        receivedField.text = ""
        root.open()
    }

    // Bancnotele uzuale peste totalul comenzii - chelnerul apasă una în loc să
    // tasteze, ceea ce e mai rapid și nu greșește.
    function quickAmounts() {
        var notes = [50, 100, 200, 500, 1000]
        var out = []
        for (var i = 0; i < notes.length && out.length < 4; ++i) {
            if (notes[i] > root.total)
                out.push(notes[i])
        }
        return out
    }

    parent: Overlay.overlay
    modal: true
    padding: 0
    width: parent ? parent.width : 400
    x: 0
    y: parent ? parent.height - height : 0
    height: sheetContent.implicitHeight
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Poziția trebuie să rămână o LEGĂTURĂ vie, ca sheet-ul să stea lipit de
    // marginea de jos și când conținutul își schimbă înălțimea. Dar animațiile
    // de mai jos scriu în `y`, iar o scriere distruge legătura - de-aceea o
    // refacem după ce animația de intrare s-a terminat.
    //
    // Fără asta apăreau două defecte: a doua deschidere rămânea complet în
    // afara ecranului (se întuneca doar fundalul, fără dialog vizibil, pentru
    // că `y` rămăsese la valoarea de la ieșire), iar sheet-ul nu se mai
    // repoziționa când apărea rândul de rest.
    onOpened: y = Qt.binding(function() {
        return root.parent ? root.parent.height - root.height : 0
    })

    // `to` e explicit în ambele tranziții: lăsat implicit, ar fi însemnat
    // "valoarea curentă a lui y", care după o închidere e deja în afara
    // ecranului - exact cazul în care sheet-ul nu se mai vedea deloc.
    enter: Transition {
        NumberAnimation {
            property: "y"
            from: root.parent ? root.parent.height : 400
            to: root.parent ? root.parent.height - root.height : 0
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    exit: Transition {
        NumberAnimation {
            property: "y"
            to: root.parent ? root.parent.height : 400
            duration: 180
            easing.type: Easing.InCubic
        }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140 }
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    // Doar colțurile de sus rotunjite: sheet-ul stă lipit de marginea de jos a
    // ecranului, unde niște colțuri rotunde arată ca un defect de desen.
    // Rectangle nu are rază pe colț în Qt 5, deci acoperim partea de jos cu un
    // al doilea dreptunghi, drept.
    background: Item {
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Theme.surface
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 16
            color: Theme.surface
        }
    }

    // ColumnLayout-ul NU e direct `contentItem`: Popup impune inaltimea
    // contentItem-ului, iar un Layout caruia i se impune inaltimea isi
    // recalculeaza implicitHeight-ul pornind de la ea. Rezulta o bucla care
    // dubla inaltimea sheet-ului (aparea peste tot ecranul, fara pagina in
    // spate). Invelisul rupe bucla: Layout-ul isi pastreaza inaltimea
    // implicita, iar Popup se dimensioneaza din ea.
    contentItem: Item {
        implicitHeight: sheetContent.implicitHeight

        ColumnLayout {
            id: sheetContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            // --- Antet: total de plată ---
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: qsTr("To pay")
                        font.pixelSize: 12 * Theme.fontScale
                        color: Theme.textSecondary
                    }
                    Label {
                        text: qsTr("%1 MDL").arg(Format.amount(root.total))
                        font.pixelSize: 26 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }

                IconClose {
                    color: Theme.textSecondary
                    TouchArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        circular: true
                        onClicked: root.close()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // --- Metode de plată ---
            Repeater {
                model: root.methods

                Item {
                    id: methodRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62

                    // Copiat într-o proprietate cu nume propriu: `modelData` se
                    // pierde ușor în scope-urile imbricate, `methodRow.method` nu.
                    readonly property var method: modelData
                    readonly property bool selected: root.selectedMethod === methodRow.method.key

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // Buton radio desenat manual - tema nu are unul, iar
                        // RadioButton-ul standard nu se potrivește cu restul.
                        Rectangle {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 11
                            color: "transparent"
                            border.width: 2
                            border.color: methodRow.selected ? Theme.primary : Theme.border

                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 12; radius: 6
                                visible: methodRow.selected
                                color: Theme.primary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: methodRow.method.label
                                font.pixelSize: 15 * Theme.fontScale
                                font.bold: methodRow.selected
                                color: Theme.textPrimary
                            }
                            Label {
                                text: methodRow.method.hint
                                font.pixelSize: 11 * Theme.fontScale
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    TouchArea {
                        anchors.fill: parent
                        onClicked: root.selectedMethod = methodRow.method.key
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Theme.border
                    }
                }
            }

            // --- Numerar: suma primită + rest ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                spacing: 10
                visible: root.selectedMethod === "cash"

                Label {
                    text: qsTr("Cash received (leave empty for exact amount)")
                    font.pixelSize: 12 * Theme.fontScale
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.quickAmounts()

                        Rectangle {
                            id: quickNote
                            readonly property real amount: modelData
                            readonly property bool chosen: root.receivedAmount === quickNote.amount

                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 20
                            color: quickNote.chosen ? Theme.primary : Theme.keyBackground

                            Label {
                                anchors.centerIn: parent
                                text: quickNote.amount
                                font.pixelSize: 14 * Theme.fontScale
                                font.bold: true
                                color: quickNote.chosen ? "white" : Theme.textPrimary
                            }

                            TouchArea {
                                anchors.fill: parent
                                // Scriem în câmp, nu doar în proprietate: altfel
                                // câmpul ar rămâne cu o sumă veche, contrazicând
                                // vizual bancnota tocmai apăsată.
                                onClicked: receivedField.text = String(quickNote.amount)
                            }
                        }
                    }
                }

                TextInputField {
                    Layout.fillWidth: true
                    id: receivedField
                    placeholder: qsTr("Other amount")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextChanged: {
                        var v = parseFloat(text.replace(",", "."))
                        root.receivedAmount = (isNaN(v) || v <= 0) ? 0 : v
                    }
                }

                // Zonă de înălțime FIXĂ pentru rest / avertisment. Dacă ar apărea și
                // ar dispărea, sheet-ul și-ar schimba înălțimea la fiecare atingere
                // a unei bancnote și ar sări sub degetul chelnerului - de-aceea
                // comutăm opacitatea, nu vizibilitatea.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26

                    RowLayout {
                        anchors.fill: parent
                        opacity: root.changeDue > 0 ? 1 : 0

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Change")
                            font.pixelSize: 15 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Label {
                            text: qsTr("%1 MDL").arg(Format.amount(root.changeDue))
                            font.pixelSize: 18 * Theme.fontScale
                            font.bold: true
                            color: Theme.primary
                        }
                    }

                    Label {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        opacity: (root.receivedAmount > 0 && root.receivedAmount < root.total) ? 1 : 0
                        text: qsTr("The amount received is less than the total.")
                        font.pixelSize: 12 * Theme.fontScale
                        color: Theme.danger
                        elide: Text.ElideRight
                    }
                }
            }

            // --- Confirmare ---
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.topMargin: root.selectedMethod === "cash" ? 0 : 16
                Layout.preferredHeight: 50
                radius: 25
                color: root.canConfirm ? Theme.primary : Theme.border

                Label {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Pay and print receipt · %1 MDL").arg(Format.amount(root.total))
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: root.canConfirm ? "white" : Theme.textSecondary
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 11
                    elide: Text.ElideRight
                }

                TouchArea {
                    anchors.fill: parent
                    enabled: root.canConfirm
                    onClicked: {
                        root.close()
                        root.payRequested(root.selectedMethod, root.receivedAmount)
                    }
                }
            }
        }
    }
}
