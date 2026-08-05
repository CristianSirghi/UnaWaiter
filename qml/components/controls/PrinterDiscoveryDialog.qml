import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Dialog de căutare a imprimantelor din rețeaua locală.
// Folosește obiectul C++ `printerManager` (expus din main.cpp): pornește o
// scanare LAN pe portul dat, arată progresul + candidații găsiți, iar la
// alegerea unuia emite printerSelected(candidate).
//
// Utilizare:
//   PrinterDiscoveryDialog {
//       id: dlg
//       onPrinterSelected: { AppSettings.printerIp = candidate.ip; ... }
//   }
//   dlg.openAndScan()
Popup {
    id: root

    // Portul pe care scanăm (de obicei 9100).
    property int scanPort: 9100
    property string selectedKey: ""
    property var selectedCandidate: null

    signal printerSelected(var candidate)

    readonly property real hostWidth: parent ? parent.width : 400
    readonly property real hostHeight: parent ? parent.height : 800
    readonly property bool hasCandidates: printerManager.candidates.length > 0
    readonly property bool canUseSelection: selectedCandidate !== null && selectedKey !== ""

    function candidatePort(candidate) {
        var value = candidate && candidate.port !== undefined ? parseInt(candidate.port, 10) : root.scanPort
        return isNaN(value) || value <= 0 ? root.scanPort : value
    }

    function candidateKey(candidate) {
        if (!candidate)
            return ""
        return String(candidate.ip || "") + ":" + String(candidatePort(candidate))
    }

    function selectCandidate(candidate) {
        selectedCandidate = candidate
        selectedKey = candidateKey(candidate)
    }

    function startFreshScan() {
        selectedCandidate = null
        selectedKey = ""
        printerManager.startScanOnPort(root.scanPort)
    }

    function openAndScan() {
        root.open()
        startFreshScan()
    }

    function useSelectedCandidate() {
        if (!canUseSelection)
            return
        if (printerManager.scanning)
            printerManager.stopScan()
        root.printerSelected(selectedCandidate)
        root.close()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    dim: true
    padding: 20
    width: Math.min(root.hostWidth - 32, 380)
    height: Math.min(root.hostHeight - 80, 560)
    closePolicy: Popup.CloseOnEscape

    onClosed: {
        if (printerManager.scanning)
            printerManager.stopScan()
    }

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: 20
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: 14

        // ---- Antet ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: qsTr("Find printer")
                color: Theme.textPrimary
                font.pixelSize: 20 * Theme.fontScale
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: printerManager.scanNetwork !== ""
                      ? qsTr("Network %1").arg(printerManager.scanNetwork)
                      : qsTr("Local network")
                color: Theme.textSecondary
                font.pixelSize: 12 * Theme.fontScale
                wrapMode: Text.WordWrap
            }
        }

        // ---- Bară de progres ----
        Rectangle {
            Layout.fillWidth: true
            height: 10
            radius: 5
            clip: true
            color: Theme.keyBackground

            Rectangle {
                height: parent.height
                radius: 5
                width: parent.width * Math.max(0, Math.min(printerManager.progress, 100)) / 100
                color: printerManager.scanning
                       ? Theme.primary
                       : (printerManager.progress >= 100 ? Theme.success : Theme.primary)

                Behavior on width {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
            }
        }

        // ---- Linie de stare ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: printerManager.scanning
                      ? qsTr("Scanning %1/%2").arg(printerManager.scannedHosts).arg(printerManager.totalHosts)
                      : qsTr("%1 printers found").arg(printerManager.candidates.length)
                color: Theme.textSecondary
                font.pixelSize: 12 * Theme.fontScale
                elide: Text.ElideRight
            }

            Label {
                text: printerManager.scanning ? qsTr("SCANNING") : qsTr("READY")
                color: printerManager.scanning ? Theme.primary : Theme.success
                font.pixelSize: 11 * Theme.fontScale
                font.bold: true
            }
        }

        // ---- Lista de candidați ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 160
            radius: 14
            color: Theme.background
            border.width: 1
            border.color: Theme.border
            clip: true

            ListView {
                id: candidateList
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                clip: true
                model: printerManager.candidates
                visible: root.hasCandidates

                delegate: Rectangle {
                    id: candidateRow

                    width: candidateList.width
                    height: 68
                    radius: 12

                    readonly property string candidateIp: String(modelData.ip || "")
                    readonly property int candidatePortValue: root.candidatePort(modelData)
                    readonly property string rowKey: root.candidateKey(modelData)
                    readonly property bool rowSelected: root.selectedKey === rowKey
                    readonly property string manufacturerText: String(modelData.manufacturer || "")

                    color: Theme.surface
                    border.width: rowSelected ? 2 : 1
                    border.color: rowSelected ? Theme.primary : Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            radius: 6
                            color: candidateRow.rowSelected ? Theme.success : Theme.primary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: candidateRow.candidateIp
                                color: Theme.textPrimary
                                font.pixelSize: 15 * Theme.fontScale
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: candidateRow.manufacturerText !== ""
                                      ? candidateRow.manufacturerText
                                      : qsTr("Raw TCP printer")
                                color: Theme.textSecondary
                                font.pixelSize: 12 * Theme.fontScale
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 26
                            radius: 8
                            color: Theme.keyBackground

                            Label {
                                anchors.centerIn: parent
                                text: String(candidateRow.candidatePortValue)
                                color: Theme.textSecondary
                                font.pixelSize: 12 * Theme.fontScale
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectCandidate(modelData)
                    }
                }

                ScrollIndicator.vertical: ScrollIndicator {}
            }

            // Stare goală (fără candidați) — mesaj centrat.
            Label {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: !root.hasCandidates
                text: printerManager.scanning
                      ? qsTr("Scanning...")
                      : (printerManager.lastError !== ""
                         ? printerManager.lastError
                         : qsTr("No printers found"))
                color: printerManager.lastError !== "" ? Theme.danger : Theme.textSecondary
                font.pixelSize: 14 * Theme.fontScale
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        // ---- Butoane ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Anulează
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 14
                color: Theme.keyBackground

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    color: Theme.textPrimary
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (printerManager.scanning)
                            printerManager.stopScan()
                        root.close()
                    }
                }
            }

            // Caută din nou
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 14
                color: Theme.keyBackground
                opacity: printerManager.scanning ? 0.4 : 1.0

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Rescan")
                    color: Theme.textPrimary
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !printerManager.scanning
                    onClicked: root.startFreshScan()
                }
            }

            // Folosește imprimanta selectată
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 14
                color: root.canUseSelection ? Theme.primary : Theme.border

                Label {
                    anchors.centerIn: parent
                    text: qsTr("Use")
                    color: root.canUseSelection ? "white" : Theme.textSecondary
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.canUseSelection
                    onClicked: root.useSelectedCandidate()
                }
            }
        }
    }
}
