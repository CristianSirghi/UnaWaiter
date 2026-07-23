import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "theme"
import "app"
import "pages" as Pages
import "components/controls" as Components

ApplicationWindow {
    id: appWindow

    // Referință la pagina de mese, ca să putem reveni direct la ea din OrderPage
    // (fluxul de comandă nouă trece prin SelectTablePage, deci un simplu pop nu ajunge).
    property var tablesPage: null

    readonly property bool isDesktopPlatform: Qt.platform.os === "windows"
        || Qt.platform.os === "osx"
        || Qt.platform.os === "linux"

    visible: true
    width: 400
    height: 860
    title: "UnaWaiter"
    visibility: isDesktopPlatform ? Window.AutomaticVisibility : Window.AutomaticVisibility

    // Pe Android, butonul fizic/gestul de back declanșează closing() direct pe
    // fereastră (nu navigare în StackView) - fără asta, orice apăsare de back
    // închide toată aplicația, indiferent pe ce pagină ești. Cât mai sunt
    // pagini pe stivă, facem pop() în loc să ieșim; doar la pagina de start
    // (WelcomePage, depth === 1) lăsăm back-ul să închidă aplicația normal.
    //
    // Excepție: pe TablesPage (ecranul "acasă" după login), un pop simplu ar
    // naviga înapoi la LoginPage - tehnic corect, dar arată ca o deconectare
    // bruscă, fără nicio întrebare. Acolo arătăm aceeași confirmare "Sign
    // out?" ca din meniul hamburger, în loc să navigăm silențios.
    onClosing: function(close) {
        if (!appWindow.isDesktopPlatform && stackView.depth > 1) {
            close.accepted = false
            if (stackView.currentItem === appWindow.tablesPage)
                appWindow.tablesPage.confirmSignOut()
            else
                stackView.pop()
        }
    }

    // Adevărat cât timp verificarea automată de actualizări pornită la
    // deschiderea aplicației e în zbor. Semnalele dataService/appUpdateManager
    // sunt globale - fără acest guard, o verificare manuală din UpdatePage ar
    // declanșa și dialogul obligatoriu de aici (și invers).
    property bool startupCheckPending: false

    // Theme / AppSettings / OrdersStore sunt acum singleton-uri (qml/theme, qml/app),
    // accesate direct oriunde — nu se mai instanțiază și nu se mai pasează prin proprietăți.
    // Aplică limba curentă la pornire și când se schimbă din Setări
    // (translationManager e expus din C++, main.cpp).
    Component.onCompleted: {
        translationManager.setLanguage(AppSettings.language)

        // Verificare automată de versiune, o singură dată, la pornire (pe
        // WelcomePage, înainte de login - să nu întrerupem chelnerul din
        // lucru). Dacă serverul nu răspunde, pornirea continuă normal.
        appWindow.startupCheckPending = true
        dataService.loadUpdateInfo()
    }

    // ===================== Auto-update la pornire =====================
    Connections {
        target: dataService

        function onUpdateInfoUrlChanged() {
            if (appWindow.startupCheckPending)
                appUpdateManager.checkForUpdate(dataService.updateInfoUrl)
        }

        function onRequestFailed(command, error) {
            // Fără net / server căzut la pornire: renunțăm silențios, nu
            // blocăm aplicația - chelnerul poate lucra, iar dialogul va
            // reapărea la următoarea pornire reușită.
            if (command === "get_update_info" && appWindow.startupCheckPending)
                appWindow.startupCheckPending = false
        }
    }

    Connections {
        target: appUpdateManager

        function onUpdateAvailable(version, notes) {
            if (!appWindow.startupCheckPending)
                return
            appWindow.startupCheckPending = false
            startupUpdateDialog.version = version
            startupUpdateDialog.notes = notes
            startupUpdateDialog.open()
        }

        function onUpToDate() {
            appWindow.startupCheckPending = false
        }

        function onCheckFailed(error) {
            appWindow.startupCheckPending = false
        }
    }

    // Dialogul obligatoriu: nu se poate închide prin tap în afară/Escape,
    // singura opțiune e "Actualizează acum" - care duce în UpdatePage cu
    // descărcarea pornită automat (autoDownload).
    Components.ConfirmDialog {
        id: startupUpdateDialog

        property string version: ""
        property string notes: ""

        mandatory: true
        infoOnly: true
        title: qsTr("New version available: %1").arg(version)
        message: notes !== "" ? notes : qsTr("The app must be updated to continue.")
        confirmText: qsTr("Update now")
        onConfirmed: stackView.push(updatePageComponent, {
            updateState: "available",
            newVersion: version,
            newNotes: notes,
            autoDownload: true
        })
    }

    Connections {
        target: AppSettings
        function onLanguageChanged() {
            translationManager.setLanguage(AppSettings.language)
        }
    }

    // Adresa backend-ului (câmpul "Server" din Administrare) alimentează
    // dataService. Nu mai există URL implicit în C++: cât timp câmpul e gol,
    // dataService.baseUrl rămâne gol și orice cerere eșuează explicit
    // ("Missing backend address") în loc să vorbească tăcut cu alt client.
    Binding {
        target: dataService
        property: "baseUrl"
        value: AppSettings.serverUrl
        when: AppSettings.serverUrl !== ""
    }

    background: Rectangle {
        color: Theme.background
    }

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: Pages.WelcomePage {
            onAuthenticateRequested: stackView.push(loginPageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
        }
    }

    Component {
        id: settingsPageComponent

        Pages.SettingsPage {
            onAdminRequested: stackView.push(adminPageComponent)
            onUpdateRequested: stackView.push(updatePageComponent)
        }
    }

    Component {
        id: adminPageComponent

        Pages.AdminPage {}
    }

    Component {
        id: updatePageComponent

        Pages.UpdatePage {}
    }

    Component {
        id: loginPageComponent

        Pages.LoginPage {
            onLoginConfirmed: appWindow.tablesPage = stackView.push(tablesPageComponent)
        }
    }

    Component {
        id: tablesPageComponent

        Pages.TablesPage {
            onNewTableRequested: stackView.push(selectTablePageComponent)
            onOrderOpened: stackView.push(orderPageComponent, { zone: zone, tableNumber: tableNumber })
            onProfileRequested: stackView.push(profilePageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
            onStockRequested: stackView.push(stockPageComponent)
            onPaidOrdersRequested: stackView.push(paidOrdersPageComponent)
        }
    }

    Component {
        id: profilePageComponent

        Pages.ProfilePage {}
    }

    Component {
        id: stockPageComponent

        Pages.StockPage {}
    }

    Component {
        id: paidOrdersPageComponent

        Pages.AchitatePage {}
    }

    Component {
        id: selectTablePageComponent

        Pages.SelectTablePage {
            onTableSelected: function(zone, tableNumber) {
                stackView.push(orderPageComponent, { zone: zone, tableNumber: tableNumber })
            }
        }
    }

    Component {
        id: orderPageComponent

        Pages.OrderPage {
            // După trimitere/ștergere revenim direct la lista de mese, sărind
            // peste SelectTablePage când comanda a fost creată nou.
            onDone: stackView.pop(appWindow.tablesPage)
        }
    }
}
