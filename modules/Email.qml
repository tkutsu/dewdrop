import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// Unread mail, with the threads themselves in the popup. A click on the icon
// opens the mail popup; selecting a row opens its thread in Gmail.
BarItem {
    // #custom-email.loading { opacity: 0.55 }
    opacity: Email.stale ? Theme.dimOpacity : 1

    tooltip: Email.tooltip
    popup: EmailPopup {}
    quiet: Email.count === 0

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Email.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Email.label
    }

    // Left is the popup (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Email.refresh()
        })
}
