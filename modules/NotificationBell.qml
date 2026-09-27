import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The bell: how many notifications are being kept, and the way into them.
BarItem {
    popup: NotificationsPopup {}
    // Do-not-disturb is something true right now even with nothing waiting,
    // so the bell only goes in the drawer when it is both empty and ordinary.
    quiet: Notifications.count === 0 && !Notifications.dnd

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Notifications.icon
        badge: Notifications.label
    }

    // Left opens the centre, the way the system's clock does, and right clears
    // everything in it. Do not disturb is the centre's header, beside its own
    // clear; middle pins the bell (BarItem.pinKey).
    actions: ({
            [Qt.LeftButton]: () => Notifications.toggleCentre(),
            [Qt.RightButton]: () => Notifications.clearAll()
        })
}
