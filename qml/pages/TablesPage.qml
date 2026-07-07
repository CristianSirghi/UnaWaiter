import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root

    property bool showMineOnly: true

    signal newTableRequested()
    signal orderOpened(string zone, int tableNumber)
    signal profileRequested()
    signal settingsRequested()
    signal stockRequested()

    // "zone" e cod intern ("hall"/"terrace") — îl traducem la afișare, ca
    // antetele de secțiune să rămână corecte în orice limbă.
    function zoneLabel(zone) {
        return zone === "terrace" ? qsTr("Terrace") : qsTr("Hall")
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 64

        Item { Layout.preferredWidth: 16 }

        Rectangle {
            width: 36
            height: 36
            radius: 18
            color: Theme.primary

            Label {
                anchors.centerIn: parent
                text: AppSettings.waiterName.length > 0
                    ? AppSettings.waiterName.charAt(0).toUpperCase()
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

        Icons.IconHamburger {
            color: Theme.textPrimary
            onClicked: navDrawer.open()
        }

        Item { Layout.preferredWidth: 16 }
    }

    Components.AppDrawer {
        id: navDrawer

        onProfileRequested: root.profileRequested()
        onSettingsRequested: root.settingsRequested()
        onStockRequested: root.stockRequested()
        onSignOutRequested: signOutDialog.open()
    }

    Components.ConfirmDialog {
        id: signOutDialog
        title: qsTr("Sign out?")
        message: qsTr("You will be logged out of your profile.")
        confirmText: qsTr("Sign out")
        destructive: true
        onConfirmed: root.StackView.view.pop(null)
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
                labelHorizontalAlignment: Text.AlignLeft
                currentValue: root.showMineOnly ? "mine" : "all"
                options: [
                    { label: qsTr("Mine"), value: "mine" },
                    { label: qsTr("All"), value: "all" }
                ]
                onOptionSelected: root.showMineOnly = (value === "mine")
            }
        }

        // Empty state — nicio comandă deschisă.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: OrdersStore.ordersModel.count === 0
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
                    border.color: Theme.border
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle { width: 34; height: 3; radius: 1.5; color: Theme.border }
                    Rectangle { width: 34; height: 3; radius: 1.5; color: Theme.border }
                    Rectangle { width: 22; height: 3; radius: 1.5; color: Theme.border }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No open orders")
                font.pixelSize: 20 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("There are no open orders. Please start a new one.")
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            clip: true
            visible: OrdersStore.ordersModel.count > 0
            model: OrdersStore.ordersModel

            // Grupăm cardurile pe zonă (Sala / Terasă), cu un antet per grup.
            section.property: "zone"
            section.delegate: Label {
                width: ListView.view.width
                topPadding: 4
                bottomPadding: 8
                text: root.zoneLabel(section)
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            delegate: Rectangle {
                width: ListView.view.width
                height: cardContent.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.color: Theme.border

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
                        spacing: 8

                        Label {
                            text: tableName
                            font.pixelSize: 16 * Theme.fontScale
                            font.bold: true
                            color: active ? Theme.primary : Theme.textSecondary
                        }

                        // Etichetă zonă (Sala / Terasă) — distinge masa 1 din sală de masa 1 de pe terasă.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: zoneTag.implicitWidth + 16
                            implicitHeight: zoneTag.implicitHeight + 6
                            radius: height / 2
                            color: Theme.keyBackground

                            Label {
                                id: zoneTag
                                anchors.centerIn: parent
                                text: root.zoneLabel(zone)
                                font.pixelSize: 11 * Theme.fontScale
                                color: Theme.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderTime
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: waiterName
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: orderNo
                            font.pixelSize: 13 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }

                    Label {
                        text: preview
                        font.pixelSize: 13 * Theme.fontScale
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: "👤 " + guestCount
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: total
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
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
        color: Theme.primary
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20

        Label {
            anchors.centerIn: parent
            text: "+"
            color: "white"
            font.pixelSize: 28 * Theme.fontScale
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.newTableRequested()
        }
    }
}
