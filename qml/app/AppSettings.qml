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

    // --- Server (backend PHP) ---
    // URL-ul către oracle_waiter.php. Gol => dataService folosește URL-ul
    // implicit din C++ (endpoint-ul de test). Se completează din Administrare.
    property string serverUrl: ""

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
        property alias serverUrl: root.serverUrl
        property alias printerIp: root.printerIp
        property alias printerPort: root.printerPort
        property alias printerName: root.printerName
    }
}
