pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Where each module stands while the drawer is closed, in either pill,
// keyed by BarItem.pinKey (a tray icon by "tray:<its id>"). Three ways:
//
//   auto    the module's own `quiet` decides: out while it has something
//           to say, in the drawer while it does not. No entry.
//   pinned  out, whatever it has to say. `true`, and what a middle
//           click on the module toggles.
//   drawer  kept in, even with something to say (night mode on, but out of
//           sight). `false`. Opening the drawer still shows it.
//
// Kept across restarts, and at the root for use by BarItem and the drawer.
Singleton {
    id: root

    property alias pins: stored.pins

    function pinned(key: string): bool {
        return root.pins[key] === true;
    }

    function kept(key: string): bool {
        return root.pins[key] === false;
    }

    function mode(key: string): string {
        return root.pinned(key) ? "pinned" : root.kept(key) ? "drawer" : "auto";
    }

    function setMode(key: string, mode: string): void {
        const pins = Object.assign({}, root.pins);
        if (mode === "pinned")
            pins[key] = true;
        else if (mode === "drawer")
            pins[key] = false;
        else
            delete pins[key];
        root.pins = pins;
        // Let the new mode propagate before persisting the adapter.
        Qt.callLater(file.writeAdapter);
    }

    // The middle click: pinned goes back to auto, anything else is pinned.
    function toggle(key: string): void {
        root.setMode(key, root.pinned(key) ? "auto" : "pinned");
    }

    FileView {
        id: file

        path: Paths.state("drawer.json")
        printErrors: false
        onLoadFailed: file.writeAdapter()

        JsonAdapter {
            id: stored

            property var pins: ({})
        }
    }
}
