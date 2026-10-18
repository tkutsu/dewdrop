import QtQuick
import qs

// A PopupRow that a sideways swipe takes away, either way, as mail's rows
// go: on the touchpad or with a mouse drag the row moves the way content
// scrolls on this machine, `glyph` (what letting go will do) opens behind
// it, and past `reach` it pops. Letting go there slides the row off, folds
// it away and says `swiped`; short of it, the row springs back.
//
// The contents ride along by adding `swipe` to their x. The row's height is
// `fullHeight`, folded down as it leaves.
PopupRow {
    id: row

    property string glyph: Theme.glyph.check
    property real fullHeight: 0

    property real swipe: 0
    readonly property real reach: row.width * 0.4
    readonly property bool armed: Math.abs(row.swipe) >= row.reach
    readonly property bool swiping: row.swipe !== 0 || row.tracking
    property bool tracking: false
    property bool leaving: false
    // How far the row has folded away once it has slid off.
    property real gone: 0
    // The gesture's axis, fixed by its first movement, so a scroll that
    // drifts sideways never becomes a swipe.
    property string axis: ""

    signal swiped

    height: row.fullHeight * (1 - row.gone)
    clip: row.leaving
    held: row.swiping
    slide: row.swipe
    acceptsTap: !row.swiping

    Behavior on swipe {
        enabled: !row.tracking && !row.leaving
        SpringAnimation {
            spring: Theme.drawerSpring
            damping: Theme.drawerDamping
        }
    }

    function track(dx: real): void {
        row.tracking = true;
        row.swipe = Math.max(-row.width, Math.min(row.width, dx));
    }

    function release(): void {
        if (!row.tracking)
            return;
        row.tracking = false;
        if (row.armed && !row.leaving) {
            row.leaving = true;
            slideOff.to = row.swipe < 0 ? -row.width : row.width;
            leave.start();
        } else {
            row.swipe = 0;
        }
    }

    SequentialAnimation {
        id: leave

        NumberAnimation {
            id: slideOff
            target: row
            property: "swipe"
            duration: 140
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: row
            property: "gone"
            to: 1
            duration: Theme.foldMs * 0.6
            easing.type: Easing.InOutCubic
        }
        ScriptAction {
            script: row.swiped()
        }
    }

    // The gesture ends when the touchpad says so, or failing that when it
    // has gone quiet.
    Timer {
        id: quiet
        interval: 150
        onTriggered: {
            row.axis = "";
            row.release();
        }
    }

    // What letting go will do, opening from the edge the row is leaving.
    Item {
        visible: row.swipe !== 0
        x: row.swipe < 0 ? row.width + row.swipe : 0
        width: Math.abs(row.swipe)
        height: row.height
        opacity: row.armed ? 1 : 0.6
        clip: true

        Glyph {
            // Centred in the room it would have once armed, so it rides in
            // with the edge and then holds still.
            x: (row.swipe < 0 ? parent.width - Math.min(parent.width, row.reach) / 2 : Math.min(parent.width, row.reach) / 2) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            text: row.glyph
            fontSize: Theme.popupTextSize
            color: Theme.label
            scale: row.armed ? 1.3 : 1

            Behavior on scale {
                SpringAnimation {
                    spring: 4
                    damping: 0.3
                }
            }
        }
    }

    // On top, so it sees the wheel first and hands back whatever is not
    // sideways; a mouse drag anywhere on the row swipes it too.
    Item {
        z: 1
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                const dx = wheel.pixelDelta.x;
                const dy = wheel.pixelDelta.y;
                // Momentum after a swipe is the swipe's; after a scroll it
                // is the scroll's.
                if (wheel.phase === Qt.ScrollMomentum) {
                    wheel.accepted = row.axis === "x" || row.leaving;
                    return;
                }
                if (wheel.phase === Qt.ScrollBegin)
                    row.axis = "";
                if (row.axis === "" && (dx !== 0 || dy !== 0))
                    row.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
                if (row.axis !== "x" || row.leaving) {
                    wheel.accepted = row.leaving;
                    if (wheel.phase === Qt.ScrollEnd)
                        row.axis = "";
                    else if (row.axis !== "")
                        quiet.restart();
                    return;
                }
                wheel.accepted = true;
                row.track(row.swipe + dx);
                if (wheel.phase === Qt.ScrollEnd) {
                    quiet.stop();
                    row.axis = "";
                    row.release();
                } else {
                    quiet.restart();
                }
            }
        }

        DragHandler {
            target: null
            yAxis.enabled: false
            enabled: !row.leaving
            onActiveChanged: if (!active)
                row.release()
            onActiveTranslationChanged: if (active)
                row.track(activeTranslation.x)
        }
    }
}
