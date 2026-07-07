import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"

// Panou de jos pentru alegerea adaosurilor unui produs.
// Nu deține starea comenzii: primește lista de adaosuri prin openWith(...) și
// emite addonAdjusted(...) la fiecare +/- — pagina aplică modificarea și rămâne
// sursa unică de adevăr. Sheet-ul își actualizează doar propriul model afișat.
//
// Utilizare:
//   AddonSheet {
//       id: addonSheet
//       onAddonAdjusted: page.adjustAddon(productName, addonName, delta)
//   }
//   ...
//   addonSheet.openWith("Blinie cu somon", [{ name: "Smântână", price: 8, qty: 0 }, ...])
Popup {
    id: root

    property string productName: ""

    // Emis când chelnerul apasă +/- pe un adaos (delta = +1 / -1).
    signal addonAdjusted(string addonName, int delta)

    function fmt(v) {
        return v.toFixed(2).replace(".", ",")
    }

    // Deschide sheet-ul pentru un produs, cu adaosurile lui și cantitățile curente.
    // `addons` = listă de { name, price, qty }.
    function openWith(name, addons) {
        root.productName = name
        addonModel.clear()
        for (var i = 0; i < addons.length; ++i)
            addonModel.append({ name: addons[i].name, price: addons[i].price, qty: addons[i].qty })
        root.open()
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

    // Urcă de jos + fade, ca un bottom sheet. Doar "from" (enter) / "to" (exit) sunt
    // explicite — capătul rămas nespecificat se ia din binding-ul curent al lui "y"
    // (parent.height - height), deci poziționarea corectă rămâne validă și pentru
    // viitoare deschideri cu alt număr de adaosuri (înălțime diferită).
    enter: Transition {
        NumberAnimation { property: "y"; from: root.parent ? root.parent.height : 400; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    exit: Transition {
        NumberAnimation { property: "y"; to: root.parent ? root.parent.height : 400; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140 }
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    background: Rectangle {
        color: Theme.surface
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
                    font.pixelSize: 12 * Theme.fontScale
                    color: Theme.textSecondary
                }
                Label {
                    text: root.productName
                    font.pixelSize: 17 * Theme.fontScale
                    font.bold: true
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            IconClose {
                color: Theme.textSecondary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: root.close()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(addonModel.count, 5) * 56
            clip: true
            interactive: addonModel.count > 5
            model: ListModel { id: addonModel }

            delegate: Rectangle {
                width: ListView.view.width
                height: 56
                color: Theme.surface

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
                            font.pixelSize: 15 * Theme.fontScale
                            color: Theme.textPrimary
                        }
                        Label {
                            text: qsTr("+%1 MDL").arg(root.fmt(price))
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    Rectangle {
                        visible: qty > 0
                        width: 30; height: 30; radius: 15
                        color: Theme.keyBackground
                        IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.addonAdjusted(name, -1)
                                addonModel.setProperty(index, "qty", model.qty - 1)
                            }
                        }
                    }

                    Label {
                        visible: qty > 0
                        text: qty
                        Layout.preferredWidth: 18
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: Theme.primary
                        IconPlus { anchors.centerIn: parent; color: "white" }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.addonAdjusted(name, 1)
                                addonModel.setProperty(index, "qty", model.qty + 1)
                            }
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

        // Buton "Gata"
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 16
            Layout.preferredHeight: 48
            radius: 24
            color: Theme.primary

            Label {
                anchors.centerIn: parent
                text: qsTr("Done")
                font.pixelSize: 15 * Theme.fontScale
                font.bold: true
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }
    }
}
