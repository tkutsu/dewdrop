//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env __NV_DISABLE_EXPLICIT_SYNC=1
//@ pragma Env QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3
//@ pragma IconTheme themis

// Drive popup motion and fades at the display refresh rate. gtk3, because the
// session's qt6ct points Qt at a different icon theme from GTK's.
//
// App icons are Themis's, whatever the system's theme, because the bar is drawn
// for them; without it installed, Qt falls back to hicolor, and Settings >
// Appearance says where to get it. Another theme's name here uses that one.
//
// No NVIDIA explicit sync: on some wakes nvidia-drm logs "Failed to register
// auto-value-update ... sync FD semaphore surface" and the render thread hung in
// NVIDIA's EGL, freezing the bar for seconds or for good. None since this
// pragma (2026-11-10). Drop it once NVIDIA fixes the driver.
//
// Not Vulkan, though it rode out those wakes: every popup, tag and launcher
// window gets its own Vulkan device, and NVIDIA's vkDestroyDevice can spin
// 6-22 s on close while ~QQuickWindow holds the whole bar waiting.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.src.core
import qs.src.bar
import qs.src.modules
import qs.src.services

ShellRoot {
    // The window list keeps itself current, but an XWayland window's class lives
    // in the IPC object beside it, which Quickshell only fills in on a refresh,
    // so a refresh after windows open: the workspace icons and the launcher read
    // the class from there. And after windows close: Hyprland swallows a
    // terminal as the app opens and gives it back as the app closes, with no
    // event of its own, and `hidden` (Workspaces.qml leaves such a window off
    // the strip) comes only with a fresh `hyprctl clients`.
    //
    // Once for the whole shell, however many bars, and debounced, so a burst
    // asks once. A window that flaps (VLC opening a file
    // mapped and unmapped a dozen times in a second) otherwise fires a request
    // per open, and each Hyprland IPC request is a chance at Quickshell 0.3.2's
    // use-after-free: makeRequest deletes its socket inside that socket's own
    // readyRead. One such burst crashed the bar on 2026-10-12.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow")
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

    // Referenced here so the programs are looked for at startup: a singleton waits
    // to be asked, and the first thing to ask may be choosing Shut Down.
    readonly property var programsFound: Tools.found

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

    // Loaded only while it is up, for two reasons: nothing holds keyboard
    // focus while the launcher is closed, and there is no screen-sized click
    // target over the desktop the rest of the time.
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

    // Referenced here so the bar registers as the session's polkit agent at
    // startup rather than when something first reads Polkit.
    readonly property bool polkitAgent: Polkit.registered

    // The password panel, up for as long as a request is.
    LazyLoader {
        active: Polkit.shown

        AuthDialog {
            flow: Polkit.flow
        }
    }

    // The lock screen. Not lazy: the session lock must be in the same place
    // after a reload to carry a held lock over (LockScreen.qml).
    LockScreen {}

}
