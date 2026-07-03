import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root

    property var theme
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

    // Cantități per produs (cheie = nume) + preț pentru total.
    property var qtyStore: ({})
    property var priceOf: ({})
    property int orderCount: 0
    property real orderTotal: 0
    property int orderRevision: 0   // forțează reevaluarea badge-urilor

    function fmt(v) {
        return v.toFixed(2).replace(".", ",")
    }

    function populateCategory(i) {
        productsModel.clear()
        var items = menuData[i].items
        for (var k = 0; k < items.length; ++k) {
            productsModel.append({
                name: items[k].name,
                unit: items[k].unit,
                price: items[k].price
            })
        }
    }

    function qtyFor(name) {
        return qtyStore[name] ? qtyStore[name] : 0
    }

    function changeQty(name, delta) {
        var q = (qtyStore[name] ? qtyStore[name] : 0) + delta
        if (q < 0) q = 0
        qtyStore[name] = q
        recompute()
    }

    function recompute() {
        var count = 0
        var total = 0
        for (var key in qtyStore) {
            count += qtyStore[key]
            total += qtyStore[key] * (priceOf[key] ? priceOf[key] : 0)
        }
        orderCount = count
        orderTotal = total
        orderRevision++
    }

    Component.onCompleted: {
        // Construim tabela de prețuri o singură dată.
        var map = {}
        for (var i = 0; i < menuData.length; ++i)
            for (var k = 0; k < menuData[i].items.length; ++k)
                map[menuData[i].items[k].name] = menuData[i].items[k].price
        priceOf = map
        populateCategory(currentCategory)
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

            // Back
            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                Rectangle {
                    x: 4; y: 12 - height / 2
                    width: 12; height: 2.4; radius: 1.2
                    color: theme.textPrimary
                    transformOrigin: Item.Left
                    rotation: -35
                }
                Rectangle {
                    x: 4; y: 12 - height / 2
                    width: 12; height: 2.4; radius: 1.2
                    color: theme.textPrimary
                    transformOrigin: Item.Left
                    rotation: 35
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: root.StackView.view.pop()
                }
            }

            Item { Layout.preferredWidth: 8 }

            ColumnLayout {
                spacing: 0
                Label {
                    text: "Masa " + root.tableNumber
                    font.pixelSize: 18
                    font.bold: true
                    color: theme.textPrimary
                }
                Label {
                    text: root.zone
                    font.pixelSize: 12
                    color: theme.textSecondary
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: root.fmt(root.orderTotal) + " MDL"
                font.pixelSize: 18
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
                    font.pixelSize: 14
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
                            font.pixelSize: 15
                            color: theme.textPrimary
                        }
                        Label {
                            text: unit + "  ·  " + root.fmt(price) + " MDL"
                            font.pixelSize: 12
                            color: theme.textSecondary
                        }
                    }

                    // Cantitatea curentă (dacă > 0) + controale
                    Label {
                        visible: (root.orderRevision, root.qtyFor(name)) > 0
                        text: (root.orderRevision, root.qtyFor(name))
                        font.pixelSize: 15
                        font.bold: true
                        color: theme.textPrimary
                        Layout.preferredWidth: 22
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Buton minus (doar când există cantitate)
                    Rectangle {
                        visible: (root.orderRevision, root.qtyFor(name)) > 0
                        width: 34; height: 34; radius: 17
                        color: theme.keyBackground
                        Rectangle {
                            anchors.centerIn: parent
                            width: 14; height: 2.4; radius: 1.2
                            color: theme.textPrimary
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.changeQty(name, -1)
                        }
                    }

                    // Buton plus
                    Rectangle {
                        width: 34; height: 34; radius: 17
                        color: theme.primary
                        Rectangle {
                            anchors.centerIn: parent
                            width: 14; height: 2.4; radius: 1.2
                            color: "white"
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 2.4; height: 14; radius: 1.2
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.changeQty(name, 1)
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
                        ? "Trimite comanda · " + root.orderCount + " · " + root.fmt(root.orderTotal) + " MDL"
                        : "Adaugă produse"
                    font.pixelSize: 15
                    font.bold: true
                    color: root.orderCount > 0 ? "white" : theme.textSecondary
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.orderCount > 0
                    onClicked: {
                        // Pasul următor: trimitere la bucătărie + în UAMenu.
                    }
                }
            }
        }
    }
}
