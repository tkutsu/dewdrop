import QtQuick
import Quickshell.Wayland

// How bright the screen is behind a box that is about to open, read once.
//
// The frost is a thin dark fill over the compositor's blur (Theme.popupBg), and
// one alpha cannot do both jobs: thin enough to be glass over a dark terminal
// is a light grey over a white page, with white text on it. The launcher asks
// this what it is opening over and thickens its frost to match
// (Theme.frostOver).
//
// One still of the screen, taken as the window comes up, while the box on it
// is still a line with nothing drawn round it, so what is read is what the box
// will sit on and not the box. Read at a sixteenth of the size, which is the
// blur's scale anyway and next to nothing to walk. The still is let go once it
// has been read: whoever put this here takes it away on `measured`, and puts
// a new one back to read again.
Item {
    id: root

    // The screen to read, and the part of it the box will cover, in the
    // window's pixels. The window is screen-sized, so the two are the same.
    required property var screen
    required property rect region
    // Left out of the region, for a reading taken with the box already up:
    // the still has the box in it by then, so what is read is the ring round
    // it, the nearest guess there is at what is under it. Nothing by default.
    property rect exclude

    // How bright the brightest part of the region is, 0 to 1: the luma a tenth
    // of it is at or over. The mean would be a half-white screen read as grey,
    // and the text over its white half is what has to hold.
    signal measured(real luma)

    readonly property int scale: 16

    // Drawn, but contributing nothing, as InkProbe is: the view only has to be
    // in the scene for the grab to have something to render.
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
            const r = root.region;
            const x0 = Math.max(0, Math.floor(r.x / root.scale)), x1 = Math.min(width, Math.ceil((r.x + r.width) / root.scale));
            const y0 = Math.max(0, Math.floor(r.y / root.scale)), y1 = Math.min(height, Math.ceil((r.y + r.height) / root.scale));
            if (x1 <= x0 || y1 <= y0)
                return;
            const data = ctx.getImageData(x0, y0, x1 - x0, y1 - y0).data;
            grab = null;

            const e = root.exclude;
            const lumas = [];
            for (let i = 0; i < data.length; i += 4) {
                const x = (x0 + (i / 4) % (x1 - x0) + 0.5) * root.scale;
                const y = (y0 + Math.floor(i / 4 / (x1 - x0)) + 0.5) * root.scale;
                if (x >= e.x && x < e.x + e.width && y >= e.y && y < e.y + e.height)
                    continue;
                lumas.push((0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255);
            }
            if (lumas.length === 0)
                return;
            lumas.sort((a, b) => a - b);
            const luma = lumas[Math.floor(lumas.length * 0.9)];

            // Out of the paint first, as InkProbe does: the answer is what
            // retires this, and a canvas should not go from inside its paint.
            Qt.callLater(() => root.measured(luma));
        }
    }
}
