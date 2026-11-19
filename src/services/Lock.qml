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
    // The password was wrong: the field shakes.
    signal rejected

    // A check asked for with Return, which the field shows and waits on. One
    // run as typed is silent.
    readonly property bool checking: pam.active && root.explicit
    property bool explicit: false
    property bool explicitNext: false
    property string attempt: ""
    property bool answered: false

    // Unlock Without Return checks every change, which only the lock's own
    // PAM file can stand (pam/dewdrop-lock says why); Return uses the
    // system's stack, faillock and all.
    readonly property bool asTyped: Settings.lockAsTyped

    function lock(): void {
        if (kept.phase === "") {
            Launcher.hide();
            OpenPopup.dismiss();
            root.password = "";
            root.message = "";
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
        if (root.asTyped)
            root.check(false);
    }

    function erase(): void {
        if (kept.phase !== "locked" || root.checking)
            return;
        root.password = root.password.slice(0, -1);
        if (root.asTyped && root.password)
            root.check(false);
    }

    function clear(): void {
        if (!root.checking)
            root.password = "";
    }

    function submit(): void {
        if (kept.phase !== "locked" || !root.password)
            return;
        if (pam.active) {
            // Already on its way: say how it went. A check of an older
            // password says so once it is done, with this one.
            if (root.attempt === root.password)
                root.explicit = true;
            else
                root.explicitNext = true;
            return;
        }
        root.check(true);
    }

    // One check at a time. Typing during one is checked once it is done, as
    // whatever the field says by then, so a fast typist costs a check or two
    // rather than one a key.
    function check(explicit: bool): void {
        if (pam.active) {
            root.explicitNext = root.explicitNext || explicit;
            return;
        }
        root.attempt = root.password;
        root.answered = false;
        root.explicit = explicit;
        root.explicitNext = false;
        if (!pam.start()) {
            root.message = "Could not check the password.";
            root.explicit = false;
        }
    }

    function finish(success: bool, trouble: string): void {
        const shown = root.explicit;
        root.explicit = false;
        if (success && kept.phase === "locked") {
            root.password = "";
            root.message = "";
            kept.phase = "leave";
            return;
        }
        if (trouble)
            root.message = trouble;
        if (shown) {
            root.password = "";
            root.rejected();
            return;
        }
        // A silent check went stale while it ran: try what is there now.
        if (root.password && (root.password !== root.attempt || root.explicitNext))
            root.check(root.explicitNext);
    }

    PamContext {
        id: pam

        configDirectory: root.asTyped ? Quickshell.shellPath("pam") : "/etc/pam.d"
        config: root.asTyped ? "dewdrop-lock" : "login"

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
