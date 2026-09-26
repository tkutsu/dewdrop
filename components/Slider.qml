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
    signal moved(real value)

    implicitWidth: 140
    implicitHeight: 14

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackGradient ? root.height : root.trackHeight
        radius: height / 2
        color: root.trackGradient ? "transparent" : Qt.rgba(1, 1, 1, 0.2)
        gradient: root.trackGradient

        Rectangle {
            visible: !root.trackGradient
            width: Math.max(root.trackHeight, track.width * Math.max(0, Math.min(1, root.value)))
            height: parent.height
            radius: parent.radius
            color: Theme.fg
        }
    }

    // The knob. A system slider always has one — the fill alone says how
    // much, the knob says where to take hold.
    Rectangle {
        visible: !root.trackGradient
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - 2
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(root.width - width, root.value * root.width - width / 2))
        color: Theme.fg
        border.width: Theme.pillBorder
        border.color: Qt.rgba(0, 0, 0, 0.35)
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
        // The marker crosses white, yellow and black on the same track; an
        // outline is what keeps it from vanishing into one of them.
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.7)
    }

    MouseArea {
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
    }
}
