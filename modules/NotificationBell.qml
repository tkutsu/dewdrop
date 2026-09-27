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

    // Left opens the centre, the way the system's clock does, and right is do
    // not disturb. Clearing everything is the centre's header, beside its own
    // do-not-disturb; middle pins the bell (BarItem.pinKey).
    onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton)
            Notifications.setDnd(!Notifications.dnd);
        else if (mouse.button === Qt.LeftButton)
            Notifications.toggleCentre();
    }
}
