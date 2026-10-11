pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Refresh after renumbering, then release the bar only when IPC models agree with the compositor.
Singleton {
    id: root

    property bool settled: true
    property int tries: 0
    property int generation: 0

    readonly property bool hasPlaceholder: Hyprland.workspaces.values.some(w => w.id === -1
        && (w.active || Hyprland.toplevels.values.some(t => t.workspace === w)))
    onHasPlaceholderChanged: if (hasPlaceholder) root.unsettle()

    function unsettle(): void {
        if (root.settled)
            root.tries = 0;
        root.generation++;
        root.settled = false;
        release.stop();
        refresh.restart();
    }

    // Compare IDs, window placement and monitor focus rather than assuming requests have finished.
    function agrees(workspaces, clients, monitors): bool {
        if (root.hasPlaceholder)
            return false;
        const actualWorkspaces = Hyprland.workspaces.values;
        const actualWindows = Hyprland.toplevels.values;
        if (!workspaces.every(expected => actualWorkspaces.some(w => w.id === expected.id && w.name === expected.name)))
            return false;
        // Public refreshes leave unused old IDs behind; they do not belong to the drawn strip.
        if (actualWorkspaces.some(w => !workspaces.some(expected => expected.id === w.id)
            && (w.active || w.lastIpcObject?.ispersistent || actualWindows.some(t => t.workspace === w))))
            return false;
        const windows = clients.filter(c => c.mapped);
        if (actualWindows.length !== windows.length || !windows.every(expected =>
            actualWindows.some(t => t.address === expected.address.replace(/^0x/, "")
                && t.workspace?.id === expected.workspace.id)))
            return false;
        const actualMonitors = Hyprland.monitors.values;
        if (!monitors.every(expected => actualMonitors.some(m => m.name === expected.name
            && m.activeWorkspace?.id === expected.activeWorkspace.id)))
            return false;
        const focused = monitors.find(m => m.focused);
        return !focused || Hyprland.focusedWorkspace?.id === focused.activeWorkspace.id;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "changeworkspaceid") {
                root.unsettle();
            } else if (!root.settled && ["createworkspacev2", "destroyworkspacev2", "renameworkspace",
                "movewindowv2", "openwindow", "closewindow", "workspacev2", "focusedmon",
                "moveworkspacev2", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name)) {
                root.unsettle();
            }
        }
    }

    Timer {
        id: refresh
        interval: root.tries < 3 ? 10 : 250
        onTriggered: {
            root.tries++;
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
            release.restart();
        }
    }

    Timer {
        id: release
        interval: 100
        onTriggered: {
            if (verify.running) {
                release.restart();
                return;
            }
            verify.generation = root.generation;
            verify.running = true;
            deadline.restart();
        }
    }

    // A read-only batch produces three JSON replies separated by blank lines.
    Process {
        id: verify
        property int generation: 0
        command: ["hyprctl", "-j", "--batch", "workspaces;clients;monitors"]
        stdout: StdioCollector { id: reply }
        onExited: code => {
            deadline.stop();
            if (root.settled)
                return;
            let valid = false;
            if (code === 0 && verify.generation === root.generation) {
                try {
                    const parts = reply.text.trim().split(/\n\s*\n/).map(part => JSON.parse(part));
                    valid = parts.length === 3 && root.agrees(parts[0], parts[1], parts[2]);
                } catch (error) {
                    valid = false;
                }
            }
            if (valid) {
                refresh.stop();
                release.stop();
                root.settled = true;
            } else {
                refresh.restart();
            }
        }
    }

    Timer {
        id: deadline
        interval: 1000
        onTriggered: verify.running = false
    }
}
