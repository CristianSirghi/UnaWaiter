import QtQuick 2.15

// Săgeată ">" desenată din două dreptunghiuri rotite (ca BackButton/IconCheck),
// fără unicode — pe unele telefoane (Samsung) glifele ▾/▸ nu se randează.
// Se rotește 90° când `expanded` e true, ca să indice starea extinsă.
Item {
    id: root

    property color color: "black"
    property bool expanded: false

    implicitWidth: 16
    implicitHeight: 16

    rotation: expanded ? 90 : 0
    transformOrigin: Item.Center

    Behavior on rotation { NumberAnimation { duration: 120 } }

    Rectangle {
        x: root.width - 5; y: root.height / 2 - height / 2
        width: 8; height: 2; radius: 1
        color: root.color
        transformOrigin: Item.Right
        rotation: 35
    }
    Rectangle {
        x: root.width - 5; y: root.height / 2 - height / 2
        width: 8; height: 2; radius: 1
        color: root.color
        transformOrigin: Item.Right
        rotation: -35
    }
}
