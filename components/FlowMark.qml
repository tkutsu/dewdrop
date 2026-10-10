import QtQuick
import qs

// Shared head-and-tail motion and glass geometry for horizontal selections.
Liquid {
    id: root
    property bool held: false
    property bool resetWhenHidden: false
    readonly property bool animating: liftSpring.running || leftSpring.running || rightSpring.running || tailMotion.running
    property real slabY: 0
    required property real slabHeight

    readonly property int inset: Theme.markInset

    // How the ends run: the workspace mark's pace unless told otherwise.
    property real spring: Theme.springStiffness
    property real damping: Theme.markDamping
    property int flowMs: Theme.markMs

    // How far the glass has come up off the pill, 0..1: a press held
    // on an icon lifts it a pixel towards the pill's edges and
    // lights it a step, and letting go drops it back on the spring.
    // A pixel, because the bar's surface ends at the pill's foot and
    // the mark cannot swell past it the way a lens on a phone does.
    property real lift: root.held ? 1 : 0

    Behavior on lift {
        SpringAnimation {
            id: liftSpring
            spring: Theme.springStiffness
            damping: Theme.markDamping
        }
    }

    readonly property real edge: inset - lift
    readonly property real slabTop: root.slabY + Theme.pillBorder + edge
    readonly property real thickness: root.slabHeight - Theme.pillBorder - edge * 2
    readonly property color tone: Theme.mix(Theme.selectionStrong, Theme.markLifted, lift)

    property real wantLeft: 0
    property real wantRight: 0

    // Each end runs from wherever it is to where the mark belongs, so
    // a switch made mid-run picks both ends up where they are rather
    // than snapping them together first. Not until the mark has been
    // placed once, or it would flow in from the screen's edge.
    property bool placed: false
    onPlacedChanged: if (placed) {
        tailLeft = wantLeft;
        tailRight = wantRight;
        tailProgress = 1;
        roundness = 0;
    }

    // A hidden power selector resets; workspaces retain motion through IPC gaps.
    onVisibleChanged: {
        if (visible && !placed)
            Qt.callLater(() => { if (root.visible) root.placed = true; });
        else if (!visible && root.resetWhenHidden) {
            root.placed = false;
            root.followTail();
        }
    }

    property real headLeft: wantLeft
    property real headRight: wantRight
    property real tailLeft: wantLeft
    property real tailRight: wantRight
    property point tailStart: Qt.point(wantLeft, wantRight)
    property real tailProgress: 1
    property real roundness: 0

    // Set by the owner when the destination is the same place changing size,
    // not a new place: at rest the ends follow the new edges exactly instead
    // of flowing to them, and a flow already under way keeps going, since it
    // heads for wherever the destination is now.
    property bool resizing: false
    readonly property bool _following: resizing && tailProgress >= 1

    // A new destination keeps the tail wherever the previous move left it.
    function followTail(): void {
        if (!root.placed || root._following) {
            root.tailLeft = root.wantLeft;
            root.tailRight = root.wantRight;
            root.tailProgress = 1;
            root.roundness = 0;
            return;
        }
        if (root.resizing)
            return;
        root.tailStart = Qt.point(root.tailLeft, root.tailRight);
        root.tailProgress = 0;
    }

    onWantLeftChanged: followTail()
    onWantRightChanged: followTail()

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
    FrameAnimation {
        id: tailMotion
        running: root.visible && root.placed && (root.tailProgress < 1 || root.roundness > 0)

        // Distance and the tail's shrinking size accelerate the same cubic flow.
        onTriggered: {
            const previousMid = root.tailMid;
            const distance = root.apart / (root.thickness * 4);
            const shrink = 1 - root.blobHeight / root.thickness;
            const speed = (1 + 0.75 * distance * distance) * (1 + 0.75 * shrink);
            root.tailProgress = Math.min(1, root.tailProgress + frameTime * 1000 * speed / (root.flowMs * 1.1));
            const t = Math.max(0, (root.tailProgress - 0.2) / 0.8);
            const eased = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
            const left = root.tailStart.x + (root.wantLeft - root.tailStart.x) * eased;
            const right = root.tailStart.y + (root.wantRight - root.tailStart.y) * eased;
            const velocity = root.tailProgress < 1 && frameTime > 0 ? Math.abs((left + right) / 2 - previousMid) / frameTime : 0;
            root.tailLeft = left;
            root.tailRight = right;
            // Ease into a ball as flow speeds up, and back into a pill at rest.
            const pace = Math.min(1, velocity / (root.thickness * 24));
            const round = pace * pace * (3 - 2 * pace);
            const roundingTime = round > root.roundness ? 0.025 : 0.05;
            root.roundness += (round - root.roundness) * (1 - Math.exp(-frameTime / roundingTime));
            if (round === 0 && root.roundness < 0.001)
                root.roundness = 0;
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
    readonly property real bulbTop: root.slabY + Theme.pillBorder + bulbEdge
    readonly property real bulbThickness: root.slabHeight - Theme.pillBorder - bulbEdge * 2
    readonly property real bulbWidth: press > 0 ? bulbThickness * 1.2 : 0
    readonly property real bulbLeft: pastRight > pastLeft ? wallRight - bulbWidth : wallLeft

    readonly property real headMid: (frontLeft + frontRight) / 2
    readonly property real tailMid: (tailLeft + tailRight) / 2
    readonly property real apart: Math.abs(headMid - tailMid)
    // Full thickness while the ends overlap, down to 40% of it once
    // they are three thicknesses apart: a neighbour's mark only
    // stretches, a long way off it pours through a thread.
    readonly property real neck: thickness * (1 - 0.6 * Math.pow(Math.min(1, apart / (thickness * 3)), 2))
    readonly property real tailWidth: tailRight - tailLeft + lift * 2
    readonly property real blobWidth: tailWidth + (neck - tailWidth) * roundness
    readonly property real blobHeight: thickness + (neck - thickness) * roundness

    box0: Qt.vector4d(tailMid - blobWidth / 2, slabTop + (thickness - blobHeight) / 2, blobWidth, blobHeight)
    box1: Qt.vector4d(frontLeft, slabTop, frontRight - frontLeft, thickness)
    box2: Qt.vector4d(Math.min(headMid, tailMid), slabTop + (thickness - neck) / 2, apart, neck)

    // At rest the head lies on the tail, and a reach would swell the
    // two into something fatter than either; it comes up only as they
    // part.
    reach: Theme.pillSpread * Math.min(1, apart / thickness)
    box3: Qt.vector4d(bulbLeft, bulbTop, bulbWidth, bulbThickness)
    // The bulb joins the head with a small reach of its own: enough
    // to round the step between the two, and short enough that the
    // swell a join adds (a quarter of the reach) stays inside the
    // pixel between the wall and the pill's edge.
    reaches: Qt.vector4d(reach, reach, reach, 3 * press)
    // The strong step, not a popup row's hover: on a pill this thin
    // over a bright wallpaper, the row fill was barely there.
    fill: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
    rimTop: Qt.vector4d(Theme.markRimTop.r, Theme.markRimTop.g, Theme.markRimTop.b, Theme.markRimTop.a)
    // The bulb's band, which is the rest of the mark's or taller when
    // it bulges.
    rimFrom: bulbTop
    rimTo: bulbTop + bulbThickness
}
