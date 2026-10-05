pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services

// Keep the old wallpaper opaque until its replacement has loaded and faded in,
// and with parallax, pan its crop as the workspace changes.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell:backdrop"
    WlrLayershell.layer: WlrLayer.Background

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    color: "black"
    visible: root.ready

    property bool ready: false
    property var front: first
    property var back: second
    readonly property var wallpaperLayers: [first, second]
    readonly property real progress: root.back.opacity
    readonly property color average: {
        const a = root.front.average, b = root.back.average, t = root.progress;
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    readonly property string wantedPath: Wallpaper.onScreen ? "" : Wallpaper.current
    readonly property string wantedColor: Wallpaper.onScreen

    property var monitor: Hyprland.monitorFor(root.screen)
    readonly property var activeWorkspace: root.monitor?.activeWorkspace ?? null
    // Parallax zooms in to leave room to pan. Each layer keeps the zoom it was
    // adopted with, so switching parallax crossfades like a new wallpaper.
    readonly property real wantedZoom: Wallpaper.parallax ? Settings.wallpaperParallaxZoom : 1

    // Where the crop sits along this monitor's numbered workspaces, from 0 at
    // the first to 1 at the last, and the spring that carries it there.
    readonly property QtObject pan: QtObject {
        id: pan

        property real fraction: 0.5
        readonly property bool running: pan.motion.running

        property var workspace: null
        property real target: 0.5
        property real start: 0.5
        property real progress: 1
        property real velocity: 0

        // Hyprland's glide in hypr/configs/animation.lua: mass 1, stiffness
        // 246.7, damping 31.42. That damping is 2√stiffness, so the spring is
        // critically damped and settles at the one rate √stiffness.
        readonly property real rate: Math.sqrt(246.7)

        readonly property FrameAnimation motion: FrameAnimation {
            onTriggered: pan.advance(frameTime)
        }

        // Retarget from the current crop and carry velocity through rapid
        // switches. Jump instead where there is nothing to see move: before
        // the first wallpaper, under a flat colour, or behind a crossfade.
        function moveTo(target, jump) {
            if (jump || !root.ready || !root.front.path) {
                pan.motion.stop();
                pan.target = target;
                pan.fraction = target;
                return;
            }
            if (target === pan.target)
                return;
            const distance = target - pan.fraction;
            pan.velocity = pan.running && Math.abs(distance) > 0.000001
                ? pan.velocity * (pan.target - pan.start) / distance : 0;
            pan.start = pan.fraction;
            pan.target = target;
            pan.progress = 0;
            pan.motion.restart();
        }

        // Advance the spring analytically, independent of refresh rate.
        function advance(dt) {
            const t = Math.max(0, dt), w = pan.rate;
            const d = pan.progress - 1, v = pan.velocity;
            const decay = Math.exp(-w * t);
            pan.progress = 1 + (d + (v + w * d) * t) * decay;
            pan.velocity = (v - w * (v + w * d) * t) * decay;
            if (Math.abs(1 - pan.progress) <= 0.001 && Math.abs(pan.velocity) <= 0.001) {
                pan.progress = 1;
                pan.velocity = 0;
                pan.motion.stop();
            }
            pan.fraction = Math.max(0, Math.min(1, pan.start + (pan.target - pan.start) * pan.progress));
        }

        // Renumbering the same workspace must not move the current crop.
        function follow(jump) {
            const active = root.activeWorkspace;
            if (!Wallpaper.parallax || !active || active.id <= 0 || !/^\d+$/.test(active.name))
                return;
            if (!jump && active === pan.workspace)
                return;
            const occupied = new Set(Hyprland.toplevels.values.map(t => t.workspace?.id));
            // At startup, wait for the window model before counting the empty slot.
            if (!pan.workspace && occupied.size === 0 && Hyprland.workspaces.values.some(w => w.lastIpcObject?.windows > 0))
                return;
            const numbered = Hyprland.workspaces.values.filter(w => w === active || w.monitor === root.monitor
                && w.id > 0 && /^\d+$/.test(w.name) && (w.lastIpcObject?.ispersistent || occupied.has(w.id))).sort((a, b) => a.id - b.id);
            const index = numbered.indexOf(active);
            if (index < 0)
                return;
            pan.workspace = active;
            // The keyboard ring always has an empty slot, even before it is created.
            const slots = numbered.length + (numbered.some(w => !occupied.has(w.id)) ? 0 : 1);
            pan.moveTo(slots > 1 ? index / (slots - 1) : 0.5, jump);
        }
    }

    onActiveWorkspaceChanged: Qt.callLater(root.pan.follow)

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { Qt.callLater(root.pan.follow); }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { Qt.callLater(root.pan.follow); }
    }

    // Coalesce the service's image/colour setters, which change two properties.
    onWantedPathChanged: Qt.callLater(root.adopt)
    onWantedColorChanged: Qt.callLater(root.adopt)
    // Put the crop where the new zoom wants it before the crossfade shows it.
    onWantedZoomChanged: {
        root.pan.follow(true);
        Qt.callLater(root.adopt);
    }
    Component.onCompleted: {
        Wallpaper.registerBackdrop(root.screen.name, root);
        Qt.callLater(root.pan.follow);
        Qt.callLater(root.adopt);
    }
    Component.onDestruction: {
        if (Wallpaper.backdrops[root.screen.name] === root)
            Wallpaper.registerBackdrop(root.screen.name, null);
    }

    Connections {
        target: Wallpaper
        function onMeasuredPathChanged() { Qt.callLater(root.startFade); }
        function onSampledPathChanged() { Qt.callLater(root.startFade); }
    }

    // While a fade runs, keep its layers intact and apply the latest choice next.
    function adopt() {
        if (fade.running || (!root.wantedPath && !root.wantedColor))
            return;
        // A flat colour has nothing to zoom, so only an image fades to a new zoom.
        if (root.ready && root.front.path === root.wantedPath && (!root.wantedPath || root.front.zoom === root.wantedZoom)) {
            root.front.swatch = root.wantedColor;
            root.front.zoom = root.wantedZoom;
            root.back.path = "";
            root.back.swatch = "";
            return;
        }
        root.back.opacity = 0;
        root.back.swatch = root.wantedColor;
        root.back.zoom = root.wantedZoom;
        root.back.path = root.wantedPath;
        root.startFade();
    }

    // A stale load completion must not put a superseded wallpaper on screen.
    function startFade() {
        if (fade.running || root.back.path !== root.wantedPath || root.back.swatch !== root.wantedColor || root.back.zoom !== root.wantedZoom)
            return;
        if (!root.back.path && !root.back.swatch)
            return;
        if (root.back.path && root.back.status !== Image.Ready)
            return;
        if (root.back.path) {
            if (Wallpaper.sampledPath !== root.back.path || Wallpaper.measuredPath !== root.back.path)
                return;
            root.back.natural = Wallpaper.currentSize;
            root.back.sampled = Wallpaper.sampled || String(root.front.average);
        }
        const strip = Wallpaper.strips[root.screen.name];
        if (root.ready && strip && !strip.readyFor(root.back))
            return;
        if (root.ready)
            fade.start();
        else
            root.finishFade();
    }

    // Release the outgoing image after the incoming layer is fully opaque.
    function finishFade() {
        const previous = root.front;
        root.front = root.back;
        root.back = previous;
        root.front.opacity = 1;
        root.back.opacity = 0;
        root.back.path = "";
        root.back.swatch = "";
        root.back.sampled = "";
        root.back.natural = Qt.size(0, 0);
        root.ready = true;
        Qt.callLater(root.adopt);
    }

    component WallpaperLayer: Rectangle {
        id: layer

        property string path: ""
        property string swatch: ""
        property string sampled: ""
        property size natural: Qt.size(0, 0)
        property real zoom: 1
        // Parallax travel, none at zoom 1, which leaves no room to move.
        readonly property real offsetX: (0.5 - root.pan.fraction) * root.width * (layer.zoom - 1)
        readonly property real offsetY: (0.5 - Wallpaper.parallaxY) * root.height * (layer.zoom - 1)
        // Whether the bar can cut its strip from this layer: an image whose
        // size is known.
        readonly property bool glass: layer.path !== "" && layer.natural.width > 0
        readonly property color average: layer.path ? Qt.color(layer.sampled || "black") : layer.color
        property alias status: image.status

        anchors.fill: parent
        // An image needs no backing rectangle: fading both would dim the blend.
        color: layer.path ? "transparent" : layer.swatch || "black"
        opacity: 0

        Behavior on color {
            enabled: root.ready && root.front === layer && !fade.running
            ColorAnimation { duration: Theme.fadeMs }
        }

        Image {
            id: image

            width: root.width * layer.zoom
            height: root.height * layer.zoom
            x: (root.width - width) / 2 + layer.offsetX
            y: (root.height - height) / 2 + layer.offsetY
            source: layer.path ? "file://" + layer.path.split("/").map(encodeURIComponent).join("/") : ""
            // Decode at the window's pixel size, including fractional scaling.
            sourceSize: Qt.size(Math.ceil(width * root.devicePixelRatio), Math.ceil(height * root.devicePixelRatio))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            cache: false
            onStatusChanged: {
                if (status === Image.Ready)
                    Qt.callLater(root.startFade);
                else if (status === Image.Error) {
                    console.warn("Could not load wallpaper:", layer.path);
                    // Black rather than nothing when it is the first.
                    root.ready = true;
                }
            }
        }
    }

    WallpaperLayer {
        id: first
        z: root.front === first ? 0 : 1
    }

    WallpaperLayer {
        id: second
        z: root.front === second ? 0 : 1
    }

    NumberAnimation {
        id: fade
        target: root.back
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.fadeMs
        onFinished: root.finishFade()
    }
}
