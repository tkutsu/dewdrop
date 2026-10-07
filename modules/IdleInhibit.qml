import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// idle_inhibitor. Native wayland protocol, so unlike every other module here
// there is no process behind it at all.
BarItem {
    id: root

    readonly property bool active: Caffeine.active

    tooltip: active ? "Caffeine on" : "Caffeine off"
    // Only worth a place on the bar while it is holding the screen awake.
    quiet: !active

    // A pixel less air on the left than the row gives (user's call).
    Layout.leftMargin: -1

    // Bound rather than read once: the bar's window does not exist yet when
    // this item completes. One per bar is harmless; any of them holds it.
    IdleInhibitor {
        enabled: root.active
        window: QsWindow.window
    }

    Glyph {
        Layout.fillHeight: true
        text: root.active ? Theme.glyph.idleOn : Theme.glyph.idleOff
        fontSize: Theme.glyphSizeLarge + 1
    }

    actions: ({
            [Qt.LeftButton]: () => {
                Caffeine.active = !Caffeine.active;
            }
        })
}
