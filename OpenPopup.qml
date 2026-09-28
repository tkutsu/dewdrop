pragma Singleton

import QtQuick
import Quickshell

// The bar item whose popup a click has opened, or null. One at a time, the
// way a menu bar's menus are: opening one puts away whichever was up. Kept by
// components/BarItem.qml; a click anywhere else closes it (Bar.qml, and the
// focus grab in BarItem for clicks off the bar).
Singleton {
    id: root

    property Item owner: null

    function toggle(item: Item): void {
        root.owner = root.owner === item ? null : item;
    }

    function close(item: Item): void {
        if (root.owner === item)
            root.owner = null;
    }

    // Whichever is up: for a button in a popup that sends you somewhere else.
    function dismiss(): void {
        root.owner = null;
    }
}
