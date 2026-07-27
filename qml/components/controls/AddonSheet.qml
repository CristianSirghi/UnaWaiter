import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../icons"
import "../../app/Format.js" as Format

// Panou de jos pentru alegerea adaosurilor unui produs.
// Nu deține starea comenzii: primește lista de adaosuri prin openWith(...) și
// emite addonAdjusted(...) la fiecare +/- — pagina aplică modificarea și rămâne
// sursa unică de adevăr. Sheet-ul își actualizează doar propriul model afișat.
//
// Utilizare:
//   AddonSheet {
//       id: addonSheet
//       onAddonAdjusted: page.adjustAddon(addonSheet.productCode, addonName, delta)
//   }
//   ...
//   addonSheet.openWith(1234, "Blinie cu somon", [{ name: "Smântână", price: 8, qty: 0 }, ...])
Popup {
    id: root

    // Codul produsului-părinte (vms_bliuda.cod) - cheia sub care pagina ține
    // adaosurile. Numele e doar pentru afișare: nu e unic în meniu, deci nu
    // poate identifica produsul (vezi comentariul de la productByCode din
    // OrderPage.qml).
    property int productCode: 0
    property string productName: ""

    // Emis când chelnerul apasă +/- pe un adaos (delta = +1 / -1).
    signal addonAdjusted(string addonName, int delta)

    // Deschide sheet-ul pentru un produs, cu adaosurile lui și cantitățile curente.
    // `addons` = listă de { name, price, qty }.
    function openWith(code, name, addons) {
        root.productCode = code
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

    // Urcă de jos + fade, ca un bottom sheet.
    //
    // CORECȚIE: varianta veche lăsa un capăt al animației nespecificat, crezând
    // că se ia din legătura lui `y`. De fapt animația SCRIE în `y`, iar scrierea
    // distruge legătura - după o închidere `y` rămânea la marginea de jos a
    // ecranului, deci "capătul implicit" al următoarei intrări era tot acolo și
    // sheet-ul nu se mai vedea deloc. Acum ambele capete sunt explicite, iar
    // legătura se reface după intrare (ca să se repoziționeze corect când se
    // deschide cu alt număr de adaosuri).
    onOpened: y = Qt.binding(function() {
        return root.parent ? root.parent.height - root.height : 0
    })

    enter: Transition {
        NumberAnimation {
            property: "y"
            from: root.parent ? root.parent.height : 400
            to: root.parent ? root.parent.height - root.height : 0
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    exit: Transition {
        NumberAnimation {
            property: "y"
            to: root.parent ? root.parent.height : 400
            duration: 180
            easing.type: Easing.InCubic
        }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140 }
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    // Doar colțurile de sus rotunjite: sheet-ul stă lipit de marginea de jos.
    background: Item {
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Theme.surface
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 16
            color: Theme.surface
        }
    }

    // ColumnLayout-ul NU e direct `contentItem`: Popup impune inaltimea
    // contentItem-ului, iar un Layout caruia i se impune inaltimea isi
    // recalculeaza implicitHeight-ul pornind de la ea. Rezulta o bucla care
    // dubla inaltimea sheet-ului (aparea peste tot ecranul, fara pagina in
    // spate). Invelisul rupe bucla: Layout-ul isi pastreaza inaltimea
    // implicita, iar Popup se dimensioneaza din ea.
    contentItem: Item {
        implicitHeight: sheetContent.implicitHeight

        ColumnLayout {
            id: sheetContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
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
                    TouchArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        circular: true
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
                                text: qsTr("+%1 MDL").arg(Format.amount(price))
                                font.pixelSize: 12 * Theme.fontScale
                                color: Theme.textSecondary
                            }
                        }

                        Rectangle {
                            visible: qty > 0
                            width: 30; height: 30; radius: 15
                            color: Theme.keyBackground
                            IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                            TouchArea {
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
                            TouchArea {
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

                TouchArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }
        }
    }
}
