pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The few things that differ from one machine to the next: which modules the
// bar shows, where the wallpapers and the music are, what terminal to open,
// how the clock reads. Kept in settings.json beside shell.qml, which git
// ignores, and edited from the settings page (modules/SettingsPage.qml)
// rather than by hand.
//
// A path left empty means its default, so the file only ever holds what was
// actually changed, and a default moving later moves everyone who kept it.
//
// At the root rather than in services/ because BarItem reads it (see
// Popup.qml's note on why components cannot import qs.services).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // --- the page ------------------------------------------------------------
    property bool shown: false
    // Outlives `shown` by the length of the page's fold, like the centre.
    readonly property bool active: linger.active

    function toggle(): void {
        root.shown = !root.shown;
    }

    Linger {
        id: linger
        shown: root.shown
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggle();
        }
    }

    // --- modules -------------------------------------------------------------
    // Every module the bar can go without, keyed as BarItem.settingsKey, in the
    // order the page lists them. Off means gone from the bar, not put in the
    // drawer: the drawer is for things with nothing to say right now, and
    // this is for things this machine does not have.
    readonly property var modules: [
        { key: "music", name: "Music", note: "Now playing, from mpd" },
        { key: "email", name: "Mail", note: "Unread Gmail" },
        { key: "tasks", name: "Tasks", note: "Google Tasks" },
        { key: "updater", name: "Updates", note: "Pending pacman and AUR updates" },
        { key: "bell", name: "Notifications", note: "The notification centre" },
        { key: "satty", name: "Screenshot", note: "Annotate a screenshot with satty" },
        { key: "idle", name: "Caffeine", note: "Keep the screen awake" },
        { key: "wallpaper", name: "Wallpaper", note: "Cycle the wallpaper folder" },
        { key: "night", name: "Night mode", note: "Warm the screen" },
        { key: "sys", name: "System", note: "CPU, memory and temperatures" },
        { key: "tray", name: "Tray", note: "Apps' status icons" },
        { key: "audio", name: "Volume", note: "Output and level" },
        { key: "language", name: "Keyboard layout", note: "The current layout" }
    ]

    function moduleOn(key: string): bool {
        return key === "" || stored.modules[key] !== false;
    }

    function setModule(key: string, on: bool): void {
        const modules = Object.assign({}, stored.modules);
        if (on)
            delete modules[key];
        else
            modules[key] = false;
        root.set("modules", modules);
    }

    // --- values --------------------------------------------------------------
    readonly property bool clock24h: stored.clock24h

    readonly property string defaultTerminal: "kitty"
    readonly property string terminal: stored.terminal || root.defaultTerminal

    readonly property string defaultWallpaperDir: "~/Pictures/Wallpapers"
    readonly property string wallpaperDir: root.expand(stored.wallpaperDir || root.defaultWallpaperDir)

    // mpd's music_directory: the bar finds album covers beside the files.
    readonly property string defaultMusicDir: "~/Music"
    readonly property string musicDir: root.expand(stored.musicDir || root.defaultMusicDir).replace(/\/?$/, "/")

    // The bar speaks the MPD protocol over a unix socket, which mpd.conf has
    // to name with a bind_to_address line.
    readonly property string defaultMpdSocket: "$XDG_RUNTIME_DIR/mpd.sock"
    readonly property string mpdSocket: root.expand(stored.mpdSocket || root.defaultMpdSocket)

    // What the file holds, before defaults: an empty path is "the default",
    // and the page shows it as that rather than as the path it stands for.
    function value(key: string): var {
        return stored[key];
    }

    function set(key: string, value: var): void {
        stored[key] = value;
        file.writeAdapter();
    }

    // "~" and "$XDG_RUNTIME_DIR" as the shell would read them, so the page can
    // show and store paths the way they are written by hand.
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

    FileView {
        id: file

        path: Quickshell.shellPath("settings.json")
        printErrors: false
        // Saved on the first run, so there is a file to open and see what can go
        // in it; everything in it is a default at that point.
        onLoadFailed: file.writeAdapter()

        JsonAdapter {
            id: stored

            property var modules: ({})
            property bool clock24h: true
            property string terminal: ""
            property string wallpaperDir: ""
            property string musicDir: ""
            property string mpdSocket: ""
        }
    }
}
