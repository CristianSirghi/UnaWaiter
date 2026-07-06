import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components

Page {
    id: root

    property var theme
    property var settings
    property var store
    property string zone: ""
    property int tableNumber: 0

    // Semnalăm către main.qml că am terminat (trimis sau șters) — el ne readuce
    // la lista de mese, indiferent câte pagini sunt pe stivă.
    signal done()

    // ---- Meniu mock (până vine backend-ul Oracle) ----
    // Unele produse au `addons` — adaosuri legate de produs (ex. smântână la blini).
    readonly property var menuData: [
        { cat: "Blini", items: [
            { name: "Blinie cu unt", unit: "185g", price: 18.50, addons: [
                { name: "Smântână", price: 8.00 },
                { name: "Dulceață", price: 10.00 },
                { name: "Miere", price: 12.00 }
            ] },
            { name: "Blinie cu brânză", unit: "220g", price: 22.00, addons: [
                { name: "Smântână", price: 8.00 }
            ] },
            { name: "Blinie cu cașcaval", unit: "210g", price: 21.00 },
            { name: "Blinie cu somon", unit: "220g", price: 60.00, addons: [
                { name: "Smântână", price: 8.00 },
                { name: "Icre roșii", price: 45.00 }
            ] }
        ] },
        { cat: "Salate", items: [
            { name: "Salată Cezar", unit: "250g", price: 45.00, addons: [
                { name: "Extra pui", price: 20.00 },
                { name: "Parmezan", price: 15.00 }
            ] },
            { name: "Salată grecească", unit: "230g", price: 38.00 }
        ] },
        { cat: "Supe", items: [
            { name: "Ciorbă de burtă", unit: "300g", price: 40.00 },
            { name: "Zeamă de casă", unit: "300g", price: 35.00 }
        ] },
        { cat: "Băuturi", items: [
            { name: "Coca-cola 0.5l", unit: "0.5l", price: 20.00 },
            { name: "Apă plată", unit: "0.5l", price: 15.00 }
        ] },
        { cat: "Desert", items: [
            { name: "Tiramisu", unit: "150g", price: 42.00 },
            { name: "Înghețată", unit: "100g", price: 25.00 }
        ] }
    ]

    property int currentCategory: 0
    property bool summaryExpanded: false
    readonly property int summaryMaxRows: 5
    // true dacă masa are deja o comandă trimisă (deschisă din TablesPage) — arată butonul de ștergere.
    property bool isEditing: false

    // Cantități per produs (cheie = nume, persistă la schimbarea categoriei) + preț pentru total.
    property var qtyStore: ({})
    property var priceOf: ({})
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
        root.store.submitOrder(
            root.zone,
            root.tableNumber,
            qsTr("Table %1").arg(root.tableNumber),
            root.settings.waiterName.length > 0 ? root.settings.waiterName : qsTr("Waiter"),
            root.qtyStore,
            root.addonStore,
            root.guestCount,
            qsTr("%1 MDL").arg(root.fmt(root.orderTotal))
        )
        root.done()
    }

    function deleteOrder() {
        root.store.removeOrder(root.zone, root.tableNumber)
        root.done()
    }

    Component.onCompleted: {
        // Construim tabela de prețuri o singură dată.
        var map = {}
        for (var i = 0; i < menuData.length; ++i)
            for (var k = 0; k < menuData[i].items.length; ++k)
                map[menuData[i].items[k].name] = menuData[i].items[k].price
        priceOf = map

        // Dacă masa are deja o comandă trimisă, o reîncărcăm pentru editare.
        var existing = root.store ? root.store.itemsFor(root.zone, root.tableNumber) : ({})
        var loadedQty = {}
        var hasExisting = false
        for (var name in existing) {
            hasExisting = true
            loadedQty[name] = existing[name]
        }
        if (hasExisting) {
            root.isEditing = true
            root.qtyStore = loadedQty
            // Copiem adaosurile salvate (obiect nou pe fiecare părinte, ca să nu mutăm referința din store).
            var savedAddons = root.store.addonsFor(root.zone, root.tableNumber)
            var loadedAddons = {}
            for (var pn in savedAddons) {
                loadedAddons[pn] = {}
                for (var an in savedAddons[pn])
                    loadedAddons[pn][an] = savedAddons[pn][an]
            }
            root.addonStore = loadedAddons
            root.guestCount = root.store.guestsFor(root.zone, root.tableNumber)
            recomputeTotals()
        }

        populateCategory(currentCategory)
        rebuildSelectedModel()
    }

    background: Rectangle {
        color: theme.background
    }

    // ---------- Header ----------
    header: Rectangle {
        color: theme.surface
        height: 60

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16

            Components.BackButton {
                color: theme.textPrimary
                onClicked: root.StackView.view.pop()
            }

            Item { Layout.preferredWidth: 8 }

            ColumnLayout {
                spacing: 0
                Label {
                    text: qsTr("Table %1").arg(root.tableNumber)
                    font.pixelSize: 18 * theme.fontScale
                    font.bold: true
                    color: theme.textPrimary
                }
                Label {
                    text: root.zoneLabel()
                    font.pixelSize: 12 * theme.fontScale
                    color: theme.textSecondary
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("%1 MDL").arg(root.fmt(root.orderTotal))
                font.pixelSize: 18 * theme.fontScale
                font.bold: true
                color: theme.primary
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
                color: index === root.currentCategory ? theme.primary : theme.surface
                border.width: 1
                border.color: index === root.currentCategory ? theme.primary : theme.border

                Label {
                    id: catLabel
                    anchors.centerIn: parent
                    text: modelData.cat
                    font.pixelSize: 14 * theme.fontScale
                    color: index === root.currentCategory ? "white" : theme.textPrimary
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

        Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

        // Lista de produse
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel { id: productsModel }

            delegate: Rectangle {
                width: ListView.view.width
                // Rândul crește când arătăm linkul de adaosuri sub produs.
                height: (qty > 0 && hasAddons) ? 88 : 66
                color: theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            text: name
                            font.pixelSize: 15 * theme.fontScale
                            color: theme.textPrimary
                        }
                        Label {
                            text: qsTr("%1  ·  %2 MDL").arg(unit).arg(root.fmt(price))
                            font.pixelSize: 12 * theme.fontScale
                            color: theme.textSecondary
                        }

                        // Link "Adaosuri" — apare doar la produsele cu adaosuri, după ce
                        // au fost adăugate. Arată câte adaosuri sunt alese.
                        Rectangle {
                            visible: qty > 0 && hasAddons
                            Layout.topMargin: 2
                            implicitWidth: addonLink.implicitWidth + 20
                            implicitHeight: addonLink.implicitHeight + 8
                            radius: height / 2
                            color: addonCount > 0 ? theme.primary : "transparent"
                            border.width: 1
                            border.color: theme.primary

                            Label {
                                id: addonLink
                                anchors.centerIn: parent
                                text: addonCount > 0
                                    ? qsTr("Add-ons · %1").arg(addonCount)
                                    : qsTr("Add-ons")
                                font.pixelSize: 12 * theme.fontScale
                                font.bold: true
                                color: addonCount > 0 ? "white" : theme.primary
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: addonSheet.openFor(name)
                            }
                        }
                    }

                    // Cantitatea curentă (dacă > 0) + controale
                    Label {
                        visible: qty > 0
                        text: qty
                        font.pixelSize: 15 * theme.fontScale
                        font.bold: true
                        color: theme.textPrimary
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Buton minus (doar când există cantitate)
                    Rectangle {
                        visible: qty > 0
                        Layout.alignment: Qt.AlignVCenter
                        width: 34; height: 34; radius: 17
                        color: theme.keyBackground
                        Components.IconMinus {
                            anchors.centerIn: parent
                            color: theme.textPrimary
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
                        color: theme.primary
                        Components.IconPlus {
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
                    color: theme.border
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
            color: theme.surface
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.border }

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

                            Components.IconPerson {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                color: theme.textSecondary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: theme.keyBackground
                                opacity: root.guestCount > 1 ? 1 : 0.4
                                Components.IconMinus { anchors.centerIn: parent; color: theme.textPrimary }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (root.guestCount > 1) root.guestCount -= 1
                                }
                            }

                            Label {
                                text: root.guestCount
                                Layout.preferredWidth: 16
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 15 * theme.fontScale
                                font.bold: true
                                color: theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: theme.primary
                                Components.IconPlus { anchors.centerIn: parent; color: "white" }
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
                                    font.pixelSize: 14 * theme.fontScale
                                    font.bold: true
                                    color: theme.textPrimary
                                    elide: Text.ElideRight
                                }

                                Components.IconChevron {
                                    Layout.alignment: Qt.AlignVCenter
                                    color: theme.textSecondary
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
                        color: theme.surface

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
                                font.pixelSize: 14 * theme.fontScale
                                color: theme.textSecondary
                            }

                            Label {
                                text: name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: (isAddon ? 13 : 14) * theme.fontScale
                                color: isAddon ? theme.textSecondary : theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: theme.keyBackground
                                Components.IconMinus { anchors.centerIn: parent; color: theme.textPrimary }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: isAddon ? root.adjustAddon(parentName, name, -1) : root.adjustQty(name, -1)
                                }
                            }

                            Label {
                                text: qty
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 14 * theme.fontScale
                                color: theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: theme.primary
                                Components.IconPlus { anchors.centerIn: parent; color: "white" }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: isAddon ? root.adjustAddon(parentName, name, 1) : root.adjustQty(name, 1)
                                }
                            }

                            Label {
                                text: qsTr("%1 MDL").arg(root.fmt(lineTotal))
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 14 * theme.fontScale
                                font.bold: !isAddon
                                color: isAddon ? theme.textSecondary : theme.textPrimary
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: theme.border
                        }
                    }
                }
            }
        }

        // Bara de jos — ștergere (doar la editare) + trimite comanda
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: theme.surface

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.border }

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
                    border.color: theme.danger

                    Components.IconTrash {
                        anchors.centerIn: parent
                        color: theme.danger
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
                    color: root.orderCount > 0 ? theme.primary : theme.border

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.orderCount > 0
                            ? qsTr("Send order · %1 · %2 MDL").arg(root.orderCount).arg(root.fmt(root.orderTotal))
                            : qsTr("Add products")
                        font.pixelSize: 15 * theme.fontScale
                        font.bold: true
                        color: root.orderCount > 0 ? "white" : theme.textSecondary
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

    Components.ConfirmDialog {
        id: deleteDialog
        theme: root.theme
        title: qsTr("Delete order?")
        message: qsTr("The order for %1 will be removed.").arg(qsTr("Table %1").arg(root.tableNumber))
        confirmText: qsTr("Delete")
        destructive: true
        onConfirmed: root.deleteOrder()
    }

    // Panou de jos pentru alegerea adaosurilor unui produs. Strâns legat de starea
    // paginii (addonStore), deci îl ținem inline, nu ca un component generic.
    Popup {
        id: addonSheet

        property string parentName: ""

        // Populează sheet-ul cu adaosurile produsului și cantitățile curente.
        function openFor(productName) {
            addonSheet.parentName = productName
            addonSheetModel.clear()
            for (var ci = 0; ci < root.menuData.length; ++ci) {
                var items = root.menuData[ci].items
                for (var ii = 0; ii < items.length; ++ii) {
                    if (items[ii].name === productName && items[ii].addons) {
                        var addons = items[ii].addons
                        for (var ai = 0; ai < addons.length; ++ai) {
                            var a = addons[ai]
                            var cur = (root.addonStore[productName] && root.addonStore[productName][a.name])
                                ? root.addonStore[productName][a.name] : 0
                            addonSheetModel.append({ name: a.name, price: a.price, qty: cur })
                        }
                    }
                }
            }
            addonSheet.open()
        }

        parent: Overlay.overlay
        modal: true
        dim: true
        padding: 0
        width: parent ? parent.width : 400
        x: 0
        y: parent ? parent.height - height : 0
        height: sheetContent.implicitHeight
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#99000000" }

        background: Rectangle {
            color: root.theme.surface
            radius: 16
        }

        contentItem: ColumnLayout {
            id: sheetContent
            spacing: 0

            // Antet: numele produsului + închidere
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: qsTr("Add-ons")
                        font.pixelSize: 12 * root.theme.fontScale
                        color: root.theme.textSecondary
                    }
                    Label {
                        text: addonSheet.parentName
                        font.pixelSize: 17 * root.theme.fontScale
                        font.bold: true
                        color: root.theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Components.IconClose {
                    color: root.theme.textSecondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: addonSheet.close()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.theme.border }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(addonSheetModel.count, 5) * 56
                clip: true
                interactive: addonSheetModel.count > 5
                model: ListModel { id: addonSheetModel }

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 56
                    color: root.theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: name
                                font.pixelSize: 15 * root.theme.fontScale
                                color: root.theme.textPrimary
                            }
                            Label {
                                text: qsTr("+%1 MDL").arg(root.fmt(price))
                                font.pixelSize: 12 * root.theme.fontScale
                                color: root.theme.textSecondary
                            }
                        }

                        Rectangle {
                            visible: qty > 0
                            width: 30; height: 30; radius: 15
                            color: root.theme.keyBackground
                            Components.IconMinus { anchors.centerIn: parent; color: root.theme.textPrimary }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.adjustAddon(addonSheet.parentName, name, -1)
                                    addonSheetModel.setProperty(index, "qty", model.qty - 1)
                                }
                            }
                        }

                        Label {
                            visible: qty > 0
                            text: qty
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 15 * root.theme.fontScale
                            font.bold: true
                            color: root.theme.textPrimary
                        }

                        Rectangle {
                            width: 30; height: 30; radius: 15
                            color: root.theme.primary
                            Components.IconPlus { anchors.centerIn: parent; color: "white" }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.adjustAddon(addonSheet.parentName, name, 1)
                                    addonSheetModel.setProperty(index, "qty", model.qty + 1)
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: root.theme.border
                    }
                }
            }

            // Buton "Gata"
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.preferredHeight: 48
                radius: 24
                color: root.theme.primary

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Done")
                    font.pixelSize: 15 * root.theme.fontScale
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: addonSheet.close()
                }
            }
        }
    }
}
