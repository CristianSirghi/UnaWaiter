import QtQuick 2.15

// Săgeată "înapoi" ("<") desenată din două dreptunghiuri rotite,
// cu zonă de atingere extinsă. Folosită în header-ele paginilor.
Item {
    id: root

    property color color: "black"

    signal clicked()

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        x: 6; y: root.height / 2 - height / 2
        width: 12; height: 2.4; radius: 1.2
        color: root.color
        transformOrigin: Item.Left
        rotation: -35
    }
    Rectangle {
        x: 6; y: root.height / 2 - height / 2
        width: 12; height: 2.4; radius: 1.2
        color: root.color
        transformOrigin: Item.Left
        rotation: 35
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -10
        onClicked: root.clicked()
    }
}
