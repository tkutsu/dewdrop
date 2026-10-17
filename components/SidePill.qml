import QtQuick
import qs
import "../Drops.js" as Drops

// A pill arriving beside a neighbour, with contents and input following its glass.
Pill {
    id: root
    required property Item control
    property real morphValue: 0
    // Sliding contents keep their icon separate from the text as the glass gathers.
    property bool slidesContent: false
    property bool bounceBeforeCollapse: false
    readonly property var geometry: Drops.geometry(Theme)
    // On exit, hide text during the bounce, then fade the icon and gather glass.
    readonly property real textReveal: bounceBeforeCollapse ? Math.max(0, 2 * controlReveal - 1) : 1
    readonly property real iconOpacity: !bounceBeforeCollapse ? 1
        : control.stowed ? geometry.contents(dropReveal) : Math.min(1, iconProgress / 0.08)
    // Keep entry covered through the central pill; start the spring as the icon emerges.
    readonly property real iconProgress: control.stowed ? 2 * (1 - controlReveal)
        : 2 * Math.max(0, controlReveal - (bounceBeforeCollapse ? 0.25 : 0.2))
    readonly property real iconScale: slidesContent && !retiring
        ? geometry.iconScale(iconProgress) : 1

    property bool closeWhenEmpty: false
    property bool empty: false
    property Item emptyPopupOwner: control
    property bool retiring: false
    property bool holdingEmpty: false
    readonly property real controlReveal: control.reveal
    readonly property real dropReveal: retiring && control.stowed ? geometry.emptyReveal(controlReveal)
        : bounceBeforeCollapse ? Math.min(1, 2 * controlReveal) : controlReveal
    // Use the same gathering shape as the bar, measured from this pill's origin.
    readonly property vector4d foldBox: geometry.drop(
        side === Pill.Side.Left ? -Theme.pillSpread : width + Theme.pillSpread,
        side === Pill.Side.Left ? 1 : -1, width, dropReveal, control.stowed)

    // Finish service updates first: a timer can leave the list and start
    // ringing in the same turn, without its popover being empty.
    onEmptyChanged: Qt.callLater(root.checkEmpty)
    function checkEmpty() {
        if (!root.empty) {
            root.holdingEmpty = false;
            root.retiring = false;
        } else if (root.closeWhenEmpty && root.emptyPopupOwner?.popupOpen) {
            if (!Theme.reduceMotion) {
                root.retiring = true;
                root.holdingEmpty = true;
            }
            OpenPopup.close(root.emptyPopupOwner);
            root.finishReturn();
        }
    }

    // Hand the almost-formed capsule straight to the collapse, before the
    // return spring settles. New content cancels the exit.
    function finishReturn() {
        if (root.holdingEmpty && root.morphValue <= 0.1 && root.controlReveal === 1 && !emptyWidthMotion.running)
            root.holdingEmpty = false;
        if (root.controlReveal === 0 && !root.holdingEmpty)
            root.retiring = false;
    }
    onMorphValueChanged: finishReturn()
    onControlRevealChanged: finishReturn()

    Binding {
        target: root.closeWhenEmpty ? root.control : null
        property: "exitHeld"
        value: root.holdingEmpty
    }

    implicitWidth: retiring ? Math.round(Theme.barHeight * 2.8) : moduleHost.implicitWidth
    Behavior on implicitWidth {
        enabled: root.retiring && !Theme.reduceMotion
        NumberAnimation {
            id: emptyWidthMotion
            duration: Theme.morphCloseMs
            easing.type: Easing.InOutCubic
            onRunningChanged: if (!running) root.finishReturn()
        }
    }

    edges: false
    drawsSlab: false
    // With nothing to show there is no pill, rather than an empty one. Off
    // the module's `reveal` rather than its visibility: hiding an item hides
    // its children with it, so a pill reading its child's `visible` would
    // latch shut the first time the module was quiet.
    visible: root.control.reveal > 0
    contentOpacity: retiring ? 0 : (slidesContent ? 1 : geometry.contents(controlReveal)) * geometry.morphContents(morphValue)
    contentZoom: slidesContent ? 1 : Math.min(1, foldBox.z / Math.max(width, 1), foldBox.w / Theme.barHeight)
        * (Theme.reduceMotion ? 1 : 0.96 + 0.04 * contentOpacity)
    contentBlur: slidesContent || Theme.reduceMotion ? 0 : 1 - contentOpacity
    contentShiftX: slidesContent ? 0 : foldBox.x + foldBox.z / 2 - width / 2
    contentScale: root.geometry.morph(Qt.vector4d(0, 0, width, Theme.barHeight), root.morphValue).z / Math.max(width, 1)
    contentSink: Theme.barHeight * Math.max(0, (root.morphValue - 0.5) / 1.5)
    interactive: !retiring && root.morphValue <= 0
    trackOpacity: slidesContent ? (retiring ? 0 : geometry.contents(controlReveal) * geometry.morphContents(morphValue)) : contentOpacity
    trackReady: !retiring && root.morphValue === 0
    trackSlab: Item {
        x: root.foldBox.x
        y: root.foldBox.y
        width: root.foldBox.z
        height: root.foldBox.w
    }
}
