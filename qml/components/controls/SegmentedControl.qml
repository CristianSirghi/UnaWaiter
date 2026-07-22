import QtQuick 2.15
import "../../theme"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQml 2.15

Item {
    id: root

    property var options: []       // [{ label, value, enabled? }]
    property var currentValue
    property int labelHorizontalAlignment: Text.AlignHCenter

    signal optionSelected(var value)

    implicitWidth: 240
    implicitHeight: 44

    readonly property int segmentCount: options.length
    readonly property real segmentWidth: segmentCount > 0 ? (width - 6) / segmentCount : 0
    readonly property int currentIndex: indexOfValue(currentValue)

    function indexOfValue(value) {
        for (var i = 0; i < options.length; ++i)
            if (options[i].value === value)
                return i
        return 0
    }

    function isEnabledAt(index) {
        return options[index] !== undefined && options[index].enabled !== false
    }

    function nearestIndex(indicatorX) {
        var i = Math.round(indicatorX / root.segmentWidth)
        if (i < 0) i = 0
        if (i > root.segmentCount - 1) i = root.segmentCount - 1
        return i
    }

    // Poziția pastilei sub deget cât timp e apăsată (tap simplu sau începutul
    // unui drag, înainte ca drag.active să pornească) - aceleași limite ca
    // drag.minimumX/maximumX de mai jos.
    function pressedTargetX(mouseX) {
        var t = mouseX - indicator.width / 2
        var maxX = track.width - indicator.width - 3
        if (t < 3) t = 3
        if (t > maxX) t = maxX
        return t
    }

    // Șina (fundalul) controlului.
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface
        border.color: Theme.border
    }

    // Pastila care culisează pe segmentul selectat / urmărește degetul.
    Rectangle {
        id: indicator
        y: 3
        width: root.segmentWidth
        height: track.height - 6
        radius: height / 2
        color: Theme.primary
        scale: dragArea.pressed ? 1.05 : 1.0

        Behavior on x {
            enabled: !dragArea.drag.active
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    // Ține pastila sincronizată cu selecția curentă / cu degetul, complet
    // declarativ. NU scriem niciodată indicator.x imperativ (ex. din
    // onPressed/onReleased): o scriere directă rupe binding-ul instalat de
    // acest Binding, iar cum `when` rămâne true pe durata unui tap simplu
    // (nu există o tranziție false→true care să-l repornească), pastila ar
    // rămâne "moartă" la orice schimbare ulterioară a currentValue care nu
    // vine dintr-un tap pe acest control chiar el. Vezi bug similar (scriere
    // imperativă peste un binding activ) în unawaiter-build-env.md #6.
    Binding {
        target: indicator
        property: "x"
        value: dragArea.pressed ? root.pressedTargetX(dragArea.mouseX)
                                 : root.currentIndex * root.segmentWidth + 3
        when: !dragArea.drag.active
        restoreMode: Binding.RestoreBinding
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 0

        Repeater {
            model: root.options

            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                // Forțează o "greutate" egală pentru toate etichetele — altfel
                // Layout.fillWidth împarte spațiul proporțional cu lățimea
                // naturală a fiecărui text (Layout.preferredWidth implicit =
                // implicitWidth), nu în treimi egale ca pastila.
                Layout.preferredWidth: 1
                horizontalAlignment: root.labelHorizontalAlignment
                verticalAlignment: Text.AlignVCenter
                leftPadding: horizontalAlignment === Text.AlignLeft ? 14 : 0
                rightPadding: 0
                text: modelData.label
                font.pixelSize: 13 * Theme.fontScale
                color: index === root.currentIndex ? "white" : Theme.textPrimary
                opacity: (modelData.enabled !== false) ? 1.0 : 0.4
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: dragArea

        // Urmărește dacă gestul curent a devenit vreodată un drag real -
        // citim asta la onReleased în loc de `drag.active` direct, pentru că
        // ordinea exactă (drag.active revine la false chiar înainte/după
        // semnalul released) nu e garantată.
        property bool dragHappened: false

        anchors.fill: parent
        drag.target: indicator
        drag.axis: Drag.XAxis
        drag.minimumX: 3
        drag.maximumX: Math.max(3, track.width - indicator.width - 3)

        onPressed: dragArea.dragHappened = false
        drag.onActiveChanged: if (drag.active) dragArea.dragHappened = true

        // Poziția pastilei e gestionată declarativ de Binding-ul de mai sus
        // (pastila sare sub deget la apăsare via `dragArea.pressed`, apoi
        // urmărește mișcarea via `drag.target` odată ce pornește un drag real).

        onReleased: function (mouse) {
            // Dacă a fost un drag real, `indicator.x` e deja poziția corectă
            // (scrisă de mecanismul intern drag.target, nu de Binding-ul de mai
            // sus - Binding-ul e oricum inactiv cât timp drag.active e true).
            // Altfel (tap simplu, fără drag), folosim poziția din eveniment,
            // nu `indicator.x` - Binding-ul poate deja s-o fi resetat la
            // selecția curentă în clipa în care `dragArea.pressed` a devenit false.
            var releaseX = dragArea.dragHappened ? (indicator.x - 3)
                                                  : (root.pressedTargetX(mouse.x) - 3)
            var snapIndex = root.nearestIndex(releaseX)
            if (!root.isEnabledAt(snapIndex))
                snapIndex = root.currentIndex

            if (snapIndex !== root.currentIndex)
                root.optionSelected(root.options[snapIndex].value)
        }
    }
}
