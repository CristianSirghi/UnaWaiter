import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    property var theme

    // ---- Stocuri mock (până vine backend-ul Oracle) ----
    readonly property var stockItems: [
        { name: "Blinie cu unt", status: "ok" },
        { name: "Blinie cu somon", status: "low" },
        { name: "Salată Cezar", status: "ok" },
        { name: "Salată grecească", status: "out" },
        { name: "Ciorbă de burtă", status: "ok" },
        { name: "Zeamă de casă", status: "low" },
        { name: "Tiramisu", status: "out" },
        { name: "Înghețată", status: "ok" }
    ]

    function statusLabel(status) {
        if (status === "out")
            return qsTr("Out of stock")
        if (status === "low")
            return qsTr("Low stock")
        return qsTr("In stock")
    }

    function statusBackground(status) {
        if (status === "out")
            return "#F6D3D3"
        if (status === "low")
            return "#FCE7B0"
        return "#CFEFDA"
    }

    function statusColor(status) {
        if (status === "out")
            return "#B23A3A"
        if (status === "low")
            return "#8A6D1D"
        return "#1E7A3C"
    }

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
            text: qsTr("Stock")
            font.pixelSize: 20 * theme.fontScale
            font.bold: true
            color: theme.textPrimary
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 12 }
    }

    ListView {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        model: root.stockItems

        delegate: Rectangle {
            width: ListView.view.width
            height: 56
            radius: 12
            color: theme.surface
            border.color: theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                Label {
                    Layout.fillWidth: true
                    text: modelData.name
                    font.pixelSize: 15 * theme.fontScale
                    color: theme.textPrimary
                    elide: Text.ElideRight
                }

                Rectangle {
                    radius: 10
                    Layout.preferredHeight: 24
                    implicitWidth: statusText.implicitWidth + 16
                    color: root.statusBackground(modelData.status)

                    Label {
                        id: statusText
                        anchors.centerIn: parent
                        text: root.statusLabel(modelData.status)
                        font.pixelSize: 11 * theme.fontScale
                        color: root.statusColor(modelData.status)
                    }
                }
            }
        }
    }
}
