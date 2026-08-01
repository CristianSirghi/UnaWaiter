import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQml 2.15
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

    // Fixează restaurantul acestui telefon. Schimbarea lui uită și chelnerul
    // reținut: un chelner e înrolat la o filială anume (uw_waiters are cheia
    // (cod_univ, oficiant)), deci PIN-ul lui n-ar mai trece la restaurantul
    // nou, iar ecranul de PIN ar cere la nesfârșit un cod care nu se poate
    // valida. Mai bine repornim de la lista de chelneri a noului restaurant.
    function applyRestaurant(cod, name) {
        var changed = AppSettings.restaurantCod !== cod
        AppSettings.restaurantCod = cod
        AppSettings.restaurantName = name
        if (changed) {
            AppSettings.waiterOficiant = 0
            AppSettings.waiterName = ""
        }
    }

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
    // O pagină care are ceva de pierdut la ieșire (ex. OrderPage, cu o comandă
    // în lucru netrimisă) expune `requestBack()` și decide singură dacă cere
    // confirmare sau iese direct. Fără cârligul ăsta, butonul de sistem ocolea
    // confirmarea pe care butonul din antet o afișa deja.
    onClosing: function(close) {
        if (!appWindow.isDesktopPlatform && stackView.depth > 1) {
            close.accepted = false
            if (stackView.currentItem === appWindow.tablesPage)
                appWindow.tablesPage.confirmSignOut()
            else if (stackView.currentItem
                     && typeof stackView.currentItem.requestBack === "function")
                stackView.currentItem.requestBack()
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
        //
        // La prima pornire, cât timp restaurantul nu e ales, cererea ar eșua
        // oricum ("No restaurant selected") - e tratată tăcut mai jos, dar mai
        // bine n-o pornim deloc. Verificarea se va face la următoarea pornire,
        // după ce telefonul are un restaurant.
        if (AppSettings.restaurantCod > 0) {
            appWindow.startupCheckPending = true
            dataService.loadUpdateInfo()
        }
    }

    // ===================== Auto-update la pornire =====================
    Connections {
        target: dataService

        function onUpdateInfoUrlChanged() {
            if (!appWindow.startupCheckPending)
                return
            // Dacă verificarea n-a pornit deloc (altă verificare în curs, URL
            // gol), nu va veni niciun semnal care să stingă steagul - îl
            // stingem aici. Fără asta rămânea blocat pe true, iar următoarea
            // verificare manuală din UpdatePage deschidea și dialogul
            // obligatoriu de pornire peste ea.
            if (!appUpdateManager.checkForUpdate(dataService.updateInfoUrl))
                appWindow.startupCheckPending = false
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

    // ===================== Bon netipărit (SmartOne) =====================
    // Ascultătorul ăsta trebuie să stea AICI, nu în OrderPage. Pagina se închide
    // pe `paymentSucceeded` (comanda închisă în Oracle), iar tipărirea pleacă
    // abia la 1,5s după comiterea documentului - deci Oracle câștigă cursa
    // aproape de fiecare dată, pagina e deja distrusă (`stackView.pop` pe un
    // item creat dintr-un Component) și semnalul nu mai avea cine să-l asculte.
    // Rezultatul: un bon netipărit trecea complet neobservat - clientul pleca
    // fără bon, iar chelnerul credea că totul a fost în regulă.
    Connections {
        target: paymentController

        function onPrintNeedsReprint(documentNumber, reason) {
            reprintDialog.reason = reason
            // Reținem numărul documentului: dialogul poate rămâne deschis peste
            // o plată nouă, iar starea controller-ului nu-l mai are atunci.
            reprintDialog.documentNumber = documentNumber
            reprintDialog.open()
        }

        // Recuperare pornită singură (după o cădere sau după revenirea
        // serviciului) care n-a reușit. Nu i-a cerut-o nimeni și de obicei
        // nicio pagină nu e deschisă pe comanda aia, deci o arătăm aici,
        // numind comanda - altfel eșecul ar fi trecut complet neobservat.
        function onBackgroundPaymentFailed(nrComand, reason) {
            backgroundPayDialog.reason = reason
            backgroundPayDialog.nrComand = nrComand
            backgroundPayDialog.open()
        }

        // Rezultatul retipăririi cerute din dialogul de mai jos. Fără el, un
        // "Tipărește din nou" care eșua a doua oară nu spunea nimic - chelnerul
        // rămânea să se uite la o imprimantă tăcută. Când retipărirea e cerută
        // din PaidOrderPage, pagina aia are propriul handler și îl arată acolo.
        function onReprintFinished(ok, reason) {
            if (ok || stackView.currentItem === null)
                return
            if (typeof stackView.currentItem.reprinting !== "undefined")
                return
            reprintFailedDialog.reason = reason
            reprintFailedDialog.open()
        }
    }

    Components.ConfirmDialog {
        id: reprintFailedDialog

        property string reason: ""

        title: qsTr("Couldn't print")
        message: reason
        confirmText: qsTr("OK")
        infoOnly: true
    }

    Components.ConfirmDialog {
        id: backgroundPayDialog

        property string reason: ""
        property int nrComand: 0

        title: qsTr("Unfinished payment")
        message: qsTr("A payment started earlier could not be completed (order %1): %2")
            .arg(backgroundPayDialog.nrComand).arg(backgroundPayDialog.reason)
        confirmText: qsTr("OK")
        infoOnly: true
    }

    // Vânzarea E finalizată, doar hârtia a lipsit. Se oferă RETIPĂRIREA, nu
    // reluarea plății: o a doua emitere ar scoate un al doilea bon fiscal.
    Components.ConfirmDialog {
        id: reprintDialog

        property string reason: ""
        property string documentNumber: ""

        title: qsTr("Receipt not printed")
        message: qsTr("The payment went through, but the receipt didn't print: %1").arg(reprintDialog.reason)
        confirmText: qsTr("Print again")
        cancelText: qsTr("Skip")
        onConfirmed: paymentController.reprint(reprintDialog.documentNumber)
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
        // Explicit, ca la SegmentedControl.qml/ChangeTablePicker.qml - fara
        // el Qt 5.15 avertizeaza in logcat la fiecare pornire (comportamentul
        // implicit ramane oricum RestoreBinding pe Qt 5, dar devine altceva
        // pe Qt 6, deci il fixam explicit acum).
        restoreMode: Binding.RestoreBinding
    }

    // Restaurantul ales alimentează dataService, care îl atașează la fiecare
    // cerere. Fără `when`, un telefon nou (restaurantCod = 0) ar trimite
    // "restaurant=0" în loc de nimic; DataService oricum refuză valorile <= 0,
    // dar e mai limpede să nu ajungă deloc acolo.
    Binding {
        target: dataService
        property: "restaurant"
        value: AppSettings.restaurantCod
        when: AppSettings.restaurantCod > 0
        restoreMode: Binding.RestoreBinding
    }

    background: Rectangle {
        color: Theme.background
    }

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: Pages.WelcomePage {
            // Fără restaurant ales nu se poate face nimic: lista de chelneri,
            // mesele și comenzile sunt toate ale unei filiale anume. Deci
            // întrebarea vine înaintea logării, o singură dată pe telefon.
            onAuthenticateRequested: AppSettings.restaurantCod > 0
                ? stackView.push(loginPageComponent)
                : stackView.push(selectRestaurantPageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
        }
    }

    Component {
        id: settingsPageComponent

        Pages.SettingsPage {
            onAdminRequested: stackView.push(adminPageComponent)
            onUpdateRequested: stackView.push(updatePageComponent)
            onChangeRestaurantRequested: stackView.push(selectRestaurantPageComponent,
                                                        { changing: true })
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
        id: selectRestaurantPageComponent

        Pages.SelectRestaurantPage {
            onRestaurantChosen: function(cod, name) {
                appWindow.applyRestaurant(cod, name)
                if (changing) {
                    stackView.pop()
                } else {
                    // Prima alegere: înlocuim ecranul, nu-l stivuim - un back
                    // din PIN înapoi la "alege restaurantul" n-ar avea sens
                    // acum că e deja ales.
                    stackView.replace(loginPageComponent)
                }
            }
        }
    }

    Component {
        id: tablesPageComponent

        Pages.TablesPage {
            onNewTableRequested: stackView.push(selectTablePageComponent)
            onOrderOpened: stackView.push(orderPageComponent,
                                          { zone: zone, tableNumber: tableNumber,
                                            openNrComand: nrComand })
            onProfileRequested: stackView.push(profilePageComponent)
            onSettingsRequested: stackView.push(settingsPageComponent)
            onPaidOrdersRequested: stackView.push(paidOrdersPageComponent)
        }
    }

    Component {
        id: profilePageComponent

        Pages.ProfilePage {}
    }

    Component {
        id: paidOrdersPageComponent

        Pages.AchitatePage {}
    }

    Component {
        id: selectTablePageComponent

        Pages.SelectTablePage {
            onTableSelected: function(zone, tableNumber, nrComand) {
                stackView.push(orderPageComponent,
                               { zone: zone, tableNumber: tableNumber,
                                 openNrComand: nrComand })
            }
            // La pachet: aceeași pagină de comandă, doar fără masă. tableNumber
            // rămâne 0 până când Oracle dă numărul comenzii - abia el devine
            // identitatea locală a comenzii (vezi OrderPage.finishSubmit).
            onTakeawayRequested: stackView.push(orderPageComponent,
                                                { zone: "takeaway", tableNumber: 0 })
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
