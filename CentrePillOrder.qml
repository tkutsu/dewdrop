pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "RightPillOrder.js" as Order

// Every module retains its central slot while shown in the right pill.
Singleton {
    id: root

    readonly property var defaults: ["date", "weather", "time", ...Order.normalise([]).filter(key => !["date", "weather", "time"].includes(key))]
    readonly property var keys: Order.normalise(Array.from(stored.order ?? []), root.defaults)

    function move(key, beforeKey, visibleKeys): bool {
        const next = Order.move(root.keys, key, beforeKey, visibleKeys, root.defaults);
        if (next.every((k, index) => k === root.keys[index]))
            return false;
        stored.order = next;
        file.writeAdapter();
        return true;
    }

    FileView {
        id: file
        path: Paths.state("centre-pill.json")
        printErrors: false

        JsonAdapter {
            id: stored
            property var order: []
        }
    }
}
