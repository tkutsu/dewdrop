//@ pragma Env QSG_RENDER_LOOP=threaded

// Drive popup motion and fades at the display refresh rate.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.modules
import qs.services

ShellRoot {
    // The window list keeps itself current, but an XWayland window's class lives
    // in the IPC object beside it, which Quickshell only fills in on a refresh,
    // so a refresh on every window that opens: the workspace icons and the
    // launcher read the class from there.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "changeworkspaceid")
                workspaceRefresh.restart();
            if (event.name === "openwindow")
                Hyprland.refreshToplevels();
        }
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged(): void {
            if (Hyprland.workspaces.values.some(workspace => workspace.id === -1))
                workspaceRefresh.restart();
        }
    }

    // Coalesce a compaction pass so workspace IDs, app membership and focus agree.
    Timer {
        id: workspaceRefresh
        interval: 50
        onTriggered: {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
        }
    }

    Variants {
        // One bar per screen, rebuilt as monitors come and go — or only on the
        // ones settings.json names.
        model: Quickshell.screens.filter(s => Settings.screenOn(s.name))

        Bar {}
    }

    // Per screen for the same reason, and below everything else the shell puts
    // up: images crossfade here, and solid colours follow their daily drift.
    Variants {
        model: Quickshell.screens

        Backdrop {}
    }

    // One menu for the whole session rather than one per screen; it picks the
    // focused monitor itself. Loaded only while it is up, so an overlay layer
    // with exclusive keyboard focus does not sit there all session.
    //
    // Off `active` rather than `shown` because the menu animates itself shut and
    // has to still be here while it does — see services/Power.qml.
    LazyLoader {
        active: Power.active

        PowerMenu {}
    }

    // Same treatment as the power menu, and for the same two reasons: nothing
    // holds exclusive keyboard focus while the launcher is closed, and there is
    // no screen-sized click target over the desktop the rest of the time.
    //
    // The window is normally rebuilt on each open, but not always: a reopen
    // inside its own closing animation gets the same window back, so clearing
    // the query line is LauncherMenu.qml's job rather than a side effect.
    LazyLoader {
        active: Launcher.active

        LauncherMenu {}
    }

    // The settings window, on the same terms as the launcher.
    LazyLoader {
        active: Preferences.active

        SettingsMenu {}
    }

}
