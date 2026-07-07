import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    property var theme
    property var settings

    property bool editingName: false
    property string statsPeriod: "day"

    // Statistici mock (până vine backend-ul) — mese servite per perioadă.
    readonly property var statsByPeriod: ({
        day: 0,
        week: 3,
        month: 12
    })

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
            text: qsTr("Profile")
            font.pixelSize: 20 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
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
            color: theme.primary

            Label {
                anchors.centerIn: parent
                text: root.settings.waiterName.length > 0
                    ? root.settings.waiterName.charAt(0).toUpperCase()
                    : "W"
                color: "white"
                font.pixelSize: 32 * theme.fontScale
                font.bold: true
            }
        }

        // Numele chelnerului — apasă direct pe el ca să-l editezi.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.max(nameDisplay.implicitWidth, nameField.implicitWidth) + 8
            implicitHeight: 32

            Label {
                id: nameDisplay
                visible: !root.editingName
                anchors.centerIn: parent
                text: root.settings.waiterName
                font.pixelSize: 20 * theme.fontScale
                font.bold: true
                color: theme.textPrimary

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        nameField.text = root.settings.waiterName
                        root.editingName = true
                        nameField.forceActiveFocus()
                        nameField.selectAll()
                    }
                }
            }

            TextField {
                id: nameField
                visible: root.editingName
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 20 * theme.fontScale
                font.bold: true
                color: theme.textPrimary
                background: Rectangle { color: "transparent" }

                function commit() {
                    if (text.length > 0)
                        root.settings.waiterName = text
                    root.editingName = false
                }

                onAccepted: commit()
                onActiveFocusChanged: if (!activeFocus && root.editingName) commit()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 24
            color: theme.surface
            border.color: theme.border

            Label {
                anchors.centerIn: parent
                text: qsTr("Sign out")
                color: theme.textPrimary
                font.pixelSize: 15 * theme.fontScale
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
            color: theme.surface
            border.color: theme.border
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
                    font.pixelSize: 14 * theme.fontScale
                    color: theme.textSecondary
                }

                Label {
                    text: root.statsByPeriod[root.statsPeriod]
                    font.pixelSize: 34 * theme.fontScale
                    font.bold: true
                    color: theme.textPrimary
                }

                Components.SegmentedControl {
                    Layout.fillWidth: true
                    theme: root.theme
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
                    font.pixelSize: 11 * theme.fontScale
                    color: theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
