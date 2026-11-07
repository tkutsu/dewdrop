pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which of the optional programs are installed, for the code that has to know
// before it runs one. Process.onExited never fires for a program that could not
// start, so a service waiting on it waits for ever, and a button for it does
// nothing at all. Anything run through sh or timeout reports a failed exit
// instead, and needs nothing from here.
//
// Everything counts as installed until the answer arrives, a few milliseconds
// after startup, so that nothing appears only to be taken away again. Installed
// later, a program counts from the next pacman transaction, from the moment
// Install's terminal closes, or from a restart.
Singleton {
    id: root

    // Tried in this order when the terminal setting is empty. Each takes
    // --title=<title> and -e <command>.
    readonly property var terminals: ["kitty", "foot", "alacritty", "ghostty"]

    // Where each comes from: an Arch package, or a page for what has none.
    // `needs` names the package, so the line says what Install installs.
    readonly property var sources: ({
            "blueman-manager": "blueman",
            "btop": "btop",
            "checkupdates": "pacman-contrib",
            "ddcutil": "ddcutil",
            "brightnessctl": "brightnessctl",
            "fd": "fd",
            "gdbus": "glib2",
            "hyprsunset": "hyprsunset",
            "jq": "jq",
            "nm-connection-editor": "network-manager-applet",
            "notify-send": "libnotify",
            "python3": "python",
            "qalc": "libqalculate",
            "setpriv": "util-linux",
            "stdbuf": "coreutils",
            "kitty": "kitty",
            "foot": "foot",
            "alacritty": "alacritty",
            "ghostty": "ghostty",
            "themis": "https://github.com/tkutsu/themis-icons"
        })
    readonly property var labels: ({
            "themis": "Themis Icons"
        })

    readonly property var programs: [
        "blueman-manager", "brightnessctl", "btop", "checkupdates", "ddcutil", "fd", "gdbus", "hyprsunset", "jq",
        "nm-connection-editor", "notify-send", "pacman", "python3", "qalc", "setpriv", "stdbuf", ...root.terminals, Settings.values.terminal ?? "",
        Settings.program(Settings.networkCommand), Settings.program(Settings.bluetoothCommand), Settings.program(Settings.monitorCommand)
    ].filter((name, index, all) => name !== "" && all.indexOf(name) === index)
    property var found: null

    // The setting, or the first terminal installed. Empty when there is none.
    readonly property string terminal: (Settings.values.terminal ?? "").trim()
        || root.terminals.find(name => root.found === null || root.found.includes(name)) || ""
    readonly property bool hasTerminal: root.terminal !== "" && root.has(root.terminal)

    // Install runs this with the package names after it, in the terminal.
    readonly property string installCommand: (Settings.values.installCommand ?? "").trim()
        || (root.has("pacman") ? "sudo pacman -S --needed" : "")
    readonly property bool canInstall: root.installCommand !== "" && root.hasTerminal

    function has(name: string): bool {
        return root.found === null || root.found.includes(name);
    }

    function missing(names: var): var {
        return names.filter(name => !root.has(name));
    }

    function refresh(): void {
        probe.running = true;
    }

    function source(name: string): string {
        return root.sources[name] ?? "";
    }

    function label(name: string): string {
        if (name === "")
            return "a terminal";
        return root.labels[name] ?? (root.sources[name] && !root.sources[name].includes("/") ? root.sources[name] : name);
    }

    // What a feature lacks, as a rich-text line: "Weather needs python.", and
    // a link that installs it, or opens the page of what is no package.
    // Empty when nothing is missing. Grey links, as every UI link is.
    function needs(feature: string, names: var, linkColor: string): string {
        const lacking = root.missing(names);
        if (lacking.length === 0)
            return "";
        const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
        const list = lacking.map(name => escape(root.label(name)));
        const words = (feature ? feature + " needs " : "Needs ") + (list.length > 1 ? list.slice(0, -1).join(", ") + " and " + list[list.length - 1] : list[0]) + ".";
        const pages = lacking.map(root.source).filter(src => src.includes("/"));
        const packages = lacking.every(name => root.source(name) !== "" && !root.source(name).includes("/"));
        const link = (href, text) => ` <a href="${href}" style="color: ${linkColor}">${text}</a>`;
        if (packages && root.canInstall)
            return words + link("install", "Install");
        if (pages.length === 1 && lacking.length === 1)
            return words + link(pages[0], "Get");
        return words;
    }

    // The link in a `needs` line.
    function follow(link: string, names: var): void {
        if (link === "install")
            root.install(names);
        else
            Qt.openUrlExternally(link);
    }

    function install(names: var): void {
        const packages = root.missing(names).map(root.source).filter(src => src !== "" && !src.includes("/"));
        if (packages.length === 0 || !root.canInstall || installer.running)
            return;
        installer.command = Settings.inTerminal(["sh", "-c", root.installCommand + ' "$@"', "sh", ...packages], "Install (floating)", true);
        installer.running = true;
    }

    onProgramsChanged: root.refresh()

    Process {
        id: probe

        running: true
        // The programs, and then the icon theme, found by its index file in
        // the folders an icon theme lives in.
        command: ["sh", "-c", 'for program; do command -v "$program" >/dev/null && echo "$program"; done
            IFS=:
            for dir in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
                [ -e "$dir/icons/themis/index.theme" ] && echo themis && break
            done
            true', "sh", ...root.programs]
        stdout: StdioCollector {
            onStreamFinished: root.found = text.split("\n").filter(line => line !== "")
        }
    }

    // The terminal closes when the install is done, or given up on; either
    // way, look again.
    Process {
        id: installer

        onExited: root.refresh()
    }
}
