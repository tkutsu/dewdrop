import QtQuick
import qs

// Spring motion and glass geometry for horizontal selections.
Liquid {
    id: root
    property bool held: false
    property bool resetWhenHidden: false
    readonly property bool animating: liftSpring.running || leftSpring.running || rightSpring.running
    property real slabY: 0
    required property real slabHeight

    readonly property int inset: Theme.markInset

    // How the ends run: the workspace mark's pace unless told otherwise.
    property real spring: Theme.markSpring
    property real damping: Theme.markDamping

    // How far the glass has come up off the pill, 0..1: a press held
    // on an icon lifts it a pixel towards the pill's edges and
    // lights it a step, and letting go drops it back on the spring.
    // A pixel, because the bar's surface ends at the pill's foot and
    // the mark cannot swell past it the way a lens on a phone does.
    property real lift: root.held ? 1 : 0

    Behavior on lift {
        SpringAnimation {
            id: liftSpring
            spring: Theme.markSpring
            damping: Theme.markDamping
        }
    }

    readonly property real edge: inset - lift
    readonly property real slabTop: root.slabY + edge
    readonly property real thickness: root.slabHeight - edge * 2
    readonly property color tone: Theme.mix(Theme.selectionStrong, Theme.markLifted, lift)

    property real wantLeft: 0
    property real wantRight: 0

    // Each end runs from wherever it is to where the mark belongs, so
    // a switch made mid-run picks both ends up where they are rather
    // than snapping them together first. Not until the mark has been
    // placed once, or it would flow in from the screen's edge.
    property bool placed: false

    // A hidden power selector resets; workspaces retain motion through IPC gaps.
    onVisibleChanged: {
        if (visible && !placed)
            Qt.callLater(() => { if (root.visible) root.placed = true; });
        else if (!visible && root.resetWhenHidden)
            root.placed = false;
    }

    property real headLeft: wantLeft
    property real headRight: wantRight

    // Follow layout changes directly at rest; an ongoing spring keeps moving
    // towards the updated destination.
    property bool resizing: false
    readonly property bool _following: resizing && !leftSpring.running && !rightSpring.running

    Behavior on headLeft {
        enabled: root.placed && !root._following
        SpringAnimation {
            id: leftSpring
            spring: root.spring
            damping: root.damping
        }
    }
    Behavior on headRight {
        enabled: root.placed && !root._following
        SpringAnimation {
            id: rightSpring
            spring: root.spring
            damping: root.damping
        }
    }

    // The pill's ends, as walls for the head. A pixel short of the
    // slab's edge, so the pill's rim stays in view outside the glass
    // pressed against it. Only at the first and last workspace: in
    // the middle of the strip the overshoot has room to run.
    property bool atFirst: false
    property bool atLast: false
    required property real wallLeft
    // The pill keeps its old width briefly after an empty workspace leaves.
    required property real wallRight

    // A long jump can overshoot by more than a narrow workspace's width.
    readonly property real frontLeft: Math.min(atFirst ? Math.max(headLeft - lift, wallLeft) : headLeft - lift, atLast ? wallRight : Infinity)
    readonly property real frontRight: Math.max(frontLeft, atLast ? Math.min(headRight + lift, wallRight) : headRight + lift)

    // How far past a wall the spring would have carried the head, on
    // whichever side it is pressing.
    readonly property real pastLeft: atFirst ? wallLeft - (headLeft - lift) : 0
    readonly property real pastRight: atLast ? headRight + lift - wallRight : 0

    // How hard the head is pressed into the wall, 0..1, eased out so
    // the glass gives quickly at first and then stiffens. It comes
    // out as a bulb of glass against the wall, taller than the rest
    // of the mark, the way a drop run into something piles up where
    // it hit rather than swelling all along.
    readonly property real press: {
        const t = Math.min(1, Math.max(pastLeft, pastRight, 0) / Theme.markPress);
        return 1 - (1 - t) * (1 - t);
    }
    readonly property real bulbEdge: Math.max(0, edge - Theme.markBulge * press)
    readonly property real bulbTop: root.slabY + bulbEdge
    readonly property real bulbThickness: root.slabHeight - bulbEdge * 2
    readonly property real bulbWidth: press > 0 ? bulbThickness * 1.2 : 0
    readonly property real bulbLeft: pastRight > pastLeft ? wallRight - bulbWidth : wallLeft

    box0: Qt.vector4d(frontLeft, slabTop, frontRight - frontLeft, thickness)
    box1: Qt.vector4d(bulbLeft, bulbTop, bulbWidth, bulbThickness)
    reach: 0
    // The bulb joins the head with a small reach of its own: enough
    // to round the step between the two, and short enough that the
    // swell a join adds (a quarter of the reach) stays inside the
    // pixel between the wall and the pill's edge.
    reaches: Qt.vector4d(0, 3 * press, 0, 0)
    // The strong step, not a popup row's hover: on a pill this thin
    // over a bright wallpaper, the row fill was barely there.
    fill: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
    rimTop: Qt.vector4d(Theme.markRimTop.r, Theme.markRimTop.g, Theme.markRimTop.b, Theme.markRimTop.a)
    // The bulb's band, which is the rest of the mark's or taller when
    // it bulges.
    rimFrom: bulbTop
    rimTo: bulbTop + bulbThickness
}
