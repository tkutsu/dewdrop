import QtQuick
import qs

// The attention bounce: the one motion on this bar, and the loudest thing it
// can say. A count badge means "there are things here" and is read when you
// look; this means "this wants you now" and is meant to be caught when you are
// not looking. It is spent on three states only — a tray icon asking for
// attention, a window asking for it, and a timer going off.
//
// Bind `offset` to the y translation of whatever should move. Positive is down,
// so the crouch is positive and the hops are negative. An animation rather than
// a visual item, so it can sit inside a layout without taking room in it.
//
// With Reduce motion on (Theme.reduceMotion) the hops keep their time but not
// their height, and `fade` dims and comes back over that time instead, on the
// same beat. Bind it to the opacity of a thing the bounce is the only sign
// on (a window's icon, an empty workspace's marker), so the state is still
// said with only the movement gone. The tray's attention icon and the ringing
// timer's pill say theirs without it, and simply hold still.
//
// The shape is a crouch, a launch, and three hops. Under gravity a free-flying
// body traces a parabola, which is exactly what a quadratic ease is, so the
// rise is OutQuad and the fall InQuad and the arc is right rather than merely
// smooth. Cubic or sine would look softer and be wrong. Each hop gives back a
// fixed share of the last one's height (Theme.jumpBounce) and takes the square
// root of that share in time, because time of flight goes with the square root
// of height. Only the first hop is chosen by hand; the rest follow from it.
SequentialAnimation {
    id: root

    // How long one bounce takes end to end, landing to landing. Given as the
    // whole cycle rather than as the rest between hops so a caller can say
    // "once per beat" and mean it — the rest is whatever is left after the
    // hops have had their time.
    property int periodMs: Theme.jumpPeriodMs

    // What the caller moves. Written by the animation, read by the binding.
    property real offset: 0
    property real fade: 1

    // 0 under Reduce motion, which flattens every hop below to nothing.
    readonly property real lift: Theme.reduceMotion ? 0 : 1
    readonly property real rise1: Theme.jumpRise * root.lift
    readonly property real rise2: root.rise1 * Theme.jumpBounce
    readonly property real rise3: root.rise2 * Theme.jumpBounce
    readonly property real ms2: Theme.jumpMs * Math.sqrt(Theme.jumpBounce)
    readonly property real ms3: root.ms2 * Math.sqrt(Theme.jumpBounce)
    readonly property real flightMs: Theme.jumpCrouchMs + Theme.jumpMs + root.ms2 + root.ms3

    loops: Animation.Infinite
    // Stopping mid-bounce — the attention going while the icon is in the air —
    // would strand it off its line, so the offset is put back whenever the
    // animation ends, for whatever reason.
    onStopped: {
        root.offset = 0;
        root.fade = 1;
    }

    // Gather. Down into the crouch and slowing as it settles, so the launch
    // that follows reads as a push off it. This one is animation rather than
    // physics: it is the difference between jumping and being flicked upward.
    ParallelAnimation {
        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "offset"
                to: Theme.jumpCrouch * root.lift
                duration: Theme.jumpCrouchMs
                easing.type: Easing.OutQuad
            }

            // Flight. One parabola per hop, each smaller and quicker than the last.
            NumberAnimation {
                target: root
                property: "offset"
                to: -root.rise1
                duration: Theme.jumpMs / 2
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "offset"
                to: 0
                duration: Theme.jumpMs / 2
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: root
                property: "offset"
                to: -root.rise2
                duration: root.ms2 / 2
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "offset"
                to: 0
                duration: root.ms2 / 2
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: root
                property: "offset"
                to: -root.rise3
                duration: root.ms3 / 2
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "offset"
                to: 0
                duration: root.ms3 / 2
                easing.type: Easing.InQuad
            }
        }

        // The dissolve that stands in for the flight under Reduce motion,
        // and goes from 1 to 1 otherwise.
        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "fade"
                to: 1 - 0.65 * (1 - root.lift)
                duration: root.flightMs / 2
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: root
                property: "fade"
                to: 1
                duration: root.flightMs / 2
                easing.type: Easing.InOutQuad
            }
        }
    }

    // Rest is most of the cycle on purpose: one bounce every few seconds
    // catches the eye without turning the bar into a metronome.
    PauseAnimation {
        duration: Math.max(0, root.periodMs - root.flightMs)
    }
}
