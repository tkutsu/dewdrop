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
// later, a program counts from the next pacman transaction or restart.
Singleton {
    id: root

    readonly property var programs: [
        "blueman-manager", "btop", "fd", "gdbus", "jq", "nm-connection-editor", "notify-send", "python3", "qalc",
        "setpriv", "stdbuf", Settings.terminal
    ]
    property var found: null

    readonly property bool hasTerminal: root.has(Settings.terminal)

    function has(name: string): bool {
        return root.found === null || root.found.includes(name);
    }

    function refresh(): void {
        probe.running = true;
    }

    onProgramsChanged: root.refresh()

    Process {
        id: probe

        running: true
        command: ["sh", "-c", 'for program; do command -v "$program" >/dev/null && echo "$program"; done', "sh", ...root.programs]
        stdout: StdioCollector {
            onStreamFinished: root.found = text.split("\n").filter(line => line !== "")
        }
    }
}
