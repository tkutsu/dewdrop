import QtQuick

// Measures how tall an item's artwork actually is inside its box, by taking a
// picture of it and reading back the alpha.
//
// Height, not width: the bar is a row, so every icon is read against the ones
// either side of it on a shared line, and the one thing that makes one look
// bigger than its neighbour is how far up and down it reaches. Widths are
// allowed to differ — a wifi fan is wide and a padlock is narrow, and neither
// reads as the wrong size.
//
// Same idea as BarText's tightWidth, one layer down: lay the thing out on its
// ink rather than on the box its author chose to put the ink in.
//
// It measures a picture of the item rather than loading the icon a second time
// and measuring that. Two reasons, and the first is the one that matters: an
// icon name does not have one answer. A theme keeps different artwork at 16, 22
// and 24, drawn to different margins, and a second load picks whichever size it
// feels like rather than the one on the bar — so the measurement would be of an
// icon nobody is looking at. Grabbing what was drawn asks the question about
// the right picture. (The second reason: a Canvas asked for a url some other
// Image in the scene already pulled through the same provider gets handed
// something that is not the icon at all.)
//
// One measurement is all it does. It reports and stops touching anything, so
// whoever put it here can take it away again — which is the intent: the answer
// outlives the canvas that found it, and a bar at rest is carrying none of
// this.
Canvas {
    id: root

    // The item to measure, and whether it has anything to show yet.
    property Item target: null
    property bool ready: false

    // The height of the artwork's ink as a fraction of its box, once. Nothing
    // is reported for a grab that failed or a box with nothing in it, so a
    // caller that hears nothing keeps whatever it was already doing.
    signal measured(real extent)
    // The same scan, reported as rows and columns rather than a fraction:
    // first and last inked row, first and last inked column, in the pixels
    // of the grab. For the things that need to know where the ink is rather
    // than only how tall it stands.
    //
    // Then the first and last column that shows at bar size, also in the
    // grab's pixels: the grab averaged back down to the pixels the item is
    // really drawn in, and a column counted once some pixel in it is a sixth
    // covered. The floor above is right for how far an icon reaches, but at
    // four times the size it also counts the sliver a thin tip leaves, and
    // blueman's rune measured a column wider than anything that showed.
    signal bounds(int top, int bottom, int left, int right, int edgeLeft, int edgeRight)

    property var _grab: null

    // Alpha below this is the antialiased edge of a stroke rather than the
    // stroke, and counting it puts the bounds a pixel outside the artwork on
    // every icon that has a soft edge — which is all of them.
    readonly property int _floor: 24

    // Four times the size anything here is drawn at, so a quarter-pixel of ink
    // still moves the answer. The grab scales the item up to fill it.
    width: 64
    height: 64

    // Drawn, but contributing nothing: the scene still renders it, which is
    // what makes the paint happen, and nothing of it reaches the screen.
    opacity: 0

    // Image over FBO, and on the GUI thread: getImageData is only reliable off
    // an image target, and at 64 squared there is nothing to gain by threading.
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onReadyChanged: _take()
    onAvailableChanged: if (available) _take()
    Component.onCompleted: _take()

    function _take() {
        if (!available || !ready || !target || _grab)
            return;
        target.grabToImage(function (result) {
            root._grab = result;
            root.requestPaint();
        }, Qt.size(width, height));
    }

    onPaint: {
        if (!_grab)
            return;

        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(_grab.url, 0, 0, width, height);
        const data = ctx.getImageData(0, 0, width, height).data;

        // The box the ink stands in: first and last row, first and last
        // column. Every pixel is looked at, which for a grab this size is
        // still nothing.
        let top = -1, bottom = -1, left = width, right = -1;
        for (let y = 0; y < height; y++) {
            let inked = false;
            for (let x = 0; x < width; x++) {
                if (data[(y * width + x) * 4 + 3] <= root._floor)
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

        // The grab is a copy of the artwork at four times its size, and holding
        // one per icon for the life of the bar is four figures of kilobytes
        // spent on a question that has already been answered.
        _grab = null;
        if (bottom < 0)
            return;

        // The columns that show once drawn at size (see `bounds`).
        const cols = Math.max(1, Math.round(target.width));
        const rows = Math.max(1, Math.round(target.height));
        const sx = width / cols, sy = height / rows;
        let edgeLeft = -1, edgeRight = -1;
        // Only the grab pixels wholly inside each drawn pixel: the ones it
        // shares with a neighbour carry that neighbour's ink into it.
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

        // Out of the paint before the answer lands: it is what retires this
        // probe, and a canvas should not be destroyed from inside its own
        // paint handler.
        const extent = (bottom - top + 1) / height;
        Qt.callLater(function () {
            root.measured(extent);
            root.bounds(top, bottom, left, right, edgeLeft, edgeRight);
        });
    }
}
