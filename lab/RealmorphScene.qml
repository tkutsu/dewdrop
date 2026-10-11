import QtQuick
import qs
import qs.components

// The real thing: a pill drawn the way Bar.qml draws the music and timer
// pills (Liquid glass shaped by Bar.morph off a real Morph) and a real Popup
// with `morphs`, opening and closing on a script. The lab borrows the bar's
// layer name for this scene (Lab.qml), so Hyprland blurs behind the popup.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property bool isOpen: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 500 }
        ScriptAction { script: { scene.isOpen = true; pop.requestedVisible = true; pop.visible = true; } }
        PauseAnimation { duration: 1600 }
        ScriptAction { script: { scene.isOpen = false; pop.requestedVisible = false; } }
        PauseAnimation { duration: pop.exitMs }
        ScriptAction { script: pop.visible = false }
        PauseAnimation { duration: 900 }
    }

    Morph {
        id: morph
        open: scene.isOpen
    }

    // Bar.morph and Bar.morphContents, as the bar has them.
    function shape(box, s) {
        if (s >= 2)
            return Qt.vector4d(0, 0, 0, 0);
        if (s === 0 || box.z <= 0)
            return box;
        const gather = Math.min(1, s);
        const sink = Math.max(0, s - 1);
        const mid = box.x + box.z / 2;
        const w = box.z + (Theme.barHeight * 1.3 - box.z) * gather;
        return Qt.vector4d(mid - w / 2, box.y + box.w * sink, w, box.w);
    }

    Item {
        id: strip
        x: (scene.width - width) / 2
        y: 10
        width: 190
        height: Theme.barHeight + 2 * Theme.barInset

        Liquid {
            x: -strip.x
            y: 0
            width: scene.width
            height: strip.height
            backdrop: scene.backdrop
            box0: scene.shape(Qt.vector4d(strip.x, Theme.barInset, strip.width, Theme.barHeight), morph.value)
        }

        Pill {
            side: Pill.Side.Centre
            drawsSlab: false
            contentOpacity: Math.max(0, Math.min(1, 1 - 2 * morph.value))

            BarItem {
                id: anchor
                Glyph { text: Theme.glyph.playing }
                BarText { text: "Bohren & der Club of Gore" }
            }
        }
    }

    Popup {
        id: pop

        anchorItem: anchor
        visible: false
        morphs: true
        spacing: 8

        Row {
            spacing: 12
            Rectangle {
                width: 64
                height: 64
                radius: 8
                gradient: Gradient {
                    GradientStop { position: 0; color: "#3a4a6a" }
                    GradientStop { position: 1; color: "#111522" }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                PopupText { text: "Prowler"; font.weight: Font.DemiBold }
                PopupText { text: "Bohren & der Club of Gore"; color: Theme.label2; font.pixelSize: Theme.captionSize }
            }
        }
        Slider {
            width: 250
            value: 0.4
        }
        Row {
            spacing: 40
            x: 70
            Glyph { text: Theme.glyph.mediaPrev }
            Glyph { text: Theme.glyph.playing }
            Glyph { text: Theme.glyph.mediaNext }
        }
    }
}
