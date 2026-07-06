import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Dialog de confirmare reutilizabil (ștergere comandă, deconectare etc.).
// Se centrează peste toată fereastra și întunecă fundalul. Emite confirmed()
// la apăsarea butonului principal.
//
// Utilizare:
//   ConfirmDialog {
//       id: dlg
//       theme: appTheme
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

    property var theme
    property string title: ""
    property string message: ""
    property string confirmText: qsTr("Confirm")
    property string cancelText: qsTr("Cancel")
    // true → butonul principal e roșu (acțiune ireversibilă).
    property bool destructive: false

    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    dim: true
    padding: 0
    width: Math.min(320, (parent ? parent.width : 320) - 48)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        color: root.theme.surface
        radius: 16
        border.width: 1
        border.color: root.theme.border
    }

    contentItem: ColumnLayout {
        spacing: 0

        Label {
            Layout.fillWidth: true
            Layout.margins: 20
            Layout.bottomMargin: 8
            text: root.title
            font.pixelSize: 18 * root.theme.fontScale
            font.bold: true
            color: root.theme.textPrimary
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 20
            visible: root.message.length > 0
            text: root.message
            font.pixelSize: 14 * root.theme.fontScale
            color: root.theme.textSecondary
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // Anulează
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: "transparent"

                Label {
                    anchors.centerIn: parent
                    text: root.cancelText
                    font.pixelSize: 15 * root.theme.fontScale
                    color: root.theme.textSecondary
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 52; color: root.theme.border }

            // Confirmă
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: "transparent"

                Label {
                    anchors.centerIn: parent
                    text: root.confirmText
                    font.pixelSize: 15 * root.theme.fontScale
                    font.bold: true
                    color: root.destructive ? root.theme.danger : root.theme.primary
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
