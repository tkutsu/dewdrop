pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.src.core

// The lock screen's state and its password check. LockScreen.qml draws it.
//
// A lock goes through four phases and back to none:
//
//   cover   the wallpaper fades in over the windows, as the desktop frames it
//   locked  the session is locked; the glass is up and the picture follows
//           the pointer
//   leave   the password was right: the glass goes and the picture glides
//           back to the desktop's framing, still locked
//   reveal  unlocked; the wallpaper fades out from over the windows
//
// So the windows are only ever faded into the wallpaper and back, never cut.
// The session is locked for `locked` and `leave` (`held`).
//
// Kept across a reload, which rebuilds this singleton: a fresh "" would
// unlock a locked session, as the new WlSessionLock takes over the old one.
Singleton {
    id: root

    readonly property string phase: kept.phase
    readonly property bool active: kept.phase !== ""
    readonly property bool held: kept.phase === "locked" || kept.phase === "leave"

    // What has been typed. Never leaves this file but into PAM.
    property string password: ""
    // PAM's own words, from faillock ("The account is locked...") or a
    // failure to run at all.
    property string message: ""
    // Whether Caps Lock is on, as LockScreen.qml reads it off the keys.
    property bool capsLock: false
    // Whether Shift is held, likewise.
    property bool shift: false
    // The password was wrong: the field shakes.
    signal rejected

    // A check under way; the field waits on it and takes no keys.
    readonly property bool checking: pam.active
    property string attempt: ""
    property bool answered: false
    property bool automatic: false

    // PIN Mode checks the password the moment it is as long as the length
    // set for it, once, as if Return had been pressed: so through the
    // system's stack like any other try, faillock and all. A miss leaves it
    // to Return until the next unlock, so a length that no longer fits (a
    // changed password) cannot keep the field from getting any longer.
    property bool missed: false
    readonly property bool automaticReady: Settings.lockAsTyped && Settings.lockPasswordLength > 0 && !root.missed

    function lock(): void {
        if (kept.phase === "") {
            Launcher.hide();
            OpenPopup.dismiss();
            root.password = "";
            root.message = "";
            root.shift = false;
            kept.phase = "cover";
        } else if (kept.phase === "reveal") {
            kept.phase = "locked";
        }
    }

    // LockScreen.qml reports each fade done.
    function covered(): void {
        if (kept.phase === "cover")
            kept.phase = "locked";
    }

    function left(): void {
        if (kept.phase === "leave")
            kept.phase = "reveal";
    }

    function revealed(): void {
        if (kept.phase === "reveal")
            kept.phase = "";
    }

    // --- typing --------------------------------------------------------------
    function type(text: string): void {
        if (kept.phase !== "locked" || root.checking || !text)
            return;
        root.password += text;
        root.message = "";
        if (root.automaticReady && root.password.length === Settings.lockPasswordLength)
            root.check(true);
    }

    function erase(): void {
        if (kept.phase === "locked" && !root.checking)
            root.password = root.password.slice(0, -1);
    }

    function clear(): void {
        if (!root.checking)
            root.password = "";
    }

    function submit(): void {
        if (kept.phase === "locked" && root.password && !root.checking)
            root.check(false);
    }

    function check(automatic: bool): void {
        root.attempt = root.password;
        root.answered = false;
        root.automatic = automatic;
        if (!pam.start())
            root.message = "Could not check the password.";
    }

    function finish(success: bool, trouble: string): void {
        if (success && kept.phase === "locked") {
            root.missed = false;
            root.attempt = "";
            root.password = "";
            root.message = "";
            kept.phase = "leave";
            return;
        }
        if (root.automatic)
            root.missed = true;
        root.attempt = "";
        root.password = "";
        root.message = trouble;
        root.rejected();
    }

    PamContext {
        id: pam

        // The system's own stack, as a login is checked.
        config: "login"

        // The password once; anything asked after it (a new password, a
        // second factor) is more than a lock screen can answer.
        onResponseRequiredChanged: {
            if (!pam.responseRequired)
                return;
            if (root.answered) {
                pam.abort();
                root.finish(false, pam.message);
                return;
            }
            root.answered = true;
            pam.respond(root.attempt);
        }
        onCompleted: result => {
            const error = result === PamResult.Error ? "Could not check the password." : "";
            root.finish(result === PamResult.Success, pam.messageIsError ? pam.message : error);
        }
        onError: root.finish(false, "Could not check the password.")
    }

    PersistentProperties {
        id: kept
        reloadableId: "lock-state"

        property string phase: ""

        // Mid-fade at the reload: settle on the side that keeps it safe.
        onLoaded: {
            if (kept.phase === "cover" || kept.phase === "leave")
                kept.phase = "locked";
            else if (kept.phase === "reveal")
                kept.phase = "";
        }
    }

    // `qs ipc call lock lock`, for a keybind or hypridle's lock_cmd. There is
    // no unlock: that takes the password.
    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }

        function locked(): bool {
            return root.held;
        }
    }
}
