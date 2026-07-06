import QtQuick 2.15

// Coș de gunoi desenat din dreptunghiuri (fără unicode/font) — buton de ștergere.
Item {
    id: root

    property color color: "black"

    implicitWidth: 18
    implicitHeight: 20

    // Mânerul capacului
    Rectangle {
        x: root.width / 2 - 3; y: 0
        width: 6; height: 2; radius: 1
        color: root.color
    }
    // Bara capacului
    Rectangle {
        x: 0; y: 3
        width: root.width; height: 2; radius: 1
        color: root.color
    }
    // Corpul coșului (contur)
    Rectangle {
        x: 2; y: 6
        width: root.width - 4; height: root.height - 6
        radius: 2
        color: "transparent"
        border.width: 2
        border.color: root.color
    }
    // Două nervuri verticale
    Rectangle {
        x: root.width / 2 - 3; y: 9
        width: 2; height: root.height - 12; radius: 1
        color: root.color
    }
    Rectangle {
        x: root.width / 2 + 1; y: 9
        width: 2; height: root.height - 12; radius: 1
        color: root.color
    }
}
