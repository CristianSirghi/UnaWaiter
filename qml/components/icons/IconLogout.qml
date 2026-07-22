import QtQuick 2.15

// Iconiță "deconectare" — aceeași imagine folosită în Una_Prod.
Item {
    id: root

    property color color: "black"
    property bool dark: false

    implicitWidth: 22
    implicitHeight: 22

    Image {
        anchors.fill: parent
        source: root.dark ? "qrc:/icons/logout_white.png" : "qrc:/icons/logout.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: width
        sourceSize.height: height
    }
}
