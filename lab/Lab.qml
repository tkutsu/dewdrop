import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs

// One scene of prototypes over a strip of the wallpaper, at the bottom of the
// screen above everything, taking no input: each scene scripts its own
// pointer. The wallpaper is laid out as it is at the top of the screen, which
// is what the bar's glass sits on.
PanelWindow {
    id: win

    readonly property string scene: Quickshell.env("LAB_SCENE") || "press"
    readonly property var sizes: ({
            press: Qt.size(640, 300),
            popup: Qt.size(1200, 300),
            bead: Qt.size(560, 440),
            light: Qt.size(1200, 290),
            edges: Qt.size(540, 270),
            popupgel: Qt.size(1500, 300),
            popupdew: Qt.size(1200, 300),
            realpress: Qt.size(400, 180),
            compile: Qt.size(10, 10),
            underedge: Qt.size(1200, 290),
            realslider: Qt.size(400, 140),
            reallight: Qt.size(400, 80),
            realpopup: Qt.size(500, 330),
            accent: Qt.size(360, 120),
            mark: Qt.size(500, 248),
            morph: Qt.size(1020, 250),
            refract: Qt.size(1020, 200),
            realmorph: Qt.size(420, 240),
            glass: Qt.size(1080, 370),
            sheen: Qt.size(1080, 340)
        })
    readonly property string wallpaper: "/home/kutsui/_media/wallpapers/nature/akshaya-jayaprakash-XgY0NxAWlL0-unsplash.jpg"

    // The bar's name for the real popup, so Hyprland blurs behind it as it does
    // behind the bar's popups (wrules.lua's blur_popups).
    WlrLayershell.namespace: scene === "realpopup" || scene === "realmorph" ? "quickshell:bar" : "quickshell:lab"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    implicitWidth: sizes[scene].width
    implicitHeight: sizes[scene].height
    // No input, but for a scene that asks for it (a real control under a
    // synthetic pointer).
    mask: win.scene === "realslider" ? null : noInput
    color: "black"

    Region {
        id: noInput
    }

    Item {
        id: stage

        width: win.width
        height: win.height
        clip: true

        // The 6016x4016 picture cropped to a 2560x1440 screen the way the
        // desktop crops it: full width, the middle of its height.
        Image {
            x: -(2560 - win.width) / 2
            y: -(2560 * 4016 / 6016 - 1440) / 2
            width: 2560
            height: 2560 * 4016 / 6016
            sourceSize.width: 2560
            source: "file://" + win.wallpaper
        }
    }

    // What the glass bends: the stage, as Liquid wants it.
    ShaderEffectSource {
        id: backdrop

        property real glassWeight: 1
        width: stage.width
        height: stage.height
        sourceItem: stage
        visible: false
    }

    // What a popup's frost shows: the stage blurred about as Hyprland does,
    // and a little darker, as its blur is.
    MultiEffect {
        id: blur

        width: stage.width
        height: stage.height
        source: stage
        blurEnabled: true
        blur: 1
        blurMax: 64
        brightness: -0.08
        autoPaddingEnabled: false
    }

    ShaderEffectSource {
        id: blurred

        width: stage.width
        height: stage.height
        sourceItem: blur
        hideSource: true
        visible: false
    }

    Loader {
        id: loader

        anchors.fill: parent
        Component.onCompleted: setSource(win.scene.charAt(0).toUpperCase() + win.scene.slice(1) + "Scene.qml", {
            backdrop: backdrop,
            blurred: blurred
        })
    }
}
