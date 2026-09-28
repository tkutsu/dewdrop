pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The bar item whose popup a click has opened, or null. One at a time, the
// way a menu bar's menus are: opening one puts away whichever was up. Kept by
// components/BarItem.qml and the tray's icons; a click anywhere else closes it
// (Bar.qml for clicks on the bar, the Connections below for the rest).
Singleton {
    id: root

    property Item owner: null

    // Whether the popup now up took over from another one rather than opening
    // from nothing. The Mac draws a menu that the pointer slid across to at
    // once, without the reveal it gave the first: that one was the answer to
    // a click, and the rest are the same menu bar being browsed. Read by
    // components/Popup.qml as the new popup comes up.
    property bool switched: false

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
                root.dismiss();
        }
    }

    function set(item: Item, handover: bool): void {
        root.switched = handover;
        root.owner = item;
    }

    function toggle(item: Item): void {
        root.set(root.owner === item ? null : item, false);
    }

    // The pointer has arrived on `item`, which can open a popup of its own.
    // Once one popup is up the bar is being browsed rather than passed over,
    // so the popup follows the pointer, the way a menu bar's menus do after
    // the first click. With nothing up, a hover is only a hover.
    function browse(item: Item): void {
        if (root.owner !== null && root.owner !== item)
            root.set(item, true);
    }

    function close(item: Item): void {
        if (root.owner === item)
            root.set(null, false);
    }

    // Whichever is up: for a button in a popup that sends you somewhere else.
    function dismiss(): void {
        root.set(null, false);
    }
}
