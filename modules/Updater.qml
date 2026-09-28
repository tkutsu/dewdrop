import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/updater. The upgrade itself still runs taskbar-update.sh in a kitty
// window — that half of the script is the action, not bar plumbing.
BarItem {

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

    // Left is the popup (BarItem.popupButton). Cleaning up is the button at
    // the foot of it, not a click.
    actions: ({
            [Qt.RightButton]: () => Updates.refresh()
        })
}
