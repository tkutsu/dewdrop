import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.src.core
import qs.src.components
import qs.src.services

// Unread mail, with the threads themselves in the popup. A click on the icon
// opens the mail popup, a right click Gmail itself.
BarItem {
    id: root

    name: "Mail"
    // #custom-email.loading { opacity: 0.55 }
    opacity: Email.stale ? Theme.dimOpacity : 1

    tooltip: Email.tooltip
    popup: EmailPopup {}
    quiet: Email.count === 0

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Email.icon
        alternates: [Theme.glyph.mailUnread, Theme.glyph.mailRead]
        glyphSize: Theme.glyphSizeLarge
        badge: Settings.badgeStyle("email") === "hide" ? "" : Email.label
        dot: Settings.badgeStyle("email") === "dot"
        underdot: Settings.badgeStyle("email") === "underdot"
    }

    // A card about several new mails was clicked: they are all here. One
    // Mail per bar, so the one on the focused screen answers.
    Connections {
        target: Email

        function onSummoned() {
            if (root.QsWindow.window?.screen?.name !== Hyprland.focusedMonitor?.name)
                return;
            OpenPopup.set(root);
        }
    }

    // Left is the popup (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Email.openInbox()
        })
}
