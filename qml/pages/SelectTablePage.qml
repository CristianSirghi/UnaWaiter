import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    // Mesele vin din backend (uw_tables, via pg_mobile_web_waiter.get_tables) -
    // nu mai sunt hardcodate aici, ca restaurantul să poată adăuga/renumerota
    // mese doar cu un INSERT/UPDATE în Oracle, fără recompilare.
    property var hallTables: []
    property var terraceTables: []
    property bool tablesReady: false
    property string loadError: ""

    signal tableSelected(string zone, int tableNumber)

    function buildTables(rows) {
        var hall = []
        var terrace = []
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var no = parseInt(r.TABLE_NO)
            if (r.ZONE === "hall")
                hall.push(no)
            else if (r.ZONE === "terrace")
                terrace.push(no)
        }
        root.hallTables = hall
        root.terraceTables = terrace
        root.tablesReady = true
    }

    Connections {
        target: dataService

        function onTablesChanged() { root.buildTables(dataService.tables) }
        function onRequestFailed(command, error) {
            if (command === "get_tables")
                root.loadError = error
        }
    }

    Component.onCompleted: dataService.loadTables()

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
            text: qsTr("Select table")
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
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
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Grid {
                x: 16
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: root.hallTables

                    Rectangle {
                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: Theme.surface
                        border.width: 1.5
                        border.color: Theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 22 * Theme.fontScale
                            font.bold: true
                            color: Theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.tableSelected("hall", modelData)
                        }
                    }
                }
            }

            Item { width: 1; height: 12; visible: root.terraceTables.length > 0 }

            // ----- Terasă (ascunsă dacă nu există mese active, ex. sezon închis) -----
            Label {
                x: 16
                visible: root.terraceTables.length > 0
                text: qsTr("Terrace")
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Grid {
                x: 16
                visible: root.terraceTables.length > 0
                columns: 3
                rowSpacing: 12
                columnSpacing: 12

                Repeater {
                    model: root.terraceTables

                    Rectangle {
                        width: contentCol.cardSize
                        height: contentCol.cardSize
                        radius: 14
                        color: Theme.surface
                        border.width: 1.5
                        border.color: Theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 22 * Theme.fontScale
                            font.bold: true
                            color: Theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.tableSelected("terrace", modelData)
                        }
                    }
                }
            }
        }
    }

    // Stare de încărcare / eroare, până sosesc mesele.
    Label {
        anchors.centerIn: parent
        visible: !root.tablesReady
        horizontalAlignment: Text.AlignHCenter
        width: parent.width - 48
        wrapMode: Text.WordWrap
        text: root.loadError !== ""
            ? qsTr("Couldn't load tables:\n%1").arg(root.loadError)
            : qsTr("Loading tables…")
        font.pixelSize: 15 * Theme.fontScale
        color: root.loadError !== "" ? Theme.danger : Theme.textSecondary
    }
}
