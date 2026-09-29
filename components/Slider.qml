import QtQuick
import qs

// A flat drag-and-click track. Hand-built rather than QtQuick.Controls because
// everything about the bar's look is defined here and a styled Controls slider
// would be more code, not less.
Item {
    id: root

    property real value: 0      // 0..1
    property real trackHeight: 4
    // A track painted with the range it covers — a rainbow, a black-to-white
    // ramp. There is no "how much" on one of those, only "which", so the grown
    // fill gives way to a marker and the track takes the full height.
    property Gradient trackGradient: null
    // A scrubber rather than a slider, the way Apple draws a position: it is
    // read far more often than it is set, so it goes without a knob and only
    // says it can be taken hold of once the pointer is on it, by swelling.
    // Drawn as the music pill draws its line — the rest of the track a trace
    // of the fill's colour, and the whole of it lit from above.
    property bool knob: true
    property color fill: Theme.fg
    // How far one notch of the wheel moves the value. Zero leaves the wheel
    // to whatever is underneath — the sound popup has one handler for all
    // its rows, which a slider taking the wheel for itself would cut short.
    // Negative for a position, which the wheel goes through the way it goes
    // down a page: down is later. Up is more only for an amount.
    property real wheelStep: 0
    property real _wheelAcc: 0
    signal moved(real value)

    implicitWidth: 140
    implicitHeight: 14

    Rectangle {
        id: track

        readonly property bool swollen: !root.knob && (hover.hovered || area.pressed)

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackGradient ? root.height : swollen ? 2 * root.trackHeight : root.trackHeight
        radius: height / 2
        color: root.trackGradient ? "transparent" : root.knob ? Theme.sliderTrack : Qt.rgba(root.fill.r, root.fill.g, root.fill.b, Theme.pillTrackRest)
        gradient: root.trackGradient

        Behavior on height {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutQuad
            }
        }

        layer.enabled: !root.knob
        layer.effect: ShaderEffect {
            property real foot: Theme.pillTrackFoot

            fragmentShader: Qt.resolvedUrl("../shaders/track.frag.qsb")
        }

        // Cut off square where the value is rather than rounded there, so
        // the end of the fill is the value and not half a cap past it.
        Item {
            visible: !root.trackGradient
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            clip: true

            Rectangle {
                width: track.width
                height: parent.height
                radius: track.radius
                color: root.fill
            }
        }
    }

    // The knob. A system slider always has one — the fill alone says how
    // much, the knob says where to take hold.
    Rectangle {
        visible: root.knob && !root.trackGradient
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - 2
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(root.width - width, root.value * root.width - width / 2))
        color: Theme.fg
        border.width: Theme.pillBorder
        border.color: Theme.knobEdge
    }

    Rectangle {
        visible: root.trackGradient !== null
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: track.height
        // Held inside the track at both ends, so the marker at either extreme
        // is as readable as the ones in the middle.
        x: Math.max(0, Math.min(root.width - width, root.value * root.width - width / 2))
        color: Theme.fg
        border.width: 1
        border.color: Theme.markerEdge
    }

    // A handler rather than hover on the MouseArea, which would take the
    // hover from anything under it.
    HoverHandler {
        id: hover
    }

    MouseArea {
        id: area

        anchors.fill: parent
        cursorShape: Qt.ArrowCursor

        function seek(x) {
            root.moved(Math.max(0, Math.min(1, x / root.width)));
        }

        onPressed: function (mouse) {
            seek(mouse.x);
        }
        onPositionChanged: function (mouse) {
            if (pressed)
                seek(mouse.x);
        }
        // Accumulated the way BarItem does it, so a touchpad's fractions add
        // up to notches instead of each one being a step.
        onWheel: function (wheel) {
            if (root.wheelStep === 0) {
                wheel.accepted = false;
                return;
            }
            root._wheelAcc += wheel.angleDelta.y;
            const notches = Math.trunc(root._wheelAcc / 120);
            if (notches === 0)
                return;
            root._wheelAcc -= notches * 120;
            root.moved(Math.max(0, Math.min(1, root.value + notches * root.wheelStep)));
        }
    }
}
