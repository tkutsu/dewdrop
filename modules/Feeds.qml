import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// New videos and stories (services/Feeds.qml), listed in the popup. A right
// click opens the YouTube subscriptions page.
BarItem {
    name: "Feeds"

    tooltip: Feeds.tooltip
    popup: FeedsPopup {}
    quiet: Feeds.count === 0

    // Dimmed until the first read has answered, as mail and tasks are.
    opacity: Feeds.stale ? Theme.dimOpacity : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Feeds.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Settings.badgeStyle("feeds") === "hide" ? "" : Feeds.label
        dot: Settings.badgeStyle("feeds") === "dot"
        underdot: Settings.badgeStyle("feeds") === "underdot"
    }

    // Left is the popup (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Feeds.openApp()
        })
}
