import QtQuick
import qs

// A flat drag-and-click track. Hand-built rather than QtQuick.Controls because
// everything about the bar's look is defined here and a styled Controls slider
// would be more code, not less.
Item {
    id: root

    property real value: 0      // 0..1
    property string name: ""
    readonly property real minimumValue: 0
    readonly property real maximumValue: 1
    readonly property real stepSize: root.wheelStep > 0 ? root.wheelStep : 0.05

    property real trackHeight: 4
    // A track painted with the range it covers — a rainbow, a black-to-white
    // ramp. There is no "how much" on one of those, only "which", so the grown
    // fill gives way to a marker and the track takes the full height.
    property Gradient trackGradient: null
    // A scrubber rather than a slider, the way Apple draws a position: it is
    // read far more often than it is set, so it goes without a knob and only
    // says it can be taken hold of once the pointer is on it, by swelling.
    // Flat, as Apple draws them: the fill in its colour, the rest of the track
    // the same grey every slider's is.
    property bool knob: true
    property color fill: Theme.fg
    // How far one notch of the wheel moves the value. Zero leaves the wheel
    // to whatever is underneath — the sound popup has one handler for all
    // its rows, which a slider taking the wheel for itself would cut short.
    // Down is on, towards the right end, for every slider alike, and up is
    // back: the track lies across the wheel, so it reads like a page. The
    // bar's icons go the other way round, up for more.
    property real wheelStep: 0
    property real _wheelAcc: 0
    signal moved(real value)

    implicitWidth: 140
    implicitHeight: 14

    // Qt's Value interface writes this proxy; model updates only refresh it.
    Item {
        id: accessibleValue
        objectName: "accessibleValue"
        anchors.fill: parent

        property real value: root.value
        readonly property real minimumValue: root.minimumValue
        readonly property real maximumValue: root.maximumValue
        readonly property real stepSize: root.stepSize
        onValueChanged: {
            if (value === root.value)
                return;
            if (root.enabled && root.visible)
                root.moved(Math.max(minimumValue, Math.min(maximumValue, value)));
            value = Qt.binding(() => root.value);
        }

        Accessible.role: Accessible.Slider
        Accessible.name: root.name
        Accessible.focusable: true
        Accessible.onIncreaseAction: if (root.enabled && root.visible)
            root.moved(Math.min(root.maximumValue, root.value + root.stepSize))
        Accessible.onDecreaseAction: if (root.enabled && root.visible)
            root.moved(Math.max(root.minimumValue, root.value - root.stepSize))
    }

    Rectangle {
        id: track

        readonly property bool swollen: !root.knob && (hover.hovered || area.pressed)

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackGradient ? root.height : swollen ? 2 * root.trackHeight : root.trackHeight
        radius: height / 2
        color: root.trackGradient ? "transparent" : Theme.sliderTrack
        gradient: root.trackGradient

        Behavior on height {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutQuad
            }
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
            root._wheelAcc -= wheel.angleDelta.y;
            const notches = Math.trunc(root._wheelAcc / 120);
            if (notches === 0)
                return;
            root._wheelAcc -= notches * 120;
            root.moved(Math.max(0, Math.min(1, root.value + notches * root.wheelStep)));
        }
    }
}
