import QtQuick 2.15
import "../../theme"
import "../../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"

// Sheet de jos pentru mutarea unei comenzi deschise pe altă masă/zonă
// (chelnerul a trimis din greșeală pe masa greșită). Grilele Sala/Terasă
// urmează exact layout-ul din SelectTablePage; mesele cu comandă activă
// (alta decât cea editată acum) apar dezactivate/estompate.
//
// Utilizare:
//   ChangeTablePicker {
//       id: tablePicker
//       onTableSelected: function(zone, tableNumber) { ... }
//   }
//   ...
//   tablePicker.openWith(root.zone, root.tableNumber)
Popup {
    id: root

    property string currentZone: ""
    property int currentTableNumber: 0

    // "zonă_masă" → { waiter, orderNo } - completat de OrderPage din
    // dataService.tableOccupancy (Oracle, toți chelnerii/toate telefoanele).
    // Sursa de adevăr pentru cine ocupă efectiv o masă - vezi și OrdersStore
    // mai jos, folosit doar ca plasă de siguranță suplimentară.
    property var occupiedByDesk: ({})

    signal tableSelected(string zone, int tableNumber)

    function occupantFor(zone, tableNumber) {
        return root.occupiedByDesk[zone + "_" + tableNumber]
    }

    function isTaken(zone, tableNumber) {
        if (zone === root.currentZone && tableNumber === root.currentTableNumber)
            return false
        if (root.occupantFor(zone, tableNumber))
            return true
        // Plasă de siguranță locală (cache OrdersStore) - pentru cazul rar în
        // care occupiedByDesk încă nu a sosit de la server, dar acest telefon
        // știe deja local că masa e ocupată.
        return OrdersStore.hasOrder(zone, tableNumber)
    }

    function openWith(zone, tableNumber) {
        root.currentZone = zone
        root.currentTableNumber = tableNumber
        root.open()
    }

    parent: Overlay.overlay
    modal: true
    dim: true
    padding: 0
    width: parent ? parent.width : 400
    height: parent ? Math.min(520, parent.height * 0.85) : 520
    x: 0
    y: parent ? parent.height - height : 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // IMPORTANT: animăm contentItem/background, NU root - root.y are un binding
    // (y: parent.height - height) care trebuie să rămână viu la fiecare
    // deschidere. O animație directă pe root.y îl suprascrie (scriere
    // imperativă rupe binding-ul QML) - la a doua deschidere rămânea înghețat
    // pe ultima valoare animată (sheet-ul apărea sub ecran, invizibil, doar
    // dim-ul se vedea). Vezi exact același bug, deja reparat o dată pentru
    // scale, în comentariul din ConfirmDialog.qml.
    enter: Transition {
        NumberAnimation { targets: [root.contentItem, root.background]; property: "y"; from: root.height; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    exit: Transition {
        NumberAnimation { targets: [root.contentItem, root.background]; property: "y"; from: 0; to: root.height; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140 }
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    // Colțuri rotunjite doar sus (bottom sheet) — un Rectangle simplu rotunjește
    // toate cele 4 colțuri, așa că suprapunem un dreptunghi drept peste jumătatea
    // de jos ca să "pătrățească" doar colțurile de jos.
    background: Item {
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            radius: 16
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height / 2
            color: Theme.surface
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            Layout.bottomMargin: 8

            Label {
                Layout.fillWidth: true
                text: qsTr("Move to table")
                font.pixelSize: 17 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            IconClose {
                color: Theme.textSecondary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: root.close()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentCol.height
            clip: true

            Column {
                id: contentCol
                width: parent.width
                topPadding: 16
                bottomPadding: 20
                spacing: 8

                readonly property real cardSize: (width - 32 - 24) / 3

                Label {
                    x: 16
                    text: qsTr("Hall")
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Grid {
                    x: 16
                    columns: 3
                    rowSpacing: 12
                    columnSpacing: 12

                    Repeater {
                        model: 10

                        Rectangle {
                            readonly property bool isCurrent: root.currentZone === "hall" && root.currentTableNumber === index + 1
                            readonly property var occupant: root.occupantFor("hall", index + 1)
                            readonly property bool taken: root.isTaken("hall", index + 1)

                            width: contentCol.cardSize
                            height: contentCol.cardSize
                            radius: 14
                            color: isCurrent ? Theme.primary : Theme.surface
                            border.width: 1.5
                            border.color: isCurrent ? Theme.primary : Theme.border
                            opacity: taken ? 0.4 : 1

                            Label {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: (taken && occupant) ? -6 : 0
                                text: index + 1
                                font.pixelSize: 20 * Theme.fontScale
                                font.bold: true
                                color: isCurrent ? "white" : Theme.textPrimary
                            }

                            Label {
                                visible: taken && !!occupant
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: occupant ? occupant.waiter : ""
                                font.pixelSize: 10 * Theme.fontScale
                                color: Theme.textSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !taken
                                onClicked: {
                                    root.tableSelected("hall", index + 1)
                                    root.close()
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: 8 }

                Label {
                    x: 16
                    text: qsTr("Terrace")
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Grid {
                    x: 16
                    columns: 3
                    rowSpacing: 12
                    columnSpacing: 12

                    Repeater {
                        model: 10

                        Rectangle {
                            readonly property bool isCurrent: root.currentZone === "terrace" && root.currentTableNumber === index + 1
                            readonly property var occupant: root.occupantFor("terrace", index + 1)
                            readonly property bool taken: root.isTaken("terrace", index + 1)

                            width: contentCol.cardSize
                            height: contentCol.cardSize
                            radius: 14
                            color: isCurrent ? Theme.primary : Theme.surface
                            border.width: 1.5
                            border.color: isCurrent ? Theme.primary : Theme.border
                            opacity: taken ? 0.4 : 1

                            Label {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: (taken && occupant) ? -6 : 0
                                text: index + 1
                                font.pixelSize: 20 * Theme.fontScale
                                font.bold: true
                                color: isCurrent ? "white" : Theme.textPrimary
                            }

                            Label {
                                visible: taken && !!occupant
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: occupant ? occupant.waiter : ""
                                font.pixelSize: 10 * Theme.fontScale
                                color: Theme.textSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !taken
                                onClicked: {
                                    root.tableSelected("terrace", index + 1)
                                    root.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
