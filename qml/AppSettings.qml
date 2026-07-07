import QtQuick 2.15

// Setările aplicației — persistate pe disc via blocul Settings{} din main.qml
// (Qt.labs.settings), fără backend Oracle încă.
QtObject {
    property string language: "ro"
    property string waiterName: "Waiter02"

    // --- Server (backend PHP) ---
    // URL-ul către oracle_waiter.php. Gol până facem backend-ul — nefolosit încă.
    property string serverUrl: ""

    // --- Imprimantă de rețea (LAN, raw TCP) ---
    // IP-ul/portul se aleg din secțiunea Imprimantă (Setări), prin căutarea de
    // imprimante (printerManager) sau manual. Nimic hardcodat — se salvează aici.
    property string printerIp: ""
    property int printerPort: 9100
    // Nume prietenos afișat în Setări (producător/model), completat la selecție.
    property string printerName: ""
}
