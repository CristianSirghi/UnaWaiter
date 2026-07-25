pragma Singleton
import QtQuick 2.15
import Qt.labs.settings 1.0

// Setările aplicației — singleton global, accesat ca `AppSettings.language`
// (import "../app"). Se persistă singur pe disc (aceleași chei ca înainte),
// fără backend Oracle încă.
QtObject {
    id: root

    property string language: "ro"
    property string waiterName: "Waiter02"
    // Codul real de chelner (OFICIANT din UAMenu), completat la login. E și
    // identitatea reținută pe acest telefon: != 0 înseamnă că LoginPage sare
    // direct la PIN pentru acest chelner; 0 = prima logare, se alege din listă.
    // Folosit și când creăm comenzi (dataService.createOrder).
    property int waiterOficiant: 0

    // --- Throttling la introducerea PIN-ului (vezi LoginPage) ---
    // Persistate, NU ținute în pagină: LoginPage e distrusă la fiecare back
    // spre Welcome, deci orice contor local reînvie la zero când reintri -
    // atât blocarea, cât și numărul de încercări. Bypass-ul era banal: 4
    // greșeli, back, încă 4, la nesfârșit, fără să se declanșeze vreodată
    // blocarea. Din același motiv reținem un MOMENT DE EXPIRARE absolut, nu o
    // numărătoare inversă: așa supraviețuiește și unei reporniri a aplicației.
    //
    // Blocarea e pe dispozitiv, nu pe chelner: altfel "Schimbă utilizatorul"
    // ar fi fost următorul bypass. 30 de secunde sunt destul de scurte cât să
    // nu încurce un al doilea chelner real.
    property int pinFailedAttempts: 0
    property real pinLockUntilMs: 0

    // --- Server (backend PHP) ---
    // URL-ul către oracle_waiter.php. Valoare implicită vizibilă (ca la
    // Una_Prod's httpAddress) - apare ca text real, editabil, în câmpul
    // Server din Administrare, nu ascunsă într-un placeholder. La un client
    // nou, se șterge/înlocuiește manual din acel ecran. Dacă rămâne goală
    // (client nou, nesetat încă), dataService nu mai are fallback în C++ -
    // cererile eșuează explicit ("Missing backend address") în loc să
    // vorbească tăcut cu backend-ul Foișor.
    property string serverUrl: "http://una.md:3323/um/una_waiter/foisor.php"

    // Notă despre deconectare: NU golim nimic de-aici, intenționat.
    // waiterOficiant rămâne reținut, ca la următoarea logare chelnerul să sară
    // direct la PIN (decizia lui Kristian, 2026-07-25) - cine preia telefonul
    // folosește "Schimbă utilizatorul" din ecranul de PIN.
    //
    // Nici OrdersStore nu se golește: comenzile locale sunt marcate cu
    // proprietarul lor (vezi OrdersStore.isEditableBy), deci al doilea chelner
    // tot nu le poate deschide, iar primul și le regăsește intacte. Golirea
    // cache-ului ar readuce exact bug-ul pentru care a fost persistat:
    // "comanda ta pare pornită pe alt dispozitiv".

    // Persistă setările între lansări (aceleași chei ca vechiul bloc din main.qml).
    property var _persist: Settings {
        property alias language: root.language
        property alias waiterName: root.waiterName
        property alias waiterOficiant: root.waiterOficiant
        property alias serverUrl: root.serverUrl
        property alias pinFailedAttempts: root.pinFailedAttempts
        property alias pinLockUntilMs: root.pinLockUntilMs
    }
}
