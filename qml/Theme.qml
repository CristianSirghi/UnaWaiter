import QtQuick 2.15

QtObject {
    readonly property color background: "#F5F6F8"
    readonly property color surface: "#FFFFFF"
    readonly property color primary: "#1E88E5"
    readonly property color textPrimary: "#1B1F24"
    readonly property color textSecondary: "#6B7280"
    readonly property color border: "#E1E4E8"
    readonly property color success: "#2E9E4A"
    readonly property color keyBackground: "#E7E9ED"

    // Multiplicator global de mărime a textului, setat din SettingsPage
    // (Mic 0.9 / Mediu 1.0 / Mare 1.15). Toate `font.pixelSize` din pagini
    // se înmulțesc cu el, așa că schimbarea aici se reflectă peste tot.
    property real fontScale: 1.0
}
