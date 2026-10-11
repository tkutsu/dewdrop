import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components
import qs.services

// The bell: how many notifications are being kept, and the way into them. Its
// popup is the notification centre.
BarItem {
    id: root
    name: "Notifications"

    tooltip: Notifications.tooltip
    popup: NotificationsPopup {}
    // Do-not-disturb is something true right now even with nothing waiting,
    // so the bell only goes in the drawer when it is both empty and ordinary —
    // and never while its popup hangs off it. Empty means nothing waiting: a
    // notice still on show beside the clock has not reached the bell yet.
    quiet: Notifications.waiting === 0 && !Notifications.dnd && !root.popupOpen

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Notifications.icon
        badge: Notifications.label
    }

    // The centre asked for from elsewhere: the notice beside the clock, or
    // `qs ipc call notifications toggle|latest`. One bell per bar, so the one
    // on the focused screen answers.
    Connections {
        target: Notifications

        function onCentreRequested(toggle: bool): void {
            if (root.QsWindow.window?.screen?.name !== Hyprland.focusedMonitor?.name)
                return;
            if (toggle)
                root.togglePopup();
            else
                OpenPopup.owner = root;
        }
    }

    // Left is the popup (BarItem.popupButton), and right clears everything.
    // Do not disturb is the popup's header, beside its own clear; middle pins
    // the bell (BarItem.pinKey).
    actions: ({
            [Qt.RightButton]: () => {
                Notifications.clearAll();
                if (Notifications.count === 0)
                    OpenPopup.close(root);
            }
        })
}
