pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import qs.src.services
import "../lib/Fuzzy.js" as Fuzzy

// The keybind cheatsheet under the ? mode: Hyprland's own list of binds, read
// each time the mode opens, so a bind added to the config shows up without a
// restart.
//
// A bind is listed by its description (`description = "…"` in hl.bind). The
// Lua config hands hyprctl a function or a registry number for everything
// else, so a bind without one has nothing to say about what it does.
Singleton {
    id: root

    // Rows to show, in the order the config declares them.
    property var binds: []
    // Binds left out for want of a description, counted for the note.
    property int undescribed: 0

    // Hyprland's modmask bits, in the order a shortcut is read out.
    readonly property var modifiers: [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]

    // Key names Hyprland keeps for config files, said the way a keycap does.
    readonly property var keyNames: ({
            "mouse:272": "Left Click",
            "mouse:273": "Right Click",
            "mouse:274": "Middle Click",
            mouse_down: "Scroll Down",
            mouse_up: "Scroll Up",
            mouse_left: "Scroll Left",
            mouse_right: "Scroll Right",
            Left: "←",
            Right: "→",
            Up: "↑",
            Down: "↓",
            Return: "Enter",
            space: "Space",
            apostrophe: "'",
            grave: "`",
            comma: ",",
            period: ".",
            slash: "/",
            backslash: "\\",
            minus: "-",
            equal: "=",
            semicolon: ";",
            bracketleft: "[",
            bracketright: "]",
            Print: "Print Screen"
        })

    function keyName(b) {
        if (b.catch_all)
            return "Any Key";
        const key = b.key || (b.keycode ? "code:" + b.keycode : "");
        // A mouse bind is a drag: Super + Left Click on its own would not
        // move anything.
        if (b.mouse && /^mouse:27[234]$/.test(key))
            return root.keyNames[key].replace("Click", "Drag");
        if (root.keyNames[key])
            return root.keyNames[key];
        if (key.length === 1)
            return key.toUpperCase();
        // XF86AudioRaiseVolume and Page_Up, as words.
        return key.replace(/^XF86/, "").replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2");
    }

    // One row per description and modifiers: the navigation binds come in
    // pairs (I and ←), and ten workspace binds can share one line.
    function parse(list) {
        const rows = [];
        const byId = {};
        let undescribed = 0;
        for (const b of list) {
            // Listeners riding along on a key (the bar's click events), not
            // shortcuts anyone presses for what they do.
            if (b.non_consuming)
                continue;
            if (!b.has_description || !b.description) {
                undescribed++;
                continue;
            }
            const id = [b.submap, b.description, b.modmask, b.release].join("\n");
            if (byId[id]) {
                byId[id].keys.push(root.keyName(b));
                continue;
            }
            byId[id] = {
                title: b.description,
                submap: b.submap,
                mods: root.modifiers.filter(([bit]) => b.modmask & bit).map(([, name]) => name),
                keys: [root.keyName(b)]
            };
            rows.push(byId[id]);
        }
        return {
            undescribed: undescribed,
            binds: rows.map(r => {
                const combo = r.mods.concat([r.keys.join(" / ")]).join(" + ");
                return {
                    // Named for where it lives, so it reads apart from the
                    // modes above it and "?hypr" narrows to the binds.
                    title: "Hyprland: " + r.title,
                    combo: r.submap ? r.submap + "  ·  " + combo : combo,
                    fields: Fuzzy.prepFields([[r.title, 1], [combo, 0.8], [r.submap, 0.6], ["Hyprland", 0.4]])
                };
            })
        };
    }

    // Narrowed and ranked once something is typed; the config's own order
    // otherwise, which is how its author grouped them.
    function results(query) {
        const terms = Fuzzy.prepTerms(query);
        const scored = [];
        root.binds.forEach((b, i) => {
            const m = terms.length ? Fuzzy.matchPrepped(terms, b.fields) : -i;
            if (m !== null)
                scored.push({ s: m, b: b });
        });
        if (terms.length)
            scored.sort((a, b) => b.s - a.s);
        const rows = scored.map(x => ({
                    kind: "keybind",
                    glyph: Theme.glyph.keyboard,
                    title: x.b.title,
                    subtitle: x.b.combo
                }));
        if (!terms.length && root.undescribed)
            rows.push(Launcher.noteRow(Theme.glyph.keyboard, root.undescribed === 1 ? "1 keybind has no description" : `${root.undescribed} keybinds have no description`, "Give hl.bind a description to list it"));
        return rows;
    }

    // Read on the way into the mode rather than on every keystroke in it.
    property bool inMode: false

    function route(inMode: bool): void {
        if (inMode && !root.inMode)
            hyprctl.running = true;
        root.inMode = inMode;
    }

    Process {
        id: hyprctl

        command: ["hyprctl", "binds", "-j"]
        property string last: ""

        stdout: StdioCollector {
            onStreamFinished: {
                // The same list again rebuilds nothing, so the selection holds.
                if (text === hyprctl.last)
                    return;
                try {
                    const parsed = root.parse(JSON.parse(text));
                    root.binds = parsed.binds;
                    root.undescribed = parsed.undescribed;
                    hyprctl.last = text;
                } catch (e) {
                    // Not Hyprland, or not a reply: leave the list it had.
                }
            }
        }
    }
}
