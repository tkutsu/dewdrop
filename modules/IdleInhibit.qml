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

    // Kept through a hot reload of the config. As a plain property it went
    // back to false on every reload, and with it the cup went back into the
    // drawer, so caffeine had to be found and switched on again by hand after
    // each edit. Only reloads: a restart still comes up with it off, which is
    // what a thing that holds the screen awake should do.
    PersistentProperties {
        id: state

        reloadableId: "caffeine"

        property bool active: false
    }

    readonly property bool active: state.active

    tooltip: active ? "Caffeine on" : "Caffeine off"
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
            state.active = !state.active;
    }
}
