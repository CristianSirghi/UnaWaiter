import QtQuick 2.15

// Iconiță "stoc" — conturul unei cutii cu o linie orizontală (capacul),
// desenată doar din dreptunghiuri drepte (fără geometrie radială).
Item {
    id: root

    property color color: "black"

    implicitWidth: 22
    implicitHeight: 22

    Rectangle {
        x: 2
        y: 6
        width: 18
        height: 14
        radius: 2
        color: "transparent"
        border.width: 2
        border.color: root.color
    }

    Rectangle {
        x: 2
        y: 10
        width: 18
        height: 2
        color: root.color
    }
}
