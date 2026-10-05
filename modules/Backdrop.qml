pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services

// Keep the old wallpaper opaque until its replacement has loaded and faded in.
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
    property var panWorkspace: null
    property real panPosition: 0.5
    property real panFraction: 0.5
    property real panStart: 0.5
    property real panProgress: 1
    property real panVelocity: 0
    readonly property bool panAnimating: panMotion.running
    readonly property real zoom: Wallpaper.parallax ? Settings.wallpaperParallaxZoom : 1
    readonly property real offsetX: (0.5 - root.panFraction) * root.width * (root.zoom - 1)

    // Hyprland's glide in hypr/configs/animation.lua: mass 1, stiffness
    // 246.7, damping 31.42. Match its spring and normalized stop thresholds.
    readonly property real panSlowRate: -15.71 + Math.sqrt(15.71 * 15.71 - 246.7)
    readonly property real panFastRate: -15.71 - Math.sqrt(15.71 * 15.71 - 246.7)

    FrameAnimation {
        id: panMotion
        onTriggered: root.advancePan(frameTime)
    }

    // Retarget from the current crop and carry velocity through rapid switches.
    function animatePan(target) {
        if (!root.ready || !Wallpaper.parallax) {
            panMotion.stop();
            root.panPosition = target;
            root.panFraction = target;
            return;
        }
        if (target === root.panPosition)
            return;
        const distance = target - root.panFraction;
        root.panVelocity = panMotion.running && Math.abs(distance) > 0.000001
            ? root.panVelocity * (root.panPosition - root.panStart) / distance : 0;
        root.panStart = root.panFraction;
        root.panPosition = target;
        root.panProgress = 0;
        panMotion.restart();
    }

    // Advance the same overdamped spring analytically, independent of refresh rate.
    function advancePan(dt) {
        const slow = root.panSlowRate, fast = root.panFastRate;
        const displacement = root.panProgress - 1;
        const a = (root.panVelocity - fast * displacement) / (slow - fast);
        const b = displacement - a;
        const x = a * Math.exp(slow * Math.max(0, dt));
        const y = b * Math.exp(fast * Math.max(0, dt));
        root.panProgress = 1 + x + y;
        root.panVelocity = slow * x + fast * y;
        if (Math.abs(1 - root.panProgress) <= 0.001 && Math.abs(root.panVelocity) <= 0.001) {
            root.panProgress = 1;
            root.panVelocity = 0;
            panMotion.stop();
        }
        root.panFraction = Math.max(0, Math.min(1, root.panStart + (root.panPosition - root.panStart) * root.panProgress));
    }

    // Renumbering the same workspace must not move the current crop.
    function updatePan(force = false) {
        const active = root.activeWorkspace;
        if (!active || active.id <= 0 || !/^\d+$/.test(active.name))
            return;
        if (!force && active === root.panWorkspace)
            return;
        const occupied = new Set(Hyprland.toplevels.values.map(t => t.workspace?.id));
        // At startup, wait for the window model before counting the empty slot.
        if (!root.panWorkspace && occupied.size === 0 && Hyprland.workspaces.values.some(w => w.lastIpcObject?.windows > 0))
            return;
        const numbered = Hyprland.workspaces.values.filter(w => w.id > 0 && /^\d+$/.test(w.name)
            && (w === active || w.active || w.lastIpcObject?.ispersistent || occupied.has(w.id))).sort((a, b) => a.id - b.id);
        const index = numbered.indexOf(active);
        if (index < 0)
            return;
        root.panWorkspace = active;
        // The keyboard ring always has an empty slot, even before it is created.
        const slots = numbered.length + (numbered.some(w => !occupied.has(w.id)) ? 0 : 1);
        root.animatePan(Wallpaper.parallax && slots > 1 ? index / (slots - 1) : 0.5);
    }

    onActiveWorkspaceChanged: Qt.callLater(root.updatePan)

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { Qt.callLater(root.updatePan); }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { Qt.callLater(root.updatePan); }
    }

    // Coalesce the service's image/colour setters, which change two properties.
    onWantedPathChanged: Qt.callLater(root.adopt)
    onWantedColorChanged: Qt.callLater(root.adopt)
    Component.onCompleted: {
        Wallpaper.registerBackdrop(root.screen.name, root);
        Qt.callLater(root.updatePan);
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
        function onParallaxChanged() { Qt.callLater(() => root.updatePan(true)); }
    }

    // While a fade runs, keep its layers intact and apply the latest choice next.
    function adopt() {
        if (fade.running || (!root.wantedPath && !root.wantedColor))
            return;
        if (root.ready && root.front.path === root.wantedPath) {
            root.front.swatch = root.wantedColor;
            root.back.path = "";
            root.back.swatch = "";
            return;
        }
        root.back.opacity = 0;
        root.back.swatch = root.wantedColor;
        root.back.path = root.wantedPath;
        root.startFade();
    }

    // A stale load completion must not put a superseded wallpaper on screen.
    function startFade() {
        if (fade.running || root.back.path !== root.wantedPath || root.back.swatch !== root.wantedColor)
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

            width: root.width * root.zoom
            height: root.height * root.zoom
            x: (root.width - width) / 2 + root.offsetX
            y: (root.height - height) / 2
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
