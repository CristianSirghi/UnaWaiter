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

    // Pull-to-refresh (trage lista în jos de la vârf ca s-o reîmprospătezi
    // manual, în plus față de poll-ul automat la 25s).
    readonly property real pullThreshold: 70
    // true cât timp utilizatorul a tras dincolo de prag - săgeata se
    // răstoarnă, semnalând "eliberează pentru reîmprospătare".
    property bool pullArmed: false
    // true cât timp reîmprospătarea (declanșată de eliberare) e în curs -
    // antetul rămâne deschis, arătând punctele animate, până sosesc datele.
    property bool pullRefreshing: false
    // Baza de date răspunde aproape instant, deci fără un minim de timp
    // punctele ar clipi câteva milisecunde și n-ai vedea nimic. Ținem starea
    // "se reîmprospătează" cel puțin atâta, ca reîncărcarea din BD să fie
    // vizibilă (scopul: chelnerul vede clar re-sincronizarea cu UAMenu).
    readonly property int pullMinSpinMs: 700
    property bool pullDataArrived: false
    property bool pullMinElapsed: false

    // Închide starea de reîmprospătare doar când AMBELE condiții sunt
    // îndeplinite: datele au sosit din BD ȘI a trecut timpul minim vizibil.
    function maybeFinishRefresh() {
        if (root.pullRefreshing && root.pullDataArrived && root.pullMinElapsed)
            root.pullRefreshing = false
    }

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
        var openKeys = []
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var hasDesk = r.DESK !== undefined && r.DESK !== null && String(r.DESK).trim() !== ""
            var deskNo = hasDesk ? parseInt(r.DESK) : 0
            var zone = (deskNo > 0 && root.deskZone[deskNo]) ? root.deskZone[deskNo] : "hall"
            var hasGuestCount = r.BARMEN !== undefined && r.BARMEN !== null && String(r.BARMEN).trim() !== ""

            if (deskNo > 0)
                openKeys.push(OrdersStore.keyFor(zone, deskNo))

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

        OrdersStore.pruneMissing(openKeys)

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
        function onOpenOrdersChanged() {
            root.buildOrders(dataService.openOrders)
            root.pullDataArrived = true
            root.maybeFinishRefresh()
        }
        function onRequestFailed(command, error) {
            if (command === "get_open_orders" || command === "get_tables")
                root.loadError = error
            if (command === "get_open_orders") {
                root.pullDataArrived = true
                root.maybeFinishRefresh()
            }
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

    // Apelat din main.qml când butonul de back Android e apăsat pe această
    // pagină (ecranul "acasă" după login) - arată aceeași confirmare ca din
    // meniul hamburger, în loc să navigheze silențios înapoi la LoginPage
    // (ceea ce părea o deconectare bruscă, fără nicio întrebare).
    function confirmSignOut() {
        signOutDialog.open()
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

        // Container pentru listă + indicatorul de pull, care stă FIX în
        // spatele ei (z mai mic) - lista are fundal transparent, deci golul ei
        // de sus, dezvăluit natural la supra-tragere (contentY negativ) sau
        // cât timp topMargin ține locul deschis, lasă indicatorul să se vadă
        // prin el. Fără nicio urmărire manuală de contentY pe indicator -
        // asta a fost bug-ul (colapsa la 0 exact când se declanșa refresh-ul).
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: pullIndicator
                z: 0
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.pullThreshold

                readonly property real progress: root.pullRefreshing
                    ? 1
                    : Math.min(1, Math.max(0, -tableList.contentY) / root.pullThreshold)

                // Săgeată - vizibilă cât tragi, se răstoarnă când ai depășit pragul.
                Item {
                    anchors.centerIn: parent
                    visible: !root.pullRefreshing
                    opacity: pullIndicator.progress

                    Item {
                        anchors.centerIn: parent
                        rotation: root.pullArmed ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 150 } }

                        Icons.IconChevron {
                            anchors.centerIn: parent
                            expanded: true
                            color: root.pullArmed ? Theme.primary : Theme.textSecondary
                        }
                    }
                }

                // Trei puncte care pulsează pe rând cât timp cererea e în curs.
                Row {
                    anchors.centerIn: parent
                    visible: root.pullRefreshing
                    spacing: 6

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: Theme.primary

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: root.pullRefreshing
                                PauseAnimation { duration: index * 130 }
                                NumberAnimation { from: 0.25; to: 1; duration: 320; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1; to: 0.25; duration: 320; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            ListView {
                id: tableList
                z: 1
                anchors.fill: parent
                spacing: 12
                clip: true
                // Rămâne mereu vizibilă (chiar și goală) - altfel, cu
                // visible:false, Flickable-ul nu mai primește gesturi de
                // tragere deloc și pull-to-refresh nu mai poate fi declanșat
                // când nu există nicio comandă. Mesajul "Fără comenzi" e desenat
                // deasupra (vezi mai jos), nu ascunde lista.
                model: tableOrdersModel

                // Permite tragerea dincolo de vârf (efect elastic) - fără asta,
                // Flickable oprește contentY la 0 și n-avem cum detecta "trage
                // pentru reîmprospătare".
                boundsBehavior: Flickable.DragOverBounds

                // CRUCIAL: implicit flickableDirection e AutoFlickDirection, care
                // activează tragerea verticală DOAR când conținutul e mai înalt
                // decât ecranul. Cu o singură comandă (mult spațiu gol dedesubt),
                // lista n-ar reacționa deloc la tragere -> contentY rămâne 0 și
                // nu apare nicio reîmprospătare. Forțăm tragerea verticală mereu.
                flickableDirection: Flickable.VerticalFlick

                // Cât timp reîmprospătăm, ținem lista împinsă în jos cu un
                // topMargin animat, ca golul de sus (unde se vede pullIndicator
                // prin transparență) să rămână deschis cât durează cererea
                // reală, chiar dacă degetul s-a ridicat deja.
                topMargin: root.pullRefreshing ? root.pullThreshold : 0
                Behavior on topMargin {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                onContentYChanged: {
                    if (tableList.dragging && !root.pullRefreshing)
                        root.pullArmed = tableList.contentY < -root.pullThreshold
                }

                onDraggingChanged: {
                    if (!tableList.dragging && root.pullArmed && !root.pullRefreshing) {
                        root.pullArmed = false
                        root.pullDataArrived = false
                        root.pullMinElapsed = false
                        root.pullRefreshing = true
                        minSpinTimer.restart()
                        root.refreshOrders()
                    }
                }

            // Garantează că punctele de reîmprospătare rămân vizibile cel
            // puțin pullMinSpinMs, chiar dacă BD răspunde instant.
            Timer {
                id: minSpinTimer
                interval: root.pullMinSpinMs
                repeat: false
                onTriggered: {
                    root.pullMinElapsed = true
                    root.maybeFinishRefresh()
                }
            }

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

                    // (fără spacer fillHeight aici: cardul e dimensionat exact
                    // pe conținut - height: cardContent.implicitHeight + 28 -
                    // deci un Layout.fillHeight în interior crea o dependență
                    // circulară pe înălțime -> binding loop. N-avea spațiu de
                    // umplut oricum.)

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

        // Empty state — nicio comandă deschisă (doar după ce a sosit primul
        // răspuns real). Desenat DEASUPRA lui tableList (z mai mare), nu ca
        // frate în ColumnLayout-ul de mai sus - fără MouseArea propriu, deci
        // gesturile de tragere trec prin el direct la listă, iar
        // pull-to-refresh funcționează chiar și cu lista goală.
        ColumnLayout {
            z: 2
            anchors.fill: parent
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
        } // sfârșitul containerului listă + pullIndicator
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
