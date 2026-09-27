import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// What is on the list and what is late, as a count on the right pill.
//
// It counts today and overdue and nothing else. A badge that stood for
// everything ever written down would read 47 for months and never change, and a
// number that never changes is one nobody looks at; these two are the ones with
// a day attached to them, so the badge moves when the day does.
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
    opacity: Tasks.loaded ? 1 : Theme.dimOpacity

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Tasks.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Tasks.label
    }

    actions: ({
            [Qt.LeftButton]: () => Launcher.openWith(Launcher.taskPrefix),
            // The site rather than one of the PWA wrappers beside it: there is
            // no Google Tasks web app installed here, and a wrapper round an
            // app id nobody has is a launcher that silently does nothing.
            [Qt.RightButton]: () => Quickshell.execDetached(["xdg-open", "https://tasks.google.com/"])
        })
}
