import QtQuick
import qs

// A menu's off/on acknowledgement, completed before its action changes the list.
QtObject {
    id: root

    property Item item: null
    property bool lit: true
    property var action: null
    readonly property bool running: sequence.running

    function start(item: Item, action: var): void {
        if (root.running)
            return;
        root.item = item;
        root.action = action;
        sequence.start();
    }

    // A dismissed popup or replaced list must not run its pending selection.
    function cancel(): void {
        sequence.stop();
        root.action = null;
        root.item = null;
        root.lit = true;
    }

    property SequentialAnimation sequence: SequentialAnimation {
        PropertyAction { target: root; property: "lit"; value: false }
        PauseAnimation { duration: Theme.blinkMs }
        PropertyAction { target: root; property: "lit"; value: true }
        PauseAnimation { duration: Theme.blinkMs }
        onFinished: {
            const action = root.action;
            root.action = null;
            root.item = null;
            action();
        }
    }
}
