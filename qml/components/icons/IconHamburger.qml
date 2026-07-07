import QtQuick 2.15

// Meniu hamburger (trei linii orizontale), cu zonă de atingere extinsă.
Item {
    id: root

    property color color: "black"

    signal clicked()

    implicitWidth: 24
    implicitHeight: 24

    Column {
        anchors.centerIn: parent
        spacing: 4

        Rectangle { width: 22; height: 2.4; radius: 1.2; color: root.color }
        Rectangle { width: 22; height: 2.4; radius: 1.2; color: root.color }
        Rectangle { width: 22; height: 2.4; radius: 1.2; color: root.color }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: root.clicked()
    }
}
