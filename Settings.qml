pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything that differs from one machine to the next: which monitors and
// modules, the clock's format, fonts, the apps the bar opens, where the
// wallpapers and the music are.
//
// Two files beside shell.qml. settings.default.json is in the repo: every
// setting with its default and a comment on what it does, which makes it the
// documentation as well as the fallback. settings.json is the machine's own
// (git ignores it), starts as a copy of the defaults, and wins key by key.
// Both may carry // comments and trailing commas, which are stripped before
// parsing. Edits are picked up on save.
//
// At the root rather than in services/ because BarItem and Theme read it (see
// Popup.qml's note on why components cannot import qs.services).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    property var defaults: ({})
    property var user: ({})
    readonly property var values: Object.assign({}, root.defaults, root.user)

    // --- values --------------------------------------------------------------
    readonly property var screens: root.values.screens ?? []
    readonly property var modules: root.values.modules ?? ({})
    readonly property string timeFormat: root.values.timeFormat ?? "HH:mm"
    readonly property var layoutNames: root.values.layoutNames ?? ({})
    readonly property string font: root.values.font ?? ""
    readonly property string monoFont: root.values.monoFont ?? ""
    readonly property string terminal: root.values.terminal ?? "kitty"
    readonly property string editor: root.values.editor || Quickshell.env("EDITOR") || "nvim"
    readonly property string fileManager: root.values.fileManager ?? "xdg-open"
    readonly property string wallpaperDir: root.expand(root.values.wallpaperDir ?? "")
    readonly property string musicDir: root.expand(root.values.musicDir ?? "").replace(/\/?$/, "/")
    readonly property string mpdSocket: root.expand(root.values.mpdSocket ?? "")

    // A module off is gone from the bar, not put in the drawer. Keyed as
    // BarItem.settingsKey; one the file does not mention is on.
    function moduleOn(key: string): bool {
        return key === "" || root.modules[key] !== false;
    }

    function screenOn(name: string): bool {
        return root.screens.length === 0 || root.screens.includes(name);
    }

    // "~" and "$XDG_RUNTIME_DIR" as the shell would read them.
    function expand(path: string): string {
        return path.replace(/^~(?=\/|$)/, root.home).replace("$XDG_RUNTIME_DIR", Quickshell.env("XDG_RUNTIME_DIR"));
    }

    // A command in the chosen terminal. `--title=` in the joined form every
    // common terminal accepts, and a held window is a prompt rather than a
    // flag, because only kitty has --hold.
    function inTerminal(command: var, title: string, hold: bool): var {
        const run = hold ? ["sh", "-c", '"$@"; printf "\\nPress Enter to close. "; read _', "sh", ...command] : command;
        return [root.terminal, ...(title ? ["--title=" + title] : []), "-e", ...run];
    }

    // --- the files -----------------------------------------------------------
    // JSON plus // comments and trailing commas. The comment stripper walks
    // the text rather than using a regex so that a "//" inside a string — a
    // URL, say — is left alone.
    function parse(text: string): var {
        let out = "";
        let quoted = false;
        for (let i = 0; i < text.length; i++) {
            const c = text[i];
            if (quoted) {
                out += c;
                if (c === "\\")
                    out += text[++i] ?? "";
                else if (c === '"')
                    quoted = false;
            } else if (c === '"') {
                quoted = true;
                out += c;
            } else if (c === "/" && text[i + 1] === "/") {
                while (i + 1 < text.length && text[i + 1] !== "\n")
                    i++;
            } else {
                out += c;
            }
        }
        return JSON.parse(out.replace(/,(\s*[}\]])/g, "$1"));
    }

    // A file that does not parse keeps the last settings that did, and says
    // so where it will be seen: whoever saved it is looking at the screen.
    // Qt's JSON.parse names no line ("Parse error" and nothing else), so the
    // notice points at the edit instead.
    function load(view: var, name: string): var {
        try {
            return root.parse(view.text());
        } catch (e) {
            console.warn(`${name}: ${e.message}`);
            Quickshell.execDetached(["notify-send", "-a", "Bar", `${name} did not parse`, "Look for a missing comma or quote in the last change. The bar keeps the settings it had."]);
            return null;
        }
    }

    // Both read synchronously the first time they are asked for, so the bar
    // is built on the real values rather than drawn once on none and again a
    // moment later — and the wallpaper is never looked for in the wrong place.
    FileView {
        id: defaultFile

        path: Quickshell.shellPath("settings.default.json")
        blockLoading: true
        onLoaded: root.defaults = root.load(defaultFile, "settings.default.json") ?? root.defaults
    }

    FileView {
        id: userFile

        path: Quickshell.shellPath("settings.json")
        blockLoading: true
        printErrors: false
        // watchChanges only signals: text() goes on returning what was read
        // at startup, and `loaded` never fires again, until reload().
        watchChanges: true
        onFileChanged: userFile.reload()
        onLoaded: root.user = root.load(userFile, "settings.json") ?? root.user
        // First run: the defaults, comments and all, as the file to edit.
        onLoadFailed: userFile.setText(defaultFile.text())
    }
}
