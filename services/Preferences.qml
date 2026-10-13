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
    readonly property int dismissMs: 200

    // Up, or still blurring and fading away.
    readonly property bool active: linger.active

    Linger {
        id: linger

        shown: root.shown
        hold: root.dismissMs
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
