#!/usr/bin/env python3
"""A pop-up button's pick is set exactly once, after the blink, even when the
button goes (a settings page switched) before the blink is over."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 300; implicitHeight: 200
        QtObject {
            id: pref
            property string title: "Example"
            property var options: [{ label: "A", value: 0 }, { label: "B", value: 1 }]
            property int value: 0
            property var sets: []
            function get() { return value; }
            function set(v) { sets.push(v); value = v; }
        }
        Loader { id: slot; sourceComponent: SettingDropdown { setting: pref } }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            function pick(index) {
                slot.item.popup.open();
                tryVerify(() => slot.item.popup.visible);
                slot.item.activated(index);
                slot.item.popup.close();
            }
            function run() {
                wait(100);
                pick(1);
                check(pref.sets.length === 0, "nothing is set during the blink");
                tryVerify(() => pref.sets.length === 1);
                wait(Theme.blinkMs * 2 + 50);
                check(pref.sets.length === 1 && pref.value === 1, "the pick is set once after the blink");

                pick(0);
                wait(10);
                slot.active = false;
                wait(Theme.blinkMs * 2 + 50);
                check(pref.sets.length === 2 && pref.value === 0, "a button gone mid-blink still sets its pick, once");
                console.log("PASS: dropdown commit complete");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-dropdown-commit-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "rror" in line))
        assert result.returncode == 0 and "PASS: dropdown commit complete" in output and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
