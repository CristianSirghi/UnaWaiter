import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root

    property int pinLength: 4
    property string enteredPin: ""

    signal loginConfirmed()

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 16 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 16 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 28

        Label {
            text: qsTr("Enter PIN")
            font.pixelSize: 28 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
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
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : "transparent"
                    border.width: index === root.enteredPin.length ? 2 : 1
                    border.color: index === root.enteredPin.length ? Theme.primary : Theme.border

                    Rectangle {
                        visible: index < root.enteredPin.length
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.primary
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
                    color: Theme.keyBackground

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
                        font.pixelSize: 22 * Theme.fontScale
                        color: Theme.textPrimary
                    }

                    Icons.IconClose {
                        visible: keyDelegate.isDelete
                        anchors.centerIn: parent
                        color: Theme.textPrimary
                    }

                    Icons.IconCheck {
                        visible: keyDelegate.isConfirm
                        anchors.centerIn: parent
                        color: keyDelegate.isConfirmEnabled ? Theme.primary : Theme.textSecondary
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
