import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components

Page {
    id: root

    property var theme
    property var settings
    property var store
    property bool showMineOnly: true

    signal newTableRequested()
    signal orderOpened(string zone, int tableNumber)
    signal profileRequested()
    signal settingsRequested()
    signal stockRequested()

    background: Rectangle {
        color: theme.background
    }

    header: RowLayout {
        height: 64

        Item { Layout.preferredWidth: 16 }

        Rectangle {
            width: 36
            height: 36
            radius: 18
            color: theme.primary

            Label {
                anchors.centerIn: parent
                text: root.settings.waiterName.length > 0
                    ? root.settings.waiterName.charAt(0).toUpperCase()
                    : "W"
                color: "white"
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.profileRequested()
            }
        }

        Item { Layout.fillWidth: true }

        Components.IconHamburger {
            color: theme.textPrimary
            onClicked: navDrawer.open()
        }

        Item { Layout.preferredWidth: 16 }
    }

    Components.AppDrawer {
        id: navDrawer
        theme: root.theme
        settings: root.settings

        onProfileRequested: root.profileRequested()
        onSettingsRequested: root.settingsRequested()
        onStockRequested: root.stockRequested()
        onSignOutRequested: root.StackView.view.pop(null)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item { Layout.fillWidth: true }

            Components.SegmentedControl {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 36
                theme: root.theme
                labelHorizontalAlignment: Text.AlignLeft
                currentValue: root.showMineOnly ? "mine" : "all"
                options: [
                    { label: qsTr("Mine"), value: "mine" },
                    { label: qsTr("All"), value: "all" }
                ]
                onOptionSelected: root.showMineOnly = (value === "mine")
            }
        }

        Label {
            text: qsTr("Hall")
            font.pixelSize: 18 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
            visible: root.store.ordersModel.count > 0
        }

        // Empty state — nicio comandă deschisă.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.store.ordersModel.count === 0
            spacing: 8

            Item { Layout.fillHeight: true }

            // Iconiță bon desenată din forme (fără dependență de font).
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 72

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"
                    border.width: 3
                    border.color: theme.border
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle { width: 34; height: 3; radius: 1.5; color: theme.border }
                    Rectangle { width: 34; height: 3; radius: 1.5; color: theme.border }
                    Rectangle { width: 22; height: 3; radius: 1.5; color: theme.border }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No open orders")
                font.pixelSize: 20 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("There are no open orders. Please start a new one.")
                font.pixelSize: 14 * theme.fontScale
                color: theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            visible: root.store.ordersModel.count > 0
            model: root.store.ordersModel

            delegate: Rectangle {
                width: ListView.view.width
                height: cardContent.implicitHeight + 28
                radius: 14
                color: theme.surface
                border.color: theme.border

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.orderOpened(zone, tableNumber)
                }

                ColumnLayout {
                    id: cardContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: tableName
                            font.pixelSize: 16 * theme.fontScale
                            font.bold: true
                            color: active ? theme.primary : theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderTime
                            font.pixelSize: 13 * theme.fontScale
                            color: theme.textSecondary
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: waiterName
                            font.pixelSize: 13 * theme.fontScale
                            color: theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderNo
                            font.pixelSize: 13 * theme.fontScale
                            font.bold: true
                            color: theme.textPrimary
                        }
                    }

                    Label {
                        text: preview
                        font.pixelSize: 13 * theme.fontScale
                        color: theme.textPrimary
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: theme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: "👤 " + guestCount
                            font.pixelSize: 13 * theme.fontScale
                            color: theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: total
                            font.pixelSize: 15 * theme.fontScale
                            font.bold: true
                            color: theme.textPrimary
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        width: 56
        height: 56
        radius: 28
        color: theme.primary
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20

        Label {
            anchors.centerIn: parent
            text: "+"
            color: "white"
            font.pixelSize: 28 * theme.fontScale
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.newTableRequested()
        }
    }
}
