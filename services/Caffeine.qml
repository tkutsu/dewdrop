pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// The caffeine switch, one for the session so every bar's cup agrees. Each bar
// holds its own inhibitor bound to it (modules/IdleInhibit.qml): an inhibitor
// needs a window, and a bar's own follows that bar through hotplug and reload.
Singleton {
    id: root

    property alias active: stored.active

    // For the keybind (SUPER+J): the cup sits in the drawer while caffeine is
    // off, so the mouse way in is two clicks deep.
    //   qs ipc call caffeine toggle
    IpcHandler {
        target: "caffeine"

        function toggle(): void {
            root.active = !root.active;
        }
    }

    // Kept on disk, so it comes back as it was after a reload or a restart.
    // Read before the first bar asks, so the cup never leaves the bar and
    // comes back, and the screen is never let go in between.
    Component.onCompleted: file.text()

    FileView {
        id: file

        path: Paths.state("caffeine.json")
        blockLoading: true
        printErrors: false
        onAdapterUpdated: file.writeAdapter()

        JsonAdapter {
            id: stored

            property bool active: false
        }
    }
}
