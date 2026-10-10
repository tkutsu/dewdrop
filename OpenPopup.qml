pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

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
        enabled: root.owner !== null || root.selected !== null

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && PopupPointer.hovered === 0 && PopupPointer.bars === 0)
                root.dismiss();
            // Selection mode ends when another window takes focus, as one
            // does when Return on a workspace brings its window forward. Not
            // on the event alone: Hyprland sends it again for the same window
            // every time its title changes, and a terminal with a spinner in
            // its title changes it several times a second.
            else if (event.name === "activewindowv2" && root.selected !== null && event.data !== root._window)
                root.dismiss();
        }
    }

    function set(item: Item): void {
        root.switched = root.owner !== null && item !== null && root.owner !== item;
        root.cancelBrowse();
        // A popup the pointer browses to takes the selection with it, and
        // the keys are back on the bar whichever popup comes or goes.
        if (root.selected !== null && item !== null)
            root.selected = item;
        root.inPopup = false;
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
        root.deselect();
        root.set(null);
    }

    // --- selection mode ------------------------------------------------------
    // The bar walked from the keyboard, the way a Mac's menu bar is from
    // Ctrl+F2. It starts on the calendar with its popup open; Left and Right
    // go from item to item, opening each one's popup the way browsing with
    // the pointer does, Down goes into the popup and Up from its top row
    // comes back out, Return presses an item with no popup, and Escape ends
    // it. So does a click anywhere or another window taking focus.
    //
    // An item takes part by having a `keyPress` function, or `keyOpens` for
    // one whose popup opens on it (BarItem, the tray's icons, each
    // workspace). Bar.qml walks them and takes the keyboard.
    property Item selected: null
    // Whether the keys are down in the selected item's popup.
    property bool inPopup: false

    signal selectRequested(screenName: string)

    // The window that had focus when selection mode started.
    property string _window: ""

    function select(item: Item): void {
        if (root.selected === null)
            root._window = Hyprland.activeToplevel?.address ?? "";
        // Selected first, so the bar holds on to the keyboard while the
        // popup changes hands.
        root.selected = item;
        root.set(item?.keyOpens ? item : null);
    }

    function deselect(): void {
        root.selected = null;
        root.inPopup = false;
    }

    // Down into the open popup, onto its first control. Not when it has none
    // to go to, or is not up yet; open again if it has been put away (a tray
    // menu goes once one of its items is chosen).
    function enter(): void {
        if (root.owner !== root.selected) {
            root.set(root.selected);
            return;
        }
        const top = root.keyed[root.keyed.length - 1];
        if (!top)
            return;
        root.inPopup = true;
        top.key({ key: Qt.Key_Down });
        if (!top.keyItem)
            root.inPopup = false;
    }

    // Up past the popup's top row: back to the bar. Only from the popup
    // itself, not a tray submenu over it.
    function leave(popup: var): bool {
        if (!root.inPopup || root.keyed[0] !== popup)
            return false;
        popup.setKey(null);
        root.inPopup = false;
        return true;
    }

    IpcHandler {
        target: "bar"

        // On the focused screen's bar, or off again (Super+Ctrl+J).
        function select(): void {
            if (root.selected !== null)
                root.dismiss();
            else
                root.selectRequested(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    // The popups the keyboard drives, innermost last: an open popup, and a
    // tray menu's submenus over it. The bar that owns the open popup takes
    // the keyboard (Bar.qml) and hands each key to the last of these, so the
    // arrows walk the submenu a Right opened rather than the menu under it.
    property var keyed: []

    function addKeys(popup: var): void {
        if (!root.keyed.includes(popup))
            root.keyed = [...root.keyed, popup];
    }

    function dropKeys(popup: var): void {
        if (root.keyed.includes(popup))
            root.keyed = root.keyed.filter(p => p !== popup);
    }

    // Whether the key was taken.
    function key(event: var): bool {
        const top = root.keyed[root.keyed.length - 1];
        return top ? top.key(event) : false;
    }
}
