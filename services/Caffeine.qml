pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

// One session switch and inhibitor, attached to any remaining bar window.
Singleton {
    id: root
    property alias active: state.active
    property var windows: []

    PersistentProperties {
        id: state
        reloadableId: "caffeine"
        property bool active: false
    }

    function attach(window: var): void {
        if (window && !root.windows.includes(window))
            root.windows = root.windows.concat([window]);
    }

    function detach(window: var): void {
        root.windows = root.windows.filter(held => held !== window);
    }

    IdleInhibitor {
        enabled: root.active
        window: root.windows[0] ?? null
    }
}
