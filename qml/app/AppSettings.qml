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
    // Codul real de chelner (OFICIANT din UAMenu), completat la login din
    // uw_waiters. Folosit când creăm comenzi (dataService.createOrder).
    property int waiterOficiant: 0
    // Numele de utilizator (uw_waiters.username) reținut după prima logare -
    // telefonul îl ține minte, apoi la login se cere doar PIN-ul. Gol = prima
    // logare (se cere și user). Se golește din "Schimbă utilizatorul".
    property string waiterUsername: ""

    // --- Server (backend PHP) ---
    // URL-ul către oracle_waiter.php. Valoare implicită vizibilă (ca la
    // Una_Prod's httpAddress) - apare ca text real, editabil, în câmpul
    // Server din Administrare, nu ascunsă într-un placeholder. La un client
    // nou, se șterge/înlocuiește manual din acel ecran. Dacă rămâne goală
    // (client nou, nesetat încă), dataService nu mai are fallback în C++ -
    // cererile eșuează explicit ("Missing backend address") în loc să
    // vorbească tăcut cu backend-ul Foișor.
    property string serverUrl: "http://una.md:3323/um/una_waiter/foisor.php"

    // --- Imprimantă de rețea (LAN, raw TCP) ---
    // IP-ul/portul se aleg din secțiunea Imprimantă (Administrare), prin căutarea
    // de imprimante (printerManager) sau manual. Nimic hardcodat — se salvează aici.
    property string printerIp: ""
    property int printerPort: 9100
    // Nume prietenos afișat în Administrare (producător/model), completat la selecție.
    property string printerName: ""

    // Persistă setările între lansări (aceleași chei ca vechiul bloc din main.qml).
    property var _persist: Settings {
        property alias language: root.language
        property alias waiterName: root.waiterName
        property alias waiterOficiant: root.waiterOficiant
        property alias waiterUsername: root.waiterUsername
        property alias serverUrl: root.serverUrl
        property alias printerIp: root.printerIp
        property alias printerPort: root.printerPort
        property alias printerName: root.printerName
    }
}
