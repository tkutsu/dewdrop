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
    property bool switched: false
    property int browseDelayMs: 300
    property Item _pending: null
    onOwnerChanged: root.cancelBrowse()

    // A launcher action asks the chosen screen's bar for its existing popup.
    signal controlRequested(key: string, screenName: string)

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

    function set(item: Item): void {
        root.switched = root.owner !== null && item !== null && root.owner !== item;
        root.cancelBrowse();
        root.owner = item;
    }

    function toggle(item: Item): void {
        root.set(root.owner === item ? null : item);
    }

    // Browse only after resting on another popup's button. Leaving cancels
    // that button's request; entering another one starts a fresh wait.
    // With nothing open, hovering still only shows a tooltip.
    function browse(item: Item, hovered: bool): void {
        if (!hovered) {
            if (root._pending === item)
                root.cancelBrowse();
            return;
        }
        root.cancelBrowse();
        if (root.owner === null || root.owner === item)
            return;
        root._pending = item;
        browseDelay.restart();
    }

    function cancelBrowse(): void {
        browseDelay.stop();
        root._pending = null;
    }

    Timer {
        id: browseDelay
        interval: root.browseDelayMs
        onTriggered: {
            if (root.owner !== null && root._pending !== null)
                root.set(root._pending);
            else
                root.cancelBrowse();
        }
    }

    function close(item: Item): void {
        if (root._pending === item)
            root.cancelBrowse();
        if (root.owner === item)
            root.set(null);
    }

    // Whichever is up: for a button in a popup that sends you somewhere else.
    function dismiss(): void {
        root.set(null);
    }
}
