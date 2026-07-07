import QtQuick 2.15

// "+" desenat din două dreptunghiuri (buton de incrementare cantitate).
Item {
    id: root

    property color color: "black"

    implicitWidth: 14
    implicitHeight: 14

    Rectangle {
        anchors.centerIn: parent
        width: 14; height: 2.4; radius: 1.2
        color: root.color
    }
    Rectangle {
        anchors.centerIn: parent
        width: 2.4; height: 14; radius: 1.2
        color: root.color
    }
}
