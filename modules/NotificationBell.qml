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

    // Left opens the centre, the way the system's clock does. Middle is do not
    // disturb and right clears everything, as they were under swaync.
    onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton)
            Notifications.clearAll();
        else if (mouse.button === Qt.MiddleButton)
            Notifications.setDnd(!Notifications.dnd);
        else
            Notifications.toggleCentre();
    }
}
