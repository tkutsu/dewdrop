import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules
import qs.services

ShellRoot {
    // The window list keeps itself current, but floating and fullscreen live in
    // the IPC object beside it, which Quickshell only fills in on a refresh —
    // so a refresh on the two events that change one, and on every window
    // that opens. Without that last one a window that opened floating had no
    // IPC object to say so, counted as tiled, and a lone dialog on an empty
    // workspace turned the bar into one strip until something else refreshed.
    //
    // Here rather than in Bar.qml, which is built once per monitor: the refresh
    // is one `hyprctl clients` for the whole session, and a copy per bar only
    // buys a second one of those every time a window is floated.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "changefloatingmode" || event.name === "fullscreen")
                Hyprland.refreshToplevels();
        }
    }

    Variants {
        // "all-outputs": true — one bar per screen, rebuilt as monitors come
        // and go.
        model: Quickshell.screens

        Bar {}
    }

    // Per screen for the same reason, and below everything else the shell puts
    // up: this is the wallpaper when the wallpaper is a colour.
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

    // The notification centre, the same way again: a full-screen surface that
    // holds the keyboard for Escape, so it only exists while it is open.
    LazyLoader {
        active: Notifications.centreActive

        NotificationCentre {}
    }
}
