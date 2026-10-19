import QtQuick
import qs

// Grey glass over the workspace pill, using FlowMark's spring geometry.
// Drawn outside the pill so its textures hold the pill and icons without the
// mark.
ShaderEffect {
    id: root

    // The mark (FlowMark), the pill's glass it moves over, what the pill
    // holds (the icons), and the wallpaper as Liquid takes it. The caps bend
    // the glass always, and the icons only on the way: bent while the mark
    // settled, an icon near a cap smeared into a bright disc.
    required property Item mark
    required property Item slabItem
    required property Item inkItem
    required property Item wallpaperItem

    // Off under Reduce transparency, and until the wallpaper is in: the
    // mark draws itself, as a fill.
    readonly property bool active: !Theme.reduceTransparency && (wallpaperItem?.glassWeight ?? 0) > 0 && mark !== null

    visible: active && mark.visible

    // The lens strengthens as the mark lifts (to travel, or under a held
    // press). Settled, it lies flat.
    readonly property real lift: Math.max(0, Math.min(1, root.mark?.lift ?? 0))
    // How far the caps bend the icons: fully in flight, fading over the
    // last eight pixels before the mark lands.
    readonly property real refract: root.mark ? Math.min(1, Math.max(Math.abs(root.mark.headLeft - root.mark.wantLeft), Math.abs(root.mark.headRight - root.mark.wantRight)) / 8) : 0

    // Where an item is in its window, walked up the parent chain for a
    // binding to re-run on (as Liquid.windowPos).
    function windowPosOf(item: Item): point {
        let x = 0, y = 0;
        for (; item; item = item.parent) {
            x += item.x;
            y += item.y;
        }
        return Qt.point(x, y);
    }
    readonly property point windowPos: windowPosOf(root)

    // The mark's capsule in this item's coordinates.
    readonly property point at: root.mark ? Qt.point(root.mark.windowPos.x - root.windowPos.x, root.mark.windowPos.y - root.windowPos.y) : Qt.point(0, 0)
    readonly property size size: Qt.size(width, height)
    readonly property vector4d box: Qt.vector4d(root.at.x + (root.mark?.frontLeft ?? 0), root.at.y + (root.mark?.slabTop ?? 0), root.mark ? root.mark.frontRight - root.mark.frontLeft : 0, root.mark?.thickness ?? 0)
    readonly property real bend: 4 + 2 * lift
    readonly property real depth: 0.65
    readonly property real steep: 1.6
    readonly property real dispersion: Theme.glassDispersion
    readonly property real tint: 0.22 - 0.06 * lift
    readonly property vector3d tintColor: Qt.vector3d(0.62, 0.62, 0.64)
    readonly property real lineWidth: Theme.pillBorder
    readonly property vector4d rimTop: Qt.vector4d(Theme.pillRimTop.r, Theme.pillRimTop.g, Theme.pillRimTop.b, Theme.pillRimTop.a)
    readonly property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)
    readonly property vector4d sheen: Theme.pillSheen
    // The wallpaper is laid out in the window, as Liquid takes it.
    readonly property point wallOrigin: Qt.point(root.wallpaperItem ? root.wallpaperItem.x - root.windowPos.x : 0, root.wallpaperItem ? root.wallpaperItem.y - root.windowPos.y : 0)
    readonly property size wallSize: Qt.size(root.wallpaperItem?.width ?? 1, root.wallpaperItem?.height ?? 1)

    property var wallpaper: root.wallpaperItem
    // The pill's glass and its icons, each laid out as this item is.
    property var slab: ShaderEffectSource {
        readonly property point at: root.windowPosOf(root.slabItem)
        sourceItem: root.slabItem
        sourceRect: Qt.rect(root.windowPos.x - at.x, root.windowPos.y - at.y, root.width, root.height)
        live: root.visible
        hideSource: false
    }
    property var ink: ShaderEffectSource {
        readonly property point at: root.windowPosOf(root.inkItem)
        sourceItem: root.inkItem
        sourceRect: Qt.rect(root.windowPos.x - at.x, root.windowPos.y - at.y, root.width, root.height)
        live: root.visible
        hideSource: false
    }

    fragmentShader: Qt.resolvedUrl("../shaders/glassmark.frag.qsb")
}
