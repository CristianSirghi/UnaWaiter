import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

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
    // Comandă LA PACHET - fără masă. Semnal separat, nu o "masă specială":
    // n-are număr, nu poate fi ocupată și pot exista oricâte deodată.
    signal takeawayRequested()

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

    // Masa are o comandă deschisă. Dacă e chiar comanda chelnerului logat, de
    // pe ACEST telefon, îi oferim s-o deschidă direct de aici - înainte dialogul
    // avea doar "OK", deci trebuia să ieși din ecran și s-o cauți în lista de
    // mese, deși erai deja cu degetul pe masa ei.
    //
    // "tableSelected" e exact acțiunea potrivită: OrderPage recunoaște singur o
    // comandă existentă (OrdersStore.itemsFor) și o reîncarcă din Oracle, în loc
    // să pornească una nouă. Nu e nevoie de nicio cale separată.
    function openOccupiedDialog(zone, tableNumber, info) {
        var mine = OrdersStore.isEditableBy(zone, tableNumber, AppSettings.waiterOficiant)

        occupiedDialog.zone = zone
        occupiedDialog.tableNumber = tableNumber
        occupiedDialog.infoOnly = !mine
        occupiedDialog.title = mine ? qsTr("Your open order") : qsTr("Table occupied")
        occupiedDialog.confirmText = mine ? qsTr("Open the order") : qsTr("OK")

        if (mine) {
            occupiedDialog.message = qsTr("Table %1 already has your open order (#%2). Open it?")
                .arg(tableNumber).arg(info.orderNo)
        } else {
            occupiedDialog.message = info.waiter
                ? qsTr("Table %1 is already open by %2 (order #%3).").arg(tableNumber).arg(info.waiter).arg(info.orderNo)
                : qsTr("Table %1 is already open (order #%2).").arg(tableNumber).arg(info.orderNo)
        }
        occupiedDialog.open()
    }

    Connections {
        target: dataService

        function onTablesChanged() { root.buildTables(dataService.tables) }
        // tableOccupancy e o proprietate separată de openOrders (vezi
        // DataService) - dacă am fi refolosit openOrders aici, cererea
        // nefiltrată ar fi suprascris lista filtrată "Ale mele"/"Toate" a
        // TablesPage-ului, care ascultă același semnal chiar și cât timp
        // stă sub SelectTablePage/OrderPage pe stivă.
        function onTableOccupancyChanged() { root.buildOccupied(dataService.tableOccupancy) }
        function onRequestFailed(command, error) {
            if (command === "get_tables")
                root.loadError = error
        }
    }

    Component.onCompleted: {
        dataService.loadTables()
        dataService.loadTableOccupancy()
    }

    // Ocuparea meselor se schimbă sub noi: alt chelner deschide o masă cât timp
    // stăm pe grilă, sau ne întoarcem aici cu back din OrderPage după ce chiar
    // noi am ocupat una. Înainte se cerea o singură dată, la deschiderea
    // paginii, deci grila putea arăta liberă o masă deja luată - exact
    // scenariul pe care blocarea meselor trebuie să-l prevină.
    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active)
            dataService.loadTableOccupancy()
    }

    // Poll ușor cât timp pagina e activă, ca la TablesPage/AchitatePage.
    Timer {
        interval: 25000
        repeat: true
        running: root.StackView.status === StackView.Active
        onTriggered: dataService.loadTableOccupancy()
    }

    background: Rectangle {
        color: Theme.background
    }

    header: Components.PageHeader {
        title: qsTr("Select table")
        onBackRequested: root.StackView.view.pop()
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

                        Components.TouchArea {
                            anchors.fill: parent
                            onClicked: {
                                if (occupied)
                                    root.openOccupiedDialog("hall", modelData, occupied)
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

                        Components.TouchArea {
                            anchors.fill: parent
                            onClicked: {
                                if (occupied)
                                    root.openOccupiedDialog("terrace", modelData, occupied)
                                else
                                    root.tableSelected("terrace", modelData)
                            }
                        }
                    }
                }
            }

            // ----- La pachet -----
            // Jos, după mese, fiindcă e rar (pe producție ~2 comenzi fără masă
            // pe zi făcute de chelneri, față de zeci la mese). Lat, nu pătrat ca
            // mesele: e altfel de alegere, nu "masa 21" - altfel s-ar apăsa din
            // greșeală când chelnerul țintește ultima masă.
            Item { width: 1; height: 16; visible: root.tablesReady }

            Rectangle {
                x: 16
                width: contentCol.width - 32
                height: 1
                color: Theme.border
                visible: root.tablesReady
            }

            Item { width: 1; height: 16; visible: root.tablesReady }

            Rectangle {
                x: 16
                width: contentCol.width - 32
                height: 68
                radius: 14
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.primary
                visible: root.tablesReady

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: qsTr("Takeaway")
                            font.pixelSize: 17 * Theme.fontScale
                            font.bold: true
                            color: Theme.primary
                        }

                        Label {
                            text: qsTr("Order without a table")
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    // Fără `rotation` pus de aici: IconChevron își leagă singur
                    // rotation de `expanded`, iar o valoare din afară ar rupe
                    // acea legătură. Implicit arată deja ">".
                    Icons.IconChevron {
                        Layout.alignment: Qt.AlignVCenter
                        color: Theme.textSecondary
                    }
                }

                Components.TouchArea {
                    anchors.fill: parent
                    onClicked: root.takeawayRequested()
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

        // Masa la care se referă dialogul, ca butonul de confirmare să știe ce
        // să deschidă. Titlul/mesajul/infoOnly sunt puse din openOccupiedDialog,
        // fiindcă depind de cine deține comanda.
        property string zone: ""
        property int tableNumber: 0

        // Doar când NU e infoOnly (adică e comanda ta) confirmarea chiar are ce
        // face; în modul informativ butonul e un simplu "OK" care doar închide.
        onConfirmed: {
            if (!occupiedDialog.infoOnly)
                root.tableSelected(occupiedDialog.zone, occupiedDialog.tableNumber)
        }
    }
}
