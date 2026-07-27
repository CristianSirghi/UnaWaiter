import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"

// Meniul din butonul "hamburger" al unei comenzi deja trimise: achitare și
// ștergere. Nu deține nicio stare a comenzii - doar emite ce a ales chelnerul,
// iar pagina decide ce face (același tipar ca AddonSheet).
//
// Utilizare:
//   OrderActionSheet {
//       id: actionSheet
//       canPay: root.sentNrComand > 0
//       payBlockedReason: qsTr("Trimite mai intai modificarile.")
//       onPayRequested: root.startPayment()
//       onDeleteRequested: deleteDialog.open()
//   }
//   ...
//   actionSheet.open()
Popup {
    id: root

    // false → rândul de achitare e vizibil, dar inactiv, cu motivul dedesubt.
    // Îl arătăm dezactivat în loc să-l ascundem: un rând care dispare îl lasă
    // pe chelner să se întrebe unde e achitarea, unul gri îi spune de ce nu poate.
    property bool canPay: true
    property string payBlockedReason: ""

    signal payRequested()
    signal deleteRequested()

    parent: Overlay.overlay
    modal: true
    padding: 0
    width: parent ? parent.width : 400
    x: 0
    y: parent ? parent.height - height : 0
    height: sheetContent.implicitHeight
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Vezi explicația din PaymentSheet.qml: animația scrie în `y` și distruge
    // legătura, așa că o refacem după intrare. Fără asta, a doua deschidere
    // rămânea în afara ecranului - se întuneca fundalul, dar meniul nu apărea.
    onOpened: y = Qt.binding(function() {
        return root.parent ? root.parent.height - root.height : 0
    })

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

    // Doar colțurile de sus rotunjite - vezi PaymentSheet.qml.
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

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 8

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Order actions")
                    font.pixelSize: 17 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
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

            // --- Achită ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.canPay ? 64 : 78
                opacity: root.canPay ? 1 : 0.5

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.primary
                        IconCheck { anchors.centerIn: parent; color: "white" }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: qsTr("Pay")
                            font.pixelSize: 16 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }
                        Label {
                            visible: !root.canPay && root.payBlockedReason !== ""
                            text: root.payBlockedReason
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                TouchArea {
                    anchors.fill: parent
                    enabled: root.canPay
                    onClicked: {
                        root.close()
                        root.payRequested()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // --- Șterge ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 64

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.danger
                        IconTrash { anchors.centerIn: parent; color: Theme.danger }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Delete order")
                        font.pixelSize: 16 * Theme.fontScale
                        color: Theme.danger
                    }
                }

                TouchArea {
                    anchors.fill: parent
                    onClicked: {
                        root.close()
                        root.deleteRequested()
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 12 }
        }
    }
}
