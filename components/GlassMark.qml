import QtQuick
import qs

// Grey glass over the workspace pill, using FlowMark's spring geometry.
// Drawn outside the pill so its texture contains the icons without the mark.
ShaderEffect {
    id: root

    // The mark (FlowMark), the pill it moves in, and the wallpaper as Liquid
    // takes it.
    required property Item mark
    required property Item pillItem
    required property Item wallpaperItem

    // Off under Reduce transparency, and until the wallpaper is in: the
    // mark draws itself, as a fill.
    readonly property bool active: !Theme.reduceTransparency && (wallpaperItem?.glassWeight ?? 0) > 0 && mark !== null

    visible: active && mark.visible

    // Movement and a held press strengthen the lens, then ease it back.
    property real motion: 0
    property real idleFor: 0
    readonly property bool moving: !Theme.reduceMotion && root.mark !== null && (root.mark.held || Math.abs(root.mark.headLeft - root.mark.wantLeft) > 1 || Math.abs(root.mark.headRight - root.mark.wantRight) > 1)
    FrameAnimation {
        running: root.visible && (root.moving || root.motion > 0.001)
        onTriggered: {
            root.idleFor = root.moving ? 0 : root.idleFor + frameTime;
            const animated = root.moving || (!Theme.reduceMotion && root.idleFor < 0.25 && root.motion > 0);
            const tau = animated ? 0.072 : 0.168;
            root.motion += ((animated ? 1 : 0) - root.motion) * (1 - Math.exp(-frameTime / tau));
            if (!animated && root.motion < 0.001)
                root.motion = 0;
        }
    }

    // Where this item is in its window, walked up the parent chain for the
    // binding to re-run on (as Liquid.windowPos).
    readonly property point windowPos: {
        let x = 0, y = 0;
        for (let item = root; item; item = item.parent) {
            x += item.x;
            y += item.y;
        }
        return Qt.point(x, y);
    }

    // The mark's capsule in this item's coordinates.
    readonly property point at: root.mark ? Qt.point(root.mark.windowPos.x - root.windowPos.x, root.mark.windowPos.y - root.windowPos.y) : Qt.point(0, 0)
    readonly property size size: Qt.size(width, height)
    readonly property vector4d box: Qt.vector4d(root.at.x + (root.mark?.frontLeft ?? 0), root.at.y + (root.mark?.slabTop ?? 0), root.mark ? root.mark.frontRight - root.mark.frontLeft : 0, root.mark?.thickness ?? 0)
    readonly property real bend: 4 + 2 * motion
    readonly property real depth: 0.65
    readonly property real steep: 1.6
    readonly property real dispersion: Theme.glassDispersion
    readonly property real tint: 0.22 - 0.06 * motion
    readonly property vector3d tintColor: Qt.vector3d(0.62, 0.62, 0.64)
    readonly property real lineWidth: Theme.pillBorder
    readonly property vector4d rimTop: Qt.vector4d(Theme.pillRimTop.r, Theme.pillRimTop.g, Theme.pillRimTop.b, Theme.pillRimTop.a)
    readonly property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)
    readonly property vector4d sheen: Theme.pillSheen
    // The wallpaper is laid out in the window, as Liquid takes it.
    readonly property point wallOrigin: Qt.point(root.wallpaperItem ? root.wallpaperItem.x - root.windowPos.x : 0, root.wallpaperItem ? root.wallpaperItem.y - root.windowPos.y : 0)
    readonly property size wallSize: Qt.size(root.wallpaperItem?.width ?? 1, root.wallpaperItem?.height ?? 1)

    property var wallpaper: root.wallpaperItem
    // The pill as drawn without the mark, laid out as this item is. A
    // sibling of this item's.
    property var pill: ShaderEffectSource {
        sourceItem: root.pillItem
        sourceRect: Qt.rect(root.x - root.pillItem.x, root.y - root.pillItem.y, root.width, root.height)
        live: root.visible
        hideSource: false
    }

    fragmentShader: Qt.resolvedUrl("../shaders/glassmark.frag.qsb")
}
