#!/usr/bin/env python3
"""PIN Mode checks the password once at its set length, and a miss falls back to Return. PAM is faked: a wrong password must never reach the system's stack (faillock)."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

FAKE = '''import QtQuick
import Quickshell.Services.Pam
QtObject {
    property string config
    property string configDirectory
    property bool active: false
    property bool responseRequired: false
    property string message: ""
    property bool messageIsError: false
    property var tries: []
    signal completed(int result)
    signal error(int error)
    function start() { active = true; responseRequired = true; return true; }
    function respond(text) {
        tries.push(text);
        responseRequired = false;
        Qt.callLater(() => { active = false; completed(text === "right" ? PamResult.Success : PamResult.Failed); });
    }
    function abort() { active = false; }
}
'''

QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.services
ShellRoot {
    id: shell
    property int step: 0
    function check(ok, message) { console.log((ok ? "PASS: " : "FAIL: ") + message); }
    function typeAll(s) { for (const c of s) Lock.type(c); }
    function tries() { return Lock.pamTries(); }
    Timer {
        id: tick; interval: 120; repeat: true; running: true
        onTriggered: {
            const s = shell.step++;
            if (s === 0) {
                Settings.set("lockAsTyped", true);
                Settings.set("lockPasswordLength", 5);
                Lock.lock(); Lock.covered();
            } else if (s === 1) {
                check(Lock.phase === "locked" && Lock.automaticReady, "locked, PIN Mode ready");
                typeAll("abcd");
                check(!Lock.checking && tries().length === 0, "no check before the length");
                Lock.type("e");
                check(Lock.checking, "a check at the length");
            } else if (s === 2) {
                check(tries().length === 1 && tries()[0] === "abcde", "checked exactly what was typed, once");
                check(Lock.password === "" && Lock.missed && !Lock.automaticReady, "a miss clears and falls back to Return");
                typeAll("abcdefg");
                check(!Lock.checking && tries().length === 1 && Lock.password === "abcdefg", "after a miss, typing past the length checks nothing");
                Lock.submit();
            } else if (s === 3) {
                check(tries().length === 2 && tries()[1] === "abcdefg", "Return still checks");
                Lock.clear(); typeAll("right"); Lock.submit();
            } else if (s === 4) {
                check(Lock.phase === "leave", "Return with the right password unlocks");
                Lock.left(); Lock.revealed();
                Lock.lock(); Lock.covered();
            } else if (s === 5) {
                check(!Lock.missed && Lock.automaticReady, "the next lock is back in PIN Mode");
                typeAll("right");
            } else if (s === 6) {
                check(tries().length === 4 && Lock.phase === "leave", "the right password at its length unlocks without Return");
                Lock.left(); Lock.revealed();
                Settings.set("lockAsTyped", false);
                Lock.lock(); Lock.covered();
            } else if (s === 7) {
                typeAll("right");
                check(!Lock.checking && tries().length === 4 && Lock.phase === "locked", "PIN Mode off: no check without Return");
                Settings.set("lockAsTyped", true);
                Settings.set("lockPasswordLength", 0);
                Lock.clear(); typeAll("right");
                check(!Lock.checking && tries().length === 4, "no length set: no check without Return");
                console.log("DONE");
                Qt.quit();
            }
        }
    }
}
'''

def main():
    # A detached helper can still be writing as the folder goes.
    with tempfile.TemporaryDirectory(prefix="qs-lock-pin-", ignore_cleanup_errors=True) as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/FakePam.qml").write_text(FAKE)
        lock = target / "src/services/Lock.qml"
        src = lock.read_text()
        assert src.count("    PamContext {") == 1
        src = src.replace("    PamContext {", "    function pamTries(): var { return pam.tries; }\n\n    FakePam {", 1)
        lock.write_text(src)
        (target / "settings.json").write_text("{}")
        (target / "shell.qml").write_text(QML)
        r = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=30)
        out = r.stdout + r.stderr
        lines = [l for l in out.splitlines() if "PASS" in l or "FAIL" in l or "DONE" in l or "rror" in l]
        print("\n".join(lines))
        assert r.returncode == 0 and "DONE" in out and "FAIL" not in out, out


if __name__ == "__main__":
    main()
