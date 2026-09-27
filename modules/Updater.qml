import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// custom/updater. The upgrade itself still runs taskbar-update.sh in a kitty
// window — that half of the script is the action, not bar plumbing.
BarItem {
    readonly property string scripts: Quickshell.env("HOME") + "/_scripts"

    popup: UpdatesPopup {}
    quiet: Updates.pending === 0

    // Dimmed until the first check has answered, and again while a refresh
    // is out — same treatment as mail and tasks.
    opacity: Updates.loaded && !Updates.loading ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Updates.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Updates.label
    }

    onClicked: function (mouse) {
        // No refresh here: the count rechecks itself every six hours and
        // after every upgrade (qs ipc call updates refresh).
        if (mouse.button === Qt.RightButton)
            Quickshell.execDetached(["kitty", "--title", "cleanup", "sh", "-c", scripts + "/cleanup.sh"]);
        else if (mouse.button === Qt.LeftButton)
            Quickshell.execDetached([scripts + "/taskbar-update.sh"]);
    }
}
