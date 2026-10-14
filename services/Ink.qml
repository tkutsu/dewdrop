pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Where the bar's artwork really is inside its box, measured by drawing it
// and reading the alpha back. Two kinds of question, one per caller:
//
// - An icon (FittedIcon): how tall its ink stands as a fraction of its box,
//   and which columns it spans. A theme's panel icons keep margin, an app's
//   icon fills its box, and the bar sizes each so the ink lines up.
// - A glyph (BarText): its ink's first and last row and column, relative to
//   a Text item padded by glyphPad. The font's outline box is a pixel or two
//   from where the rasteriser puts the strokes, and only the pixels say.
//
// Every measurement happens here, on copies drawn in a window of this
// service's own, one at a time. The callers only ask and read. A grab parents
// its result to the item it grabs until it lands, so grabbing an item that
// can unload (a tray delegate, a glyph's next drawing) frees the result under
// the render thread if the item goes mid-grab — that crashed the bar on
// 2026-10-13 as a headset connected. Nothing here is ever unloaded.
//
// Measured once per icon or glyph, and kept across restarts in the cache dir,
// so a restarted bar lays everything out on its first frame. Kept only for
// sources that mean the same thing next run: a theme icon's name or a file
// outside this config. Tray pixmaps get a fresh image://qspixmap number per
// process, and the config's own drawings get edited, so those are measured
// again each run.
Singleton {
    id: root

    // Padding round a measured glyph, so ink that hangs outside the advance
    // box (a negative side bearing, a descender) is still in the grab.
    // BarText pads its Text by the same amount.
    readonly property int glyphPad: 4

    // Bumped on every answer: the caches below are plain objects, which do
    // not notify, so a binding that reads through the functions re-runs.
    property int revision: 0

    // Icon source → {extent, left, right}; glyph key → {top, bottom, left, right}.
    property var icons: ({})
    property var glyphs: ({})

    // 0 until measured, which callers treat as "draw at the asked size".
    function extentOf(source: string): real {
        root.revision;
        return root.icons[source]?.extent ?? 0;
    }

    // The first and last inked column as fractions of the box, or null until
    // measured, which callers read as "the whole box".
    function spanOf(source: string): var {
        root.revision;
        const icon = root.icons[source];
        return icon ? {left: icon.left, right: icon.right} : null;
    }

    function keyOf(family: string, weight: int, size: int, text: string): string {
        return family + "|" + weight + "|" + size + "|" + text;
    }

    function boundsOf(key: string): var {
        root.revision;
        return root.glyphs[key] ?? null;
    }

    // Ask for a measurement. Repeats, and anything already known, cost nothing.
    function measureIcon(source: string, size: int): void {
        if (source && size > 0 && !(source in root.icons))
            root._ask("icon:" + source, {source, size});
    }

    function measureGlyph(family: string, weight: int, size: int, text: string): void {
        const key = root.keyOf(family, weight, size, text);
        if (text && !(key in root.glyphs))
            root._ask("glyph:" + key, {key, family, weight, size, text});
    }

    function remember(source: string, extent: real, left: real, right: real): void {
        root.icons[source] = {extent, left, right};
        root._answered();
    }

    function rememberGlyph(key: string, top: int, bottom: int, left: int, right: int): void {
        root.glyphs[key] = {top, bottom, left, right};
        root._answered();
    }

    // Pending jobs by id, in the order asked, and the one being measured.
    property var _queue: []
    property var _asked: ({})
    property var _job: null

    function _ask(id: string, job: var): void {
        if (id in root._asked)
            return;
        root._asked[id] = true;
        root._queue.push(job);
        if (!root._job)
            Qt.callLater(root._next);
    }

    function _answered(): void {
        root.revision++;
        save.restart();
    }

    function _next(): void {
        if (root._job || root._queue.length === 0)
            return;
        root._job = root._queue.shift();
        stall.restart();
        if (root._job.source !== undefined)
            icon.source = root._job.source;
        else
            Qt.callLater(root._grab);
    }

    // The job is over, answered or not. One that could not be measured (the
    // icon failed to load, the grab was refused or never came back) is left
    // unanswered, so callers keep drawing at the asked size, and left in
    // _asked, so it is not tried again this run.
    function _done(): void {
        stall.stop();
        root._job = null;
        icon.source = "";
        Qt.callLater(root._next);
    }

    function _grab(): void {
        const job = root._job;
        if (!job)
            return;
        const target = job.source !== undefined ? icon : glyph;
        // Four times an icon's size, so a quarter-pixel of ink still moves the
        // answer; a glyph at its own size, so its rows are the real ones.
        canvas.width = job.source !== undefined ? 64 : Math.ceil(glyph.width);
        canvas.height = job.source !== undefined ? 64 : Math.ceil(glyph.height);
        const asked = target.grabToImage(result => {
            // A grab that outlived its job's stall timeout answers nothing.
            if (root._job !== job)
                return;
            canvas.grab = result;
            canvas.requestPaint();
        }, Qt.size(canvas.width, canvas.height));
        if (!asked)
            root._done();
    }

    // Read off a scanned grab: the box the ink stands in, and for an icon the
    // columns that still show once it is drawn back down at its own size.
    function _read(data: var): void {
        const job = root._job;
        const width = canvas.width, height = canvas.height;

        // Alpha below this is the antialiased edge of a stroke rather than the
        // stroke, and counting it puts the bounds a pixel outside the artwork.
        const floor = 24;
        let top = -1, bottom = -1, left = width, right = -1;
        for (let y = 0; y < height; y++) {
            let inked = false;
            for (let x = 0; x < width; x++) {
                if (data[(y * width + x) * 4 + 3] <= floor)
                    continue;
                inked = true;
                if (x < left)
                    left = x;
                if (x > right)
                    right = x;
            }
            if (!inked)
                continue;
            if (top < 0)
                top = y;
            bottom = y;
        }
        if (bottom < 0)
            return;

        if (job.source === undefined) {
            root.rememberGlyph(job.key, top, bottom, left, right);
            return;
        }

        // At four times the size, the floor also counts the sliver a thin tip
        // leaves, and blueman's rune measured a column wider than anything
        // that showed. So: the grab averaged back down to the pixels the icon
        // is really drawn in, a column counted once some pixel in it is a
        // sixth covered, and only the grab pixels wholly inside each drawn
        // pixel, since the shared ones carry a neighbour's ink.
        const cols = job.size, rows = job.size;
        const sx = width / cols, sy = height / rows;
        let edgeLeft = -1, edgeRight = -1;
        for (let cx = 0; cx < cols; cx++) {
            const x0 = Math.ceil(cx * sx), x1 = Math.max(x0 + 1, Math.floor((cx + 1) * sx));
            for (let cy = 0; cy < rows; cy++) {
                const y0 = Math.ceil(cy * sy), y1 = Math.max(y0 + 1, Math.floor((cy + 1) * sy));
                let sum = 0;
                for (let y = y0; y < y1; y++)
                    for (let x = x0; x < x1; x++)
                        sum += data[(y * width + x) * 4 + 3];
                if (sum / ((x1 - x0) * (y1 - y0)) < 43)
                    continue;
                if (edgeLeft < 0)
                    edgeLeft = x0;
                edgeRight = x1 - 1;
                break;
            }
        }
        if (edgeLeft < 0) {
            edgeLeft = left;
            edgeRight = right;
        }
        root.remember(job.source, (bottom - top + 1) / height, edgeLeft / width, (edgeRight + 1) / width);
    }

    // A source is worth keeping if it names the same picture next run.
    function _lasting(source: string): bool {
        return source.startsWith("image://icon/")
            || (source.startsWith("file:") && !source.startsWith("file://" + Quickshell.shellDir));
    }

    // Bump when the measuring changes, so answers from the old way are dropped.
    readonly property int _version: 1

    // A grab only fails to come back if its window stopped rendering, and one
    // lost job must not hold up every one behind it.
    Timer {
        id: stall
        interval: 2000
        onTriggered: root._done()
    }

    // A first run measures a whole tray at once: one write for the lot.
    Timer {
        id: save
        interval: 2000
        onTriggered: {
            const icons = {};
            for (const source in root.icons)
                if (root._lasting(source))
                    icons[source] = root.icons[source];
            stored.version = root._version;
            stored.icons = icons;
            stored.glyphs = root.glyphs;
            file.writeAdapter();
        }
    }

    FileView {
        id: file

        path: Paths.cache("ink.json")
        // Read before the first bar asks, so a known icon is never measured.
        blockLoading: true
        printErrors: false

        onLoaded: {
            if (stored.version !== root._version)
                return;
            root.icons = Object.assign({}, stored.icons, root.icons);
            root.glyphs = Object.assign({}, stored.glyphs, root.glyphs);
            root.revision++;
        }

        JsonAdapter {
            id: stored

            property int version: 0
            property var icons: ({})
            property var glyphs: ({})
        }
    }

    // The meter: one pixel at the top-left corner, under the wallpaper, taking
    // no clicks. It only has to be in a window that renders for a grab to
    // happen; what it draws is never on screen.
    PanelWindow {
        implicitWidth: 1
        implicitHeight: 1
        anchors.top: true
        anchors.left: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:ink"

        // Drawn, but contributing nothing: a grab ignores the opacity above
        // what it grabs.
        Item {
            opacity: 0

            // An icon at the size it was asked for, so the theme hands back
            // the same artwork it hands the bar at that size.
            IconImage {
                id: icon

                implicitSize: root._job?.size ?? 0
                onStatusChanged: {
                    if (root._job?.source === undefined || String(source) === "")
                        return;
                    if (status === Image.Ready)
                        Qt.callLater(root._grab);
                    else if (status === Image.Error)
                        root._done();
                }
            }

            Text {
                id: glyph

                padding: root.glyphPad
                text: root._job?.text ?? ""
                color: "white"
                font.family: root._job?.family ?? ""
                font.weight: root._job?.weight ?? Font.Normal
                font.pixelSize: root._job?.size || 1
                font.features: Theme.figures
            }

            Canvas {
                id: canvas

                property var grab: null

                // Image over FBO, and on the GUI thread: getImageData is only
                // reliable off an image target.
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate

                onPaint: {
                    if (!grab)
                        return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.drawImage(grab.url, 0, 0, width, height);
                    const data = ctx.getImageData(0, 0, width, height).data;
                    grab = null;
                    root._read(data);
                    root._done();
                }
            }
        }
    }
}
