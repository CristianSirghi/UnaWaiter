import QtQuick 2.15

// Iconiță "profil" — cap (cerc mic) + umeri (arcul de sus al unui cerc mai
// mare, tăiat de `clip: true`), contur simplu, fără geometrie radială.
Item {
    id: root

    property color color: "black"

    implicitWidth: 22
    implicitHeight: 22
    clip: true

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 1
        width: 9
        height: 9
        radius: 4.5
        color: "transparent"
        border.width: 2
        border.color: root.color
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        width: 20
        height: 20
        radius: 10
        color: "transparent"
        border.width: 2
        border.color: root.color
    }
}
