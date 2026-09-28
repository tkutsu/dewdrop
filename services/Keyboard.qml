pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs

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

    // Every layout the main keyboard cycles through, in its order, as
    // { name, short }: what the popup lists.
    property var layouts: []
    readonly property int index: layouts.findIndex(l => l.name === root.layout)

    // What the bar shows for each layout (layoutNames in settings.json), or
    // the first two letters of one it does not list.
    readonly property string short: root.abbreviate(layout)

    function abbreviate(name: string): string {
        return Settings.layoutNames[name] ?? name.slice(0, 2).toUpperCase();
    }

    function select(i: int): void {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "current", String(i)]);
    }

    // Hyprland reports the layouts as xkb's codes (us,gr) and names only the
    // active one, so the others are looked up in xkb's own list of what each
    // code and variant is called — the same names active_keymap gives.
    property var xkbNames: ({})

    FileView {
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        printErrors: false
        onLoaded: {
            const names = {};
            let section = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("!")) {
                    section = line.slice(1).trim();
                    continue;
                }
                const m = line.match(/^\s+(\S+)\s+(.+)$/);
                if (!m)
                    continue;
                if (section === "layout")
                    names[m[1]] = m[2];
                else if (section === "variant") {
                    // "  colemak_dh_ortho us: English (Colemak-DH Ortholinear)"
                    const v = m[2].match(/^(\S+): (.+)$/);
                    if (v)
                        names[v[1] + "(" + m[1] + ")"] = v[2];
                }
            }
            root.xkbNames = names;
        }
    }

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

        onExited: if (root.again) {
            root.again = false;
            query.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let devices;
                try {
                    devices = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const main = devices.keyboards?.find(k => k.main);
                if (!main)
                    return;
                root.mainKeyboard = main.name;
                root.layout = main.active_keymap;
                const variants = main.variant.split(",");
                root.layouts = main.layout.split(",").map((code, i) => {
                    const variant = variants[i] ?? "";
                    const name = i === main.active_layout_index ? main.active_keymap : root.xkbNames[`${code}(${variant})`] ?? root.xkbNames[code] ?? code.toUpperCase();
                    return {
                        name: name,
                        short: root.abbreviate(name)
                    };
                });
            }
        }
    }

    // A refresh asked for mid-query runs once that one is done, since what it
    // was asked for may have changed under the query.
    property bool again: false

    function refresh() {
        if (query.running)
            root.again = true;
        else
            query.running = true;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // A reload can change which layouts there are.
            if (event.name === "configreloaded") {
                root.refresh();
                return;
            }
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
            if (parts[0] !== root.mainKeyboard)
                return;
            root.layout = parts[1];
            // A layout the list names differently from xkb's list: ask
            // Hyprland, which names the active one itself.
            if (root.index < 0)
                root.refresh();
        }
    }

    // The list can come back before xkb's names have been read, in which case
    // it is only codes; ask again once they are here.
    onXkbNamesChanged: refresh()
    Component.onCompleted: refresh()
}
