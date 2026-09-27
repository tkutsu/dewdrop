pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The right pill's modules you have middle-clicked out of the drawer or into
// it, overruling what they say about themselves (BarItem.quiet). Keyed by
// BarItem.pinKey: true keeps a module out, false keeps it in, and a module
// with no entry goes by its own quiet. Kept across restarts, and at the root
// rather than in services/ because BarItem reads it (see Popup.qml's note on
// why components cannot import qs.services).
Singleton {
    id: root

    property var pins: ({})

    function showsClosed(key, quiet) {
        const pin = root.pins[key];
        return pin === undefined ? !quiet : pin;
    }

    // Flip where the module stands now. A flip that lands it where its own
    // quiet would have put it drops the pin instead of keeping one that says
    // nothing, so two clicks is always the way back to how it was.
    function toggle(key, quiet) {
        const next = !root.showsClosed(key, quiet);
        const pins = Object.assign({}, root.pins);
        if (next === !quiet)
            delete pins[key];
        else
            pins[key] = next;
        root.pins = pins;
        stored.pins = pins;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: Quickshell.env("HOME") + "/.local/state/quickshell/drawer.json"
        printErrors: false
        onLoaded: root.pins = stored.pins
        onLoadFailed: file.writeAdapter()

        JsonAdapter {
            id: stored

            property var pins: ({})
        }
    }
}
