import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.components

// idle_inhibitor. Native wayland protocol, so unlike every other module here
// there is no process behind it at all.
BarItem {
    id: root

    property bool active: false

    tooltip: active ? "Caffeine mode on" : "Caffeine mode off"
    // Only worth a place on the bar while it is holding the screen awake.
    quiet: !active

    IdleInhibitor {
        enabled: root.active
        window: QsWindow.window
    }

    Glyph {
        Layout.fillHeight: true
        text: root.active ? Theme.glyph.idleOn : Theme.glyph.idleOff
        fontSize: Theme.glyphSizeLarge
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            root.active = !root.active;
    }
}
