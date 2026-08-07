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

    // Se emite la PIERDEREA focusului sau la Enter - potrivit pentru "salvează
    // ce s-a tastat" (URL server, IP imprimantă).
    signal editingFinished()

    // Se emite DOAR la Enter/Done de pe tastatură, niciodată la pierderea
    // focusului. Necesar pentru câmpurile dintr-un dialog cu buton de acțiune:
    // legat de `editingFinished`, un submit se executa de DOUĂ ori - o dată
    // fiindcă atingerea butonului scoate focusul din câmp, a doua oară din
    // butonul însuși. (Pățit pe dialogul de adăugare a mesei: masa se crea, apoi
    // a doua cerere primea "există deja" și chelnerul vedea o eroare pe o
    // acțiune reușită.)
    signal accepted()

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
        onAccepted: root.accepted()
    }
}
