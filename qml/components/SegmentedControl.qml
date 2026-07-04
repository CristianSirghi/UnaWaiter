import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Control segmentat orizontal (ex: Mic/Mediu/Mare). Suportă tap direct pe o
// opțiune și glisare cu degetul a pastilei colorate — la eliberare, pastila
// se aliniază animat pe cea mai apropiată opțiune. O opțiune cu
// `enabled: false` în model rămâne vizibilă dar nu poate fi selectată
// (ex: "Dark · în curând").
Item {
    id: root

    property var theme
    property var options: []       // [{ label, value, enabled? }]
    property var currentValue

    signal optionSelected(var value)

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

    // Șina (fundalul) controlului.
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.theme.surface
        border.color: root.theme.border
    }

    // Pastila care culisează pe segmentul selectat / urmărește degetul.
    Rectangle {
        id: indicator
        y: 3
        width: root.segmentWidth
        height: track.height - 6
        radius: height / 2
        color: root.theme.primary
        scale: dragArea.pressed ? 1.05 : 1.0

        Behavior on x {
            enabled: !dragArea.drag.active
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    // Ține pastila sincronizată cu selecția curentă cât timp nu e trasă cu degetul.
    Binding {
        target: indicator
        property: "x"
        value: root.currentIndex * root.segmentWidth + 3
        when: !dragArea.drag.active
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
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData.label
                font.pixelSize: 13 * root.theme.fontScale
                color: index === root.currentIndex ? "white" : root.theme.textPrimary
                opacity: (modelData.enabled !== false) ? 1.0 : 0.4
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent

        drag.target: indicator
        drag.axis: Drag.XAxis
        drag.minimumX: 3
        drag.maximumX: Math.max(3, track.width - indicator.width - 3)

        // La apăsare, pastila sare imediat sub deget — un tap simplu pe altă
        // opțiune se simte instantaneu, iar dacă degetul continuă să se miște,
        // `drag.target` preia controlul și pastila urmărește mișcarea.
        onPressed: function (mouse) {
            var targetX = mouse.x - indicator.width / 2
            if (targetX < drag.minimumX) targetX = drag.minimumX
            if (targetX > drag.maximumX) targetX = drag.maximumX
            indicator.x = targetX
        }

        onReleased: {
            var snapIndex = root.nearestIndex(indicator.x - 3)
            if (!root.isEnabledAt(snapIndex))
                snapIndex = root.currentIndex

            indicator.x = snapIndex * root.segmentWidth + 3

            if (snapIndex !== root.currentIndex)
                root.optionSelected(root.options[snapIndex].value)
        }
    }
}
