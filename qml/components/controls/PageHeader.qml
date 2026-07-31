import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Antetul standard al unei pagini secundare: săgeata înapoi + titlu.
// Era copiat identic în 6 pagini (Select table, Paid orders, Profile, Settings,
// Administration, Updates) - aceleași distanțatoare, aceeași înălțime, aceeași
// mărime de font. O schimbare de aspect trebuia făcută în toate șase.
//
// Nu face singur `pop()`: emite `backRequested()` și lasă pagina să decidă.
// LoginPage, de exemplu, se întoarce uneori la lista de chelneri în loc să iasă
// din pagină, iar OrderPage cere confirmare dacă are o comandă nesalvată.
//
// Utilizare:
//   header: Components.PageHeader {
//       title: qsTr("Profile")
//       onBackRequested: root.StackView.view.pop()
//   }
RowLayout {
    id: root

    property string title: ""

    // Conținut opțional la dreapta titlului (SelectTablePage își pune acolo
    // legenda liber/ocupat). E `Component`, nu un slot de copii: QML împachetează
    // singur declarația inline, iar paginile care nu-l setează nu plătesc nimic -
    // Loader-ul rămâne gol și de lățime zero, deci antetul lor arată exact ca înainte.
    property Component trailing: null

    signal backRequested()

    // `height`, nu `implicitHeight`: exact ca înainte în fiecare pagină.
    // Page-ul își dimensionează antetul după asta, iar o schimbare aici ar
    // muta conținutul tuturor paginilor.
    height: 56

    Item { Layout.preferredWidth: 12 }

    BackButton {
        color: Theme.textPrimary
        onClicked: root.backRequested()
    }

    Item { Layout.preferredWidth: 8 }

    Label {
        text: root.title
        font.pixelSize: 20 * Theme.fontScale
        font.bold: true
        color: Theme.textPrimary
        elide: Text.ElideRight
        Layout.fillWidth: true
    }

    Loader {
        id: trailingLoader

        sourceComponent: root.trailing
        Layout.alignment: Qt.AlignVCenter
        // `item`, nu `active`: Loader.active e true și fără sourceComponent,
        // deci ar fi lăsat o margine de 12px în antetul celorlalte cinci pagini.
        Layout.leftMargin: trailingLoader.item ? 12 : 0
    }

    Item { Layout.preferredWidth: 12 }
}
