#!/usr/bin/env python3
"""A session lock the compositor will not take leaves nothing looking locked.

The offscreen platform has no ext-session-lock, so the lock never starts: the
same as a compositor refusing it while another lock screen holds the session.
The curtain must not stay up over windows that take every key.
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

QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.services
import qs.src.modules
ShellRoot {
    LockScreen {}
    Timer { interval: 200; running: true; onTriggered: { Lock.lock(); probe.start(); } }
    Timer {
        id: probe
        interval: 100; repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (Lock.held)
                console.log("HELD");
            if (ticks > 5 && Lock.phase === "") {
                console.log("PASS: a refused lock ends, phase empty");
                Qt.quit();
            } else if (ticks > 40) {
                console.log("FAIL: still " + Lock.phase + " with no session lock");
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


def main():
    with tempfile.TemporaryDirectory(prefix="qs-lock-refused-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/core/Notify.qml").write_text(NOTIFY)
        plain_curtain(target / "src/modules/LockScreen.qml")
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "rror" in line))
        assert "HELD" in output, "the lock never got as far as asking the compositor"
        assert "PASS: a refused lock ends" in output and "FAIL:" not in output, output
        assert "NOTIFY: Could not lock the screen" in output, "no notice that the lock failed"


if __name__ == "__main__":
    main()
