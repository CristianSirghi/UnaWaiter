import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root


    property string statsPeriod: "day"

    // Mese servite per perioadă (comenzi achitate, state=3) - din
    // get_waiter_stats, un singur rând cu toate 3 cifrele.
    property var statsByPeriod: ({ day: 0, week: 0, month: 0 })
    property bool statsReady: false

    function applyStats(rows) {
        if (!rows || rows.length === 0) {
            root.statsByPeriod = { day: 0, week: 0, month: 0 }
        } else {
            var r = rows[0]
            root.statsByPeriod = {
                day: parseInt(r.DAY_COUNT) || 0,
                week: parseInt(r.WEEK_COUNT) || 0,
                month: parseInt(r.MONTH_COUNT) || 0
            }
        }
        root.statsReady = true
    }

    Connections {
        target: dataService
        function onWaiterStatsChanged() { root.applyStats(dataService.waiterStats) }
    }

    Component.onCompleted: dataService.loadWaiterStats(String(AppSettings.waiterOficiant))

    function pad2(n) { return (n < 10 ? "0" : "") + n }

    function fmtShortDate(d) {
        return pad2(d.getDate()) + "." + pad2(d.getMonth() + 1)
    }

    // Intervalul exact numărat pentru "Săpt."/"Lună" - se termină azi (nu la
    // sfârșitul săptămânii/lunii), la fel ca WHERE-ul din get_waiter_stats
    // (data_comand >= începutul perioadei). Săptămâna începe luni (ISO),
    // la fel ca TRUNC(SYSDATE, 'IW') din query.
    function periodRangeLabel(period) {
        var today = new Date()
        var start
        if (period === "week") {
            var dow = today.getDay() // 0=duminică..6=sâmbătă
            var diffToMonday = (dow === 0) ? 6 : dow - 1
            start = new Date(today.getFullYear(), today.getMonth(), today.getDate() - diffToMonday)
        } else if (period === "month") {
            start = new Date(today.getFullYear(), today.getMonth(), 1)
        } else {
            return ""
        }
        if (start.toDateString() === today.toDateString())
            return root.fmtShortDate(today)
        return root.fmtShortDate(start) + " – " + root.fmtShortDate(today)
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
            text: qsTr("Profile")
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Item { Layout.preferredHeight: 4 }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 88
            height: 88
            radius: 44
            color: Theme.primary

            Label {
                anchors.centerIn: parent
                text: AppSettings.waiterName.length > 0
                    ? AppSettings.waiterName.charAt(0).toUpperCase()
                    : "W"
                color: "white"
                font.pixelSize: 32 * Theme.fontScale
                font.bold: true
            }
        }

        // Numele chelnerului - vine din TMS_CASIR (UAMenu), needitabil din app.
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: AppSettings.waiterName
            font.pixelSize: 20 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 24
            color: Theme.surface
            border.color: Theme.border

            Label {
                anchors.centerIn: parent
                text: qsTr("Sign out")
                color: Theme.textPrimary
                font.pixelSize: 15 * Theme.fontScale
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.StackView.view.pop(null)
            }
        }

        // ----- Statistici -----
        Rectangle {
            Layout.fillWidth: true
            radius: 16
            color: Theme.surface
            border.color: Theme.border
            implicitHeight: statsContent.implicitHeight + 28

            ColumnLayout {
                id: statsContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                spacing: 12

                Label {
                    text: qsTr("Tables served")
                    font.pixelSize: 14 * Theme.fontScale
                    color: Theme.textSecondary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Label {
                        text: root.statsReady ? root.statsByPeriod[root.statsPeriod] : "…"
                        font.pixelSize: 34 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    // Intervalul de date numărat - doar la Săpt./Lună, la Zi e
                    // evident ("azi") și n-ar aduce nimic în plus.
                    Rectangle {
                        visible: root.statsPeriod !== "day"
                        Layout.alignment: Qt.AlignVCenter
                        Layout.bottomMargin: 4
                        radius: height / 2
                        implicitWidth: rangeLabel.implicitWidth + 20
                        implicitHeight: rangeLabel.implicitHeight + 8
                        color: Theme.keyBackground

                        Label {
                            id: rangeLabel
                            anchors.centerIn: parent
                            text: root.periodRangeLabel(root.statsPeriod)
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                Components.SegmentedControl {
                    Layout.fillWidth: true
                    currentValue: root.statsPeriod
                    options: [
                        { label: qsTr("Day"), value: "day" },
                        { label: qsTr("Week"), value: "week" },
                        { label: qsTr("Month"), value: "month" }
                    ]
                    onOptionSelected: root.statsPeriod = value
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Includes completed orders assigned to you.")
                    font.pixelSize: 11 * Theme.fontScale
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
