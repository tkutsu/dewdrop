pragma Singleton

import QtQuick
import Quickshell
import qs.src.core

// What the launcher's power rows offer and what they do about it.
//
// The actions themselves are in scripts/power.sh: the launcher's "!" mode, the
// bar's launcher button and anything else that wants to shut the machine down
// all end up in the same place, and this only decides what to offer.
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/power.sh")

    // In the Apple menu's order: sleep, restart, shut down, lock, then log
    // out. `confirm` marks the ones that ask twice — the irreversible ones —
    // and `question` is what the Mac asks before each of them. `name` is what
    // the launcher and the settings page both call it.
    //
    // Hibernate stays out: it cannot work on this machine (zram-only swap,
    // no resume= parameter).
    readonly property var actions: [
        {
            key: "suspend",
            name: "Sleep",
            glyph: Theme.glyph.powerSuspend,
            arg: "--suspend",
            confirm: false
        },
        {
            key: "reboot",
            name: "Restart",
            question: "Are you sure you want to restart your computer now?",
            glyph: Theme.glyph.powerReboot,
            arg: "--reboot",
            confirm: true
        },
        {
            key: "shutdown",
            name: "Shut Down",
            question: "Are you sure you want to shut down your computer now?",
            glyph: Theme.glyph.powerShutdown,
            arg: "--poweroff",
            confirm: true
        },
        {
            key: "lock",
            name: "Lock Screen",
            glyph: Theme.glyph.powerLock,
            arg: "--lock",
            confirm: false
        },
        {
            key: "logout",
            name: "Log Out",
            question: "Are you sure you want to quit all apps and log out now?",
            glyph: Theme.glyph.powerLogout,
            arg: "--logout",
            confirm: true
        },
        {
            // Switch to the compositor's click-to-kill cursor.
            key: "killprocess",
            name: "Kill Window",
            glyph: Theme.glyph.powerKill,
            arg: "--kill",
            confirm: false
        }
    ]

    function run(arg: string): void {
        Quickshell.execDetached([root.script, arg, Settings.sessionSaveCommand]);
    }
}
