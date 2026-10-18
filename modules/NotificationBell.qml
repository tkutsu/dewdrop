import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components
import qs.services

// The bell: whether notifications are waiting, and the way into them. Its
// popup is the notification centre.
BarItem {
    id: root
    name: "Notifications"

    tooltip: Notifications.tooltip
    popup: NotificationsPopup {}
    property bool noticeMerging: false
    property bool handingOff: false
    property real handoffProgress: 1
    property real handoffX: 0
    folds: !handingOff
    foldDuration: handingOff ? 0 : Theme.foldMs
    implicitWidth: Math.round(_fullWidth * _fold * handoffProgress + _dither)
    // An empty bell goes in the drawer unless its popup is open. A notice
    // belongs to the bell only after its bead has crossed into its neighbour.
    readonly property int mergingCount: noticeMerging && Notifications.list.includes(Notifications.latest) ? 1 : 0
    quiet: Notifications.waiting <= mergingCount && !root.popupOpen

    BadgedGlyph {
        id: bellGlyph
        Layout.fillHeight: true
        opacity: root.handoffProgress
        transform: [
            ModuleIconScale { icon: bellGlyph },
            Translate { x: root.handoffX }
        ]
        glyph: Notifications.icon
        badge: Settings.badgeStyle("bell") === "hide" ? "" : Notifications.label
        dot: Settings.badgeStyle("bell") === "dot"
        underdot: Settings.badgeStyle("bell") === "underdot"
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
