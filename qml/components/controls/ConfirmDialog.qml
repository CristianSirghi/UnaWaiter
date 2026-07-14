import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Dialog de confirmare reutilizabil (ștergere comandă, deconectare etc.).
// Se centrează peste toată fereastra și întunecă fundalul. Emite confirmed()
// la apăsarea butonului principal.
//
// Utilizare:
//   ConfirmDialog {
//       id: dlg
//       title: qsTr("Delete order?")
//       message: qsTr("This order will be removed.")
//       confirmText: qsTr("Delete")
//       destructive: true
//       onConfirmed: ...
//   }
//   ...
//   dlg.open()
Popup {
    id: root

    property string title: ""
    property string message: ""
    property string confirmText: qsTr("Confirm")
    property string cancelText: qsTr("Cancel")
    // true → butonul principal e roșu (acțiune ireversibilă).
    property bool destructive: false
    // true → doar un buton (confirmText), fără opțiunea de anulare - pentru
    // mesaje pur informative (ex. "nu poți edita asta încă"), nu confirmări.
    property bool infoOnly: false

    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    dim: true
    padding: 0
    width: Math.min(320, (parent ? parent.width : 320) - 48)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Dialogul e centrat (anchors.centerIn), nu ancorat jos ca AddonSheet, deci
    // aici scale + fade se potrivește mai bine decât o alunecare — "apare" din
    // centru în loc să urce de undeva.
    //
    // IMPORTANT: scale se animă pe contentItem/background, NU pe root (popup-ul
    // însuși). anchors.centerIn se calculează pe geometria lui root — dacă am
    // anima scale acolo, ultima valoare animată (0.9) rămâne "lipită" de root
    // după închidere, iar centrarea următoare se calculează cu acel scale rezidual,
    // deplasând popup-ul cu exact jumătate din diferența de mărime (confirmat din
    // log: 272×(1-0.9)/2 = 13.6px, 165×(1-0.9)/2 = 8.25px — exact deriva observată).
    enter: Transition {
        NumberAnimation { target: root.contentItem; property: "scale"; from: 0.9; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: root.background; property: "scale"; from: 0.9; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
    }
    exit: Transition {
        NumberAnimation { target: root.contentItem; property: "scale"; from: 1.0; to: 0.9; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: root.background; property: "scale"; from: 1.0; to: 0.9; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110 }
    }

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        color: Theme.surface
        radius: 16
        border.width: 1
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: 0

        Label {
            Layout.fillWidth: true
            Layout.margins: 20
            Layout.bottomMargin: 8
            text: root.title
            font.pixelSize: 18 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 20
            visible: root.message.length > 0
            text: root.message
            font.pixelSize: 14 * Theme.fontScale
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // Anulează (ascuns în modul infoOnly - rămâne doar butonul de confirmare)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                visible: !root.infoOnly
                color: "transparent"

                Label {
                    anchors.centerIn: parent
                    text: root.cancelText
                    font.pixelSize: 15 * Theme.fontScale
                    color: Theme.textSecondary
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 52
                visible: !root.infoOnly
                color: Theme.border
            }

            // Confirmă
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: "transparent"

                Label {
                    anchors.centerIn: parent
                    text: root.confirmText
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: root.destructive ? Theme.danger : Theme.primary
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.close()
                        root.confirmed()
                    }
                }
            }
        }
    }
}
