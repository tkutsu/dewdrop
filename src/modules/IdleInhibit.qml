import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.src.core
import qs.src.services
import qs.src.components

// idle_inhibitor. Native wayland protocol, so unlike every other module here
// there is no process behind it at all.
BarItem {
    id: root
    name: "Caffeine"

    readonly property bool active: Caffeine.active

    tooltip: !active ? "Caffeine off" : Caffeine.endsAt ? `Caffeine on until ${Caffeine.endsAt}` : "Caffeine on"
    popup: CaffeinePopup {}
    // Only worth a place on the bar while it is holding the screen awake.
    quiet: !active

    // A pixel less air on the left than the row gives (user's call).
    trimLeft: 1

    // Bound rather than read once: the bar's window does not exist yet when
    // this item completes. One per bar is harmless; any of them holds it.
    IdleInhibitor {
        enabled: root.active
        window: QsWindow.window
    }

    Glyph {
        Layout.fillHeight: true
        text: root.active ? Theme.glyph.idleOn : Theme.glyph.idleOff
        alternates: [Theme.glyph.idleOn, Theme.glyph.idleOff]
        fontSize: Theme.glyphSizeLarge
    }

    // Left is the popup (BarItem.popupButton); right flips it.
    actions: ({
            [Qt.RightButton]: () => Caffeine.toggle()
        })
}
