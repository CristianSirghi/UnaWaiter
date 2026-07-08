import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root

    property string zone: ""
    property int tableNumber: 0

    // Semnalăm către main.qml că am terminat (trimis sau șters) — el ne readuce
    // la lista de mese, indiferent câte pagini sunt pe stivă.
    signal done()

    // ---- Meniu real (din backend, via dataService) ----
    // Structura pe categorii: [{ cat, grp, items: [{ name, unit, price, cod }] }].
    // Construită din dataService.categories + dataService.menu (vezi buildMenuData).
    // Produsele NU au încă `addons` — modelul de adaosuri (PARENT_NRORD) se face
    // într-un pas separat; până atunci UI-ul de adaosuri rămâne inactiv de la sine
    // (hasAddons devine false când produsul n-are câmpul `addons`).
    property var menuData: []
    // Codul de produs (bliuda) per nume — necesar la trimiterea comenzii (createOrder).
    // Deocamdată tot codul cheamă produsele după nume; codeOf face puntea nume→cod
    // pentru pasul de trimitere care urmează.
    property var codeOf: ({})
    // true după ce meniul a fost încărcat și structurat; până atunci arătăm "se încarcă".
    property bool menuReady: false
    property string loadError: ""

    property int currentCategory: 0
    property bool summaryExpanded: false
    readonly property int summaryMaxRows: 5
    // true dacă masa are deja o comandă trimisă (deschisă din TablesPage) — arată butonul de ștergere.
    property bool isEditing: false

    // Cantități per produs (cheie = nume, persistă la schimbarea categoriei).
    property var qtyStore: ({})
    // Adaosuri alese, grupate pe produsul-părinte: { numeProdus: { numeAdaos: cantitate } }.
    property var addonStore: ({})
    property int orderCount: 0
    property real orderTotal: 0
    // Numărul de oaspeți la masă (minim 1), ales de chelner și salvat cu comanda.
    property int guestCount: 1

    function fmt(v) {
        return v.toFixed(2).replace(".", ",")
    }

    // "zone" e un cod intern ("hall"/"terrace"), nu textul afișat — așa
    // rămâne corect indiferent de limba curentă a interfeței.
    function zoneLabel() {
        return zone === "terrace" ? qsTr("Terrace") : qsTr("Hall")
    }

    // Câte adaosuri (bucăți) sunt alese pentru un produs — pentru marcajul din rând.
    function addonCountFor(name) {
        var group = addonStore[name]
        if (!group) return 0
        var n = 0
        for (var a in group) n += group[a]
        return n
    }

    function populateCategory(i) {
        productsModel.clear()
        if (!menuData || i < 0 || i >= menuData.length)
            return
        var items = menuData[i].items
        for (var k = 0; k < items.length; ++k) {
            productsModel.append({
                name: items[k].name,
                unit: items[k].unit,
                price: items[k].price,
                qty: root.qtyStore[items[k].name] ? root.qtyStore[items[k].name] : 0,
                hasAddons: items[k].addons !== undefined && items[k].addons.length > 0,
                addonCount: root.addonCountFor(items[k].name)
            })
        }
    }

    // Recalculează numărul de produse și totalul (părinți + adaosuri) din stări.
    // Mai robust decât actualizarea incrementală, mai ales cu adaosuri legate de produs.
    function recomputeTotals() {
        var count = 0
        var total = 0
        for (var ci = 0; ci < menuData.length; ++ci) {
            var items = menuData[ci].items
            for (var ii = 0; ii < items.length; ++ii) {
                var p = items[ii]
                var pq = qtyStore[p.name] ? qtyStore[p.name] : 0
                if (pq <= 0) continue
                count += pq
                total += pq * p.price
                if (p.addons) {
                    for (var ai = 0; ai < p.addons.length; ++ai) {
                        var a = p.addons[ai]
                        var aq = (addonStore[p.name] && addonStore[p.name][a.name]) ? addonStore[p.name][a.name] : 0
                        total += aq * a.price
                    }
                }
            }
        }
        orderCount = count
        orderTotal = total
    }

    // Reconstruiește lista pentru panoul "Comandă curentă": fiecare produs urmat de
    // adaosurile lui (rânduri-copil, marcate cu isAddon pentru indentare).
    function rebuildSelectedModel() {
        selectedModel.clear()
        for (var ci = 0; ci < menuData.length; ++ci) {
            var items = menuData[ci].items
            for (var ii = 0; ii < items.length; ++ii) {
                var p = items[ii]
                var pq = qtyStore[p.name] ? qtyStore[p.name] : 0
                if (pq <= 0) continue
                selectedModel.append({ isAddon: false, parentName: "", name: p.name, qty: pq, lineTotal: pq * p.price })
                if (p.addons) {
                    for (var ai = 0; ai < p.addons.length; ++ai) {
                        var a = p.addons[ai]
                        var aq = (addonStore[p.name] && addonStore[p.name][a.name]) ? addonStore[p.name][a.name] : 0
                        if (aq > 0)
                            selectedModel.append({ isAddon: true, parentName: p.name, name: a.name, qty: aq, lineTotal: aq * a.price })
                    }
                }
            }
        }
    }

    // Actualizează marcajul de adaosuri dintr-un rând de produs (dacă e vizibil acum).
    function refreshRowAddonCount(name) {
        for (var i = 0; i < productsModel.count; ++i) {
            if (productsModel.get(i).name === name) {
                productsModel.setProperty(i, "addonCount", addonCountFor(name))
                break
            }
        }
    }

    // Modifică cantitatea unui produs. La 0, îi eliminăm și adaosurile.
    function adjustQty(name, delta) {
        var oldQty = qtyStore[name] ? qtyStore[name] : 0
        var newQty = oldQty + delta
        if (newQty < 0) newQty = 0
        if (newQty === oldQty) return

        qtyStore[name] = newQty
        if (newQty === 0 && addonStore[name])
            delete addonStore[name]

        for (var i = 0; i < productsModel.count; ++i) {
            if (productsModel.get(i).name === name) {
                productsModel.setProperty(i, "qty", newQty)
                productsModel.setProperty(i, "addonCount", addonCountFor(name))
                break
            }
        }

        recomputeTotals()
        rebuildSelectedModel()
    }

    // Construiește lista de adaosuri a unui produs (cu cantitățile curente) pentru AddonSheet.
    function addonListFor(productName) {
        var list = []
        for (var ci = 0; ci < menuData.length; ++ci) {
            var items = menuData[ci].items
            for (var ii = 0; ii < items.length; ++ii) {
                if (items[ii].name === productName && items[ii].addons) {
                    var addons = items[ii].addons
                    for (var ai = 0; ai < addons.length; ++ai) {
                        var a = addons[ai]
                        var cur = (addonStore[productName] && addonStore[productName][a.name])
                            ? addonStore[productName][a.name] : 0
                        list.push({ name: a.name, price: a.price, qty: cur })
                    }
                }
            }
        }
        return list
    }

    // Modifică cantitatea unui adaos legat de un produs (necesită produsul-părinte prezent).
    function adjustAddon(parent, addonName, delta) {
        if ((qtyStore[parent] ? qtyStore[parent] : 0) <= 0) return
        if (!addonStore[parent]) addonStore[parent] = {}

        var oldQty = addonStore[parent][addonName] ? addonStore[parent][addonName] : 0
        var newQty = oldQty + delta
        if (newQty < 0) newQty = 0
        if (newQty === oldQty) return

        addonStore[parent][addonName] = newQty

        refreshRowAddonCount(parent)
        recomputeTotals()
        rebuildSelectedModel()
    }

    function submitOrder() {
        OrdersStore.submitOrder(
            root.zone,
            root.tableNumber,
            qsTr("Table %1").arg(root.tableNumber),
            AppSettings.waiterName.length > 0 ? AppSettings.waiterName : qsTr("Waiter"),
            root.qtyStore,
            root.addonStore,
            root.guestCount,
            qsTr("%1 MDL").arg(root.fmt(root.orderTotal))
        )
        root.done()
    }

    function deleteOrder() {
        OrdersStore.removeOrder(root.zone, root.tableNumber)
        root.done()
    }

    // Grupează lista plată de produse (dataService.menu) pe categorii
    // (dataService.categories), păstrând ordinea categoriilor. Sare peste
    // categoriile fără produse, ca să nu apară tab-uri goale. Tot aici
    // completăm hărțile preț/cod per nume de produs.
    function buildMenuData(cats, items) {
        var byGrp = ({})
        var codeMap = ({})

        for (var i = 0; i < items.length; ++i) {
            var it = items[i]
            var grp = parseInt(it.GRP)
            var nm = it.DENUMIREA
            var prod = {
                name: nm,
                unit: it.UM ? it.UM : "",
                price: parseFloat(it.PRET),
                cod: parseInt(it.COD)
            }
            if (!byGrp[grp])
                byGrp[grp] = []
            byGrp[grp].push(prod)
            codeMap[nm] = prod.cod
        }

        var built = []
        for (var c = 0; c < cats.length; ++c) {
            var ccod = parseInt(cats[c].COD)
            var list = byGrp[ccod]
            if (!list || list.length === 0)
                continue
            built.push({ cat: cats[c].DENUMIREA, grp: ccod, items: list })
        }

        root.menuData = built
        root.codeOf = codeMap
    }

    // Construim meniul o singură dată, când AMBELE surse au sosit
    // (categorii + produse vin prin semnale separate).
    function tryBuildMenu() {
        if (root.menuReady)
            return
        var cats = dataService.categories
        var items = dataService.menu
        if (cats.length === 0 || items.length === 0)
            return

        buildMenuData(cats, items)
        root.menuReady = true
        root.setupAfterMenu()
    }

    // Rulează după ce meniul e gata: reîncarcă o comandă existentă (deocamdată
    // din OrdersStore mock) și populează categoria curentă.
    function setupAfterMenu() {
        var existing = OrdersStore ? OrdersStore.itemsFor(root.zone, root.tableNumber) : ({})
        var loadedQty = {}
        var hasExisting = false
        for (var name in existing) {
            hasExisting = true
            loadedQty[name] = existing[name]
        }
        if (hasExisting) {
            root.isEditing = true
            root.qtyStore = loadedQty
            var savedAddons = OrdersStore.addonsFor(root.zone, root.tableNumber)
            var loadedAddons = {}
            for (var pn in savedAddons) {
                loadedAddons[pn] = {}
                for (var an in savedAddons[pn])
                    loadedAddons[pn][an] = savedAddons[pn][an]
            }
            root.addonStore = loadedAddons
            root.guestCount = OrdersStore.guestsFor(root.zone, root.tableNumber)
            recomputeTotals()
        }

        if (root.currentCategory >= root.menuData.length)
            root.currentCategory = 0
        populateCategory(currentCategory)
        rebuildSelectedModel()
    }

    Connections {
        target: dataService

        function onMenuChanged() { root.tryBuildMenu() }
        function onCategoriesChanged() { root.tryBuildMenu() }
        function onRequestFailed(command, error) {
            if (command === "get_menu" || command === "get_categories")
                root.loadError = error
        }
    }

    Component.onCompleted: {
        // Cerem tot meniul dintr-o dată (categorie 0 = tot), plus dicționarul
        // de categorii. tryBuildMenu le îmbină când amândouă sosesc.
        dataService.loadCategories()
        dataService.loadMenu(0)
    }

    background: Rectangle {
        color: Theme.background
    }

    // ---------- Header ----------
    header: Rectangle {
        color: Theme.surface
        height: 60

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16

            Components.BackButton {
                color: Theme.textPrimary
                onClicked: root.StackView.view.pop()
            }

            Item { Layout.preferredWidth: 8 }

            ColumnLayout {
                spacing: 0
                Label {
                    text: qsTr("Table %1").arg(root.tableNumber)
                    font.pixelSize: 18 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                }
                Label {
                    text: root.zoneLabel()
                    font.pixelSize: 12 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("%1 MDL").arg(root.fmt(root.orderTotal))
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.primary
            }
        }
    }

    // ---------- Conținut ----------
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Chips de categorii
        ListView {
            id: categoryList
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            orientation: ListView.Horizontal
            spacing: 8
            leftMargin: 16
            rightMargin: 16
            clip: true
            model: root.menuData

            delegate: Rectangle {
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                height: 36
                width: catLabel.implicitWidth + 32
                radius: 18
                color: index === root.currentCategory ? Theme.primary : Theme.surface
                border.width: 1
                border.color: index === root.currentCategory ? Theme.primary : Theme.border

                Label {
                    id: catLabel
                    anchors.centerIn: parent
                    text: modelData.cat
                    font.pixelSize: 14 * Theme.fontScale
                    color: index === root.currentCategory ? "white" : Theme.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.currentCategory = index
                        root.populateCategory(index)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // Lista de produse
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel { id: productsModel }

            delegate: Rectangle {
                width: ListView.view.width
                // Înălțimea derivă din conținutul rândului (nume pe 1 sau 2 rânduri),
                // cu un minim pentru rândurile scurte. Important: lățimea curge
                // dinspre rând spre RowLayout (left+right ancorate), iar înălțimea
                // curge invers (din implicitHeight) — fără buclă, ca să se așeze
                // corect din prima, nu abia după un +/−.
                height: Math.max(66, rowLayout.implicitHeight + 20)
                color: Theme.surface

                RowLayout {
                    id: rowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    ColumnLayout {
                        id: infoColumn
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        // Numele se încadrează pe max 2 rânduri, ca butoanele +/−
                        // să nu fie împinse afară de produsele cu nume lung.
                        Label {
                            text: name
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: 15 * Theme.fontScale
                            color: Theme.textPrimary
                        }
                        Label {
                            text: qsTr("%1  ·  %2 MDL").arg(unit).arg(root.fmt(price))
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }

                        // Link "Adaosuri" — apare doar la produsele cu adaosuri, după ce
                        // au fost adăugate. Arată câte adaosuri sunt alese.
                        Rectangle {
                            visible: qty > 0 && hasAddons
                            Layout.topMargin: 2
                            implicitWidth: addonLink.implicitWidth + 20
                            implicitHeight: addonLink.implicitHeight + 8
                            radius: height / 2
                            color: addonCount > 0 ? Theme.primary : "transparent"
                            border.width: 1
                            border.color: Theme.primary

                            Label {
                                id: addonLink
                                anchors.centerIn: parent
                                text: addonCount > 0
                                    ? qsTr("Add-ons · %1").arg(addonCount)
                                    : qsTr("Add-ons")
                                font.pixelSize: 12 * Theme.fontScale
                                font.bold: true
                                color: addonCount > 0 ? "white" : Theme.primary
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: addonSheet.openWith(name, root.addonListFor(name))
                            }
                        }
                    }

                    // Cantitatea curentă (dacă > 0) + controale
                    Label {
                        visible: qty > 0
                        text: qty
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Buton minus (doar când există cantitate)
                    Rectangle {
                        visible: qty > 0
                        Layout.alignment: Qt.AlignVCenter
                        width: 34; height: 34; radius: 17
                        color: Theme.keyBackground
                        Icons.IconMinus {
                            anchors.centerIn: parent
                            color: Theme.textPrimary
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.adjustQty(name, -1)
                        }
                    }

                    // Buton plus
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 34; height: 34; radius: 17
                        color: Theme.primary
                        Icons.IconPlus {
                            anchors.centerIn: parent
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.adjustQty(name, 1)
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                }
            }
        }

        // Panou "Comandă curentă" — rezumatul produselor deja selectate, ca
        // chelnerul să poată revedea comanda cu clientul înainte de trimitere.
        Rectangle {
            id: summaryPanel
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryExpanded
                ? 48 + Math.min(selectedModel.count, root.summaryMaxRows) * 44
                : 48
            color: Theme.surface
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

            ListModel { id: selectedModel }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        // Selector oaspeți (butoane proprii, minim 1).
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            Icons.IconPerson {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                color: Theme.textSecondary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.keyBackground
                                opacity: root.guestCount > 1 ? 1 : 0.4
                                Icons.IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (root.guestCount > 1) root.guestCount -= 1
                                }
                            }

                            Label {
                                text: root.guestCount
                                Layout.preferredWidth: 16
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 15 * Theme.fontScale
                                font.bold: true
                                color: Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.primary
                                Icons.IconPlus { anchors.centerIn: parent; color: "white" }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.guestCount += 1
                                }
                            }
                        }

                        // Zonă de extindere (rezumat produse) — MouseArea proprie,
                        // separată de butoanele de oaspeți ca să nu se suprapună.
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: root.orderCount > 0
                                        ? qsTr("%1 products selected").arg(root.orderCount)
                                        : qsTr("No products selected")
                                    font.pixelSize: 14 * Theme.fontScale
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                }

                                Icons.IconChevron {
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Theme.textSecondary
                                    expanded: root.summaryExpanded
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.orderCount > 0
                                onClicked: root.summaryExpanded = !root.summaryExpanded
                            }
                        }
                    }
                }

                ListView {
                    visible: root.summaryExpanded
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(selectedModel.count, root.summaryMaxRows) * 44
                    clip: true
                    model: selectedModel

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 44
                        color: Theme.surface

                        RowLayout {
                            anchors.fill: parent
                            // Adaosurile sunt indentate față de produsul-părinte.
                            anchors.leftMargin: isAddon ? 32 : 16
                            anchors.rightMargin: 16
                            spacing: 8

                            // Marcaj vizual pentru adaos (liniuță).
                            Label {
                                visible: isAddon
                                text: "+"
                                font.pixelSize: 14 * Theme.fontScale
                                color: Theme.textSecondary
                            }

                            Label {
                                text: name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: (isAddon ? 13 : 14) * Theme.fontScale
                                color: isAddon ? Theme.textSecondary : Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.keyBackground
                                Icons.IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: isAddon ? root.adjustAddon(parentName, name, -1) : root.adjustQty(name, -1)
                                }
                            }

                            Label {
                                text: qty
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 14 * Theme.fontScale
                                color: Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.primary
                                Icons.IconPlus { anchors.centerIn: parent; color: "white" }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: isAddon ? root.adjustAddon(parentName, name, 1) : root.adjustQty(name, 1)
                                }
                            }

                            Label {
                                text: qsTr("%1 MDL").arg(root.fmt(lineTotal))
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 14 * Theme.fontScale
                                font.bold: !isAddon
                                color: isAddon ? Theme.textSecondary : Theme.textPrimary
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Theme.border
                        }
                    }
                }
            }
        }

        // Bara de jos — ștergere (doar la editare) + trimite comanda
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: Theme.surface

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                // Buton ștergere comandă (contur roșu; deschide dialogul de confirmare).
                Rectangle {
                    visible: root.isEditing
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.danger

                    Icons.IconTrash {
                        anchors.centerIn: parent
                        color: Theme.danger
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: deleteDialog.open()
                    }
                }

                // Butonul principal — trimite comanda.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 24
                    color: root.orderCount > 0 ? Theme.primary : Theme.border

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.orderCount > 0
                            ? qsTr("Send order · %1 · %2 MDL").arg(root.orderCount).arg(root.fmt(root.orderTotal))
                            : qsTr("Add products")
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: root.orderCount > 0 ? "white" : Theme.textSecondary
                        // Textul lung se micșorează ca să încapă în buton, în loc să iasă pe margini.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 10
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.orderCount > 0
                        onClicked: root.submitOrder()
                    }
                }
            }
        }
    }

    // Stare de încărcare / eroare peste zona de conținut, până sosește meniul.
    Label {
        anchors.centerIn: parent
        visible: !root.menuReady
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - 48
        wrapMode: Text.WordWrap
        text: root.loadError !== ""
            ? qsTr("Couldn't load the menu:\n%1").arg(root.loadError)
            : qsTr("Loading menu…")
        font.pixelSize: 15 * Theme.fontScale
        color: root.loadError !== "" ? Theme.danger : Theme.textSecondary
    }

    Components.ConfirmDialog {
        id: deleteDialog
        title: qsTr("Delete order?")
        message: qsTr("The order for %1 will be removed.").arg(qsTr("Table %1").arg(root.tableNumber))
        confirmText: qsTr("Delete")
        destructive: true
        onConfirmed: root.deleteOrder()
    }

    // Sheet de jos pentru alegerea adaosurilor unui produs (vezi components/AddonSheet.qml).
    Components.AddonSheet {
        id: addonSheet
        onAddonAdjusted: root.adjustAddon(addonSheet.productName, addonName, delta)
    }
}
