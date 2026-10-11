import QtQuick
import Quickshell
import qs
import qs.components

// The real thing: a Pill whose glass takes the pointer's light through
// GlassLight, fed the way Bar.qml's hover feeds it, by a scripted pointer
// that comes along the bar, crosses the pill and leaves.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property real px: -20
    property real py: 40
    property bool over: false

    onPxChanged: if (over)
        GlassLight.track(QsWindow.window, Qt.point(px, py))
    onOverChanged: over ? GlassLight.track(QsWindow.window, Qt.point(px, py)) : GlassLight.leave(QsWindow.window)

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PropertyAction { target: scene; property: "over"; value: true }
        NumberAnimation { target: scene; property: "px"; to: 120; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: scene; property: "px"; to: 330; duration: 1800; easing.type: Easing.InOutSine }
        NumberAnimation { target: scene; property: "px"; to: 420; duration: 700; easing.type: Easing.InOutSine }
        PropertyAction { target: scene; property: "over"; value: false }
        PauseAnimation { duration: 900 }
        PropertyAction { target: scene; property: "px"; value: -20 }
    }

    Tag {
        x: 20
        y: 10
        text: "real Pill · GlassLight (lamp " + Theme.glassLamp + ", glow " + Theme.glassHover + ")"
    }

    Item {
        x: 20
        y: 40 - (Theme.barHeight + 2 * Theme.barInset) / 2
        width: 360
        height: Theme.barHeight + 2 * Theme.barInset

        Pill {
            side: Pill.Side.Centre
            backdrop: scene.backdrop

            BarItem { Glyph { text: Theme.glyph.wallpaper } }
            BarItem { Glyph { text: Theme.glyph.satty } }
            BarItem { Glyph { text: Theme.glyph.clipboard } }
            BarItem { Glyph { text: Theme.glyph.web } }
            BarItem { Glyph { text: Theme.glyph.folder } }
        }
    }

    Cursor {
        x: scene.px
        y: scene.py
        visible: scene.over
    }
}
