import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons
import "../app/ListSync.js" as ListSync
import "../app/Format.js" as Format
import "../app/Zones.js" as Zones

Page {
    id: root

    property bool showMineOnly: true

    // Dicționar masă→zonă (din dataService.tables/uw_tables) - comenzile din
    // Oracle au doar DESK (un număr), zona se rezolvă separat de-aici.
    property var deskZone: ({})
    // Zonele restaurantului (uw_zones), pentru denumirea și ordinea secțiunilor.
    property var zones: []
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
    signal paidOrdersRequested()

    // "zone" e cod intern ("hall", "terrace", "etaj2"…) — denumirea afișată vine
    // din uw_zones, în limba curentă. "takeaway" NU e o zonă din bază, ci una
    // virtuală a aplicației, deci rămâne tradusă cu qsTr.
    function zoneLabel(zone) {
        if (zone === "takeaway")
            return qsTr("Takeaway")
        return Zones.labelFor(root.zones, zone, AppSettings.language)
    }

    // Ordinea zonelor în listă: cea din uw_zones.display_order (aceeași ca în
    // SelectTablePage, fiindcă vine din același răspuns), apoi comenzile la
    // pachet la urmă — ca antetele de secțiune să nu se repete pentru mese
    // amestecate. O zonă necunoscută (masă rămasă dintr-o zonă ștearsă) se duce
    // înaintea celor la pachet, nu peste ele.
    function zoneRank(zone) {
        if (zone === "takeaway")
            return 100000
        for (var i = 0; i < root.zones.length; ++i) {
            if (root.zones[i].code === zone)
                return i
        }
        return 99999
    }

    function buildDeskZone(rows) {
        root.deskZone = Zones.deskZones(rows)
        root.zones = Zones.build(rows)
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
            // NaN nu e nici > 0, nici <= 0 - fără normalizarea asta, un DESK
            // nenumeric ar fi scăpat de ambele ramuri de mai jos și ar fi ajuns
            // pe card ca "Masa NaN". Îl tratăm ca "fără masă utilizabilă".
            if (isNaN(deskNo))
                deskNo = 0
            var nrComandStr = (r.NR_COMAND !== undefined && r.NR_COMAND !== null)
                ? String(r.NR_COMAND).trim() : ""
            var nrComand = parseInt(nrComandStr)
            if (isNaN(nrComand))
                nrComand = 0

            // Comandă fără masă = comandă la pachet. `tableNumber` nu mai e un
            // număr de masă, ci numărul comenzii - singura identitate stabilă a
            // unei comenzi fără masă, și cheia sub care o ține OrdersStore
            // ("takeaway-<nr_comand>"). Vezi OrderPage.finishSubmit.
            var isTakeaway = !hasDesk || deskNo <= 0
            var zone = isTakeaway
                ? "takeaway"
                : (root.deskZone[deskNo] ? root.deskZone[deskNo]
                                         : Zones.fallbackCode(root.zones))
            var placeNo = isTakeaway ? nrComand : deskNo

            if (placeNo > 0)
                openKeys.push(OrdersStore.keyFor(zone, placeNo))

            items.push({
                // Identitatea rândului pentru ListSync. E numărul real de
                // comandă, nu masa: o comandă mutată pe altă masă rămâne
                // ACELAȘI rând (se actualizează pe loc), în loc să dispară și
                // să reapară. Rezerva pe indice acoperă cazul (teoretic) al
                // unei comenzi fără NR_COMAND - două astfel de rânduri ar avea
                // altfel aceeași cheie și s-ar contopi.
                rowKey: nrComandStr !== "" ? ("nr" + nrComandStr) : ("row" + i),
                zone: zone,
                tableNumber: placeNo,
                isTakeaway: isTakeaway,
                tableName: isTakeaway
                    ? qsTr("Takeaway")
                    : qsTr("Table %1").arg(deskNo),
                active: true,
                orderTime: r.ORDER_TIME ? String(r.ORDER_TIME).trim() : "",
                waiterName: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderNo: "#" + nrComandStr,
                preview: r.PREVIEW ? String(r.PREVIEW).trim() : "",
                // Numărul de clienți e local, nu vine din Oracle: coloana
                // BARMEN/PERSON pe care o foloseam nu e "număr de persoane", ci
                // codul casierului turei (TMS_CASIR.DEP) - îl scriam peste și
                // stricam atribuirea liniilor în documentul din back-office.
                guestCount: placeNo > 0 ? OrdersStore.guestsFor(zone, placeNo) : 1,
                total: Format.money(r.CLCCOSTT),
                // Nu doar "există local", ci "există local ȘI e a chelnerului
                // logat acum" - altfel, când altcineva preia telefonul
                // (deconectare, sau "Schimbă utilizatorul" din ecranul de PIN),
                // al doilea chelner găsea comenzile primului deschise spre
                // editare. Cache-ul supraviețuiește intenționat schimbării de
                // utilizator, ca primul să nu-și piardă mesele la re-logare -
                // de-aici nevoia verificării de proprietar, în loc de golire.
                editable: placeNo > 0
                    && OrdersStore.isEditableBy(zone, placeNo, AppSettings.waiterOficiant)
            })
        }

        // Al doilea argument = chelnerul pe care e filtrată lista de mai sus.
        // Fără el, un refresh pe "Ale mele" curăța și comenzile altui chelner
        // care a folosit acest telefon - vezi comentariul din pruneMissing.
        OrdersStore.pruneMissing(openKeys,
                                 root.showMineOnly ? AppSettings.waiterOficiant : 0)

        items.sort(function(a, b) { return root.zoneRank(a.zone) - root.zoneRank(b.zone) })

        // Actualizare pe loc, nu clear() + append: poll-ul de 25s (și fiecare
        // revenire pe pagină) resetau altfel derularea listei, aruncând
        // chelnerul înapoi la prima masă în mijlocul căutării.
        ListSync.sync(tableOrdersModel, items, "rowKey")
        root.ordersReady = true
    }

    function refreshOrders() {
        dataService.loadOpenOrders(root.showMineOnly ? String(AppSettings.waiterOficiant) : "")
    }

    ListModel { id: tableOrdersModel }

    Connections {
        target: dataService
        function onTablesChanged() {
            root.loadError = ""
            root.buildDeskZone(dataService.tables)
        }
        function onOpenOrdersChanged() {
            // Un răspuns reușit înseamnă că suntem iar online - ștergem orice
            // eroare rămasă de la un blip anterior, altfel mesajul roșu
            // "Couldn't load open orders" rămânea înfipt pe ecran până la
            // repornirea aplicației, chiar dacă totul funcționa iar.
            root.loadError = ""
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

    // `height`, nu `implicitHeight`: Page isi dimensioneaza antetul dupa asta,
    // iar restul continutului porneste de sub el.
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

            Components.TouchArea {
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
        message: qsTr("This order was started by another waiter or on another device, so it can't be opened here.")
        confirmText: qsTr("OK")
        infoOnly: true
    }

    // Stare conexiune la server - deschis din beculețul de sus. Mesajul e legat
    // de dataService.online, deci se actualizează live dacă statusul se schimbă
    // cât dialogul e deschis (checkConnection a cerut un ping proaspăt).
    Components.ConfirmDialog {
        id: connectionDialog
        title: qsTr("Server connection")
        message: (dataService.online
                    ? qsTr("Connected to the server.")
                    : qsTr("No connection to the server."))
                 + "\n\n" + qsTr("Server: %1").arg(AppSettings.serverUrl)
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

            // Beculeț stare conexiune la server: verde = conectat, roșu =
            // pierdut. Tap → dialog cu detalii. Pe același rând cu filtrul.
            Rectangle {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                radius: 7
                color: dataService.online ? Theme.success : Theme.danger

                Components.TouchArea {
                    anchors.fill: parent
                    anchors.margins: -10   // zonă de atingere mai generoasă
                    circular: true
                    onClicked: {
                        dataService.checkConnection()
                        connectionDialog.open()
                    }
                }
            }

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

            delegate: Rectangle {
                width: ListView.view.width
                height: cardContent.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.color: Theme.border

                Components.TouchArea {
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
                        // La pachet ar repeta exact titlul cardului, deci o ascundem.
                        Rectangle {
                            visible: !isTakeaway
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

                        // Numărul de clienți n-are sens la o comandă la pachet
                        // (nu stă nimeni la masă) - acolo rămâne mereu 1.
                        Label {
                            visible: !isTakeaway
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

            // Blocul nu mai stă la mijlocul ecranului: spațiul liber se împarte
            // 3 sus / 4 jos, deci urcă cu ~7% din înălțime. Proporție, nu o
            // margine fixă în pixeli, ca să arate la fel pe orice diagonală.
            Item { Layout.fillHeight: true; Layout.preferredHeight: 3 }

            // Desenul are fundal transparent (doar liniile), deci merge la fel
            // pe tema deschisă și pe cea închisă, fără o a doua variantă de
            // fișier ca la logout.png/logout_white.png.
            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 96 * Theme.fontScale
                Layout.preferredHeight: Layout.preferredWidth * 645 / 631
                source: "qrc:/icons/file.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
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

            Item { Layout.fillHeight: true; Layout.preferredHeight: 4 }
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

        Components.TouchArea {
            anchors.fill: parent
            onClicked: root.newTableRequested()
        }
    }
}
