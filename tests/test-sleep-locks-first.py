#!/usr/bin/env python3
"""Sleep from the shell locks first: it waits for the lock to hold, goes at
once when already locked, and still goes when the compositor refuses."""

from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env

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
            function run() {
                Power.run("--suspend");
                check(Lock.calls === 1, "sleep asks for the lock");
                wait(200);
                check(sleeps() === 0 && !Lock.held, "no sleep while the lock is still coming up");
                tryVerify(() => sleeps() === 1, 2000);
                check(Lock.held, "sleep once the lock holds");

                Power.run("--suspend");
                tryVerify(() => sleeps() === 2, 1000);
                check(Lock.calls === 1, "already locked: sleep at once, no second lock");

                Lock.phase = ""; Lock.refuse = true;
                Power.run("--suspend");
                tryVerify(() => sleeps() === 3, 1000);
                check(!Lock.held, "a refused lock still sleeps");
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''

LOCK = '''pragma Singleton
import QtQuick
QtObject {
    id: root
    property string phase: ""
    readonly property bool active: phase !== ""
    readonly property bool held: phase === "locked" || phase === "leave"
    property bool refuse: false
    property int calls: 0
    function lock() {
        calls++;
        if (!refuse && phase === "") {
            phase = "cover";
            cover.start();
        }
    }
    property Timer cover: Timer { interval: 300; onTriggered: root.phase = "locked" }
}'''

# Writes down what it was asked, and nothing else.
POWER = '#!/bin/sh\necho "$1" >> "$(dirname "$0")/../marker"\n'


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-sleep-lock-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/Lock.qml").write_text(LOCK)
        (target / "scripts/power.sh").write_text(POWER)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end='')
        assert output.count('PASS:') == 5 and not any(error in output for error in (
            'FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
