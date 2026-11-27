#!/usr/bin/env python3
"""Sleep from the shell covers the screen and locks as it wakes: the cover
holds through the sleep, the first late tick locks, the lock screen's own Sleep
drops back to the cover, and a sleep that never comes still locks after 30 s.
The real Lock, with PAM faked as in test-lock-pin."""

import subprocess
import tempfile

from test_support import copy_shell, fixture_root, shell_env

FAKE_PAM = '''import QtQuick
QtObject {
    property string config
    property bool active: false
    property bool responseRequired: false
    property string message: ""
    property bool messageIsError: false
    signal completed(int result)
    signal error(int error)
    signal pamMessage
    function start() { return true; }
    function respond(text) {}
    function abort() {}
}
'''

SHELL = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.src.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 100; implicitHeight: 100
        FileView { id: marker; path: Quickshell.shellPath("marker"); blockLoading: true; printErrors: false }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function sleeps() { marker.reload(); return marker.text().split("\\n").filter(l => l === "--suspend").length; }
            function wake() { Lock.sample(Lock.lastTick + 3000); }
            function run() {
                // Built at startup in the bar, before any sleep: let its
                // kept phase load first.
                check(Lock.phase === "", "starts unlocked");
                wait(300);
                Power.run("--suspend");
                check(Lock.phase === "cover" && Lock.sleeping && !Lock.held, "sleep covers the screen, no lock yet");
                wait(300);
                check(sleeps() === 0, "no sleep while the cover fades in");
                tryVerify(() => sleeps() === 1, 1500);
                wait(1200);
                check(Lock.phase === "cover" && !Lock.held, "the cover holds through the sleep, even past its own timeout");

                test.wake();
                check(Lock.phase === "locked" && Lock.held && !Lock.sleeping, "the first late tick locks");

                Lock.type("x");
                Power.run("--suspend");
                check(Lock.phase === "cover" && !Lock.held && Lock.password === "", "Sleep from the lock screen drops back to the cover");
                tryVerify(() => sleeps() === 2, 1500);
                test.wake();
                check(Lock.phase === "locked", "and locks again on the wake");

                Power.run("--suspend");
                const from = Lock.sleptAt;
                for (let at = from + 250; at <= from + 29000; at += 250)
                    Lock.sample(at);
                check(Lock.phase === "cover", "ticks on time are no wake");
                for (let at = from + 29250; at <= from + 30500; at += 250)
                    Lock.sample(at);
                check(Lock.phase === "locked" && !Lock.sleeping, "a sleep that never came still locks");
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''

# Writes down what it was asked, and nothing else.
POWER = '#!/bin/sh\necho "$1" >> "$(dirname "$0")/../marker"\n'


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-sleep-cover-", ignore_cleanup_errors=True) as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/FakePam.qml").write_text(FAKE_PAM)
        lock = target / "src/services/Lock.qml"
        src = lock.read_text()
        assert src.count("    PamContext {") == 1
        lock.write_text(src.replace("    PamContext {", "    FakePam {", 1))
        (target / "scripts/power.sh").write_text(POWER)
        (target / "settings.json").write_text("{}")
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end='')
        assert output.count('PASS:') == 9 and not any(error in output for error in (
            'FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
