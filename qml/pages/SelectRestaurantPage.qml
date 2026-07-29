import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components

// Alegerea restaurantului la care lucrează telefonul. Apare o singură dată, la
// prima pornire, înainte de logare - lista de chelneri și mesele diferă de la
// un restaurant la altul, deci întrebarea trebuie pusă înaintea lor.
//
// Lista NU e hardcodată aici și nici nu vine direct din Oracle: backend-ul o ia
// din registrul back-office-ului (ybmb_dif_cassa + db links) și o filtrează la
// restaurantele la care chiar se poate conecta. Un restaurant nou apare aici
// fără build nou; unul la care legătura nu există nu apare deloc, ca să nu
// poată fi ales și să eșueze abia la prima comandă.
Page {
    id: root

    // true = ecran deschis din Setări pentru schimbare, nu prima alegere.
    // Schimbă doar textele și arată butonul de înapoi; restul e identic.
    property bool changing: false

    property string loadError: ""
    property bool loaded: false

    signal restaurantChosen(int cod, string name)

    function reload() {
        root.loadError = ""
        root.loaded = false
        dataService.loadRestaurants()
    }

    Connections {
        target: dataService

        function onRestaurantsChanged() {
            root.loaded = true
            root.loadError = ""
        }

        function onRequestFailed(command, error) {
            if (command !== "get_restaurants")
                return
            root.loaded = true
            // registry_unavailable = backend-ul n-a putut citi registrul din
            // back-office ȘI n-avea nici cache. Codul tehnic nu-i spune nimic
            // chelnerului, deci îl traducem.
            root.loadError = (String(error).indexOf("registry_unavailable") >= 0)
                ? qsTr("The restaurant list is unavailable right now.")
                : error
        }
    }

    Component.onCompleted: root.reload()

    background: Rectangle {
        color: Theme.background
    }

    header: Components.PageHeader {
        title: qsTr("Change restaurant")
        // La prima alegere nu există unde să te întorci: fără restaurant,
        // aplicația nu poate face nimic. Din Setări, în schimb, se poate ieși.
        visible: root.changing
        onBackRequested: root.StackView.view.pop()
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: parent.width
            topPadding: root.changing ? 16 : 48
            bottomPadding: 24
            spacing: 16

            Label {
                x: 24
                width: parent.width - 48
                visible: !root.changing
                text: qsTr("At which restaurant do you work?")
                font.pixelSize: 22 * Theme.fontScale
                font.bold: true
                color: Theme.textPrimary
                wrapMode: Text.WordWrap
            }

            Label {
                x: 24
                width: parent.width - 48
                text: qsTr("The answer is remembered on this phone. You can change it later from Settings.")
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: dataService.restaurants

                Rectangle {
                    id: card

                    readonly property int cod: parseInt(modelData.COD_UNIV)
                    readonly property string denumire: String(modelData.DENUMIREA)
                    readonly property bool current: card.cod === AppSettings.restaurantCod

                    x: 24
                    width: contentCol.width - 48
                    height: 64
                    radius: 14
                    color: card.current ? Theme.keyBackground : Theme.surface
                    border.width: 1.5
                    border.color: card.current ? Theme.primary : Theme.border

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 40
                        text: card.denumire
                        elide: Text.ElideRight
                        font.pixelSize: 18 * Theme.fontScale
                        font.bold: card.current
                        color: Theme.textPrimary
                    }

                    Components.TouchArea {
                        anchors.fill: parent
                        onClicked: root.restaurantChosen(card.cod, card.denumire)
                    }
                }
            }

            // Registrul poate răspunde corect, dar cu zero restaurante
            // accesibile - altfel ecranul ar rămâne pustiu, fără să spună de ce.
            Label {
                x: 24
                width: parent.width - 48
                visible: root.loaded && root.loadError === "" && dataService.restaurants.length === 0
                text: qsTr("No restaurant is available. Contact the administrator.")
                font.pixelSize: 14 * Theme.fontScale
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }
    }

    Components.LoadingOverlay {
        anchors.fill: parent
        loading: !root.loaded && root.loadError === ""
        errorText: root.loadError !== ""
            ? qsTr("Couldn't load the restaurants:\n%1").arg(root.loadError)
            : ""
        loadingText: qsTr("Loading restaurants…")
        retryText: qsTr("Retry")
        onRetryRequested: root.reload()
    }
}
