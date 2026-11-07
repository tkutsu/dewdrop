import QtQuick
import Quickshell
import Quickshell.Io
import "RightPillOrder.js" as Order

// A pill's complete order, saved in the state folder; hidden modules retain
// their slots. RightPillOrder and CentrePillOrder are the two there are.
Singleton {
    id: root

    required property string file
    property var defaults: Order.normalise([])

    // JsonAdapter restores arrays as Qt sequences, which fail Array.isArray.
    readonly property var keys: Order.normalise(Array.from(stored.order ?? []), root.defaults)

    function move(key, beforeKey, visibleKeys): bool {
        const next = Order.move(root.keys, key, beforeKey, visibleKeys, root.defaults);
        if (next.every((k, index) => k === root.keys[index]))
            return false;
        stored.order = next;
        view.writeAdapter();
        return true;
    }

    FileView {
        id: view

        path: Paths.state(root.file)
        printErrors: false

        JsonAdapter {
            id: stored

            property var order: []
        }
    }
}
