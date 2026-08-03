import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../app/Format.js" as Format

// Ecranul de așteptare al achitării: ce se întâmplă acum cu bonul, apoi
// confirmarea. Ține locul singurului feedback de dinainte - textul "Se
// achită…" de pe butonul de jos - pentru un lanț care durează 4-8 secunde și
// trece prin patru operațiuni diferite (terminal de card, memorie fiscală,
// imprimantă, Oracle). Când se blochează, contează FOARTE mult care din ele e.
//
// E un Popup pe Overlay.overlay, nu un strat în pagină, din două motive:
// acoperă și antetul (deci butonul de înapoi nu mai poate scoate pagina de sub
// o plată în curs) și înghite atingerile fără să depindem de un MouseArea
// pus corect.
//
// PAȘII NU SUNT O SECVENȚĂ. Tipărirea și închiderea comenzii pleacă amândouă
// imediat ce documentul e comis și se termină independent (vezi onOrderPaid
// din paymentcontroller.cpp) - de-aceea fiecare pas își are propria stare, în
// loc de o singură "fază" curentă care ar fi trebuit să mintă despre unul.
//
// Utilizare:
//   PaymentProgressOverlay {
//       active: root.paying
//       usesCardPos: paymentController.payingWithCardPos
//       ...
//       onDismissed: root.closeAfterPayment()
//   }
Popup {
    id: root

    // Plata e în curs (sau tocmai s-a încheiat): ecranul e vizibil.
    property bool active: false
    // Comanda e închisă în Oracle - trecem de la pași la confirmare.
    property bool succeeded: false

    // Starea pașilor, citită din PaymentController.
    property bool usesCardPos: false
    property bool cardConfirmed: false
    property bool receiptIssued: false
    property bool receiptPrinted: false
    property bool orderClosed: false

    // Datele confirmării. `documentNumber` și `changeDue` sunt INSTANTANEE
    // luate de pagină în momentul succesului, nu legături vii: proprietățile
    // controller-ului aparțin "plății curente", iar cât stă cartonașul pe ecran
    // o recuperare de fundal le-ar putea muta pe altă comandă.
    property string documentNumber: ""
    property real changeDue: 0
    property real total: 0

    // Chelnerul a terminat cu confirmarea: pagina poate să se închidă.
    signal dismissed()
    // A cerut încă un exemplar pe hârtie.
    signal reprintRequested()

    // Restul se dă din mână, deci confirmarea nu are voie să dispară singură:
    // suma trebuie citită. Fără rest, o atingere în plus la fiecare masă e taxă
    // pe degeaba - se închide singură.
    readonly property bool waitsForAcknowledge: root.changeDue > 0

    readonly property var stepKeys: root.usesCardPos
        ? ["card", "issue", "print", "close"]
        : ["issue", "print", "close"]

    function stepLabel(key) {
        if (key === "card")
            return qsTr("Confirm on the card terminal")
        if (key === "issue")
            return qsTr("Issuing the fiscal receipt")
        if (key === "print")
            return qsTr("Printing the receipt")
        return qsTr("Closing the order")
    }

    function stepDone(key) {
        if (key === "card")
            return root.cardConfirmed
        if (key === "issue")
            return root.receiptIssued
        if (key === "print")
            return root.receiptPrinted
        return root.orderClosed
    }

    // "În lucru chiar acum". Pasul cardului lipsind, emiterea pornește din
    // prima clipă; tipărirea și închiderea pornesc AMÂNDOUĂ la comiterea
    // documentului, deci pot fi active în același timp.
    function stepActive(key) {
        if (key === "card")
            return !root.cardConfirmed
        if (key === "issue")
            return (!root.usesCardPos || root.cardConfirmed) && !root.receiptIssued
        if (key === "print")
            return root.receiptIssued && !root.receiptPrinted
        return root.receiptIssued && !root.orderClosed
    }

    parent: Overlay.overlay
    modal: true
    padding: 0
    x: 0
    y: 0
    width: parent ? parent.width : 400
    height: parent ? parent.height : 600
    closePolicy: Popup.NoAutoClose

    visible: root.active

    Overlay.modal: Rectangle { color: Theme.background }
    background: Rectangle { color: Theme.background }

    // Fereastra de tipărire e singurul moment în care chiar iese hârtie. În
    // rest aparatul doar lucrează, iar animația de alimentare ar fi o minciună
    // (bonul nici nu există încă).
    readonly property bool printing: root.receiptIssued && !root.receiptPrinted

    contentItem: Item {

        // --- Pașii plății ---
        ColumnLayout {
            id: progressView

            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 360)
            spacing: 0
            visible: opacity > 0
            opacity: root.succeeded ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }

            PrinterAnimation {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 26
                feeding: root.printing
                paperCutColor: Theme.background
            }

            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 22
                horizontalAlignment: Text.AlignHCenter
                text: root.printing
                    ? qsTr("Printing the receipt…")
                    : root.usesCardPos && !root.cardConfirmed
                        ? qsTr("Waiting for the card…")
                        : qsTr("Taking the payment…")
                font.pixelSize: 19 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.stepKeys

                RowLayout {
                    id: stepRow

                    // Copiate în proprietăți proprii: `modelData` se pierde în
                    // scope-urile imbricate de mai jos, astea nu.
                    readonly property string stepKey: modelData
                    readonly property bool done: root.stepDone(stepRow.stepKey)
                    readonly property bool active: root.stepActive(stepRow.stepKey)

                    Layout.fillWidth: true
                    Layout.bottomMargin: 14
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20

                        // Gata: cerc plin cu bifă.
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            visible: stepRow.done
                            color: Theme.success

                            Rectangle {
                                x: 3; y: 9.75
                                width: 6; height: 2.5; radius: 1.25
                                color: "white"
                                rotation: 45
                                transformOrigin: Item.Center
                            }
                            Rectangle {
                                x: 6.5; y: 7.75
                                width: 11; height: 2.5; radius: 1.25
                                color: "white"
                                rotation: -45
                                transformOrigin: Item.Center
                            }
                        }

                        // În lucru: punct care pulsează. Un inel rotitor ar fi
                        // cerut Shapes, pe care build-ul ăsta le evită.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 14; height: 14; radius: 7
                            visible: !stepRow.done && stepRow.active
                            color: Theme.primary

                            SequentialAnimation on opacity {
                                running: !stepRow.done && stepRow.active && root.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 560; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 560; easing.type: Easing.InOutQuad }
                            }
                        }

                        // Încă n-a început: cerc gol.
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            visible: !stepRow.done && !stepRow.active
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.border
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.stepLabel(stepRow.stepKey)
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: stepRow.active && !stepRow.done
                        color: (stepRow.done || stepRow.active) ? Theme.textPrimary : Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Avertismentul cel mai important al ecranului: cât timp e vizibil,
            // banii pot fi deja luați, iar o repetare a plății ar însemna o a
            // doua debitare sau un al doilea bon.
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 10
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Don't close the app.")
                font.pixelSize: 12 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        // --- Confirmarea ---
        ColumnLayout {
            id: successView

            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 360)
            spacing: 0
            visible: opacity > 0
            opacity: root.succeeded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 20
                width: 96; height: 96; radius: 48
                color: Theme.success

                // Intră cu un salt scurt, ca ochiul să prindă schimbarea de
                // stare fără să fie nevoie de citit textul.
                scale: root.succeeded ? 1 : 0.4
                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }

                Item {
                    anchors.centerIn: parent
                    width: 48; height: 44

                    Rectangle {
                        x: 3.5; y: 25
                        width: 17; height: 6; radius: 3
                        color: "white"
                        rotation: 45
                        transformOrigin: Item.Center
                    }
                    Rectangle {
                        x: 13; y: 19
                        width: 34; height: 6; radius: 3
                        color: "white"
                        rotation: -45
                        transformOrigin: Item.Center
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Paid · %1 MDL").arg(Format.amount(root.total))
                font.pixelSize: 21 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 6
                horizontalAlignment: Text.AlignHCenter
                visible: root.documentNumber !== ""
                text: qsTr("Fiscal receipt no. %1").arg(root.documentNumber)
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            // Restul, în cel mai vizibil bloc de pe ecran. Până acum apărea
            // doar în dialogul de dinaintea plății, adică exact înainte ca
            // chelnerul să aibă nevoie de el, niciodată după.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 22
                Layout.preferredHeight: 88
                visible: root.changeDue > 0
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("CHANGE TO GIVE")
                        font.pixelSize: 12 * Theme.fontScale
                        font.bold: true
                        color: Theme.textSecondary
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("%1 MDL").arg(Format.amount(root.changeDue))
                        font.pixelSize: 30 * Theme.fontScale
                        font.bold: true
                        color: Theme.primary
                    }
                }
            }

            // Starea tipăririi, live. Confirmarea apare când Oracle a închis
            // comanda, iar imprimanta poate fi încă în lucru - același paralelism
            // ca la pași. Dacă tipărirea eșuează după ce ecranul s-a închis,
            // dialogul de retipărire din main.qml preia treaba, ca și până acum.
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 18
                horizontalAlignment: Text.AlignHCenter
                text: root.receiptPrinted
                    ? qsTr("Receipt printed.")
                    : qsTr("Printing the receipt…")
                font.pixelSize: 13 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 18
                Layout.preferredHeight: 50
                visible: root.waitsForAcknowledge
                radius: 25
                color: Theme.primary

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Change given")
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: "white"
                }

                TouchArea {
                    anchors.fill: parent
                    onClicked: root.dismissed()
                }
            }

            // Pentru bonul rupt sau mototolit. Tipărirea pleacă, iar ecranul se
            // închide imediat: rezultatul îl raportează main.qml, pe canalul lui
            // (reprintFinished) - la fel ca la orice altă retipărire.
            //
            // Apare doar după ce primul exemplar a ieșit: cât timp tipărirea e
            // în curs, controller-ul e ocupat și ar refuza apăsarea cu "o plată
            // e deja în curs" - un mesaj care n-are nicio legătură cu ce a cerut
            // chelnerul. Iar dacă tipărirea EȘUEAZĂ, retipărirea o oferă oricum
            // dialogul din main.qml.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.preferredHeight: 46
                visible: root.documentNumber !== "" && root.receiptPrinted
                radius: 23
                color: "transparent"
                border.width: 1
                border.color: Theme.border

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Print again")
                    font.pixelSize: 14 * Theme.fontScale
                    color: Theme.textPrimary
                }

                TouchArea {
                    anchors.fill: parent
                    onClicked: root.reprintRequested()
                }
            }
        }

        // Atingerea oriunde grăbește închiderea confirmării - dar numai când nu
        // e rest de dat, altfel exact suma care trebuie citită ar putea fi
        // ștearsă de o atingere din reflex.
        //
        // `z: -1` îl duce sub coloanele de mai sus, deși e declarat ultimul:
        // altfel ar acoperi butonul de retipărire și orice apăsare pe el ar
        // închide ecranul în loc să tipărească.
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: root.succeeded && !root.waitsForAcknowledge
            onClicked: root.dismissed()
        }

        // Închiderea automată a confirmării. Nu pornește cât e rest de dat:
        // acolo închiderea o cere chelnerul, apăsând.
        //
        // Declarat în contentItem, nu direct sub Popup: proprietatea implicită a
        // unui Popup e `contentData`, iar un obiect nevizual pus acolo depinde
        // de cum îl împachetează Popup peste contentItem-ul deja setat explicit.
        Timer {
            interval: 2800
            running: root.visible && root.succeeded && !root.waitsForAcknowledge
            onTriggered: root.dismissed()
        }
    }
}
