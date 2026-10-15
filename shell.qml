//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3

// Drive popup motion and fades at the display refresh rate. gtk3, because the
// session's qt6ct points Qt at a different icon theme from GTK's.
//
// Not Vulkan, though it rides out the wakes that hang GL in NVIDIA's EGL
// (qs-watchdog restarts the bar after those): every popup, tag and launcher
// window gets its own Vulkan device, and NVIDIA's vkDestroyDevice can spin
// 6-22 s on close while ~QQuickWindow holds the whole bar waiting.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.modules
import qs.services

ShellRoot {
    // The window list keeps itself current, but an XWayland window's class lives
    // in the IPC object beside it, which Quickshell only fills in on a refresh,
    // so a refresh after windows open: the workspace icons and the launcher read
    // the class from there.
    //
    // Debounced, so a burst asks once. A window that flaps (VLC opening a file
    // mapped and unmapped a dozen times in a second) otherwise fires a request
    // per open, and each Hyprland IPC request is a chance at Quickshell 0.3.2's
    // use-after-free: makeRequest deletes its socket inside that socket's own
    // readyRead. One such burst crashed the bar on 2026-10-12.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "openwindow")
                refreshToplevels.restart();
        }
    }

    Timer {
        id: refreshToplevels
        interval: 150
        onTriggered: Hyprland.refreshToplevels()
    }

    // Referenced here so compaction is followed whether or not a bar shows
    // workspaces: the wallpaper's pan reads them too.
    readonly property bool workspacesSettled: WorkspaceSync.settled

    Variants {
        // One bar per screen, rebuilt as monitors come and go — or only on the
        // ones settings.json names.
        model: Quickshell.screens.filter(s => Settings.screenOn(s.name))

        Bar {}
    }

    // Per screen for the same reason, and below everything else the shell puts
    // up: the wallpaper, an image or a flat colour, is drawn here.
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
