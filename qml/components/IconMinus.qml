import QtQuick 2.15

// "-" desenat dintr-un singur dreptunghi (buton de decrementare cantitate).
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
}
