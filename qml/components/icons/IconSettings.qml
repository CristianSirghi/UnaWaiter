import QtQuick 2.15
import QtQuick.Window 2.15

// Iconiță "setări" — aceeași imagine folosită în Una_Prod, cu o animație de
// rotire la apăsare.
Item {
    id: root

    property color color: "black"
    property bool dark: false

    signal clicked()

    implicitWidth: 24
    implicitHeight: 24

    // Ca la BackButton/IconHamburger: estompăm desenul la apăsare, fiindcă zona
    // de atingere e extinsă cu 8px dincolo de iconiță. (Rotirea de la click
    // rămâne - aia confirmă acțiunea, asta confirmă atingerea.)
    Image {
        id: gearImage
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        opacity: touchArea.pressed ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: touchArea.pressed ? 0 : 140 } }
        source: root.dark ? "qrc:/icons/settings_white.png" : "qrc:/icons/settings.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: parent.width * Screen.devicePixelRatio
        sourceSize.height: parent.height * Screen.devicePixelRatio
    }

    RotationAnimation {
        id: spinAnimation
        target: gearImage
        property: "rotation"
        duration: 500
        easing.type: Easing.InOutCubic
    }

    MouseArea {
        id: touchArea
        anchors.fill: parent
        anchors.margins: -8
        onClicked: {
            spinAnimation.stop()
            spinAnimation.from = gearImage.rotation
            spinAnimation.to = gearImage.rotation + 360
            spinAnimation.start()
            root.clicked()
        }
    }
}
