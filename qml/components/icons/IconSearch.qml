import QtQuick 2.15

// Lupă: un cerc (contur) + un mâner scurt în colțul dreapta-jos.
Item {
    id: root

    property color color: "black"

    implicitWidth: 18
    implicitHeight: 18

    Rectangle {
        x: 0; y: 0
        width: 11; height: 11
        radius: 5.5
        color: "transparent"
        border.width: 2
        border.color: root.color
    }

    Rectangle {
        x: 9; y: 9
        width: 7; height: 2.2
        radius: 1.1
        color: root.color
        rotation: 45
        transformOrigin: Item.TopLeft
    }
}
