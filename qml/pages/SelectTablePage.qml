import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons
import "../app/Zones.js" as Zones

Page {
    id: root

    // Mesele ȘI zonele vin din backend (uw_tables + uw_zones, via
    // pg_mobile_web_waiter.get_tables) - nu mai sunt hardcodate aici, ca
    // restaurantul să poată adăuga/renumerota mese sau să deschidă o zonă nouă
    // din back-office, fără recompilare. Vezi app/Zones.js.
    property var zones: []
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

    // nrComand = 0 la o masă liberă (comandă nouă), altfel numărul comenzii deja
    // deschise pe ea, ca OrderPage s-o poată relua în loc să pornească alta.
    signal tableSelected(string zone, int tableNumber, int nrComand)
    // Comandă LA PACHET - fără masă. Semnal separat, nu o "masă specială":
    // n-are număr, nu poate fi ocupată și pot exista oricâte deodată.
    signal takeawayRequested()

    function buildTables(rows) {
        root.zones = Zones.build(rows)
        root.deskZone = Zones.deskZones(rows)
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
            var zone = root.deskZone[deskNo] ? root.deskZone[deskNo]
                                             : Zones.fallbackCode(root.zones)
            var nrComand = parseInt(r.NR_COMAND)
            map[zone + "_" + deskNo] = {
                waiter: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderNo: r.NR_COMAND !== undefined && r.NR_COMAND !== null ? String(r.NR_COMAND) : "",
                nrComand: isNaN(nrComand) ? 0 : nrComand
            }
        }
        root.occupiedByDesk = map
    }

    function occupiedInfo(zone, tableNumber) {
        return root.occupiedByDesk[zone + "_" + tableNumber]
    }

    // Masa are o comandă deschisă. Oricare ar fi ea, o poate relua oricine -
    // dialogul cere doar confirmarea, ca să nu ajungi din greșeală în comanda
    // altcuiva când voiai o masă liberă.
    //
    // "tableSelected" e exact acțiunea potrivită: primind numărul comenzii,
    // OrderPage o reîncarcă din Oracle (get_order_lines) în loc să pornească
    // una nouă. Nu e nevoie de nicio cale separată.
    //
    // Distincția "a mea"/"a altcuiva" a rămas doar pentru text: e liniștitor să
    // vezi scris al cui e bonul înainte să te bagi în el.
    function openOccupiedDialog(zone, tableNumber, info) {
        var mine = OrdersStore.isOwnLocalOrder(zone, tableNumber, AppSettings.waiterOficiant)

        occupiedDialog.zone = zone
        occupiedDialog.tableNumber = tableNumber
        occupiedDialog.nrComand = info.nrComand
        occupiedDialog.infoOnly = false
        occupiedDialog.title = mine ? qsTr("Your open order") : qsTr("Table occupied")
        occupiedDialog.confirmText = qsTr("Open the order")

        if (mine) {
            occupiedDialog.message = qsTr("Table %1 already has your open order (#%2). Open it?")
                .arg(tableNumber).arg(info.orderNo)
        } else {
            occupiedDialog.message = info.waiter
                ? qsTr("Table %1 is open by %2 (order #%3). Open that order?").arg(tableNumber).arg(info.waiter).arg(info.orderNo)
                : qsTr("Table %1 is already open (order #%2). Open that order?").arg(tableNumber).arg(info.orderNo)
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

        // Legenda culorilor, în dreapta titlului. Bulinele sunt Rectangle-uri,
        // nu emoji (🟢/🔴): emoji se desenează cu fontul de sistem, deci pe
        // Android vechi (font fără Emoji 12.0, de unde vine 🟢) ar ieși un
        // pătrățel gol, iar acolo unde apare arată altfel de la producător la
        // producător și nu ține cont nici de dark mode, nici de Theme.fontScale.
        //
        // Pe două rânduri, nu pe unul: așa ocupă ~50px în loc de ~110px, deci
        // titlul nu ajunge să fie tăiat nici pe rusă („Свободен"/„Занят"), nici
        // cu textul setat pe Mare.
        trailing: ColumnLayout {
            spacing: 2

            RowLayout {
                spacing: 5

                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: Theme.success
                }

                Label {
                    text: qsTr("Free")
                    font.pixelSize: 10 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }

            RowLayout {
                spacing: 5

                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: Theme.danger
                }

                Label {
                    text: qsTr("Occupied")
                    font.pixelSize: 10 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }
        }
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

            // ----- Zonele, în ordinea din uw_zones.display_order -----
            // O zonă fără mese active nu ajunge aici deloc (get_tables n-o mai
            // întoarce), deci "terasa închisă pe iarnă" dispare singură, la fel
            // ca înainte - doar că acum se face dintr-un UPDATE pe zonă.
            Repeater {
                model: root.zones

                Column {
                    id: zoneSection

                    // modelData e "capturat" aici fiindcă Repeater-ul de mese de
                    // mai jos îl umbrește cu numărul mesei.
                    readonly property var zoneData: modelData
                    readonly property int zoneIndex: index

                    width: contentCol.width
                    spacing: 8

                    Item { width: 1; height: zoneSection.zoneIndex > 0 ? 12 : 0 }

                    Label {
                        x: 16
                        text: Zones.label(zoneSection.zoneData, AppSettings.language)
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
                            model: zoneSection.zoneData.tables

                            Rectangle {
                                readonly property int tableNo: modelData
                                readonly property string zoneCode: zoneSection.zoneData.code
                                readonly property var occupied: root.occupiedInfo(zoneCode, tableNo)

                                width: contentCol.cardSize
                                height: contentCol.cardSize
                                radius: 14
                                color: occupied ? Theme.keyBackground : Theme.surface
                                border.width: 1.5
                                border.color: occupied ? Theme.border : Theme.primary

                                // Starea mesei, dincolo de culoarea cardului:
                                // gri-vs-alb se pierde în soare pe terasă, iar
                                // numele chelnerului de dedesubt apare doar la
                                // mesele ocupate, deci nu se poate compara.
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    color: occupied ? Theme.danger : Theme.success
                                }

                                Label {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: occupied ? -6 : 0
                                    text: tableNo
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
                                            root.openOccupiedDialog(zoneCode, tableNo, occupied)
                                        else
                                            root.tableSelected(zoneCode, tableNo, 0)
                                    }
                                }
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

        // Masa și comanda la care se referă dialogul, ca butonul de confirmare
        // să știe ce să deschidă. Titlul și mesajul sunt puse din
        // openOccupiedDialog, fiindcă depind de al cui e bonul.
        property string zone: ""
        property int tableNumber: 0
        property int nrComand: 0

        onConfirmed: root.tableSelected(occupiedDialog.zone, occupiedDialog.tableNumber,
                                        occupiedDialog.nrComand)
    }
}
