import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.src.core

// The frost for a box, thickened to what is behind it: one reading and one
// colour for every box the shell frosts (the launcher, settings, popovers, the
// authentication dialog), so that over the same screen they are the same glass.
//
// The frost is a thin dark fill over the compositor's blur (Theme.popupBg), and
// one alpha cannot do both jobs: thin enough to be glass over a dark terminal
// is a light grey over a white page, with white text on it. A box asks this
// what it is over and takes `frost`, Theme.frostOver of the answer.
//
// Read from one still of the screen, taken as the box comes up, by the ring
// round the box and its shadow: 64px of whatever is next to it, the nearest
// guess there is at what is under it. Not what is under it, because a popup
// is mapped the moment it is shown and its own first frame was in the still
// every time (measured 2026-09-30). The launcher's still came back clean, but
// one box reading what it covers and another its surroundings came out as two
// alphas over the same screen. Read at a sixteenth of the size, which is the
// blur's scale anyway and next to nothing to walk, and let go once read.
//
// Read again once a workspace switched under an open box has slid into place.
Item {
    id: root

    // The screen to read, and the part of it the box covers, in the screen's
    // pixels.
    required property var screen
    required property rect area
    // Whether the box is up. Each time this goes true is a fresh reading.
    property bool active: false

    // How bright the brightest part of the ring is, 0 to 1: the luma a tenth
    // of it is at or over. The mean would read a half-white screen as grey,
    // and the text over its white half is what has to hold. -1 until the first
    // reading, and kept through the next one so the frost never drops back.
    property real luma: -1

    // The box's fill. Eased, since the reading lands a few frames after the
    // box, and only ever up from popupBg, so the blur stays.
    property color frost: Theme.frostOver(root.luma)

    Behavior on frost {
        ColorAnimation {
            duration: Theme.revealMs
        }
    }

    readonly property int scale: 16
    readonly property int ring: 64

    property bool reading: false

    // The answer, or -1 for a reading that found nothing to read, which
    // keeps whatever there was. Out of the paint first: it
    // is what retires the canvas, and a canvas should not go from inside its
    // own paint.
    function done(luma: real): void {
        Qt.callLater(() => {
            if (luma >= 0)
                root.luma = luma;
            root.reading = false;
        });
    }

    onActiveChanged: if (active)
        root.reading = true
    Component.onCompleted: if (active)
        root.reading = true

    // A still taken mid-slide would be half of each workspace. The slide is
    // Hyprland's `glide` spring, critically damped at 0.4 s
    // (hypr/configs/animation.lua).
    Timer {
        id: settle

        interval: 450
        onTriggered: root.reading = true
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            if (root.active)
                settle.restart();
        }
    }

    Loader {
        active: root.reading

        sourceComponent: Item {
            // Drawn, but contributing nothing, as Ink's meter is: the view only
            // has to be in the scene for the grab to have something to render.
            opacity: 0

            ScreencopyView {
                id: view

                width: root.screen?.width ?? 0
                height: root.screen?.height ?? 0
                captureSource: root.screen
                live: false

                onHasContentChanged: if (hasContent)
                    view.grabToImage(result => {
                        canvas.grab = result;
                        canvas.requestPaint();
                    }, Qt.size(canvas.width, canvas.height))
            }

            Canvas {
                id: canvas

                property var grab: null

                width: Math.max(1, Math.round(view.width / root.scale))
                height: Math.max(1, Math.round(view.height / root.scale))
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate

                onPaint: {
                    if (!grab)
                        return;
                    const ctx = getContext("2d");
                    ctx.drawImage(grab.url, 0, 0, width, height);
                    grab = null;

                    // Everything read, and what is left out of it: the box
                    // and its shadow, for the ring.
                    const a = root.area;
                    const out = Theme.shadowPad + root.ring;
                    const x0 = Math.max(0, Math.floor((a.x - out) / root.scale)), x1 = Math.min(width, Math.ceil((a.x + a.width + out) / root.scale));
                    const y0 = Math.max(0, Math.floor((a.y - out) / root.scale)), y1 = Math.min(height, Math.ceil((a.y + a.height + out) / root.scale));
                    if (x1 <= x0 || y1 <= y0)
                        return root.done(-1);
                    const data = ctx.getImageData(x0, y0, x1 - x0, y1 - y0).data;

                    const lumas = [];
                    for (let i = 0; i < data.length; i += 4) {
                        const x = (x0 + (i / 4) % (x1 - x0) + 0.5) * root.scale;
                        const y = (y0 + Math.floor(i / 4 / (x1 - x0)) + 0.5) * root.scale;
                        const pad = Theme.shadowPad;
                        if (x >= a.x - pad && x < a.x + a.width + pad && y >= a.y - pad && y < a.y + a.height + pad)
                            continue;
                        lumas.push((0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255);
                    }
                    if (lumas.length === 0)
                        return root.done(-1);
                    lumas.sort((p, q) => p - q);
                    root.done(lumas[Math.floor(lumas.length * 0.9)]);
                }
            }
        }
    }
}
