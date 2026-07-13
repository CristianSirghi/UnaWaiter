import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons

Page {
    id: root

    property int pinLength: 4

    // Utilizatorul curent al acestui telefon. La prima logare e gol și cerem
    // numele de utilizator (pasul "user"); după logare reușită îl reținem în
    // AppSettings.waiterUsername, iar data următoare sărim direct la PIN.
    property string currentUsername: ""
    property bool askUsername: true

    property string enteredPin: ""
    property bool loggingIn: false
    property string errorText: ""

    signal loginConfirmed()

    Component.onCompleted: {
        root.currentUsername = AppSettings.waiterUsername
        root.askUsername = (root.currentUsername === "")
    }

    // Pasul 1 (doar la prima logare): confirmăm numele de utilizator tastat și
    // trecem la PIN. Nu-l salvăm încă în cache - abia după un login reușit.
    function chooseUsername(name) {
        var u = name.trim()
        if (u.length === 0)
            return
        root.currentUsername = u
        root.askUsername = false
        root.errorText = ""
    }

    // "Schimbă utilizatorul" - revenim la pasul de user (ex. alt chelner preia
    // telefonul). Cache-ul se suprascrie abia la următorul login reușit.
    function switchUser() {
        root.enteredPin = ""
        root.errorText = ""
        root.currentUsername = ""
        root.askUsername = true
    }

    function tryLogin() {
        if (root.loggingIn)
            return
        root.loggingIn = true
        root.errorText = ""
        dataService.login(root.currentUsername, root.enteredPin)
    }

    function pushDigit(d) {
        if (root.loggingIn || root.enteredPin.length >= root.pinLength)
            return
        root.errorText = ""
        root.enteredPin += d
        // Auto-trimitere la a 4-a cifră - fără buton OK separat.
        if (root.enteredPin.length === root.pinLength)
            root.tryLogin()
    }

    function delDigit() {
        root.errorText = ""
        root.enteredPin = root.enteredPin.slice(0, -1)
    }

    Connections {
        target: dataService

        function onLoggedIn(oficiant, name, username) {
            if (!root.loggingIn)
                return
            root.loggingIn = false
            AppSettings.waiterOficiant = oficiant
            AppSettings.waiterName = name
            AppSettings.waiterUsername = username   // reținem userul pe acest telefon
            root.enteredPin = ""
            root.errorText = ""
            root.loginConfirmed()
        }

        function onRequestFailed(command, error) {
            if (!root.loggingIn || command !== "log_in")
                return
            root.loggingIn = false
            root.enteredPin = ""
            root.errorText = (error === "invalid_credentials")
                ? qsTr("Wrong PIN")
                : error
        }
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 16 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: root.StackView.view.pop()
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 16 }
    }

    // ---------- Pasul 1: nume de utilizator (doar prima logare) ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        visible: root.askUsername

        Item { Layout.preferredHeight: 8 }

        Label {
            text: qsTr("Log in")
            font.pixelSize: 28 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Enter your username once - this phone will remember it, then you'll only need your PIN.")
            wrapMode: Text.WordWrap
            font.pixelSize: 14 * Theme.fontScale
            color: Theme.textSecondary
        }

        Components.TextInputField {
            id: userField
            Layout.fillWidth: true
            placeholder: qsTr("Username")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onEditingFinished: root.chooseUsername(text)
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 14
            color: userField.text.trim().length > 0 ? Theme.primary : Theme.border

            Label {
                anchors.centerIn: parent
                text: qsTr("Continue")
                color: userField.text.trim().length > 0 ? "white" : Theme.textSecondary
                font.pixelSize: 16 * Theme.fontScale
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: userField.text.trim().length > 0
                onClicked: root.chooseUsername(userField.text)
            }
        }
    }

    // ---------- Pasul 2: PIN (după ce userul e ales/reținut) ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        visible: !root.askUsername

        Item { Layout.preferredHeight: 4 }

        // Avatar + nume de utilizator, ca chelnerul să vadă clar cu ce cont
        // urmează să intre.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 36
            color: Theme.primary

            Label {
                anchors.centerIn: parent
                text: root.currentUsername.length > 0
                    ? root.currentUsername.charAt(0).toUpperCase()
                    : "?"
                color: "white"
                font.pixelSize: 30 * Theme.fontScale
                font.bold: true
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.currentUsername
            font.pixelSize: 18 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Enter PIN")
            font.pixelSize: 14 * Theme.fontScale
            color: Theme.textSecondary
        }

        // Puncte PIN
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Repeater {
                model: root.pinLength

                Rectangle {
                    width: 46
                    height: 46
                    radius: 10
                    color: index < root.enteredPin.length
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : "transparent"
                    border.width: index === root.enteredPin.length ? 2 : 1
                    border.color: index === root.enteredPin.length ? Theme.primary : Theme.border

                    Rectangle {
                        visible: index < root.enteredPin.length
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.primary
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: root.errorText !== ""
            text: root.errorText
            color: "#e53935"
            font.pixelSize: 14 * Theme.fontScale
        }

        // Tastatura numerică ocupă spațiul rămas (fillHeight pe grid + pe fiecare
        // tastă, cu minim 44) - se micșorează pe ecrane scurte în loc să iasă
        // sub margine.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                // Rândul de jos: șterge (X) stânga, 0 mijloc, confirmă (✓) dreapta.
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK"]

                Rectangle {
                    id: keyDelegate
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 60
                    Layout.minimumHeight: 44

                    readonly property string keyValue: modelData
                    readonly property bool isDigit: keyValue.length === 1 && keyValue >= "0" && keyValue <= "9"
                    readonly property bool isDelete: keyValue === "DEL"
                    readonly property bool isConfirm: keyValue === "OK"
                    // Confirmarea e activă doar cu PIN complet. De obicei nici nu
                    // apucă să fie apăsată (auto-login la a 4-a cifră), e un backup
                    // vizual - dar rămâne funcțională.
                    readonly property bool isConfirmEnabled: isConfirm && root.enteredPin.length === root.pinLength && !root.loggingIn

                    radius: 12
                    color: isConfirm
                        ? (isConfirmEnabled ? Theme.primary : Theme.keyBackground)
                        : Theme.keyBackground

                    Label {
                        visible: keyDelegate.isDigit
                        anchors.centerIn: parent
                        text: keyDelegate.keyValue
                        font.pixelSize: 22 * Theme.fontScale
                        color: Theme.textPrimary
                    }

                    Icons.IconClose {
                        visible: keyDelegate.isDelete
                        anchors.centerIn: parent
                        color: Theme.textPrimary
                    }

                    Icons.IconCheck {
                        visible: keyDelegate.isConfirm
                        anchors.centerIn: parent
                        color: keyDelegate.isConfirmEnabled ? "white" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.loggingIn && !(keyDelegate.isConfirm && !keyDelegate.isConfirmEnabled)
                        onClicked: {
                            if (keyDelegate.isDigit)
                                root.pushDigit(keyDelegate.keyValue)
                            else if (keyDelegate.isDelete)
                                root.delDigit()
                            else if (keyDelegate.isConfirm)
                                root.tryLogin()
                        }
                    }
                }
            }
        }

        // Schimbă utilizatorul (alt chelner preia telefonul).
        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            text: qsTr("Switch user")
            font.pixelSize: 14 * Theme.fontScale
            font.underline: true
            color: Theme.textSecondary

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                enabled: !root.loggingIn
                onClicked: root.switchUser()
            }
        }
    }
}
