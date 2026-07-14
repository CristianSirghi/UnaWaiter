import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root

    property bool showMineOnly: true

    // Dicționar masă→zonă (din dataService.tables/uw_tables) - comenzile din
    // Oracle au doar DESK (un număr), zona se rezolvă separat de-aici.
    property var deskZone: ({})
    // Ultimul răspuns brut de la get_open_orders, păstrat ca să putem
    // reconstrui lista dacă tables/orders sosesc în ordine inversată.
    property var lastOrderRows: null
    property bool tablesReady: false
    property bool ordersReady: false
    property string loadError: ""

    signal newTableRequested()
    signal orderOpened(string zone, int tableNumber)
    signal profileRequested()
    signal settingsRequested()
    signal stockRequested()
    signal paidOrdersRequested()

    // "zone" e cod intern ("hall"/"terrace") — îl traducem la afișare, ca
    // antetele de secțiune să rămână corecte în orice limbă.
    function zoneLabel(zone) {
        return zone === "terrace" ? qsTr("Terrace") : qsTr("Hall")
    }

    // Ordinea zonelor în listă: sala înaintea terasei (ca la OrdersStore),
    // ca antetele de secțiune să nu se repete pentru mese amestecate.
    function zoneRank(zone) {
        return zone === "terrace" ? 1 : 0
    }

    function fmtTotal(v) {
        var n = parseFloat(v)
        if (isNaN(n))
            return "—"
        return n.toFixed(2).replace(".", ",") + " MDL"
    }

    function buildDeskZone(rows) {
        var map = ({})
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            map[parseInt(r.TABLE_NO)] = r.ZONE
        }
        root.deskZone = map
        root.tablesReady = true
        if (root.lastOrderRows !== null)
            root.buildOrders(root.lastOrderRows)
    }

    // Construiește lista de comenzi active (get_open_orders: STATE 1/2) din
    // răspunsul real al backend-ului. "editable" marchează dacă masa are o
    // copie locală în OrdersStore (comandă creată din ACEST dispozitiv/sesiune) -
    // fără ea, OrderPage n-ar avea de unde reîncărca liniile existente și ar
    // porni o comandă nouă goală pe o masă deja ocupată (ar dubla comanda în
    // Oracle). Editarea comenzilor reale de pe alte dispozitive e un pas
    // separat (get_order_lines există deja în backend, doar nu e cablat încă).
    function buildOrders(rows) {
        root.lastOrderRows = rows
        var items = []
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var hasDesk = r.DESK !== undefined && r.DESK !== null && String(r.DESK).trim() !== ""
            var deskNo = hasDesk ? parseInt(r.DESK) : 0
            var zone = (deskNo > 0 && root.deskZone[deskNo]) ? root.deskZone[deskNo] : "hall"
            var hasGuestCount = r.BARMEN !== undefined && r.BARMEN !== null && String(r.BARMEN).trim() !== ""

            items.push({
                zone: zone,
                tableNumber: deskNo,
                tableName: deskNo > 0 ? qsTr("Table %1").arg(deskNo) : qsTr("Unknown table"),
                active: true,
                orderTime: r.ORDER_TIME ? String(r.ORDER_TIME).trim() : "",
                waiterName: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderNo: "#" + (r.NR_COMAND !== undefined && r.NR_COMAND !== null ? String(r.NR_COMAND) : ""),
                preview: r.PREVIEW ? String(r.PREVIEW).trim() : "",
                guestCount: hasGuestCount ? parseInt(r.BARMEN) : 1,
                total: root.fmtTotal(r.CLCCOSTT),
                editable: deskNo > 0 && OrdersStore.hasOrder(zone, deskNo)
            })
        }

        items.sort(function(a, b) { return root.zoneRank(a.zone) - root.zoneRank(b.zone) })

        tableOrdersModel.clear()
        for (var j = 0; j < items.length; ++j)
            tableOrdersModel.append(items[j])
        root.ordersReady = true
    }

    function refreshOrders() {
        dataService.loadOpenOrders(root.showMineOnly ? String(AppSettings.waiterOficiant) : "")
    }

    ListModel { id: tableOrdersModel }

    Connections {
        target: dataService
        function onTablesChanged() { root.buildDeskZone(dataService.tables) }
        function onOpenOrdersChanged() { root.buildOrders(dataService.openOrders) }
        function onRequestFailed(command, error) {
            if (command === "get_open_orders" || command === "get_tables")
                root.loadError = error
        }
    }

    Component.onCompleted: {
        dataService.loadTables()
        root.refreshOrders()
    }

    // Reîmprospătare imediată de fiecare dată când revenim aici (ex. după ce
    // chelnerul trimite/editează o comandă în OrderPage) - nu așteptăm poll-ul
    // de mai jos doar pentru asta.
    StackView.onStatusChanged: {
        if (StackView.status === StackView.Active)
            root.refreshOrders()
    }

    // Poll ușor cât timp pagina e activă pe stivă - nici UAMenu nu are
    // auto-refresh pentru propriul grid, deci asta e echivalentul practic al
    // "live" (fără infrastructură nouă), ca să vadă chelnerul rapid când o
    // masă a fost achitată la casă și a dispărut din get_open_orders.
    Timer {
        interval: 25000
        repeat: true
        running: root.StackView.status === StackView.Active
        onTriggered: root.refreshOrders()
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 64

        Item { Layout.preferredWidth: 16 }

        Rectangle {
            width: 36
            height: 36
            radius: 18
            color: Theme.primary

            Label {
                anchors.centerIn: parent
                text: AppSettings.waiterName.length > 0
                    ? AppSettings.waiterName.charAt(0).toUpperCase()
                    : "W"
                color: "white"
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.profileRequested()
            }
        }

        Item { Layout.fillWidth: true }

        Icons.IconHamburger {
            color: Theme.textPrimary
            onClicked: navDrawer.open()
        }

        Item { Layout.preferredWidth: 16 }
    }

    Components.AppDrawer {
        id: navDrawer

        onProfileRequested: root.profileRequested()
        onSettingsRequested: root.settingsRequested()
        onStockRequested: root.stockRequested()
        onPaidOrdersRequested: root.paidOrdersRequested()
        onSignOutRequested: signOutDialog.open()
    }

    Components.ConfirmDialog {
        id: signOutDialog
        title: qsTr("Sign out?")
        message: qsTr("You will be logged out of your profile.")
        confirmText: qsTr("Sign out")
        destructive: true
        onConfirmed: root.StackView.view.pop(null)
    }

    // Avertisment când chelnerul apasă o masă ocupată de o comandă reală care
    // n-a fost creată din acest dispozitiv/sesiune - vezi comentariul din
    // buildOrders() despre riscul de comandă dublă.
    Components.ConfirmDialog {
        id: notEditableDialog
        title: qsTr("Not editable here yet")
        message: qsTr("This order was started on another device and can't be opened here yet.")
        confirmText: qsTr("OK")
        infoOnly: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item { Layout.fillWidth: true }

            Components.SegmentedControl {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 36
                labelHorizontalAlignment: Text.AlignLeft
                currentValue: root.showMineOnly ? "mine" : "all"
                options: [
                    { label: qsTr("Mine"), value: "mine" },
                    { label: qsTr("All"), value: "all" }
                ]
                onOptionSelected: {
                    root.showMineOnly = (value === "mine")
                    root.refreshOrders()
                }
            }
        }

        // Empty state — nicio comandă deschisă (doar după ce a sosit primul răspuns real).
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.ordersReady && root.loadError === "" && tableOrdersModel.count === 0
            spacing: 8

            Item { Layout.fillHeight: true }

            // Iconiță bon desenată din forme (fără dependență de font).
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 72

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.border
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle { width: 34; height: 3; radius: 1.5; color: Theme.border }
                    Rectangle { width: 34; height: 3; radius: 1.5; color: Theme.border }
                    Rectangle { width: 22; height: 3; radius: 1.5; color: Theme.border }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No open orders")
                font.pixelSize: 20 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("There are no open orders. Please start a new one.")
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            clip: true
            visible: tableOrdersModel.count > 0
            model: tableOrdersModel

            // Grupăm cardurile pe zonă (Sala / Terasă), cu un antet per grup.
            section.property: "zone"
            section.delegate: Label {
                width: ListView.view.width
                topPadding: 4
                bottomPadding: 8
                text: root.zoneLabel(section)
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: cardContent.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.color: Theme.border

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (editable)
                            root.orderOpened(zone, tableNumber)
                        else
                            notEditableDialog.open()
                    }
                }

                ColumnLayout {
                    id: cardContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: tableName
                            font.pixelSize: 16 * Theme.fontScale
                            font.bold: true
                            color: active ? Theme.primary : Theme.textSecondary
                        }

                        // Etichetă zonă (Sala / Terasă) — distinge masa 1 din sală de masa 1 de pe terasă.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: zoneTag.implicitWidth + 16
                            implicitHeight: zoneTag.implicitHeight + 6
                            radius: height / 2
                            color: Theme.keyBackground

                            Label {
                                id: zoneTag
                                anchors.centerIn: parent
                                text: root.zoneLabel(zone)
                                font.pixelSize: 11 * Theme.fontScale
                                color: Theme.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderTime
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: waiterName
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderNo
                            font.pixelSize: 13 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }

                    Label {
                        text: preview
                        font.pixelSize: 13 * Theme.fontScale
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: "👤 " + guestCount
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: total
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }
                }
            }
        }
    }

    // Stare de încărcare / eroare, cât timp mesele/comenzile reale sosesc.
    Label {
        anchors.centerIn: parent
        visible: !(root.ordersReady && root.tablesReady) && root.loadError === ""
        text: qsTr("Loading…")
        font.pixelSize: 15 * Theme.fontScale
        color: Theme.textSecondary
    }

    Label {
        anchors.centerIn: parent
        visible: root.loadError !== ""
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - 48
        wrapMode: Text.WordWrap
        text: qsTr("Couldn't load open orders:\n%1").arg(root.loadError)
        font.pixelSize: 15 * Theme.fontScale
        color: Theme.danger
    }

    Rectangle {
        width: 56
        height: 56
        radius: 28
        color: Theme.primary
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20

        Label {
            anchors.centerIn: parent
            text: "+"
            color: "white"
            font.pixelSize: 28 * Theme.fontScale
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.newTableRequested()
        }
    }
}
