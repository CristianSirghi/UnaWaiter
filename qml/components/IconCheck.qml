import QtQuick 2.15

// Bifă ("✓") desenată din două dreptunghiuri rotite dintr-un vârf comun.
Item {
    id: root

    property color color: "black"

    implicitWidth: 24
    implicitHeight: 20

    Rectangle {
        x: 6; y: 14 - height / 2
        width: 6; height: 2.6; radius: 1.3
        color: root.color
        transformOrigin: Item.Left
        rotation: -135
    }
    Rectangle {
        x: 6; y: 14 - height / 2
        width: 17; height: 2.6; radius: 1.3
        color: root.color
        transformOrigin: Item.Left
        rotation: -43
    }
}
