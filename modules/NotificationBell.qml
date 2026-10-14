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
    // An empty bell goes in the drawer unless its popup is open. A notice
    // still on show beside the clock has not reached the bell yet.
    quiet: Notifications.waiting === 0 && !root.popupOpen

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
    // Middle pins the bell (BarItem.pinKey).
    actions: ({
            [Qt.RightButton]: () => {
                Notifications.clearAll();
                if (Notifications.count === 0)
                    OpenPopup.close(root);
            }
        })
}
