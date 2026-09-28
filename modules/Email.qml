import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// Unread mail, with the threads themselves in the popup. A click on the icon
// opens the inbox; a click on a row in the popup opens it to be read there.
BarItem {
    // #custom-email.loading { opacity: 0.55 }
    opacity: Email.loaded ? 1 : Theme.dimOpacity

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
