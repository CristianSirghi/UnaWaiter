import QtQuick 2.15
import "../../theme"

// MouseArea cu feedback vizual la apăsare: un voal subțire peste suprafața
// atinsă, cât timp degetul e pe ea. Înlocuiește direct un `MouseArea` obișnuit -
// aceleași proprietăți și semnale, doar tipul se schimbă.
//
// De ce un voal desenat, și NU `parent.opacity = ...` la apăsare: multe butoane
// din aplicație au deja un binding pe `opacity` (butonul "−" estompat la pragul
// deja trimis, coșul de gunoi estompat cât se anulează comanda). O scriere
// imperativă peste acele binding-uri le-ar rupe definitiv - exact clasa de bug
// documentată în memoria proiectului pentru SegmentedControl și ChangeTablePicker.
// Voalul e un frate desenat deasupra, deci nu atinge nimic din ce există.
//
// Utilizare:
//   Components.TouchArea {
//       anchors.fill: parent
//       onClicked: ...
//   }
// Raza urmează automat forma părintelui (`radius`-ul lui), deci butoanele
// rotunde primesc un voal rotund. Pentru zonele de atingere fără formă proprie
// (iconițe cu margini negative) pune `circular: true`.
MouseArea {
    id: root

    // Voal rotund, pentru zonele de atingere din jurul unei iconițe.
    property bool circular: false
    // Implicit copiază colțurile părintelui; un părinte fără `radius`
    // (Item, Label) dă 0, adică un voal drept.
    property real veilRadius: root.circular
        ? Math.min(width, height) / 2
        : ((parent && parent.radius !== undefined) ? parent.radius : 0)
    // Pe fundal deschis întunecăm, pe fundal închis luminăm - altfel voalul e
    // invizibil exact pe tema pe care e mai greu de văzut oricum.
    property color veilColor: Theme.darkMode ? "white" : "black"
    property real veilOpacity: 0.15

    Rectangle {
        anchors.fill: parent
        radius: root.veilRadius
        color: root.veilColor
        // `pressed` e mereu fals cât timp aria e dezactivată, deci un buton
        // inactiv nu răspunde vizual - corect, nu răspunde nici funcțional.
        opacity: root.pressed ? root.veilOpacity : 0

        // Apariție instantanee, dispariție lină: la o atingere scurtă (sub un
        // cadru) un fade-in ar putea să nu apuce să se vadă deloc.
        Behavior on opacity {
            NumberAnimation { duration: root.pressed ? 0 : 140 }
        }
    }
}
