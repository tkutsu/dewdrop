import QtQuick
import qs

// How far a pill has gone into the popover it turns into (Popup.morphs):
// 0 the pill, 1 gathered into a drop and partly sunk, 2 sunk out of the bar
// into the popover coming out under it. Bar.qml draws the pill's glass off
// it (Bar.morph). Opening, the pill goes first and the popover waits for it;
// closing, the popover goes back into the drop first and the pill waits for
// that before it takes the drop back and springs out to its width.
//
// Not under Reduce motion, nor for a popover handed over from another one,
// which only fades (Popup.moves).
Item {
    id: root

    // The pill's popover is up.
    required property bool open
    property real value: 0

    onOpenChanged: {
        gather.stop();
        release.stop();
        if (root.open && (Theme.reduceMotion || OpenPopup.switched)) {
            root.value = 2;
            return;
        }
        if (!root.open && Theme.reduceMotion) {
            root.value = 0;
            return;
        }
        if (root.open)
            gather.start();
        else if (root.value !== 0)
            release.start();
    }

    SequentialAnimation {
        id: gather
        NumberAnimation { target: root; property: "value"; to: 1; duration: Theme.morphGatherMs; easing.type: Easing.InOutCubic }
        NumberAnimation { target: root; property: "value"; to: 2; duration: 90; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: release
        PauseAnimation { duration: Theme.morphCloseMs - 60 }
        NumberAnimation { target: root; property: "value"; to: 1; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "value"; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }
}
