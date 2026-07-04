import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components

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

    // index = poziția rândului în productsModel (categoria curentă), pentru
    // a putea actualiza direct rolul "qty" și primi notificare corectă de la model.
    function changeQty(index, name, delta) {
        var oldQty = qtyStore[name] ? qtyStore[name] : 0
        var newQty = oldQty + delta
        if (newQty < 0) newQty = 0

        qtyStore[name] = newQty
        productsModel.setProperty(index, "qty", newQty)

        var qtyDelta = newQty - oldQty
        orderCount += qtyDelta
        orderTotal += qtyDelta * (priceOf[name] ? priceOf[name] : 0)
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
                            onClicked: root.changeQty(index, name, -1)
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
                            onClicked: root.changeQty(index, name, 1)
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
                        ? qsTr("Send order · %1 · %2 MDL").arg(root.orderCount).arg(root.fmt(root.orderTotal))
                        : qsTr("Add products")
                    font.pixelSize: 15 * theme.fontScale
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
