import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    property var theme

    signal tableSelected(string zone, int tableNumber)

    background: Rectangle {
        color: theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 12 }

        Components.BackButton {
            color: theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.preferredWidth: 8 }

        Label {
            text: qsTr("Select table")
            font.pixelSize: 20 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: parent.width
            topPadding: 16
            bottomPadding: 24
            spacing: 8

            // Lățimea unui card de masă (3 coloane, margini 16, spațiu 12).
            readonly property real cardSize: (width - 32 - 24) / 3

            // ----- Sala -----
            Label {
                x: 16
                text: qsTr("Hall")
                font.pixelSize: 18 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Grid {
                x: 16
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: 10

                    Rectangle {
                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: theme.surface
                        border.width: 1.5
                        border.color: theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: index + 1
                            font.pixelSize: 22 * theme.fontScale
                            font.bold: true
                            color: theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.tableSelected("hall", index + 1)
                        }
                    }
                }
            }

            Item { width: 1; height: 12 }

            // ----- Terasă -----
            Label {
                x: 16
                text: qsTr("Terrace")
                font.pixelSize: 18 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Grid {
                x: 16
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: 10

                    Rectangle {
                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: theme.surface
                        border.width: 1.5
                        border.color: theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: index + 1
                            font.pixelSize: 22 * theme.fontScale
                            font.bold: true
                            color: theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.tableSelected("terrace", index + 1)
                        }
                    }
                }
            }
        }
    }
}
