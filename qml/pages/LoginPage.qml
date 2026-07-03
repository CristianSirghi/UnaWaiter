import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root

    property var theme
    property int pinLength: 4
    property string enteredPin: ""

    signal loginConfirmed()

    background: Rectangle {
        color: theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 16 }

        // Back arrow "<" — two rotated rectangles meeting at a left vertex.
        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            Rectangle {
                x: 4; y: 10 - height / 2
                width: 12; height: 2.4; radius: 1.2
                color: theme.textPrimary
                transformOrigin: Item.Left
                rotation: -35
            }
            Rectangle {
                x: 4; y: 10 - height / 2
                width: 12; height: 2.4; radius: 1.2
                color: theme.textPrimary
                transformOrigin: Item.Left
                rotation: 35
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                onClicked: root.StackView.view.pop()
            }
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 16 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 28

        Label {
            text: "Introduceți PIN-ul"
            font.pixelSize: 28
            font.bold: true
            color: theme.textPrimary
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Repeater {
                model: root.pinLength

                Rectangle {
                    width: 56
                    height: 56
                    radius: 10
                    color: index < root.enteredPin.length
                        ? Qt.rgba(theme.primary.r, theme.primary.g, theme.primary.b, 0.12)
                        : "transparent"
                    border.width: index === root.enteredPin.length ? 2 : 1
                    border.color: index === root.enteredPin.length ? theme.primary : theme.border

                    Rectangle {
                        visible: index < root.enteredPin.length
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: theme.primary
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 12
            columnSpacing: 12

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK"]

                Rectangle {
                    id: keyDelegate
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: 12
                    color: theme.keyBackground

                    readonly property string keyValue: modelData
                    readonly property bool isDigit: keyValue.length === 1 && keyValue >= "0" && keyValue <= "9"
                    readonly property bool isDelete: keyValue === "DEL"
                    readonly property bool isConfirm: keyValue === "OK"
                    readonly property bool isConfirmEnabled: isConfirm && root.enteredPin.length === root.pinLength

                    // Digit label
                    Label {
                        visible: keyDelegate.isDigit
                        anchors.centerIn: parent
                        text: keyDelegate.keyValue
                        font.pixelSize: 22
                        color: theme.textPrimary
                    }

                    // Delete "X" — two crossed rectangles.
                    Item {
                        visible: keyDelegate.isDelete
                        anchors.centerIn: parent
                        width: 20
                        height: 20

                        Rectangle {
                            anchors.centerIn: parent
                            width: 20; height: 2.6; radius: 1.3
                            color: theme.textPrimary
                            rotation: 45
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 20; height: 2.6; radius: 1.3
                            color: theme.textPrimary
                            rotation: -45
                        }
                    }

                    // Confirm checkmark — two rotated rectangles from a bottom vertex.
                    Item {
                        visible: keyDelegate.isConfirm
                        anchors.centerIn: parent
                        width: 24
                        height: 20

                        Rectangle {
                            x: 6; y: 14 - height / 2
                            width: 6; height: 2.6; radius: 1.3
                            color: keyDelegate.isConfirmEnabled ? theme.primary : theme.textSecondary
                            transformOrigin: Item.Left
                            rotation: -135
                        }
                        Rectangle {
                            x: 6; y: 14 - height / 2
                            width: 17; height: 2.6; radius: 1.3
                            color: keyDelegate.isConfirmEnabled ? theme.primary : theme.textSecondary
                            transformOrigin: Item.Left
                            rotation: -43
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (keyDelegate.isDigit && root.enteredPin.length < root.pinLength) {
                                root.enteredPin += keyDelegate.keyValue
                            } else if (keyDelegate.isDelete) {
                                root.enteredPin = root.enteredPin.slice(0, -1)
                            } else if (keyDelegate.isConfirm && keyDelegate.isConfirmEnabled) {
                                root.loginConfirmed()
                                root.enteredPin = ""
                            }
                        }
                    }
                }
            }
        }
    }
}
