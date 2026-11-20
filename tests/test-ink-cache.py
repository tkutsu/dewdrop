#!/usr/bin/env python3
"""ink.json keeps measurements only for pictures that will be there next run."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    Timer {
        interval: 100; running: true
        onTriggered: {
            const cases = [
                ["image://icon/firefox", true],
                ["file:///usr/share/icons/hicolor/32x32/apps/x.png", true],
                ["file:///home/someone/.local/share/icons/x.png", true],
                ["file:///tmp/org.chromium.Chromium.scoped_dir.AbCd12/icon.png", false],
                ["file:///run/user/1000/app/icon.png", false],
                ["file:///dev/shm/icon.png", false],
                ["file://" + Quickshell.shellDir + "/assets/x.svg", false]
            ];
            for (const [source, kept] of cases)
                console.log((Ink._lasting(source) === kept ? "PASS" : "FAIL") + ": " + source + " kept=" + kept);
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-ink-cache-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "rror" in line))
        assert output.count("PASS:") == 7 and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
