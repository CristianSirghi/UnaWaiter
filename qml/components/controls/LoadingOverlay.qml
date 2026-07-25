import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Strat opac peste conținutul unei pagini cât timp datele ei se încarcă (sau
// dacă încărcarea a eșuat).
//
// Spre deosebire de un simplu Label "se încarcă…", acesta ÎNGHITE tap-urile.
// Asta e tot rostul lui: în OrderPage, cât timp se aștepta get_order_lines,
// mesajul era doar un Label transparent la clic, deci lista de produse de
// dedesubt rămânea perfect interactivă. Dacă chelnerul apăsa "+" în acea
// fereastră, răspunsul serverului suprascria apoi qtyStore prin
// applyServerLines() și îi ștergea tăcut ce tocmai adăugase.
//
// Se așază peste conținut, nu peste antet - butonul de înapoi rămâne
// accesibil, ca ecranul să nu devină o fundătură.
//
// Utilizare:
//   Components.LoadingOverlay {
//       anchors.fill: parent
//       loading: root.awaitingData
//       errorText: root.loadError !== "" ? qsTr("Couldn't load: %1").arg(root.loadError) : ""
//       loadingText: qsTr("Loading…")
//       retryText: qsTr("Retry")
//       onRetryRequested: root.reload()
//   }
Item {
    id: root

    property bool loading: false
    // Gol = fără eroare. Când e setat, înlocuiește textul de încărcare și
    // afișează butonul de reîncercare (dacă retryText e setat).
    property string errorText: ""
    property string loadingText: qsTr("Loading…")
    // Gol = fără buton de reîncercare (pentru ecranele unde retry n-are sens).
    property string retryText: ""

    signal retryRequested()

    visible: root.loading || root.errorText !== ""

    // Fundal opac: ascunde conținutul pe jumătate populat de dedesubt.
    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Bariera propriu-zisă. Declarată ÎNAINTE de coloana de mai jos, ca
    // butonul de reîncercare (copil al coloanei) să rămână deasupra ei și să
    // fie în continuare apăsabil.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 48
        spacing: 18

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.errorText !== "" ? root.errorText : root.loadingText
            font.pixelSize: 15 * Theme.fontScale
            color: root.errorText !== "" ? Theme.danger : Theme.textSecondary
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.errorText !== "" && root.retryText !== ""
            implicitWidth: retryLabel.implicitWidth + 44
            implicitHeight: 44
            radius: 22
            color: retryArea.pressed ? Qt.darker(Theme.primary, 1.2) : Theme.primary

            Label {
                id: retryLabel
                anchors.centerIn: parent
                text: root.retryText
                font.pixelSize: 15 * Theme.fontScale
                font.bold: true
                color: "white"
            }

            MouseArea {
                id: retryArea
                anchors.fill: parent
                onClicked: root.retryRequested()
            }
        }
    }
}
