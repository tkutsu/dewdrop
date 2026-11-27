pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import "../lib/ModulePlaces.js" as Places

// Which pill each ordered module sits in, and in what order, saved in the
// state folder: dragging a module within or between the pills is the only
// way in. A hidden module keeps its slot.
Singleton {
    id: root

    readonly property var fixedCentre: Places.fixedCentre
    // The modules a drag may carry between the pills.
    readonly property var movable: Places.keys.filter(key => !Places.fixedCentre.includes(key))
    // JsonAdapter restores arrays as Qt sequences, which fail Array.isArray.
    readonly property var places: Places.normalise({ centre: Array.from(stored.centre ?? []), right: Array.from(stored.right ?? []) })
    readonly property var centre: root.places.centre
    readonly property var right: root.places.right

    // Whether the drop changed anything; only a change is saved.
    function move(key: string, pill: string, beforeKey: var, visibleKeys: var): bool {
        const next = Places.move(root.places, key, pill, beforeKey, visibleKeys);
        if (JSON.stringify(next) === JSON.stringify(root.places))
            return false;
        stored.centre = next.centre;
        stored.right = next.right;
        view.writeAdapter();
        return true;
    }

    StateFile {
        id: view

        path: Paths.state("modules.json")
        printErrors: false

        JsonAdapter {
            id: stored

            property var centre: []
            property var right: []
        }
    }
}
