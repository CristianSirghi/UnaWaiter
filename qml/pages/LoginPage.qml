import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

Page {
    id: root

    property string username: ""
    property string password: ""
    // true cât timp așteptăm răspunsul de la dataService.login()
    property bool loggingIn: false
    property string errorText: ""

    readonly property bool canSubmit: username.trim().length > 0 && password.length > 0 && !loggingIn

    signal loginConfirmed()

    // Reacționăm la rezultatul autentificării (dataService e expus din C++).
    // Login-ul e cel din TMS_CASIR (UAMenu) - user_id/user_password reale, nu
    // un PIN al nostru.
    Connections {
        target: dataService

        function onLoggedIn(oficiant, name, username) {
            if (!root.loggingIn)
                return
            root.loggingIn = false
            AppSettings.waiterOficiant = oficiant
            AppSettings.waiterName = name
            root.password = ""
            root.errorText = ""
            root.loginConfirmed()
        }

        function onRequestFailed(command, error) {
            if (!root.loggingIn || command !== "log_in")
                return
            root.loggingIn = false
            if (error === "invalid_credentials")
                root.errorText = qsTr("Wrong username or password")
            else if (error === "no_oficiant_linked")
                root.errorText = qsTr("This account isn't linked to a waiter yet - ask an admin to set it up in UAMenu")
            else
                root.errorText = error
        }
    }

    function submit() {
        if (!root.canSubmit)
            return
        root.errorText = ""
        root.loggingIn = true
        dataService.login(root.username, root.password)
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        Label {
            text: qsTr("Log in")
            font.pixelSize: 28 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Components.TextInputField {
            Layout.fillWidth: true
            text: root.username
            placeholder: qsTr("Username")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onTextChanged: root.username = text
            onEditingFinished: root.username = text
        }

        Components.TextInputField {
            Layout.fillWidth: true
            text: root.password
            placeholder: qsTr("Password")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            onTextChanged: root.password = text
            onEditingFinished: {
                root.password = text
                root.submit()
            }
        }

        Label {
            visible: root.errorText !== ""
            text: root.errorText
            color: "#e53935"
            font.pixelSize: 14 * Theme.fontScale
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 14
            color: root.canSubmit ? Theme.primary : Theme.border

            Label {
                anchors.centerIn: parent
                text: root.loggingIn ? qsTr("Logging in…") : qsTr("Log in")
                color: root.canSubmit ? "white" : Theme.textSecondary
                font.pixelSize: 16 * Theme.fontScale
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.canSubmit
                onClicked: root.submit()
            }
        }
    }
}
