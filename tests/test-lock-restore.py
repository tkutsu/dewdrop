#!/usr/bin/env python3
"""A bar that dies under a held lock comes back locked.

Lock.qml keeps the runtime file `locked` while a lock is asked for, and a new
bar that finds it there locks at once. The offscreen platform has no
ext-session-lock, so each lock here is refused after a second, which must
clear the file again: nothing is locked then.
"""

import re
import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

NOTIFY = '''pragma Singleton
import Quickshell
Singleton {
    function send(summary, body, options) { console.log("NOTIFY: " + summary); }
}
'''

# LOCK is 1 to lock once started, so the file is written rather than read.
QML = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import qs.src.services
import qs.src.modules
ShellRoot {
    LockScreen {}
    FileView { id: flag; path: Paths.runtime("locked"); blockLoading: true; printErrors: false }
    Component.onCompleted: console.log("START " + (Lock.phase || "none"))
    Timer { interval: 200; running: LOCK; onTriggered: Lock.lock() }
    Timer {
        interval: 100; repeat: true; running: true
        property int ticks: 0
        property bool seen: false
        onTriggered: {
            ticks++;
            if (Lock.held && !seen) {
                seen = true;
                flag.reload();
                console.log("FLAG " + (flag.text().trim() || "empty"));
            }
            if (ticks > 25 && Lock.phase === "") {
                console.log("DONE");
                Qt.quit();
            } else if (ticks > 60) {
                console.log("FAIL: still " + Lock.phase);
                Qt.quit();
            }
        }
    }
}
'''


def plain_curtain(path):
    """The curtain as a plain window: the offscreen platform has no layer shell."""
    text = path.read_text().replace("PanelWindow {", "FloatingWindow {", 1)
    text = re.sub(r"\n\s*anchors \{[^}]*\}", "", text, count=1)
    lines = [line for line in text.splitlines()
             if not line.strip().startswith(("WlrLayershell.", "exclusionMode:"))]
    path.write_text("\n".join(lines) + "\n")


def run(target, lock):
    (target / "shell.qml").write_text(QML.replace("LOCK", "true" if lock else "false"))
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    print("\n".join(line for line in output.splitlines() if "qml:" in line or "rror" in line))
    assert "DONE" in output and "FAIL:" not in output, output
    return output


def main():
    with tempfile.TemporaryDirectory(prefix="qs-lock-restore-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/core/Notify.qml").write_text(NOTIFY)
        plain_curtain(target / "src/modules/LockScreen.qml")
        flag = target / "runtime/quickshell/locked"

        output = run(target, lock=True)
        assert "START none" in output, "a bar with no flag started locked"
        assert "FLAG locked" in output, "a held lock left no flag for the next bar"
        assert flag.read_text() == "", "a refused lock left the flag behind"
        print("PASS: a lock writes the flag, and a refused one clears it")

        flag.write_text("locked\n")
        output = run(target, lock=False)
        assert "START locked" in output, "a bar that died under a lock came back unlocked"
        assert "NOTIFY: Could not lock the screen" in output, "the relock was never asked of the compositor"
        assert flag.read_text() == "", "a refused relock left the flag behind"
        print("PASS: a bar that died under a lock starts locked")


if __name__ == "__main__":
    main()
