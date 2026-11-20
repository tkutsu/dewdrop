#!/usr/bin/env python3
"""The lock screen's Sleep, Restart and Shut Down: Restart and Shut Down arm on
the first press and act on the second, leaving disarms, Sleep acts at once.
Power is a stub, so nothing here sleeps or restarts the machine."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

POWER = '''pragma Singleton
import QtQuick
QtObject {
    property var runs: []
    readonly property var actions: [
        { key: "suspend", name: "Sleep", glyph: "", arg: "--suspend", confirm: false },
        { key: "reboot", name: "Restart", glyph: "", arg: "--reboot", confirm: true },
        { key: "shutdown", name: "Shut Down", glyph: "", arg: "--poweroff", confirm: true }
    ]
    function run(arg) { runs = runs.concat([arg]); }
}
'''

QML = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.src.components
import qs.src.services
ShellRoot {
    Window {
        id: win
        width: 400; height: 200; visible: true
        LockPower { id: power; anchors.centerIn: parent }
    }
    TestCase {
        id: test
        when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function centre(i) {
            const b = power.children[i];
            return b.mapToItem(win.contentItem, b.width / 2, 22);
        }
        // Over the button first, as a real pointer is when it clicks.
        function press(i) { const p = centre(i); mouseMove(win.contentItem, p.x, p.y); wait(30); mouseClick(win.contentItem, p.x, p.y); wait(30); }
        function run() {
            wait(100);
            check(power.children.filter(c => c.modelData !== undefined).length === 3, "three buttons, in order");
            press(0);
            check(String(Power.runs) === "--suspend" && power.armed === "", "Sleep acts on one press");
            press(1);
            check(power.armed === "reboot" && Power.runs.length === 1, "Restart arms on the first press");
            press(1);
            check(String(Power.runs) === "--suspend,--reboot" && power.armed === "", "and acts on the second");
            press(2);
            check(power.armed === "shutdown", "Shut Down arms");
            mouseMove(win.contentItem, 5, 5); wait(30);
            check(power.armed === "" && Power.runs.length === 2, "leaving disarms it without acting");
            console.log("DONE");
        }
    }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch (e) { console.log("FAIL: " + e); }
        Qt.quit();
    } }
}
'''


def main():
    # A detached helper can still be writing as the folder goes.
    with tempfile.TemporaryDirectory(prefix="qs-lock-power-", ignore_cleanup_errors=True) as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/Power.qml").write_text(POWER)
        (target / "shell.qml").write_text(QML)
        r = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=30)
        out = r.stdout + r.stderr
        print("\n".join(l for l in out.splitlines() if "PASS" in l or "FAIL" in l or "DONE" in l or "rror" in l))
        assert r.returncode == 0 and "DONE" in out and "FAIL" not in out, out


if __name__ == "__main__":
    main()
