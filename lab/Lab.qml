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
            bead: Qt.size(560, 270),
            light: Qt.size(700, 290),
            edges: Qt.size(540, 270)
        })
    readonly property string wallpaper: "/home/kutsui/_media/wallpapers/nature/akshaya-jayaprakash-XgY0NxAWlL0-unsplash.jpg"

    WlrLayershell.namespace: "quickshell:lab"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    implicitWidth: sizes[scene].width
    implicitHeight: sizes[scene].height
    mask: Region {}
    color: "black"

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
