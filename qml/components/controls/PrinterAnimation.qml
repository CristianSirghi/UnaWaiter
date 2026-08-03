import QtQuick 2.15
import "../../theme"

// Imprimanta de bonuri, desenată și animată: hârtia crește din fanta de sub
// corpul aparatului, cu marginea de jos zimțată, și o ia de la capăt.
//
// Totul e din Rectangle-uri simple. NU se folosesc Canvas sau Qt Quick Shapes:
// pe build-ul ăsta (Qt 5.15.2) au dat probleme pe Android, iar o animație de
// așteptare e ultimul loc unde vrei un ecran negru.
//
// `feeding` separă cele două stări pe care le are de arătat:
//   false - aparatul lucrează, dar încă nu iese hârtie (se emite documentul);
//           doar beculețul pulsează.
//   true  - se tipărește chiar acum; hârtia curge.
//
// `paperCutColor` trebuie să fie fundalul REAL de sub componentă: zimții nu
// sunt decupați din hârtie (n-avem cu ce), ci desenați peste ea în culoarea
// fundalului. Pe alt fundal decât cel dat aici, ar apărea ca niște pătrate.
Item {
    id: root

    property bool feeding: false
    property color paperCutColor: Theme.background

    implicitWidth: 200
    implicitHeight: 200

    // Corpul imprimantei stă SUS, iar hârtia iese pe dedesubt - ordinea din
    // fișier contează: viewport-ul e declarat primul, ca fanta și corpul,
    // desenate după, să acopere marginea de sus a hârtiei.
    Item {
        id: paperViewport

        x: (root.width - width) / 2
        y: 62
        width: 132
        height: 116
        clip: true

        Rectangle {
            id: paper

            width: parent.width
            height: 26
            color: "#FFFFFF"
            clip: true

            // Rândurile "tipărite". Simple dreptunghiuri gri de lățimi diferite:
            // la dimensiunea asta, un text real ar fi oricum ilizibil, iar
            // aparența de bon vine din ritmul rândurilor, nu din litere.
            Column {
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 7

                Rectangle { width: parent.width * 0.62; height: 5; radius: 2.5; color: "#3A3F47" }
                Rectangle { width: parent.width * 0.38; height: 4; radius: 2; color: "#B9BEC6" }
                Rectangle { width: parent.width; height: 1; color: "#DDE1E6" }
                Rectangle { width: parent.width * 0.85; height: 4; radius: 2; color: "#B9BEC6" }
                Rectangle { width: parent.width * 0.70; height: 4; radius: 2; color: "#B9BEC6" }
                Rectangle { width: parent.width * 0.78; height: 4; radius: 2; color: "#B9BEC6" }
                Rectangle { width: parent.width; height: 1; color: "#DDE1E6" }
                Rectangle { width: parent.width * 0.50; height: 6; radius: 3; color: "#3A3F47" }
            }

            // Marginea zimțată: pătrate rotite la 45°, cu centrul chiar pe
            // marginea de jos a hârtiei, vopsite în culoarea fundalului. Sunt
            // copii ai hârtiei, deci coboară odată cu ea; jumătatea lor de jos
            // cade oricum în afara hârtiei și e tăiată de `clip`.
            //
            // Pasul dintre ele NU e arbitrar: un pătrat de latură L rotit la 45°
            // ocupă L·√2 pe orizontală, deci `spacing` trebuie să fie
            // L·(√2-1) ≈ 5 la L=12, ca zimții să se atingă vârf la vârf. Mai
            // mic, se suprapun într-o bandă dreaptă; mai mare, rămân bucăți de
            // margine netedă între ei.
            Row {
                y: paper.height - 6
                spacing: 5

                Repeater {
                    model: 9

                    Rectangle {
                        width: 12
                        height: 12
                        color: root.paperCutColor
                        rotation: 45
                        transformOrigin: Item.Center
                    }
                }
            }
        }
    }

    // Corpul aparatului, desenat PESTE hârtie.
    Rectangle {
        id: printerBody

        x: (root.width - width) / 2
        y: 0
        width: 172
        height: 68
        radius: 14
        color: Theme.keyBackground
        border.width: 1
        border.color: Theme.border

        // Fanta din care iese hârtia.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 14
            width: 136
            height: 7
            radius: 3.5
            color: Theme.border
        }

        // Beculețul de stare: pulsează tot timpul cât componenta e vizibilă,
        // ca aparatul să nu pară înghețat în pașii dinaintea tipăririi.
        Rectangle {
            id: statusLight

            x: 18
            y: 18
            width: 11
            height: 11
            radius: 5.5
            color: Theme.primary

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 620; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
            }
        }

        // Câteva butoane inerte, doar ca să semene a aparat.
        Row {
            x: 42
            y: 20
            spacing: 7

            Repeater {
                model: 3

                Rectangle {
                    width: 16
                    height: 7
                    radius: 3.5
                    color: Theme.border
                }
            }
        }
    }

    // Bucla de tipărire. Fiecare reluare pornește de la valorile puse explicit
    // în cele două PropertyAction de la început - fără ele, a doua trecere ar
    // continua de unde a lăsat-o fade-out-ul, adică de la hârtie invizibilă.
    SequentialAnimation {
        id: feedAnimation

        running: root.feeding && root.visible
        loops: Animation.Infinite

        PropertyAction { target: paper; property: "opacity"; value: 1 }
        PropertyAction { target: paper; property: "height"; value: 26 }
        NumberAnimation {
            target: paper
            property: "height"
            to: paperViewport.height
            duration: 1500
        }
        PauseAnimation { duration: 420 }
        NumberAnimation { target: paper; property: "opacity"; to: 0; duration: 260 }

        // O animație oprită la mijloc lasă hârtia unde a apucat (pe jumătate
        // ieșită, sau chiar transparentă). O readucem la starea de repaus, ca
        // pasul următor să nu moștenească un cadru intermediar.
        onRunningChanged: {
            if (!running) {
                paper.opacity = 1
                paper.height = 26
            }
        }
    }
}
