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

    // Chelnerul ales pe acest telefon. La prima logare alegem din lista reală
    // (get_waiters); după o logare reușită reținem OFICIANT-ul în
    // AppSettings.waiterOficiant, iar data următoare sărim direct la PIN.
    property int currentOficiant: 0
    property string currentName: ""
    property bool currentHasPin: false

    // Pasul 1 (alege chelnerul din listă) vs pasul 2 (PIN).
    property bool askWaiter: true
    // Am ajuns la PIN din listă (true) sau direct din chelnerul reținut
    // (false)? Decide unde duce butonul înapoi din pasul PIN.
    property bool cameFromPicker: false

    // "enter" = chelnerul are deja PIN, îl introduce. "set" = prima dată, își
    // setează PIN-ul (de 2 ori). setStage: 0 = tastează nou, 1 = confirmă.
    property string pinMode: "enter"
    property int setStage: 0
    property string firstPin: ""
    property string pendingPin: ""   // PIN-ul trimis la set_pin, ca să logăm după

    property string enteredPin: ""
    property bool busy: false
    property string errorText: ""

    // Starea listei de chelneri (get_waiters). Fără ele, o cădere a
    // serverului lăsa chelnerul în fața unei liste goale sub textul
    // "Alege-ți numele din listă", fără nicio eroare și fără vreo cale de
    // reîncercare - pe primul ecran al aplicației.
    property bool waitersLoaded: false
    property string waitersError: ""

    // Singura sursă de adevăr pentru "arătăm lista" vs "arătăm o stare".
    // dataService.waiters păstrează ultimul răspuns reușit, deci o reîncărcare
    // eșuată lasă lista veche pe loc - fără condiția asta comună, eroarea și
    // lista s-ar afișa una peste alta.
    readonly property bool waiterListReady: root.waitersError === ""
        && root.waitersLoaded && root.filteredWaiters.length > 0

    signal loginConfirmed()

    function reloadWaiters() {
        root.waitersError = ""
        root.waitersLoaded = false
        dataService.loadWaiters()
    }

    Component.onCompleted: {
        if (AppSettings.waiterOficiant !== 0) {
            // Chelner reținut pe acest telefon → direct la PIN.
            root.currentOficiant = AppSettings.waiterOficiant
            root.currentName = AppSettings.waiterName
            root.currentHasPin = true
            root.pinMode = "enter"
            root.askWaiter = false
            root.cameFromPicker = false
        } else {
            root.askWaiter = true
            root.reloadWaiters()
        }
    }

    // Lista de chelneri filtrată după căutare (case-insensitive pe nume).
    readonly property var filteredWaiters: {
        var out = []
        var q = searchField.text.trim().toLowerCase()
        var all = dataService.waiters
        for (var i = 0; i < all.length; ++i) {
            var nm = String(all[i].DENUMIREA)
            if (q === "" || nm.toLowerCase().indexOf(q) !== -1)
                out.push(all[i])
        }
        return out
    }

    function chooseWaiter(oficiant, name, hasPin) {
        root.currentOficiant = oficiant
        root.currentName = name
        root.currentHasPin = hasPin
        root.pinMode = hasPin ? "enter" : "set"
        root.setStage = 0
        root.firstPin = ""
        root.enteredPin = ""
        root.errorText = ""
        root.askWaiter = false
        root.cameFromPicker = true
    }

    // Înapoi la lista de chelneri (alt chelner preia telefonul, sau ne-am
    // răzgândit). Nu golim waiterOficiant reținut - se suprascrie abia la
    // următoarea logare reușită.
    function backToPicker() {
        root.enteredPin = ""
        root.firstPin = ""
        root.setStage = 0
        root.errorText = ""
        root.askWaiter = true
        root.reloadWaiters()
    }

    function submitPin() {
        if (root.busy || root.enteredPin.length !== root.pinLength)
            return

        if (root.pinMode === "enter") {
            root.busy = true
            dataService.login(root.currentOficiant, root.enteredPin)
            return
        }

        // pinMode === "set"
        if (root.setStage === 0) {
            root.firstPin = root.enteredPin
            root.enteredPin = ""
            root.setStage = 1
            root.errorText = ""
        } else {
            if (root.enteredPin === root.firstPin) {
                root.busy = true
                root.pendingPin = root.enteredPin
                dataService.setPin(root.currentOficiant, root.enteredPin)
            } else {
                root.enteredPin = ""
                root.firstPin = ""
                root.setStage = 0
                root.errorText = qsTr("The PINs don't match. Try again.")
                errorDialog.open()
            }
        }
    }

    function pushDigit(d) {
        if (root.busy || root.enteredPin.length >= root.pinLength)
            return
        root.errorText = ""
        root.enteredPin += d
        if (root.enteredPin.length === root.pinLength)
            root.submitPin()
    }

    function delDigit() {
        root.errorText = ""
        root.enteredPin = root.enteredPin.slice(0, -1)
    }

    // Subtitlul de pe ecranul de PIN, în funcție de mod/pas.
    function pinPrompt() {
        if (root.pinMode === "enter")
            return qsTr("Enter PIN")
        return root.setStage === 0 ? qsTr("Set your PIN") : qsTr("Confirm your PIN")
    }

    Connections {
        target: dataService

        function onWaitersChanged() {
            root.waitersError = ""
            root.waitersLoaded = true
        }

        function onLoggedIn(oficiant, name) {
            if (!root.busy)
                return
            root.busy = false
            AppSettings.waiterOficiant = oficiant
            AppSettings.waiterName = name
            root.enteredPin = ""
            root.errorText = ""
            root.loginConfirmed()
        }

        function onPinSet(oficiant) {
            // PIN înrolat cu succes → logăm imediat cu PIN-ul tocmai setat.
            if (!root.busy)
                return
            dataService.login(oficiant, root.pendingPin)
        }

        function onRequestFailed(command, error) {
            if (command === "get_waiters") {
                // Fără dialog: eroarea se afișează inline, în locul listei,
                // împreună cu butonul de reîncercare - un popup peste un ecran
                // gol n-ar spune nimic în plus și ar trebui închis mai întâi.
                root.waitersError = error
                return
            }
            if (command === "log_in") {
                if (!root.busy)
                    return
                root.busy = false
                root.enteredPin = ""
                root.errorText = (error === "invalid_credentials")
                    ? qsTr("Wrong PIN")
                    : error
                errorDialog.open()
            } else if (command === "set_pin") {
                if (!root.busy)
                    return
                root.busy = false
                root.enteredPin = ""
                root.firstPin = ""
                root.setStage = 0
                if (error === "pin_already_set") {
                    // has_pin era depășit - chelnerul chiar are PIN. Trecem la
                    // introducere în loc de setare.
                    root.pinMode = "enter"
                    root.currentHasPin = true
                    root.errorText = qsTr("This waiter already has a PIN - enter it.")
                } else if (error === "not_a_waiter") {
                    root.errorText = qsTr("This account is not an active waiter.")
                } else if (error === "invalid_pin_format") {
                    root.errorText = qsTr("The PIN must be 4 digits.")
                } else {
                    root.errorText = error
                }
                errorDialog.open()
            }
        }
    }

    Components.ConfirmDialog {
        id: errorDialog
        title: qsTr("Login failed")
        message: root.errorText
        infoOnly: true
        confirmText: qsTr("OK")
    }

    background: Rectangle {
        color: Theme.background
    }

    header: RowLayout {
        height: 56

        Item { Layout.preferredWidth: 16 }

        Components.BackButton {
            color: Theme.textPrimary
            onClicked: {
                if (root.askWaiter)
                    root.StackView.view.pop()
                else if (root.cameFromPicker)
                    root.backToPicker()
                else
                    root.StackView.view.pop()
            }
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: 16 }
    }

    // ---------- Pasul 1: alege chelnerul (listă cu căutare) ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.topMargin: 4
        spacing: 14
        visible: root.askWaiter

        Label {
            text: qsTr("Log in")
            font.pixelSize: 28 * Theme.fontScale
            font.bold: true
            color: Theme.textPrimary
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Choose your name from the list.")
            wrapMode: Text.WordWrap
            font.pixelSize: 14 * Theme.fontScale
            color: Theme.textSecondary
        }

        Components.TextInputField {
            id: searchField
            Layout.fillWidth: true
            placeholder: qsTr("Search name")
            inputMethodHints: Qt.ImhNoPredictiveText
        }

        // Stările listei: eroare de rețea (cu reîncercare), încărcare, listă
        // reală goală, sau căutare fără rezultat. Ocupă exact locul listei.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.waiterListReady
            spacing: 16

            Item { Layout.fillHeight: true }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: {
                    if (root.waitersError !== "")
                        return qsTr("Couldn't load the waiter list:\n%1").arg(root.waitersError)
                    if (!root.waitersLoaded)
                        return qsTr("Loading waiters…")
                    if (searchField.text.trim() !== "")
                        return qsTr("No waiter found for “%1”.").arg(searchField.text.trim())
                    return qsTr("No waiters available.")
                }
                font.pixelSize: 15 * Theme.fontScale
                color: root.waitersError !== "" ? Theme.danger : Theme.textSecondary
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                // Reîncercarea are sens doar pentru o eroare de rețea; la o
                // căutare fără rezultat n-ar face decât să reîncarce inutil.
                visible: root.waitersError !== ""
                implicitWidth: waitersRetryLabel.implicitWidth + 44
                implicitHeight: 44
                radius: 22
                color: waitersRetryArea.pressed ? Qt.darker(Theme.primary, 1.2) : Theme.primary

                Label {
                    id: waitersRetryLabel
                    anchors.centerIn: parent
                    text: qsTr("Retry")
                    font.pixelSize: 15 * Theme.fontScale
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    id: waitersRetryArea
                    anchors.fill: parent
                    onClicked: root.reloadWaiters()
                }
            }

            Item { Layout.fillHeight: true }
        }

        ListView {
            id: waiterList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: root.waiterListReady
            model: root.filteredWaiters
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds

            ScrollIndicator.vertical: ScrollIndicator {}

            delegate: Rectangle {
                width: waiterList.width
                height: 54
                radius: 12
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Theme.primary

                        Label {
                            anchors.centerIn: parent
                            text: String(modelData.DENUMIREA).length > 0
                                ? String(modelData.DENUMIREA).charAt(0).toUpperCase()
                                : "?"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 15 * Theme.fontScale
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.DENUMIREA
                        font.pixelSize: 15 * Theme.fontScale
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                    }

                    // Punct discret: chelnerul și-a setat deja PIN-ul.
                    Rectangle {
                        visible: parseInt(modelData.HAS_PIN) === 1
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.success
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.chooseWaiter(parseInt(modelData.COD),
                                                 String(modelData.DENUMIREA),
                                                 parseInt(modelData.HAS_PIN) === 1)
                }
            }
        }
    }

    // ---------- Pasul 2: PIN (introdu sau setează) ----------
    Flickable {
        id: pinFlick
        anchors.fill: parent
        visible: !root.askWaiter
        clip: true
        contentWidth: width
        contentHeight: pinColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: pinColumn
            width: pinFlick.width
            spacing: 0

            Item { Layout.preferredHeight: 28 }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 72
                height: 72
                radius: 36
                color: Theme.primary

                Label {
                    anchors.centerIn: parent
                    text: root.currentName.length > 0
                        ? root.currentName.charAt(0).toUpperCase()
                        : "?"
                    color: "white"
                    font.pixelSize: 30 * Theme.fontScale
                    font.bold: true
                }
            }

            Item { Layout.preferredHeight: 16 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.currentName
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
            }

            Item { Layout.preferredHeight: 8 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.pinPrompt()
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
            }

            Item { Layout.preferredHeight: 20 }

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

            Item { Layout.preferredHeight: 28 }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 12
                spacing: 12

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 10

                    Repeater {
                        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK"]

                        Rectangle {
                            id: keyDelegate
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52

                            readonly property string keyValue: modelData
                            readonly property bool isDigit: keyValue.length === 1 && keyValue >= "0" && keyValue <= "9"
                            readonly property bool isDelete: keyValue === "DEL"
                            readonly property bool isConfirm: keyValue === "OK"
                            readonly property bool isConfirmEnabled: isConfirm && root.enteredPin.length === root.pinLength && !root.busy

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
                                enabled: !root.busy && !(keyDelegate.isConfirm && !keyDelegate.isConfirmEnabled)
                                onClicked: {
                                    if (keyDelegate.isDigit)
                                        root.pushDigit(keyDelegate.keyValue)
                                    else if (keyDelegate.isDelete)
                                        root.delDigit()
                                    else if (keyDelegate.isConfirm)
                                        root.submitPin()
                                }
                            }
                        }
                    }
                }

                // Schimbă utilizatorul (alt chelner preia telefonul).
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Switch user")
                    font.pixelSize: 14 * Theme.fontScale
                    font.underline: true
                    color: Theme.textSecondary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: !root.busy
                        onClicked: root.backToPicker()
                    }
                }

                Item { Layout.preferredHeight: 16 }
            }
        }
    }
}
