import QtQuick
import qs

// Spring motion and glass geometry for horizontal selections.
Liquid {
    id: root
    property bool held: false
    property bool resetWhenHidden: false
    readonly property bool animating: liftEase.running || leftSpring.running || rightSpring.running
    property real slabY: 0
    required property real slabHeight

    property int inset: Theme.markInset

    // How the ends run: the workspace mark's pace unless told otherwise.
    property real spring: Theme.markSpring
    property real damping: Theme.markDamping

    // How far the glass has come up off the pill, 0..1: a press held
    // on an icon lifts it `rise` pixels towards the pill's edges and
    // lights it a step, and letting go sets it back down.
    // A pixel by default, because the bar's surface ends at the pill's
    // foot and the mark cannot swell past it the way a lens on a phone
    // does.
    property real rise: 1
    // With `liftsToTravel`, the glass also lifts while it runs to a new
    // place, and settles back a moment after it lands.
    property bool liftsToTravel: false
    readonly property bool travelling: Math.abs(headLeft - wantLeft) > 1 || Math.abs(headRight - wantRight) > 1
    property bool afloat: false
    onTravellingChanged: {
        if (travelling && liftsToTravel && !Theme.reduceMotion) {
            landing.stop();
            afloat = true;
        } else {
            landing.restart();
        }
    }
    Timer {
        id: landing
        interval: 200
        onTriggered: root.afloat = false
    }
    property real lift: root.held || root.afloat ? 1 : 0

    Behavior on lift {
        id: liftBehaviour
        NumberAnimation {
            id: liftEase
            duration: liftBehaviour.targetValue > 0 ? Theme.markLiftMs : Theme.markSettleMs
            easing.type: Easing.InOutSine
        }
    }

    readonly property real edge: inset - rise * lift
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

    // A hidden selector can reset; workspaces retain motion through IPC gaps.
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
    readonly property real frontLeft: Math.min(atFirst ? Math.max(headLeft - rise * lift, wallLeft) : headLeft - rise * lift, atLast ? wallRight : Infinity)
    readonly property real frontRight: Math.max(frontLeft, atLast ? Math.min(headRight + rise * lift, wallRight) : headRight + rise * lift)

    box0: Qt.vector4d(frontLeft, slabTop, frontRight - frontLeft, thickness)
    reach: 0
    // The strong step, not a popup row's hover: on a pill this thin
    // over a bright wallpaper, the row fill was barely there.
    fill: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
    rimTop: Qt.vector4d(Theme.markRimTop.r, Theme.markRimTop.g, Theme.markRimTop.b, Theme.markRimTop.a)
    rimFrom: slabTop
    rimTo: slabTop + thickness
}
