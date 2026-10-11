import QtQuick
import qs

// The workspace mark as a bead of glass (shaders/mark.frag), drawn over the
// left pill from the mark's own geometry (FlowMark, which runs the motion
// and draws nothing while this is up). At rest it is the capsule inside the
// pill it always was, as glass over the icons rather than a fill under them.
// On the move it swells into clear glass just short of the bar's window,
// pulls the icons around its rounded ends, runs
// stretched between its head and its tail, and settles back into the
// capsule when it lands, as the tab bar's selection does in the active mark
// reel.
// Grey glass keeps the capsule inside the pill and bends the icons around
// its rim without the bead's swelling or trailing tail.
//
// Over the window rather than inside the pill because the glass bends the
// pill and its icons, which it takes as a texture: inside the pill it would
// be in that texture itself.
ShaderEffect {
    id: root

    readonly property bool grey: Settings.workspaceMark === "grey"

    // The mark (FlowMark), the pill it moves in, and the wallpaper as Liquid
    // takes it.
    required property Item mark
    required property Item pillItem
    required property Item wallpaperItem

    // Off under Reduce transparency, and until the wallpaper is in: the
    // mark draws itself, as a fill.
    readonly property bool active: !Theme.reduceTransparency && (wallpaperItem?.glassWeight ?? 0) > 0 && mark !== null

    visible: active && mark.visible

    // How far it has swelled, 0..1: up while the mark moves (or is held), and
    // down after a brief pause once it has landed. Eased every frame, so a
    // run that starts again before it has settled picks up where it is.
    property real clear: 0
    property real idleFor: 0
    // The bead's back end, eased after the mark's head (in this item's
    // pixels), so it stretches out behind as it runs, the faster the longer,
    // and draws back in as it lands.
    property real tail: root.head
    // Moving: the head more than a pixel from where it is going, or the tail
    // not yet caught up with it, or held. Not the springs' own running, which
    // goes on through a settle too small to see.
    readonly property bool moving: !Theme.reduceMotion && root.mark !== null && (root.mark.held || Math.abs(root.tail - root.head) > 1 || Math.abs(root.mark.headLeft - root.mark.wantLeft) > 1 || Math.abs(root.mark.headRight - root.mark.wantRight) > 1)
    FrameAnimation {
        running: root.visible && (root.moving || root.clear > 0.001 || root.tail !== root.head)
        onTriggered: {
            root.tail += (root.head - root.tail) * (1 - Math.exp(-frameTime / 0.084));
            if (Math.abs(root.head - root.tail) < 0.05)
                root.tail = root.head;
            root.idleFor = root.moving ? 0 : root.idleFor + frameTime;
            const expanded = root.moving || (!Theme.reduceMotion && root.idleFor < 0.25 && root.clear > 0);
            const tau = expanded ? 0.072 : 0.168;
            root.clear += ((expanded ? 1 : 0) - root.clear) * (1 - Math.exp(-frameTime / tau));
            if (!expanded && root.clear < 0.001)
                root.clear = 0;
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

    // The mark in this item's pixels: where its glass is, and its head and
    // tail.
    readonly property point at: root.mark ? Qt.point(root.mark.windowPos.x - root.windowPos.x, root.mark.windowPos.y - root.windowPos.y) : Qt.point(0, 0)
    readonly property real thick: root.mark?.thickness ?? 0
    readonly property real mid: root.at.y + (root.mark?.slabTop ?? 0) + root.thick / 2
    // Leave 2px above and below the expanded bead, centred on the slab.
    readonly property real tall: Math.max(root.thick, 2 * Math.min(root.mid, root.height - root.mid) - 4)
    readonly property real w: root.mark ? root.mark.frontRight - root.mark.frontLeft : 0
    readonly property real head: root.at.x + (root.mark ? (root.mark.frontLeft + root.mark.frontRight) / 2 : 0)
    readonly property real stretch: root.grey ? 0 : Math.abs(root.head - root.tail)
    readonly property real h: root.grey ? root.thick : root.thick + (root.tall - root.thick) * root.clear - Math.min(3, root.stretch * 0.06) * root.clear
    readonly property real bw: root.grey ? root.w : root.w + (Math.max(root.w + 8, root.tall * 1.3) - root.w) * root.clear

    readonly property size size: Qt.size(width, height)
    readonly property vector4d box: Qt.vector4d((grey ? head : Math.min(head, tail)) - bw / 2, mid - h / 2, stretch + bw, h)
    readonly property real bend: grey ? 4 + 2 * clear : 1.5 + 10.5 * clear
    readonly property real depth: grey ? 0.65 : 0.5
    readonly property real steep: 1.6
    readonly property real dispersion: Theme.glassDispersion
    readonly property real restTint: grey ? 0.22 : 0.16
    readonly property real beadTint: grey ? 0.16 : 0.03
    readonly property vector3d tintColor: grey ? Qt.vector3d(0.62, 0.62, 0.64) : Qt.vector3d(1, 1, 1)
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

    fragmentShader: Qt.resolvedUrl("../shaders/mark.frag.qsb")
}
