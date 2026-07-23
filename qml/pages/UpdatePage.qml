import QtQuick 2.15
import "../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

// Pagina "Actualizări" (Setări -> Updates): versiunea instalată, verificare
// manuală și, dacă există o versiune nouă, descărcare + instalare. Flow-ul e
// în doi pași fiindcă appUpdateManager (C++) nu vorbește direct la backend-ul
// nostru: dataService cere întâi URL-ul version.json (get_update_info), abia
// apoi appUpdateManager îl descarcă și compară versiunea.
//
// Toate stările sunt afișate inline (carduri), nu în dialoguri - o singură
// zonă de status care își schimbă conținutul:
//   idle -> checking -> uptodate | available | error
//   available -> downloading -> installing | error
//
// Grafica (iconița de download, spinner-ul cu puncte) e construită din
// Rectangle-uri simple - Canvas/Shapes nu randează pe device-urile țintă
// (vezi gotcha-urile de build din memoria proiectului).
Page {
    id: root

    property string updateState: "idle"
    property string errorTitle: ""
    property string errorText: ""
    property string newVersion: ""
    property string newNotes: ""
    // true → pagina a fost deschisă din dialogul obligatoriu de la pornire
    // (main.qml), cu updateState/newVersion/newNotes deja setate: nu mai
    // așteptăm nicio apăsare, pornim direct descărcarea.
    property bool autoDownload: false

    background: Rectangle {
        color: Theme.background
    }

    Component.onCompleted: {
        if (autoDownload)
            appUpdateManager.downloadAndInstall()
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
            spacing: 16

            // ===================== Hero: aplicația + versiunea instalată =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: heroCol.implicitHeight + 56
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: heroCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 28
                    spacing: 14

                    // Insigna cu iconița de download (săgeată în tavă).
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 68
                        height: 68
                        radius: 22
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)

                        Item {
                            anchors.centerIn: parent
                            width: 36
                            height: 36

                            // Tija săgeții.
                            Rectangle {
                                x: 16.5; y: 4
                                width: 3; height: 15; radius: 1.5
                                color: Theme.primary
                            }
                            // Vârful săgeții ("v"), două bare rotite din vârful (18, 21).
                            Rectangle {
                                x: 9; y: 19.5
                                width: 9; height: 3; radius: 1.5
                                color: Theme.primary
                                transformOrigin: Item.Right
                                rotation: 45
                            }
                            Rectangle {
                                x: 18; y: 19.5
                                width: 9; height: 3; radius: 1.5
                                color: Theme.primary
                                transformOrigin: Item.Left
                                rotation: -45
                            }
                            // Tava în care "cade" săgeata.
                            Rectangle {
                                x: 8; y: 21
                                width: 3; height: 9; radius: 1.5
                                color: Theme.primary
                            }
                            Rectangle {
                                x: 25; y: 21
                                width: 3; height: 9; radius: 1.5
                                color: Theme.primary
                            }
                            Rectangle {
                                x: 8; y: 27
                                width: 20; height: 3; radius: 1.5
                                color: Theme.primary
                            }
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: "UnaWaiter"
                        font.pixelSize: 19 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    // Pastila cu versiunea instalată.
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: versionLabel.implicitWidth + 28
                        implicitHeight: versionLabel.implicitHeight + 12
                        radius: height / 2
                        color: Theme.keyBackground

                        Label {
                            id: versionLabel
                            anchors.centerIn: parent
                            text: qsTr("Version %1").arg(
                                      appUpdateManager.currentVersion !== ""
                                      ? appUpdateManager.currentVersion
                                      : qsTr("unknown"))
                            font.pixelSize: 13 * Theme.fontScale
                            font.bold: true
                            color: Theme.textSecondary
                        }
                    }
                }
            }

            // ===================== Checking: puncte animate =====================
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                visible: root.updateState === "checking"
                spacing: 10

                Row {
                    spacing: 5

                    Repeater {
                        model: 3

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: Theme.primary
                            opacity: 0.25

                            // Pauzele din capete țin ciclul la aceeași durată
                            // pentru toate punctele (800ms), deci rămân în fază.
                            SequentialAnimation on opacity {
                                running: root.updateState === "checking"
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 160 }
                                NumberAnimation { to: 1.0; duration: 240 }
                                NumberAnimation { to: 0.25; duration: 240 }
                                PauseAnimation { duration: (2 - index) * 160 }
                            }
                        }
                    }
                }

                Label {
                    text: qsTr("Checking for updates…")
                    font.pixelSize: 14 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }

            // ===================== Ești la zi =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: upToDateRow.implicitHeight + 32
                visible: root.updateState === "uptodate"
                radius: 14
                color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.35)

                RowLayout {
                    id: upToDateRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.success

                        Icons.IconCheck {
                            anchors.centerIn: parent
                            scale: 0.62
                            color: "white"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: qsTr("You're up to date")
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("You have the latest version of the app.")
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ===================== Versiune nouă disponibilă =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: availableCol.implicitHeight + 36
                visible: root.updateState === "available"
                radius: 14
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.primary

                ColumnLayout {
                    id: availableCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 10

                    Label {
                        text: qsTr("New version available")
                        font.pixelSize: 11 * Theme.fontScale
                        font.bold: true
                        font.letterSpacing: 1.2
                        font.capitalization: Font.AllUppercase
                        color: Theme.primary
                    }

                    Label {
                        text: root.newVersion
                        font.pixelSize: 30 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: root.newNotes !== ""
                        text: root.newNotes
                        font.pixelSize: 14 * Theme.fontScale
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.preferredHeight: 50
                        radius: 12
                        color: downloadArea.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: qsTr("Download and install")
                            color: "white"
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                        }

                        MouseArea {
                            id: downloadArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: appUpdateManager.downloadAndInstall()
                        }
                    }
                }
            }

            // ===================== Descărcare în curs =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: downloadingCol.implicitHeight + 36
                visible: root.updateState === "downloading"
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: downloadingCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: qsTr("Downloading update…")
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: appUpdateManager.downloadProgress + "%"
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.primary
                        }
                    }

                    // Bară de progres proprie (track + fill), pe tokenii temei.
                    Rectangle {
                        id: progressTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.keyBackground

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: progressTrack.width * appUpdateManager.downloadProgress / 100
                            radius: 4
                            color: Theme.primary

                            Behavior on width {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Keep the app open until the installer appears.")
                        font.pixelSize: 12 * Theme.fontScale
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ===================== Descărcare gata, instalarea a pornit =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: installingRow.implicitHeight + 32
                visible: root.updateState === "installing"
                radius: 14
                color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.35)

                RowLayout {
                    id: installingRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.success

                        Icons.IconCheck {
                            anchors.centerIn: parent
                            scale: 0.62
                            color: "white"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: qsTr("Download complete")
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Confirm the installation on the screen.")
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ===================== Eroare =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errorRow.implicitHeight + 32
                visible: root.updateState === "error"
                radius: 14
                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)

                RowLayout {
                    id: errorRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.danger

                        Icons.IconClose {
                            anchors.centerIn: parent
                            scale: 0.55
                            color: "white"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: root.errorTitle
                            font.pixelSize: 15 * Theme.fontScale
                            font.bold: true
                            color: Theme.textPrimary
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: root.errorText !== ""
                            text: root.errorText
                            font.pixelSize: 13 * Theme.fontScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ===================== Butonul de verificare =====================
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.preferredHeight: 52
                visible: root.updateState !== "available" && root.updateState !== "downloading"
                radius: 12
                color: checkArea.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary
                opacity: root.updateState === "checking" ? 0.55 : 1.0

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Check for updates")
                    color: "white"
                    font.pixelSize: 16 * Theme.fontScale
                    font.bold: true
                }

                MouseArea {
                    id: checkArea
                    anchors.fill: parent
                    enabled: root.updateState !== "checking"
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.updateState = "checking"
                        dataService.loadUpdateInfo()
                    }
                }
            }

            // Notă de liniștire, mereu vizibilă.
            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: qsTr("The new version installs over the current app — orders and settings are kept.")
                font.pixelSize: 12 * Theme.fontScale
                color: Theme.textSecondary
                opacity: 0.8
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ===================== Wiring =====================
    Connections {
        target: dataService

        function onUpdateInfoUrlChanged() {
            // Doar noi apelăm loadUpdateInfo(), dar păstrăm garda: reacționăm
            // numai la verificarea pornită din pagina asta.
            if (root.updateState === "checking")
                appUpdateManager.checkForUpdate(dataService.updateInfoUrl)
        }

        function onRequestFailed(command, error) {
            if (command !== "get_update_info")
                return
            root.errorTitle = qsTr("Could not check for updates.")
            root.errorText = error
            root.updateState = "error"
        }
    }

    Connections {
        target: appUpdateManager

        function onUpdateAvailable(version, notes) {
            root.newVersion = version
            root.newNotes = notes
            root.updateState = "available"
        }

        function onUpToDate() {
            root.updateState = "uptodate"
        }

        function onCheckFailed(error) {
            root.errorTitle = qsTr("Could not check for updates.")
            root.errorText = error
            root.updateState = "error"
        }

        function onDownloadStarted() {
            root.updateState = "downloading"
        }

        function onDownloadFailed(error) {
            root.errorTitle = qsTr("Download failed.")
            root.errorText = error
            root.updateState = "error"
        }

        function onInstallLaunched() {
            root.updateState = "installing"
        }
    }
}
