#!/usr/bin/env python3
"""Saving a setting looks for the optional programs again only when the list of
them changed: a new Right Click app is found, an unrelated switch spawns nothing."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.core
ShellRoot {
    id: shell
    property int found: 0
    function check(ok, message) { console.log((ok ? "PASS: " : "FAIL: ") + message); }
    Connections { target: Tools; function onFoundChanged() { shell.found++; } }
    Timer { interval: 600; running: true; onTriggered: {
        shell.found = 0;
        Settings.set("lockClock", false);
        Settings.set("reduceMotion", true);
        unrelated.start();
    } }
    Timer { id: unrelated; interval: 600; onTriggered: {
        check(shell.found === 0, "unrelated settings look for nothing (" + shell.found + " looks)");
        Settings.set("networkCommand", "ls -l");
        related.start();
    } }
    Timer { id: related; interval: 600; onTriggered: {
        check(shell.found === 1 && Tools.has("ls"), "a new Right Click app is looked for, once, and found (" + shell.found + " looks)");
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-tools-probe-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "PASS" in line or "FAIL" in line or "rror" in line))
        assert output.count("PASS:") == 2 and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
