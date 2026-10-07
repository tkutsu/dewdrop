pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Whether the settings window is up. The window itself is SettingsMenu
// (modules/), loaded by shell.qml while `active`; what it changes is
// Settings, through Settings.set().
Singleton {
    id: root

    property bool shown: false

    // Up, or still folding itself away.
    readonly property bool active: linger.active

    Linger {
        id: linger

        shown: root.shown
    }

    function toggle(): void {
        root.shown = !root.shown;
    }

    function hide(): void {
        root.shown = false;
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggle();
        }
    }
}
