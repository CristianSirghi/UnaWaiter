import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15

// Câmp de text tematizat, reutilizabil (URL server, IP imprimantă, port etc.).
// Fundal + chenar din temă; chenarul se colorează în `primary` la focus.
Item {
    id: root

    property alias text: field.text
    property string placeholder: ""
    property int inputMethodHints: Qt.ImhNone
    property alias readOnly: field.readOnly
    property alias echoMode: field.echoMode

    signal editingFinished()

    implicitHeight: 48
    implicitWidth: 200

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: field.activeFocus ? Theme.primary : Theme.border
    }

    TextField {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 15 * Theme.fontScale
        color: Theme.textPrimary
        placeholderText: root.placeholder
        placeholderTextColor: Theme.textSecondary
        inputMethodHints: root.inputMethodHints
        selectByMouse: true
        // Fără fundal propriu — îl desenăm noi (Rectangle de mai sus).
        background: null
        onEditingFinished: root.editingFinished()
    }
}
