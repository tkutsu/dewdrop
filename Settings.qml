pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything that differs from one machine to the next: which monitors,
// the clock's format, fonts, the apps the bar opens, where the
// wallpapers and the music are.
//
// Two files beside shell.qml. settings.default.json is in the repo: every
// setting with its default and a comment on what it does, which makes it the
// documentation as well as the fallback. settings.json is the machine's own
// (git ignores it), starts as a copy of the defaults, and wins key by key.
// Both may carry // comments and trailing commas, which are stripped before
// parsing. Edits are picked up on save.
//
// Shared settings live at the root for use by components and services.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    property var defaults: ({})
    property var user: ({})
    readonly property var values: Object.assign({}, root.defaults, root.user)

    // --- values --------------------------------------------------------------
    readonly property var screens: root.values.screens ?? []
    readonly property bool groupWindows: root.values.groupWindows ?? true
    readonly property string timeFormat: root.values.timeFormat ?? "HH:mm"
    readonly property var layoutNames: root.values.layoutNames ?? ({})
    readonly property string font: root.values.font ?? ""
    readonly property string monoFont: root.values.monoFont ?? ""
    readonly property string terminal: root.values.terminal ?? "kitty"
    readonly property string editor: root.values.editor || Quickshell.env("EDITOR") || "nvim"
    readonly property string fileManager: root.values.fileManager ?? "xdg-open"
    readonly property var hiddenApps: root.values.hiddenApps ?? ["blueman-adapters", "libreoffice-startcenter"]
    readonly property string wallpaperDir: root.expand(root.values.wallpaperDir ?? "")
    readonly property real wallpaperParallaxZoom: Math.max(1, Number(root.values.wallpaperParallaxZoom ?? 1.08) || 1)
    readonly property string musicDir: root.expand(root.values.musicDir ?? "").replace(/\/?$/, "/")
    readonly property string mpdSocket: root.expand(root.values.mpdSocket ?? "")
    readonly property string scriptsDir: root.expand(root.values.scriptsDir ?? "")

    // The settings window's way in: one key into settings.json. The file is
    // written back whole as plain JSON, so comments typed into it by hand go;
    // every setting is documented in settings.default.json instead. Whatever
    // the file already said wins over the defaults as before, and the watcher
    // below reads the new file back like any other edit.
    function set(key: string, value: var): void {
        const user = Object.assign({}, root.user, { [key]: value });
        root.user = user;
        userFile.setText("// This machine's settings over settings.default.json, which documents\n// each one. The settings window (the gear) rewrites this file.\n" + JSON.stringify(user, null, 4) + "\n");
    }

    // A list setting with `item` put in or taken out.
    function toggleIn(key: string, item: string): void {
        const list = Array.from(root.values[key] ?? []);
        const at = list.indexOf(item);
        if (at >= 0)
            list.splice(at, 1);
        else
            list.push(item);
        root.set(key, list);
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

    // A Google web app through its PWA wrapper in scriptsDir when the machine
    // has one, the default browser when it does not. Without a url the
    // wrapper focuses the app where it was left, and the browser opens `home`.
    function webApp(script: string, url: string, home: string): var {
        return ["sh", "-c", 'w=$1 page=$2; shift 2; [ -x "$w" ] && exec "$w" "$@"; exec xdg-open "$page"', "sh", `${root.scriptsDir}/${script}`, url || home, ...(url ? [url] : [])];
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
            } else if (c === "}" || c === "]") {
                out = out.replace(/,\s*$/, "");
                out += c;
            } else {
                out += c;
            }
        }
        return JSON.parse(out);
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

    // Both read here, before anything that asked for a setting has finished
    // being built, so the bar starts on the real values rather than on none
    // and again a moment later. `loaded` is too late for that: it comes after
    // the first reader has already been handed "" — the wallpaper service
    // scanned `find ""` at boot, found nothing, and restored nothing. text()
    // on a blocking view reads the file on the spot instead. A missing
    // settings.json is left to onLoadFailed below rather than reported as
    // one that did not parse.
    Component.onCompleted: {
        root.defaults = root.load(defaultFile, "settings.default.json") ?? root.defaults;
        userFile.text();
        if (userFile.loaded)
            root.user = root.load(userFile, "settings.json") ?? root.user;
    }

    // After startup these keep the values current: an edit to settings.json
    // lands here.
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
