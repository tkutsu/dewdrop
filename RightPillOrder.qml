pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "RightPillOrder.js" as Order

// The right pill's complete order; hidden modules retain their slots.
Singleton {
    id: root

    // JsonAdapter restores arrays as Qt sequences, which fail Array.isArray.
    readonly property var keys: Order.normalise(Array.from(stored.order ?? []))

    function move(key, beforeKey, visibleKeys): bool {
        const next = Order.move(root.keys, key, beforeKey, visibleKeys);
        if (next.every((k, index) => k === root.keys[index]))
            return false;
        stored.order = next;
        file.writeAdapter();
        return true;
    }

    FileView {
        id: file

        path: Paths.state("right-pill.json")
        printErrors: false

        JsonAdapter {
            id: stored

            property var order: []
        }
    }
}
