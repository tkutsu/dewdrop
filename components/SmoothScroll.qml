import QtQuick
import qs

// Ease wheel notches in the viewport; row controls and native touchpad gestures
// keep their own input handling. Never animate keyboard or model-driven jumps.
MouseArea {
    id: root

    required property Flickable view
    property real step: 100
    property real offset: 0
    property int direction: 0
    property bool applying: false

    parent: view.contentItem
    x: view.contentX
    y: view.contentY
    width: view.width
    height: view.height
    z: -1
    acceptedButtons: Qt.NoButton
    enabled: view.interactive

    readonly property real minimum: view.originY - view.topMargin
    readonly property real maximum: Math.max(minimum, view.originY + view.contentHeight + view.bottomMargin - view.height)

    function clamp(value: real): real {
        return Math.max(minimum, Math.min(maximum, value));
    }

    onOffsetChanged: {
        applying = true;
        view.contentY = clamp(offset);
        applying = false;
    }

    onWheel: wheel => {
        // Pixel deltas already carry the touchpad's motion and momentum.
        if (wheel.pixelDelta.y !== 0 || wheel.angleDelta.y === 0) {
            glide.stop();
            wheel.accepted = false;
            return;
        }
        view.cancelFlick();
        const delta = -wheel.angleDelta.y / 120 * step;
        const continuing = glide.running && direction === Math.sign(delta);
        const destination = clamp((continuing ? glide.to : view.contentY) + delta);
        if (destination === view.contentY && !glide.running) {
            wheel.accepted = false;
            return;
        }
        direction = Math.sign(delta);
        if (Theme.reduceMotion) {
            glide.stop();
            view.contentY = destination;
        } else {
            if (!glide.running)
                offset = view.contentY;
            glide.to = destination;
            glide.restart();
        }
        wheel.accepted = true;
    }

    property SmoothedAnimation animation: SmoothedAnimation {
        id: glide
        target: root
        property: "offset"
        velocity: -1
        duration: 220
        reversingMode: SmoothedAnimation.Immediate
    }

    property Connections watcher: Connections {
        target: root.view
        function onContentYChanged() {
            // Pixel-aligned views may round our last animation frame.
            if (!root.applying && Math.abs(root.view.contentY - root.clamp(root.offset)) > 1)
                glide.stop();
        }
        function onDraggingChanged() { if (root.view.dragging) glide.stop(); }
        function onContentHeightChanged() { root.retarget(); }
        function onOriginYChanged() { root.retarget(); }
        function onHeightChanged() { glide.stop(); }
        function onVisibleChanged() { if (!root.view.visible) glide.stop(); }
        function onInteractiveChanged() { if (!root.view.interactive) glide.stop(); }
    }

    // List views refine their extent as delegates appear during the scroll.
    function retarget(): void {
        const destination = clamp(glide.to);
        if (glide.running && destination !== glide.to) {
            glide.to = destination;
            glide.restart();
        }
    }
}
