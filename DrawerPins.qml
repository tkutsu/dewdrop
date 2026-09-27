pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The right pill's modules you have middle-clicked out of the drawer for good,
// keyed by BarItem.pinKey. A pin only ever adds: an unpinned module still comes
// out whenever it has something to say (BarItem.quiet), because taking the pin
// off means "back to normal", not "hide". Kept across restarts, and at the root
// rather than in services/ because BarItem reads it (see Popup.qml's note on
// why components cannot import qs.services).
Singleton {
    id: root

    property var pins: ({})

    function pinned(key) {
        return root.pins[key] === true;
    }

    function toggle(key) {
        const pins = Object.assign({}, root.pins);
        if (root.pinned(key))
            delete pins[key];
        else
            pins[key] = true;
        root.pins = pins;
        stored.pins = pins;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: Paths.state("drawer.json")
        printErrors: false
        onLoaded: root.pins = stored.pins
        onLoadFailed: file.writeAdapter()

        JsonAdapter {
            id: stored

            property var pins: ({})
        }
    }
}
