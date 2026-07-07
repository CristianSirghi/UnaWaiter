import QtQuick 2.15

// "X" desenat din două dreptunghiuri încrucișate (buton de ștergere).
Item {
    id: root

    property color color: "black"

    implicitWidth: 20
    implicitHeight: 20

    Rectangle {
        anchors.centerIn: parent
        width: 20; height: 2.6; radius: 1.3
        color: root.color
        rotation: 45
    }
    Rectangle {
        anchors.centerIn: parent
        width: 20; height: 2.6; radius: 1.3
        color: root.color
        rotation: -45
    }
}
