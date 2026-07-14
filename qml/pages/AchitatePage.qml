import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Comenzile achitate azi (STATE=3 pe get_paid_orders), doar ale chelnerului
// logat - vezi discuția din sesiune despre statusul de plată. Ecran separat de
// TablesPage (nu o secțiune în aceeași listă), ca să nu se încurce chelnerul
// cu mese deja închise la casă.
Page {
    id: root

    property string loadError: ""
    property bool loaded: false

    function fmtTotal(v) {
        var n = parseFloat(v)
        if (isNaN(n))
            return "—"
        return n.toFixed(2).replace(".", ",") + " MDL"
    }

    function buildRows(rows) {
        ordersModel.clear()
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var hasDesk = r.DESK !== undefined && r.DESK !== null && String(r.DESK).trim() !== ""
            var desk = hasDesk ? parseInt(r.DESK) : 0
            ordersModel.append({
                nrComand: r.NR_COMAND !== undefined && r.NR_COMAND !== null ? String(r.NR_COMAND) : "",
                tableLabel: desk > 0 ? qsTr("Table %1").arg(desk) : qsTr("Unknown table"),
                waiterName: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderTime: r.DATA_COMAND ? String(r.DATA_COMAND).trim() : "",
                total: root.fmtTotal(r.CLCCOSTT)
            })
        }
        root.loaded = true
    }

    function refresh() {
        dataService.loadPaidOrders(String(AppSettings.waiterOficiant))
    }

    ListModel { id: ordersModel }

    Connections {
        target: dataService
        function onPaidOrdersChanged() { root.buildRows(dataService.paidOrders) }
        function onRequestFailed(command, error) {
            if (command === "get_paid_orders")
                root.loadError = error
        }
    }

    Component.onCompleted: root.refresh()

    // Poll ușor cât timp pagina e activă pe stivă (nu și când e sub alta) -
    // nici UAMenu nu are auto-refresh pentru propriul grid, deci asta e
    // echivalentul practic al "live" fără infrastructură nouă (websocket/SSE).
    Timer {
        interval: 25000
        repeat: true
        running: root.StackView.status === StackView.Active
        onTriggered: root.refresh()
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 12 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.preferredWidth: 8 }

        Label {
            text: qsTr("Paid orders")
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Stare goală - nicio comandă achitată azi.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.loaded && ordersModel.count === 0 && root.loadError === ""
            spacing: 8

            Item { Layout.fillHeight: true }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No paid orders yet today")
                font.pixelSize: 16 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Orders closed at the register will show up here.")
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
            visible: ordersModel.count > 0
            model: ordersModel

            delegate: Rectangle {
                width: ListView.view.width
                height: cardContent.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.success

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
                            text: tableLabel
                            font.pixelSize: 16 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: paidTag.implicitWidth + 16
                            implicitHeight: paidTag.implicitHeight + 6
                            radius: height / 2
                            color: Theme.success

                            Label {
                                id: paidTag
                                anchors.centerIn: parent
                                text: qsTr("Paid")
                                font.pixelSize: 11 * Theme.fontScale
                                font.bold: true
                                color: "white"
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
                            text: "#" + nrComand
                            font.pixelSize: 13 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: total
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: !root.loaded && root.loadError === ""
        text: qsTr("Loading…")
        font.pixelSize: 15 * Theme.fontScale
        color: Theme.textSecondary
    }

    Label {
        anchors.centerIn: parent
        visible: root.loadError !== ""
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - 48
        wrapMode: Text.WordWrap
        text: qsTr("Couldn't load paid orders:\n%1").arg(root.loadError)
        font.pixelSize: 15 * Theme.fontScale
        color: Theme.danger
    }
}
