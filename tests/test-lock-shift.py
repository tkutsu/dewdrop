#!/usr/bin/env python3
"""The lock's capitals mark waits for Shift held a beat: a keyboard that types a
symbol as Shift and a key (a QMK symbol layer) flashes nothing, while Caps Lock
shows at once."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.services
import qs.src.components
ShellRoot {
    id: shell
    property int step: 0
    property Item mark: null
    function check(ok, message) { console.log((ok ? "PASS: " : "FAIL: ") + message); }
    function find(item) {
        if (item.objectName === "capitals")
            return item;
        for (const child of item.children) {
            const found = find(child);
            if (found)
                return found;
        }
        return null;
    }

    FloatingWindow {
        implicitWidth: 600
        implicitHeight: 700
        color: "black"
        Rectangle { id: scene; anchors.fill: parent; color: "#334455" }
        LockPanel { id: panel; anchors.centerIn: parent; backdrop: scene }
    }

    Timer {
        id: tick; interval: 100; repeat: true; running: true
        onTriggered: {
            const s = shell.step++;
            if (s === 0) {
                shell.mark = find(panel);
                check(shell.mark !== null && !shell.mark.visible, "the capitals mark is found, hidden");
                // A symbol: Shift down and up round one keystroke.
                Lock.shift = true;
                Lock.shift = false;
            } else if (s === 1) {
                check(!mark.visible, "Shift for one keystroke shows nothing");
                Lock.shift = true;
            } else if (s === 2) {
                check(!mark.visible, "not yet, a moment into a hold");
            } else if (s === 5) {
                check(mark.visible, "Shift held a beat shows the mark");
                Lock.shift = false;
            } else if (s === 6) {
                check(!mark.visible, "letting go hides it at once");
                Lock.capsLock = true;
            } else if (s === 7) {
                check(mark.visible, "Caps Lock shows it at once");
                console.log("DONE");
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-lock-shift-", ignore_cleanup_errors=True) as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "settings.json").write_text("{}")
        (target / "shell.qml").write_text(QML)
        r = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=30)
        out = r.stdout + r.stderr
        lines = [l for l in out.splitlines() if "PASS" in l or "FAIL" in l or "DONE" in l or "rror" in l]
        print("\n".join(lines))
        assert r.returncode == 0 and "DONE" in out and "FAIL" not in out, out


if __name__ == "__main__":
    main()
