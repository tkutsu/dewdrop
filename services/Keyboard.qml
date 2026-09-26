pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Active keyboard layout. (Named Keyboard, not Layout: QtQuick.Layouts already
// owns `Layout` as an attached property on every item in the bar.)
//
// taskbar-lang.sh ran hyprctl once a second to catch a change that Hyprland
// already announces; here the `activelayout` event drives the read, so the
// module costs nothing while the layout sits still.
Singleton {
    id: root

    property string layout: ""
    // Which keyboard's layout the bar is showing. Read once at startup, because
    // the activelayout event names a keyboard and only the main one counts.
    property string mainKeyboard: ""

    readonly property var shortNames: ({
        "English (US)": "EN",
        "Greek": "GR",
        "English (Colemak-DH Ortholinear)": "EN-cmk",
        "Greek Colemak-DH": "GR-cmk",
        "Enthium": "EN-ent",
        "Grthium": "GR-ent"
    })

    readonly property string short: shortNames[layout] ?? layout

    // Not Hyprland.dispatch: `dispatch` is a Lua call now, and hl.dsp has no
    // xkb dispatcher to call. The top-level hyprctl command is the only way in,
    // and it is what the waybar module shelled out to anyway.
    function cycle(dir) {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "current", dir]);
    }

    function next() {
        cycle("next");
    }

    function prev() {
        cycle("prev");
    }

    Process {
        id: query
        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                let devices;
                try {
                    devices = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const main = devices.keyboards?.find(k => k.main);
                if (main) {
                    root.mainKeyboard = main.name;
                    root.layout = main.active_keymap;
                }
            }
        }
    }

    function refresh() {
        if (!query.running)
            query.running = true;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "activelayout")
                return;
            // The event carries KEYBOARDNAME,LAYOUTNAME, so the layout is
            // already here and the hyprctl round trip that used to answer this
            // is only needed to find out whose keyboard it is — once, at
            // startup. parse(2) splits on the first comma alone, so a layout
            // name keeps whatever punctuation it came with.
            if (!root.mainKeyboard) {
                root.refresh();
                return;
            }
            const parts = event.parse(2);
            if (parts[0] === root.mainKeyboard)
                root.layout = parts[1];
        }
    }

    Component.onCompleted: refresh()
}
