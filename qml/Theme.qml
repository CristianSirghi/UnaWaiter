import QtQuick 2.15

QtObject {
    // Comută întreaga paletă (setat din SettingsPage, secțiunea Temă).
    property bool darkMode: false

    readonly property color background: darkMode ? "#15171B" : "#F5F6F8"
    readonly property color surface: darkMode ? "#1E2128" : "#FFFFFF"
    readonly property color primary: darkMode ? "#4FA8F0" : "#1E88E5"
    readonly property color textPrimary: darkMode ? "#F0F1F3" : "#1B1F24"
    readonly property color textSecondary: darkMode ? "#9AA0A8" : "#6B7280"
    readonly property color border: darkMode ? "#2A2D33" : "#E1E4E8"
    readonly property color success: darkMode ? "#3FC463" : "#2E9E4A"
    readonly property color keyBackground: darkMode ? "#282B33" : "#E7E9ED"

    // Multiplicator global de mărime a textului, setat din SettingsPage
    // (Mic 0.9 / Mediu 1.0 / Mare 1.15). Toate `font.pixelSize` din pagini
    // se înmulțesc cu el, așa că schimbarea aici se reflectă peste tot.
    property real fontScale: 1.0
}
