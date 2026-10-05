import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// What is on the list and what is late, as a count on the right pill.
//
// The badge counts incomplete tasks due today, overdue, or undated.
// Future-dated tasks remain available in the popup.
//
// Hidden entirely until Google Tasks is connected: a machine that has never run
// gtasks-setup is not a machine with an empty task list, and an icon for
// something that was never set up is one more thing to wonder about.
BarItem {
    id: root

    present: Tasks.configured
    quiet: Tasks.count === 0

    tooltip: Tasks.tooltip
    popup: TasksPopup {}

    // Same treatment the mail module gets, and for the same reason: a count of
    // zero because nothing has come back yet must not read as a clear list.
    opacity: Tasks.stale ? Theme.dimOpacity : 1

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Tasks.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Tasks.label
    }

    // Left is the popup (BarItem.popupButton).
    actions: ({
            // The site rather than one of the PWA wrappers beside it: there is
            // no Google Tasks web app installed here, and a wrapper round an
            // app id nobody has is a launcher that silently does nothing.
            [Qt.RightButton]: () => {
                OpenPopup.dismiss();
                Quickshell.execDetached(["xdg-open", "https://tasks.google.com/"]);
            }
        })
}
