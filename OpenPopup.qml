pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The bar item whose popup a click has opened, or null. One at a time, the
// way a menu bar's menus are: opening one puts away whichever was up. Kept by
// components/BarItem.qml; a click anywhere else closes it (Bar.qml for clicks
// on the bar, the Connections below for the rest).
Singleton {
    id: root

    property Item owner: null

    // Layer surfaces hear nothing of clicks in other windows, so Hyprland
    // tells us: a non-consuming bind in hypr/configs/keybinds.lua emits
    // `custom>>click` on every press and still hands it to whatever was under
    // the pointer. A focus grab heard them too, but it ate the click that
    // ended it, so the first click on another window did not even focus it.
    // Clicks on a bar or in a popup are theirs to sort out.
    Connections {
        target: Hyprland
        enabled: root.owner !== null

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && PopupPointer.hovered === 0 && PopupPointer.bars === 0)
                root.owner = null;
        }
    }

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
