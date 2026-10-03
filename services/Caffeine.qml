pragma Singleton

import QtQuick
import Quickshell

// The caffeine switch, one for the session so every bar's cup agrees. Each bar
// holds its own inhibitor bound to it (modules/IdleInhibit.qml): an inhibitor
// needs a window, and a bar's own follows that bar through hotplug and reload.
Singleton {
    property alias active: state.active

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
}
