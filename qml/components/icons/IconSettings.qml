import QtQuick 2.15

// Iconiță "setări" — aceeași imagine folosită în Una_Prod, cu o animație de
// rotire la apăsare.
Item {
    id: root

    property color color: "black"
    property bool dark: false

    signal clicked()

    implicitWidth: 24
    implicitHeight: 24

    Image {
        id: gearImage
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        source: root.dark ? "qrc:/icons/settings_white.png" : "qrc:/icons/settings.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: width
        sourceSize.height: height
    }

    RotationAnimation {
        id: spinAnimation
        target: gearImage
        property: "rotation"
        duration: 500
        easing.type: Easing.InOutCubic
    }

    MouseArea {
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
