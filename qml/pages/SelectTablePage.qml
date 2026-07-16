import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    // Mesele vin din backend (uw_tables, via pg_mobile_web_waiter.get_tables) -
    // nu mai sunt hardcodate aici, ca restaurantul să poată adăuga/renumerota
    // mese doar cu un INSERT/UPDATE în Oracle, fără recompilare.
    property var hallTables: []
    property var terraceTables: []
    property bool tablesReady: false
    property string loadError: ""

    // Masă→zonă, ca să putem interpreta DESK-urile din get_open_orders (care
    // n-au zonă) - vezi buildOccupied.
    property var deskZone: ({})
    // "zonă_masă" → { waiter, orderNo } pentru orice masă cu o comandă
    // deschisă în Oracle, indiferent cine a creat-o sau de pe ce telefon -
    // interogăm backend-ul direct (get_open_orders FĂRĂ filtru de chelner),
    // nu ne bazăm pe OrdersStore (cache local, gol la fiecare pornire), ca
    // să nu se mai poată deschide a doua comandă pe o masă deja ocupată.
    property var occupiedByDesk: ({})
    // Răspunsul brut de la get_open_orders, păstrat ca să reconstruim harta
    // dacă sosește înaintea mapării masă→zonă.
    property var lastOpenOrderRows: null

    signal tableSelected(string zone, int tableNumber)

    function buildTables(rows) {
        var hall = []
        var terrace = []
        var zoneMap = {}
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var no = parseInt(r.TABLE_NO)
            zoneMap[no] = r.ZONE
            if (r.ZONE === "hall")
                hall.push(no)
            else if (r.ZONE === "terrace")
                terrace.push(no)
        }
        root.hallTables = hall
        root.terraceTables = terrace
        root.deskZone = zoneMap
        root.tablesReady = true
        if (root.lastOpenOrderRows !== null)
            root.buildOccupied(root.lastOpenOrderRows)
    }

    function buildOccupied(rows) {
        root.lastOpenOrderRows = rows
        var map = {}
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var hasDesk = r.DESK !== undefined && r.DESK !== null && String(r.DESK).trim() !== ""
            if (!hasDesk) continue
            var deskNo = parseInt(r.DESK)
            if (deskNo <= 0) continue
            var zone = root.deskZone[deskNo] ? root.deskZone[deskNo] : "hall"
            map[zone + "_" + deskNo] = {
                waiter: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderNo: r.NR_COMAND !== undefined && r.NR_COMAND !== null ? String(r.NR_COMAND) : ""
            }
        }
        root.occupiedByDesk = map
    }

    function occupiedInfo(zone, tableNumber) {
        return root.occupiedByDesk[zone + "_" + tableNumber]
    }

    function openOccupiedDialog(tableNumber, info) {
        occupiedDialog.message = info.waiter
            ? qsTr("Table %1 is already open by %2 (order #%3).").arg(tableNumber).arg(info.waiter).arg(info.orderNo)
            : qsTr("Table %1 is already open (order #%2).").arg(tableNumber).arg(info.orderNo)
        occupiedDialog.open()
    }

    Connections {
        target: dataService

        function onTablesChanged() { root.buildTables(dataService.tables) }
        function onOpenOrdersChanged() { root.buildOccupied(dataService.openOrders) }
        function onRequestFailed(command, error) {
            if (command === "get_tables")
                root.loadError = error
        }
    }

    Component.onCompleted: {
        dataService.loadTables()
        // Fără filtru de chelner - vrem TOATE mesele ocupate, nu doar ale mele.
        dataService.loadOpenOrders("")
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 12 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.preferredWidth: 8 }

        Label {
            text: qsTr("Select table")
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: parent.width
            topPadding: 16
            bottomPadding: 24
            spacing: 8

            // Lățimea unui card de masă (3 coloane, margini 16, spațiu 12).
            readonly property real cardSize: (width - 32 - 24) / 3

            // ----- Sala -----
            Label {
                x: 16
                text: qsTr("Hall")
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Grid {
                x: 16
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: root.hallTables

                    Rectangle {
                        readonly property var occupied: root.occupiedInfo("hall", modelData)

                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: occupied ? Theme.keyBackground : Theme.surface
                        border.width: 1.5
                        border.color: occupied ? Theme.border : Theme.primary

                        Label {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: occupied ? -6 : 0
                            text: modelData
                            font.pixelSize: 22 * Theme.fontScale
                            font.bold: true
                            color: occupied ? Theme.textSecondary : Theme.primary
                        }

                        Label {
                            visible: !!occupied
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: occupied ? occupied.waiter : ""
                            font.pixelSize: 11 * Theme.fontScale
                            color: Theme.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (occupied)
                                    root.openOccupiedDialog(modelData, occupied)
                                else
                                    root.tableSelected("hall", modelData)
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 12; visible: root.terraceTables.length > 0 }

            // ----- Terasă (ascunsă dacă nu există mese active, ex. sezon închis) -----
            Label {
                x: 16
                visible: root.terraceTables.length > 0
                text: qsTr("Terrace")
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Grid {
                x: 16
                visible: root.terraceTables.length > 0
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: root.terraceTables

                    Rectangle {
                        readonly property var occupied: root.occupiedInfo("terrace", modelData)

                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: occupied ? Theme.keyBackground : Theme.surface
                        border.width: 1.5
                        border.color: occupied ? Theme.border : Theme.primary

                        Label {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: occupied ? -6 : 0
                            text: modelData
                            font.pixelSize: 22 * Theme.fontScale
                            font.bold: true
                            color: occupied ? Theme.textSecondary : Theme.primary
                        }

                        Label {
                            visible: !!occupied
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: occupied ? occupied.waiter : ""
                            font.pixelSize: 11 * Theme.fontScale
                            color: Theme.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (occupied)
                                    root.openOccupiedDialog(modelData, occupied)
                                else
                                    root.tableSelected("terrace", modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // Stare de încărcare / eroare, până sosesc mesele.
    Label {
        anchors.centerIn: parent
        visible: !root.tablesReady
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - 48
        wrapMode: Text.WordWrap
        text: root.loadError !== ""
            ? qsTr("Couldn't load tables:\n%1").arg(root.loadError)
            : qsTr("Loading tables…")
        font.pixelSize: 15 * Theme.fontScale
        color: root.loadError !== "" ? Theme.danger : Theme.textSecondary
    }

    // Avertisment când chelnerul apasă o masă cu o comandă deschisă de
    // oricine (alt chelner sau alt telefon) - vezi occupiedByDesk mai sus.
    Components.ConfirmDialog {
        id: occupiedDialog
        title: qsTr("Table occupied")
        infoOnly: true
        confirmText: qsTr("OK")
    }
}
