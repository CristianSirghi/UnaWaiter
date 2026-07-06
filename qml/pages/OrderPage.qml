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

    // ---- Meniu mock (până vine backend-ul Oracle) ----
    readonly property var menuData: [
        { cat: "Blini", items: [
            { name: "Blinie cu unt", unit: "185g", price: 18.50 },
            { name: "Blinie cu brânză", unit: "220g", price: 22.00 },
            { name: "Blinie cu cașcaval", unit: "210g", price: 21.00 },
            { name: "Blinie cu somon", unit: "220g", price: 60.00 }
        ] },
        { cat: "Salate", items: [
            { name: "Salată Cezar", unit: "250g", price: 45.00 },
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

    // Cantități per produs (cheie = nume, persistă la schimbarea categoriei) + preț pentru total.
    property var qtyStore: ({})
    property var priceOf: ({})
    property int orderCount: 0
    property real orderTotal: 0

    function fmt(v) {
        return v.toFixed(2).replace(".", ",")
    }

    // "zone" e un cod intern ("hall"/"terrace"), nu textul afișat — așa
    // rămâne corect indiferent de limba curentă a interfeței.
    function zoneLabel() {
        return zone === "terrace" ? qsTr("Terrace") : qsTr("Hall")
    }

    function populateCategory(i) {
        productsModel.clear()
        var items = menuData[i].items
        for (var k = 0; k < items.length; ++k) {
            productsModel.append({
                name: items[k].name,
                unit: items[k].unit,
                price: items[k].price,
                qty: root.qtyStore[items[k].name] ? root.qtyStore[items[k].name] : 0
            })
        }
    }

    // Reconstruiește lista de produse selectate (pentru panoul "Comandă curentă"),
    // afișată separat de lista completă a categoriei curente.
    function rebuildSelectedModel() {
        selectedModel.clear()
        for (var name in root.qtyStore) {
            var qty = root.qtyStore[name]
            if (qty > 0) {
                selectedModel.append({
                    name: name,
                    qty: qty,
                    price: root.priceOf[name] ? root.priceOf[name] : 0
                })
            }
        }
    }

    // Modifică cantitatea unui produs după nume — folosită atât din lista
    // completă a categoriei curente, cât și din panoul "Comandă curentă".
    function adjustQty(name, delta) {
        var oldQty = qtyStore[name] ? qtyStore[name] : 0
        var newQty = oldQty + delta
        if (newQty < 0) newQty = 0
        if (newQty === oldQty) return

        qtyStore[name] = newQty

        for (var i = 0; i < productsModel.count; ++i) {
            if (productsModel.get(i).name === name) {
                productsModel.setProperty(i, "qty", newQty)
                break
            }
        }

        var qtyDelta = newQty - oldQty
        orderCount += qtyDelta
        orderTotal += qtyDelta * (priceOf[name] ? priceOf[name] : 0)

        rebuildSelectedModel()
    }

    function submitOrder() {
        root.store.submitOrder(
            root.zone,
            root.tableNumber,
            qsTr("Table %1").arg(root.tableNumber),
            root.settings.waiterName.length > 0 ? root.settings.waiterName : qsTr("Waiter"),
            root.qtyStore,
            1,
            qsTr("%1 MDL").arg(root.fmt(root.orderTotal))
        )
        root.StackView.view.pop()
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
        var count = 0
        var total = 0
        var hasExisting = false
        for (var name in existing) {
            hasExisting = true
            var qty = existing[name]
            loadedQty[name] = qty
            count += qty
            total += qty * (priceOf[name] ? priceOf[name] : 0)
        }
        if (hasExisting) {
            root.qtyStore = loadedQty
            root.orderCount = count
            root.orderTotal = total
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
                height: 66
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
                    }

                    // Cantitatea curentă (dacă > 0) + controale
                    Label {
                        visible: qty > 0
                        text: qty
                        font.pixelSize: 15 * theme.fontScale
                        font.bold: true
                        color: theme.textPrimary
                        Layout.preferredWidth: 22
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Buton minus (doar când există cantitate)
                    Rectangle {
                        visible: qty > 0
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

                        Label {
                            Layout.fillWidth: true
                            text: root.orderCount > 0
                                ? qsTr("%1 products selected").arg(root.orderCount)
                                : qsTr("No products selected")
                            font.pixelSize: 14 * theme.fontScale
                            font.bold: true
                            color: theme.textPrimary
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
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 8

                            Label {
                                text: name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: 14 * theme.fontScale
                                color: theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: theme.keyBackground
                                Components.IconMinus { anchors.centerIn: parent; color: theme.textPrimary }
                                MouseArea { anchors.fill: parent; onClicked: root.adjustQty(name, -1) }
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
                                MouseArea { anchors.fill: parent; onClicked: root.adjustQty(name, 1) }
                            }

                            Label {
                                text: qsTr("%1 MDL").arg(root.fmt(qty * price))
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 14 * theme.fontScale
                                font.bold: true
                                color: theme.textPrimary
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

        // Bara de jos — trimite comanda
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: theme.surface

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.border }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 32
                height: 48
                radius: 24
                color: root.orderCount > 0 ? theme.primary : theme.border

                Label {
                    anchors.centerIn: parent
                    text: root.orderCount > 0
                        ? qsTr("Send order · %1 · %2 MDL").arg(root.orderCount).arg(root.fmt(root.orderTotal))
                        : qsTr("Add products")
                    font.pixelSize: 15 * theme.fontScale
                    font.bold: true
                    color: root.orderCount > 0 ? "white" : theme.textSecondary
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
