import QtQuick 2.15

// Setările aplicației — persistate pe disc via blocul Settings{} din main.qml
// (Qt.labs.settings), fără backend Oracle încă.
QtObject {
    property string language: "ro"
    property string waiterName: "Waiter02"
}
