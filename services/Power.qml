pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// What the launcher's power rows offer and what they do about it.
//
// The actions themselves stay in ~/_scripts/power.sh, the way rofi-power.sh
// delegated to it: the launcher's "!" mode, the bar's launcher button and
// anything else that wants to shut the machine down all end up in the same
// place, and this only decides what to offer and how to leave the screen.
Singleton {
    id: root

    readonly property string script: Paths.script("power.sh")

    // The action whose CRT exit the launcher box is playing. The command
    // runs when that finishes (Launcher.leave); clearing this cancels it.
    property var leaving: null

    // Outlive the launcher until session teardown or the wake signal after Sleep.
    property bool blackout: false

    // Whether the screen is going or gone black: the Blackout window's life.
    readonly property bool dark: root.leaving !== null || root.blackout

    // In the Apple menu's order: sleep, restart, shut down, lock, then log
    // out. `confirm` marks the ones that ask twice — the irreversible ones —
    // and `question` is what the Mac asks before each of them. `label` is the
    // launcher's word for it; `name` is the settings page's.
    //
    // Hibernate stays out: it cannot work on this machine (zram-only swap,
    // no resume= parameter).
    readonly property var actions: [
        {
            key: "suspend",
            label: "suspend",
            name: "Sleep",
            glyph: Theme.glyph.powerSuspend,
            arg: "--suspend",
            confirm: false
        },
        {
            key: "reboot",
            label: "reboot",
            name: "Restart",
            question: "Are you sure you want to restart your computer now?",
            glyph: Theme.glyph.powerReboot,
            arg: "--reboot",
            confirm: true
        },
        {
            key: "shutdown",
            label: "shut down",
            name: "Shut Down",
            question: "Are you sure you want to shut down your computer now?",
            glyph: Theme.glyph.powerShutdown,
            arg: "--poweroff",
            confirm: true
        },
        {
            key: "lock",
            label: "lock",
            name: "Lock Screen",
            glyph: Theme.glyph.lock,
            arg: "--lock",
            confirm: false
        },
        {
            key: "logout",
            label: "log out",
            name: "Log Out",
            question: "Are you sure you want to quit all apps and log out now?",
            glyph: Theme.glyph.powerLogout,
            arg: "--logout",
            confirm: true
        },
        {
            // Switch to the compositor's click-to-kill cursor.
            key: "killprocess",
            label: "kill process",
            name: "Kill Window",
            glyph: Theme.glyph.powerKill,
            arg: "--kill",
            confirm: false
        }
    ]

    // The ones that end the session or the screen, and so leave through the CRT.
    function fades(arg: string): bool {
        return ["--poweroff", "--reboot", "--logout", "--suspend"].includes(arg);
    }

    // Ordinary actions just run; CRT exits keep black through teardown/sleep.
    function run(arg: string, keepBlack: bool): void {
        root.blackout = keepBlack && root.fades(arg);
        if (root.blackout) {
            action.command = [root.script, arg];
            action.running = true;
        } else {
            Quickshell.execDetached([root.script, arg]);
        }
    }

    // systemctl suspend returns once queued; only logind's wake signal releases black.
    Process {
        running: root.blackout && action.command[1] === "--suspend"
        command: ["setpriv", "--pdeathsig", "TERM", "--", "stdbuf", "-oL", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("org.freedesktop.login1.Manager.PrepareForSleep (false"))
                    root.blackout = false;
            }
        }
        onExited: {
            if (root.blackout && action.command[1] === "--suspend") {
                console.warn("Sleep wake monitor exited; releasing blackout");
                root.blackout = false;
            }
        }
    }

    Process {
        id: action

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("Power action: " + text.trim())
        }
        // Successful systemctl requests return before the compositor exits.
        onExited: function (code, status) {
            if (code !== 0 || status !== 0) {
                console.warn("Power action failed: " + code);
                root.blackout = false;
            }
        }
    }
}
