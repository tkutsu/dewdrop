pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
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

    // Coalesce the service's image/colour setters, which change two properties.
    onWantedPathChanged: Qt.callLater(root.adopt)
    onWantedColorChanged: Qt.callLater(root.adopt)
    Component.onCompleted: {
        Wallpaper.registerBackdrop(root.screen.name, root);
        Qt.callLater(root.adopt);
    }
    Component.onDestruction: {
        if (Wallpaper.backdrops[root.screen.name] === root)
            Wallpaper.registerBackdrop(root.screen.name, null);
    }

    Connections {
        target: Wallpaper
        function onCurrentSizeChanged() { Qt.callLater(root.startFade); }
        function onSampledPathChanged() { Qt.callLater(root.startFade); }
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
            if (Wallpaper.sampledPath !== root.back.path || Wallpaper.currentSize.width <= 0)
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

            anchors.fill: parent
            source: layer.path ? "file://" + layer.path.split("/").map(encodeURIComponent).join("/") : ""
            // Decode at the window's pixel size, including fractional scaling.
            sourceSize: Qt.size(Math.ceil(root.width * root.devicePixelRatio), Math.ceil(root.height * root.devicePixelRatio))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            onStatusChanged: {
                if (status === Image.Ready)
                    Qt.callLater(root.startFade);
                else if (status === Image.Error)
                    console.warn("Could not load wallpaper:", layer.path);
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
