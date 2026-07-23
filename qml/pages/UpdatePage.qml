import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Pagina "Actualizări" (Setări -> Actualizări): arată versiunea instalată,
// permite verificarea manuală și, dacă e o versiune nouă, descărcarea +
// instalarea ei. Flow-ul e în doi pași fiindcă appUpdateManager (C++) nu
// vorbește direct la backend-ul nostru, ca orice altă cerere: dataService
// cere întâi URL-ul version.json (get_update_info), abia apoi
// appUpdateManager îl descarcă și compară versiunea.
Page {
    id: root

    property string statusText: ""
    property color statusColor: Theme.textSecondary
    property bool downloading: false

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
            text: qsTr("Updates")
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
        contentHeight: contentColumn.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: contentColumn
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 20

            // ----- Versiune instalata -----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: versionCol.implicitHeight + 32
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: versionCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 4

                    Label {
                        text: qsTr("INSTALLED VERSION")
                        font.pixelSize: 12 * Theme.fontScale
                        font.bold: true
                        font.letterSpacing: 1
                        color: Theme.textSecondary
                    }
                    Label {
                        text: appUpdateManager.currentVersion !== "" ? appUpdateManager.currentVersion : qsTr("unknown")
                        font.pixelSize: 26 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }
            }

            // ----- Buton verificare -----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 12
                color: checkArea.pressed ? Qt.darker(Theme.primary, 1.1) : Theme.primary
                opacity: (appUpdateManager.checking || root.downloading) ? 0.6 : 1.0

                Label {
                    anchors.centerIn: parent
                    text: appUpdateManager.checking ? qsTr("Checking…") : qsTr("Check for updates")
                    color: "white"
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                }

                MouseArea {
                    id: checkArea
                    anchors.fill: parent
                    enabled: !appUpdateManager.checking && !root.downloading
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.statusText = ""
                        dataService.loadUpdateInfo()
                    }
                }
            }

            // ----- Status verificare -----
            Label {
                Layout.fillWidth: true
                visible: root.statusText !== "" && !root.downloading
                text: root.statusText
                color: root.statusColor
                font.pixelSize: 14 * Theme.fontScale
                wrapMode: Text.WordWrap
            }

            // ----- Progres descarcare -----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.downloading
                spacing: 8

                Label {
                    text: qsTr("Downloading update… %1%").arg(appUpdateManager.downloadProgress)
                    font.pixelSize: 14 * Theme.fontScale
                    color: Theme.textPrimary
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: appUpdateManager.downloadProgress
                }
            }
        }
    }

    // ===================== Wiring =====================
    Connections {
        target: dataService

        function onUpdateInfoUrlChanged() {
            appUpdateManager.checkForUpdate(dataService.updateInfoUrl)
        }

        function onRequestFailed(command, error) {
            if (command !== "get_update_info")
                return
            root.statusText = qsTr("Could not check for updates.") + "\n" + error
            root.statusColor = Theme.danger
        }
    }

    Connections {
        target: appUpdateManager

        function onUpdateAvailable(version, notes) {
            confirmDialog.version = version
            confirmDialog.notes = notes
            confirmDialog.open()
        }

        function onUpToDate() {
            root.statusText = qsTr("You are on the latest version.")
            root.statusColor = Theme.success
        }

        function onCheckFailed(error) {
            root.statusText = qsTr("Could not check for updates.") + "\n" + error
            root.statusColor = Theme.danger
        }

        function onDownloadStarted() {
            root.downloading = true
        }

        function onDownloadFailed(error) {
            root.downloading = false
            infoDialog.title = qsTr("Download failed")
            infoDialog.message = error
            infoDialog.open()
        }

        function onInstallLaunched() {
            root.downloading = false
        }
    }

    Components.ConfirmDialog {
        id: confirmDialog
        property string version: ""
        property string notes: ""
        title: qsTr("New version available: %1").arg(version)
        message: notes
        confirmText: qsTr("Download")
        onConfirmed: appUpdateManager.downloadAndInstall()
    }

    Components.ConfirmDialog {
        id: infoDialog
        infoOnly: true
        confirmText: qsTr("OK")
    }
}
