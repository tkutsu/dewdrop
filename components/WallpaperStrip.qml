pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services

// A small texture of the wallpaper under the bar, driven by the desktop fade.
ShaderEffectSource {
    id: root

    required property var screen
    property bool atTop: true
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? root.screen.devicePixelRatio ?? 1
    readonly property var renderer: Wallpaper.backdrops[root.screen.name] ?? null
    readonly property real progress: root.renderer?.progress ?? 0
    readonly property real glassWeight: root.renderer ? (root.renderer.front.glass ? 1 : 0) * (1 - root.progress) + (root.renderer.back.glass ? 1 : 0) * root.progress : 0
    readonly property var columns: root.glassWeight > 0 ? (first.columns.length ? first.columns : second.columns) : []

    hideSource: true
    live: true
    textureSize: Qt.size(Math.ceil(width * root.dpr), Math.ceil(height * root.dpr))

    function stripFor(presentation) {
        return presentation === first.presentation ? first : second;
    }

    // The desktop waits for both the image strip and its sampled colours,
    // when there is a strip to wait for.
    function readyFor(presentation) {
        const strip = root.stripFor(presentation);
        return !presentation.glass || (strip.imageStatus === Image.Ready && strip.sampleReady);
    }

    function checkReady() {
        if (root.renderer)
            Qt.callLater(root.renderer.startFade);
    }

    function mix(a, b) {
        const t = root.progress;
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    function average(from, to) {
        if (!root.renderer)
            return Theme.backdrop;
        return root.mix(root.stripFor(root.renderer.front).average(from, to), root.stripFor(root.renderer.back).average(from, to));
    }

    function averageRegion(area) {
        if (!root.renderer)
            return Theme.backdrop;
        return root.mix(root.stripFor(root.renderer.front).averageRegion(area), root.stripFor(root.renderer.back).averageRegion(area));
    }

    Component.onCompleted: Wallpaper.registerStrip(root.screen.name, root)
    Component.onDestruction: {
        if (Wallpaper.strips[root.screen.name] === root)
            Wallpaper.registerStrip(root.screen.name, null);
    }
    onRendererChanged: root.checkReady()

    sourceItem: Item {
        parent: root.parent
        x: root.x
        y: root.y
        width: root.width
        height: root.height
        clip: true

        Strip { id: first; presentation: root.renderer?.wallpaperLayers[0] ?? null }
        Strip { id: second; presentation: root.renderer?.wallpaperLayers[1] ?? null }
    }

    component Strip: Rectangle {
        id: strip

        property var presentation: null
        readonly property string path: strip.presentation?.path ?? ""
        readonly property real zoom: strip.presentation?.zoom ?? 1
        readonly property real offsetX: strip.presentation?.offsetX ?? 0
        readonly property real offsetY: strip.presentation?.offsetY ?? 0
        readonly property var columns: image.columns
        readonly property int imageStatus: image.status
        readonly property bool sampleReady: image.sampleReady

        anchors.fill: parent
        color: strip.path ? "transparent" : strip.presentation?.color ?? "transparent"
        opacity: strip.presentation?.opacity ?? 0
        z: root.renderer?.front === strip.presentation ? 0 : 1

        function average(from, to) {
            return strip.path ? image.average(from, to) : strip.presentation?.color ?? Theme.backdrop;
        }

        function averageRegion(area) {
            return strip.path ? image.averageRegion(area) : strip.presentation?.color ?? Theme.backdrop;
        }

        Image {
            id: image

            // The bar is the width of the screen, so only its height says where
            // it is: at the top, or (a bar anchored to the bottom) at the foot.
            readonly property real stripTop: root.atTop ? 0 : root.screen.height - root.height
            readonly property size natural: strip.presentation?.natural ?? Qt.size(0, 0)
            readonly property real cover: natural.width > 0 && natural.height > 0 ? Math.max(root.screen.width / natural.width, root.screen.height / natural.height) * strip.zoom : 1
            readonly property real cropLeft: (natural.width * cover - width) / 2
            // The zoom's spare height, which the wallpaper can be moved through.
            readonly property real travel: root.screen.height * (strip.zoom - 1)
            readonly property real cropTop: (natural.height * cover - root.screen.height - travel) / 2 + stripTop

            // Load the whole travel range once; only its position moves per frame.
            width: root.screen.width * strip.zoom
            height: strip.height + travel
            x: (root.screen.width - width) / 2 + strip.offsetX
            y: strip.offsetY - travel / 2
            asynchronous: true
            retainWhileLoading: true
            cache: false
            source: strip.path && natural.width > 0 ? "file://" + strip.path.split("/").map(encodeURIComponent).join("/") : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(Math.ceil(root.screen.width * strip.zoom * root.dpr), Math.ceil(root.screen.height * strip.zoom * root.dpr))
            sourceClipRect: Qt.rect(Math.round(cropLeft * root.dpr), Math.round(cropTop * root.dpr), Math.ceil(width * root.dpr), Math.ceil(height * root.dpr))

            // Cache a small colour grid once per wallpaper or screen geometry.
            // Badges average their icon's region from it as the layout moves;
            // the column averages keep Pill.surface cheap to read.
            readonly property int columnWidth: 8
            readonly property int rowHeight: 4
            property var grid: ({ nx: 0, cells: [] })
            property bool sampleReady: false
            onStatusChanged: root.checkReady()
            onSampleReadyChanged: root.checkReady()
            onSourceChanged: grid = { nx: 0, cells: [] }

            // Each column's colour over the rows the bar shows, which move
            // with the wallpaper's height but not with its pan.
            readonly property var columns: {
                const nx = grid.nx, ny = nx ? grid.cells.length / nx : 0;
                if (!ny)
                    return [];
                const dy = image.height / ny;
                const first = Math.max(0, Math.floor(-image.y / dy)), last = Math.min(ny, Math.ceil((strip.height - image.y) / dy));
                const n = Math.max(1, last - first), averages = [];
                for (let x = 0; x < nx; x++) {
                    let r = 0, g = 0, b = 0;
                    for (let row = first; row < last; row++) {
                        const c = grid.cells[row * nx + x];
                        r += c.r;
                        g += c.g;
                        b += c.b;
                    }
                    averages.push(Qt.rgba(r / n, g / n, b / n, 1));
                }
                return averages;
            }

            function average(from, to) {
                if (!columns.length)
                    return strip.presentation?.average ?? Theme.backdrop;
                const step = width / Math.max(1, columns.length);
                const first = Math.max(0, Math.floor((from - image.x) / step));
                const last = Math.min(columns.length, Math.ceil((to - image.x) / step));
                let r = 0, g = 0, b = 0;
                for (let i = first; i < last; i++) {
                    r += columns[i].r;
                    g += columns[i].g;
                    b += columns[i].b;
                }
                const n = Math.max(1, last - first);
                return Qt.rgba(r / n, g / n, b / n, 1);
            }

            // Weight partial cells so a moving icon changes colour smoothly.
            function averageRegion(area) {
                const nx = grid.nx, ny = nx ? grid.cells.length / nx : 0;
                if (!ny)
                    return strip.presentation?.average ?? Theme.backdrop;
                const dx = width / nx, dy = height / ny;
                const left = Math.max(0, area.x - image.x), right = Math.min(width, area.x + area.width - image.x);
                const top = Math.max(0, area.y - image.y), bottom = Math.min(height, area.y + area.height - image.y);
                let r = 0, g = 0, b = 0, weight = 0;
                for (let y = Math.max(0, Math.floor(top / dy)); y < Math.min(ny, Math.ceil(bottom / dy)); y++) {
                    const h = Math.min(bottom, (y + 1) * dy) - Math.max(top, y * dy);
                    for (let x = Math.max(0, Math.floor(left / dx)); x < Math.min(nx, Math.ceil(right / dx)); x++) {
                        const w = h * (Math.min(right, (x + 1) * dx) - Math.max(left, x * dx));
                        const c = grid.cells[y * nx + x];
                        r += c.r * w;
                        g += c.g * w;
                        b += c.b * w;
                        weight += w;
                    }
                }
                return weight > 0 ? Qt.rgba(r / weight, g / weight, b / weight, 1) : Theme.backdrop;
            }

            readonly property string sampleRequest: {
                if (!source.toString() || natural.width <= 0 || natural.height <= 0 || width <= 0 || height <= 0)
                    return "";
                const inImage = v => Math.round(v / cover);
                const left = inImage(cropLeft);
                const top = inImage(cropTop);
                return JSON.stringify([strip.path, `${Math.max(1, inImage(width))}x${Math.max(1, inImage(height))}+${left}+${top}`, Math.ceil(width / columnWidth), Math.ceil(height / rowHeight)]);
            }

            onSampleRequestChanged: sampleReady = !sampleRequest

            QueuedProcess {
                id: stripSample

                interval: 0
                want: image.sampleRequest
                command: {
                    if (!arg)
                        return [];
                    const [path, crop, nx, ny] = JSON.parse(arg);
                    return ["timeout", "10", "magick", path + "[0]", "-crop", crop, "+repage", "-scale", `${nx}x${ny}!`, "-depth", "8", "txt:-"];
                }

                // An answer belongs to its request, even if the wallpaper changed
                // while magick was still reading the previous one.
                onResult: (request, text) => {
                    if (request !== want)
                        return;
                    image.sampleReady = true;
                    const [, , nx, ny] = JSON.parse(request);
                    const hexes = text.split("\n").filter(line => /^\d+,\d+:/.test(line)).map(line => line.match(/#[0-9A-Fa-f]{6}/)?.[0]);
                    if (hexes.length !== nx * ny || !hexes.every(Boolean))
                        return;
                    image.grid = { nx, cells: hexes.map(hex => Qt.color(hex)) };
                }
            }
        }
    }
}
