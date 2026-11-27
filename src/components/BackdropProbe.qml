import QtQuick
import Quickshell.Hyprland
import qs.src.core
import qs.src.services

// How bright the screen is behind a box of frost, for Theme.frostOver.
//
// The frost is a thin dark fill over the compositor's blur (Theme.popupBg), and
// one alpha cannot do both jobs: thin enough to be glass over a dark terminal
// is a light grey over a white page, with white text on it. A box asks this
// what it is over and thickens its frost to match.
//
// Read from one still of the screen, taken as the box comes up. A box whose
// first frame is not on screen yet by then is read exactly: what is under it.
// One that is (ringOnly) is read by the ring round it, below. Read at a
// sixteenth of the size, which is the blur's scale anyway and next to nothing
// to walk.
//
// Read again once a workspace switched under an open box has slid into place.
// The box is in that still, so that reading takes the ring round the box and
// its shadow instead: 64px of whatever is next to it, the nearest guess there
// is at what is under it.
Item {
    id: root

    // The screen to read, and the part of it the box covers, in the screen's
    // pixels.
    required property var screen
    required property rect area
    // Whether the box is up. Each time this goes true is a fresh reading.
    property bool active: false
    // Whether the box beats the still to the screen, so that every reading
    // has to take the ring. A popup does: it is mapped the moment it is
    // shown, and its first frame was in the still every time (measured
    // 2026-09-30). The launcher's surface waits on a round trip with the
    // compositor first, and its still came back clean.
    property bool ringOnly: false

    // How bright the area is on average, 0 to 1. Not its brightest tenth:
    // sized to that, the frost went to a dark slab over a bright wallpaper
    // while a popover over a darker corner stayed glass, and the blur spreads
    // a bright patch over the box anyway. -1 until the first reading, and
    // kept through the next one so the frost never drops back.
    property real luma: -1

    readonly property int scale: 16
    readonly property int ring: 64

    // The still asked for and not yet answered, 0 when none is, and whether
    // its reading takes the ring.
    property int ticket: 0
    property bool around: false

    function ask(around: bool): void {
        root.around = around;
        root.ticket = Stills.take(root.screen, root.scale);
    }

    // Once all of a new probe's properties are in: one made with `active`
    // already set hears it change before it has its screen, then completes.
    function start(): void {
        if (root.active)
            root.ask(root.ringOnly);
    }
    onActiveChanged: Qt.callLater(root.start)
    Component.onCompleted: Qt.callLater(root.start)

    // A still taken mid-slide would be half of each workspace. The slide is
    // Hyprland's `glide` spring, critically damped at 0.4 s
    // (hypr/configs/animation.lua).
    Timer {
        id: settle

        interval: 450
        onTriggered: root.ask(true)
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            if (root.active)
                settle.restart();
        }
    }

    // The still is taken in Stills, never here: a grab of an item in the
    // popup's own window crashed the bar when the popup went mid-grab.
    Connections {
        target: Stills

        function onTaken(ticket: int, still: var) {
            if (ticket !== root.ticket)
                return;
            root.ticket = 0;
            const luma = still ? root.read(still) : -1;
            if (luma >= 0)
                root.luma = luma;
        }
    }

    // How bright the still is where the box is, or around it for the ring:
    // -1 for a reading that found nothing to read, which keeps whatever
    // there was.
    function read(still: var): real {
        const {width, height, data} = still;
        // Everything read, and what is left out of it: nothing for a first
        // reading, the box and its shadow for the ring.
        const a = root.area;
        const pad = Theme.shadowPad;
        const out = root.around ? pad + root.ring : 0;
        const x0 = Math.max(0, Math.floor((a.x - out) / root.scale)), x1 = Math.min(width, Math.ceil((a.x + a.width + out) / root.scale));
        const y0 = Math.max(0, Math.floor((a.y - out) / root.scale)), y1 = Math.min(height, Math.ceil((a.y + a.height + out) / root.scale));
        if (x1 <= x0 || y1 <= y0)
            return -1;

        let sum = 0, count = 0;
        for (let py = y0; py < y1; py++) {
            for (let px = x0; px < x1; px++) {
                const x = (px + 0.5) * root.scale, y = (py + 0.5) * root.scale;
                if (root.around && x >= a.x - pad && x < a.x + a.width + pad && y >= a.y - pad && y < a.y + a.height + pad)
                    continue;
                const i = (py * width + px) * 4;
                sum += (0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255;
                count++;
            }
        }
        return count === 0 ? -1 : sum / count;
    }
}
