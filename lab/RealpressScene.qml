import QtQuick
import qs
import qs.components

// The real thing, not a prototype: a Pill of BarItems over the wallpaper,
// pressed through GlassPress the way PressGlass presses it. Two pills, so a
// press on one is seen not to light the other.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property Item pressed: null

    function pressOn(item) {
        const box = item.keyBox;
        scene.pressed = item;
        GlassPress.press(box, box.mapToItem(null, box.width / 2, box.height / 2 + 3));
    }
    function release() {
        GlassPress.release(scene.pressed.keyBox);
    }

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 500 }
        ScriptAction { script: scene.pressOn(b2) }
        PauseAnimation { duration: 750 }
        ScriptAction { script: scene.release() }
        PauseAnimation { duration: 650 }
        ScriptAction { script: scene.pressOn(c1) }
        PauseAnimation { duration: 100 }
        ScriptAction { script: scene.release() }
        PauseAnimation { duration: 130 }
        ScriptAction { script: scene.pressOn(c1) }
        PauseAnimation { duration: 100 }
        ScriptAction { script: scene.release() }
        PauseAnimation { duration: 700 }
        ScriptAction { script: scene.pressOn(b0) }
        PauseAnimation { duration: 400 }
        ScriptAction { script: scene.release() }
        PauseAnimation { duration: 800 }
    }

    Tag {
        x: 20
        y: 20
        text: "real Pill + BarItem"
    }

    Item {
        x: 20
        y: 60
        width: 360
        height: Theme.barHeight + 2 * Theme.barInset

        Pill {
            side: Pill.Side.Centre
            backdrop: scene.backdrop

            BarItem { id: b0; Glyph { text: Theme.glyph.wallpaper } }
            BarItem { id: b1; Glyph { text: Theme.glyph.satty } }
            BarItem { id: b2; Glyph { text: Theme.glyph.clipboard } }
            BarItem { id: b3; Glyph { text: Theme.glyph.web } }
        }
    }

    Item {
        x: 20
        y: 120
        width: 360
        height: Theme.barHeight + 2 * Theme.barInset

        Pill {
            side: Pill.Side.Centre
            backdrop: scene.backdrop

            BarItem { id: c0; Glyph { text: Theme.glyph.folder } }
            BarItem { id: c1; Glyph { text: Theme.glyph.lock } }
        }
    }
}
