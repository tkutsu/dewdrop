pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// What the power menu offers and what it does about it.
//
// The actions themselves stay in ~/_scripts/power.sh, the way rofi-power.sh
// delegated to it: SUPER+SHIFT+L, the bar's launcher button and anything else
// that wants to shut the machine down all end up in the same place, and this
// only decides what to show and when to ask first.
Singleton {
    id: root

    readonly property string script: Paths.script("power.sh")

    // Whether the menu is wanted on screen. Everything that opens or closes the
    // menu goes through here rather than reaching for the window.
    property bool shown: false

    // Whether the window exists, which is not the same thing: PowerMenu.qml
    // folds itself shut when `shown` goes false, so the window has to outlive
    // the intent by the length of that. See qs.Linger.
    readonly property bool active: linger.active || root.blackout

    // Outlive the menu until the compositor exits after a CRT power action.
    property bool blackout: false

    Linger {
        id: linger

        shown: root.shown
        hold: Theme.fadeMs
    }

    // The same five rofi-power.sh listed, in the Apple menu's order: sleep,
    // restart, shut down, then log out. `confirm` marks the ones it would not
    // do without asking twice — the irreversible ones — and `question` is
    // what the Mac asks before each of them. `label` is the launcher's word
    // for it; `name` is the menu's plain action label.
    //
    // lockscreen and hibernate stay out for the reasons the old script gave:
    // lock was unwanted, and hibernate cannot work on this machine (zram-only
    // swap, no resume= parameter).
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

    // An action the menu should come up already asking about, rather than
    // showing its five. The launcher sets this on its way out: picking
    // "reboot" there is picking it here, and here is still where the second
    // look happens — the launcher has one row per action and nowhere to put a
    // yes/no strip, and an irreversible thing should not lose its confirm just
    // because it was reached by typing.
    property var armed: null

    function toggle(): void {
        root.blackout = false;
        root.shown = !root.shown;
    }

    function arm(action): void {
        root.blackout = false;
        root.armed = action;
        root.shown = true;
    }

    // Ordinary actions close first; CRT exits keep black until session teardown.
    function run(arg: string, keepBlack: bool): void {
        root.blackout = keepBlack && ["--poweroff", "--reboot", "--logout"].includes(arg);
        root.shown = false;
        if (root.blackout) {
            action.command = [root.script, arg];
            action.running = true;
        } else {
            Quickshell.execDetached([root.script, arg]);
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

    // SUPER+SHIFT+L reaches the menu through this:
    //   qs ipc call power toggle
    IpcHandler {
        target: "power"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.blackout = false;
            root.shown = true;
        }

        function close(): void {
            root.blackout = false;
            root.shown = false;
        }
    }
}
