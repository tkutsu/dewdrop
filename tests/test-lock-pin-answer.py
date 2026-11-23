#!/usr/bin/env python3
"""PIN Mode's line answers a check in colour: Theme.success held full as the lock lifts, Theme.failure through the shake before the field comes back. PAM is faked, as in test-lock-pin."""

import importlib.util
import subprocess
import tempfile
from pathlib import Path

from test_support import fixture_root, copy_shell, shell_env

spec = importlib.util.spec_from_file_location("lock_pin", Path(__file__).with_name("test-lock-pin.py"))
lock_pin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lock_pin)

QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.services
import qs.src.components
ShellRoot {
    id: shell
    property int step: 0
    property Item pin: null
    function check(ok, message) { console.log((ok ? "PASS: " : "FAIL: ") + message); }
    function typeAll(s) { for (const c of s) Lock.type(c); }
    function find(item) {
        if (item.holding !== undefined && item.said !== undefined)
            return item;
        for (const child of item.children) {
            const found = find(child);
            if (found)
                return found;
        }
        return null;
    }
    function near(a, b) { return Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b) < 0.03; }
    // The capsule beside the line: the field's other child.
    function box() { return pin.parent.children[0]; }
    function filled() { return pin.children[1]; }

    FloatingWindow {
        implicitWidth: 600
        implicitHeight: 700
        color: "black"
        Rectangle { id: scene; anchors.fill: parent; color: "#334455" }
        LockPanel { id: panel; anchors.centerIn: parent; backdrop: scene }
    }

    Timer {
        id: tick; interval: 150; repeat: true; running: true
        onTriggered: {
            const s = shell.step++;
            if (s === 0) {
                Settings.set("lockAsTyped", true);
                Settings.set("lockPasswordLength", 5);
                Lock.lock(); Lock.covered();
                shell.pin = find(panel);
                check(shell.pin !== null, "the PIN line is found");
            } else if (s === 1) {
                check(pin.visible && !box().visible && !pin.holding, "PIN Mode shows the line, not the field");
                typeAll("wrong");
            } else if (s === 2) {
                check(Lock.missed && pin.visible && pin.holding && !box().visible, "a miss holds the line before the field");
                check(near(pin.answer, Theme.failure) && filled().width === pin.width, "full, in the failure colour");
            } else if (s === 3) {
                check(pin.said === 1 && near(filled().color, Theme.failure), "red by now");
            } else if (s === 6) {
                check(!pin.holding && !pin.visible && box().visible, "then the field comes back for Return");
                Lock.clear(); typeAll("right"); Lock.submit();
            } else if (s === 7) {
                check(Lock.phase === "leave" && box().visible && !pin.visible, "Return unlocking keeps the field, no line on the way out");
                Lock.left(); Lock.revealed();
                Lock.lock(); Lock.covered();
            } else if (s === 8) {
                check(pin.visible && !pin.holding && pin.said === 0 && filled().width === 0, "the next lock starts the line over");
                typeAll("right");
            } else if (s === 9) {
                check(Lock.phase === "leave" && pin.visible && pin.holding && near(pin.answer, Theme.success), "a right PIN holds the line in the success colour");
            } else if (s === 10) {
                check(pin.said === 1 && near(filled().color, Theme.success) && filled().width === pin.width, "full and green as the lock lifts");
                Lock.lock();
            } else if (s === 11) {
                check(Lock.phase === "locked" && !pin.holding && pin.said === 0, "locked again on the way out: white again");
                console.log("DONE");
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-lock-pin-answer-", ignore_cleanup_errors=True) as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/FakePam.qml").write_text(lock_pin.FAKE)
        lock = target / "src/services/Lock.qml"
        src = lock.read_text()
        assert src.count("    PamContext {") == 1
        lock.write_text(src.replace("    PamContext {", "    FakePam {", 1))
        (target / "settings.json").write_text("{}")
        (target / "shell.qml").write_text(QML)
        r = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=30)
        out = r.stdout + r.stderr
        lines = [l for l in out.splitlines() if "PASS" in l or "FAIL" in l or "DONE" in l or "rror" in l]
        print("\n".join(lines))
        assert r.returncode == 0 and "DONE" in out and "FAIL" not in out, out


if __name__ == "__main__":
    main()
