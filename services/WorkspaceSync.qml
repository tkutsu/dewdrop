pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Keeps Quickshell's workspaces in step with Hyprland's compaction
// (hypr/configs/workspaces.lua), which renumbers workspaces in place.
//
// Quickshell has no event for a renumbering, so its workspaces keep their old
// ids until a refresh, and a refresh cannot create the new ones: the window
// list then points at placeholder workspaces with id -1 until the next
// workspace refresh names them. `settled` is false from the renumbering until
// that has passed, so the bar can hold what it last drew rather than draw the
// muddle in between.
Singleton {
    id: root

    property bool settled: true
    property int tries: 0

    function placeholder(): bool {
        return Hyprland.workspaces.values.some(w => w.id === -1);
    }

    function unsettle(): void {
        if (root.settled)
            root.tries = 0;
        root.settled = false;
        refresh.restart();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "changeworkspaceid")
                root.unsettle();
        }
    }

    Connections {
        target: Hyprland.workspaces

        function onValuesChanged(): void {
            if (root.placeholder())
                root.unsettle();
        }
    }

    // Short, to gather the burst of renumberings one compaction sends.
    Timer {
        id: refresh
        interval: 10
        onTriggered: {
            root.tries++;
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
            release.restart();
        }
    }

    // The replies are local and land within a few milliseconds. A placeholder
    // that outlives three refreshes is let through rather than held forever.
    Timer {
        id: release
        interval: 100
        onTriggered: {
            if (root.placeholder() && root.tries < 3)
                refresh.restart();
            else
                root.settled = true;
        }
    }
}
