import QtQuick
import qs
import qs.components

// The pointer's light on the glass (reel 10), four ways, on one wandering
// pointer that spends most of its time below the pill, as it does over the
// windows under the bar.
//
// Everything that follows the pointer is eased every frame towards where it
// should be (exponentially, the way a critically damped spring settles), never
// by an animation restarted on each move, so it glides and never jumps.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    // The pointer, in a column's own pixels.
    property real px: 150
    property real py: 230

    ParallelAnimation {
        running: true
        loops: Animation.Infinite

        SequentialAnimation {
            NumberAnimation { target: scene; property: "px"; to: 30; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "px"; to: 60; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "px"; to: 230; duration: 1700; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "px"; to: 280; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "px"; to: 150; duration: 1500; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            NumberAnimation { target: scene; property: "py"; to: 140; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 32; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 26; duration: 1700; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 110; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 230; duration: 1400; easing.type: Easing.InOutSine }
        }
    }

    Row {
        LightColumn { lamp: 0; glow: 0; title: "none (today)" }
        LightColumn { lamp: 1.0; glow: 0; title: "1 · the pointer is the light" }
        LightColumn { lamp: 0; glow: 1; title: "2 · glow under the pointer" }
        LightColumn { lamp: 0.6; glow: 0.7; title: "3 · both, softer" }
    }

    component LightColumn: Item {
        id: col

        required property real lamp
        required property real glow
        required property string title

        width: 300
        height: scene.height

        readonly property int room: 6
        readonly property rect pill: Qt.rect(50, 20, 200, Theme.barHeight)

        // Where the light is, trailing the pointer a little, and how much the
        // pointer is on the pill: 1 on it, easing to nothing 24px off it.
        property real lx: scene.px
        property real ly: scene.py
        property real on: 0
        readonly property real onTarget: {
            const dx = Math.max(pill.x - scene.px, 0, scene.px - (pill.x + pill.width));
            const dy = Math.max(pill.y - scene.py, 0, scene.py - (pill.y + pill.height));
            return Math.max(0, 1 - Math.hypot(dx, dy) / 24);
        }
        FrameAnimation {
            running: true
            onTriggered: {
                const follow = 1 - Math.exp(-frameTime / 0.06);
                const fade = 1 - Math.exp(-frameTime / 0.12);
                col.lx += (scene.px - col.lx) * follow;
                col.ly += (scene.py - col.ly) * follow;
                col.on += (col.onTarget - col.on) * fade;
            }
        }

        LabGlass {
            x: col.pill.x - col.room
            y: col.pill.y - col.room
            width: col.pill.width + 2 * col.room
            height: col.pill.height + 2 * col.room
            backdrop: scene.backdrop
            box0: Qt.vector4d(col.room, col.room, col.pill.width, col.pill.height)
            rimFrom: col.room
            rimTo: col.room + col.pill.height
            light: Qt.vector4d(col.lx - x, col.ly - y, 140, col.lamp)
            hover: Qt.vector4d(col.lx - x, col.ly - y, 40, col.glow * col.on)
        }

        Text {
            x: col.pill.x
            width: col.pill.width
            y: col.pill.y
            height: col.pill.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "Sun 11 Oct     01:20"
            color: Theme.fg
            font.family: Settings.font
            font.pixelSize: Theme.textSize
        }

        Tag {
            anchors.horizontalCenter: parent.horizontalCenter
            y: col.height - height - 10
            text: col.title
        }

        Cursor {
            x: scene.px
            y: scene.py
        }
    }
}
