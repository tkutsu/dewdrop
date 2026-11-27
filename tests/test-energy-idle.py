#!/usr/bin/env python3
"""Caffeine holds the bar's own idle timers, and wakes a screen that was already off."""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

FAKE_IDLE = '''import QtQuick
QtObject {
    property bool enabled: true
    property real timeout
    property bool respectInhibitors
    property bool isIdle: false
}
'''

SHELL = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
    property int step: 0
    property int count: 0
    function last() { return Energy.sent[Energy.sent.length - 1]; }
    // One step a tick, as Caffeine is switched from the bar.
    Timer { interval: 150; running: true; repeat: true; onTriggered: {
        try {
            const [display, sleep] = Energy.idle;
            const s = step++;
            if (s === 0) {
                check(!Caffeine.active && display.enabled && sleep.enabled, "without Caffeine both timers run");
                display.isIdle = true;
                check(last() === 'hl.dsp.dpms({ action = "off" })', "idle turns the screen off");
                Caffeine.turn(true);
            } else if (s === 1) {
                check(!display.enabled && !sleep.enabled, "Caffeine turns both timers off");
                check(last() === 'hl.dsp.dpms({ action = "on" })', "Caffeine on a dark screen turns it back on");
                display.isIdle = false;
                count = Energy.sent.length;
                Caffeine.turn(false);
            } else if (s === 2) {
                check(display.enabled && sleep.enabled && Energy.sent.length === count, "Caffeine off runs them again, sending nothing");
                Caffeine.turn(true);
            } else {
                check(!display.enabled && Energy.sent.length === count, "Caffeine on a lit screen sends nothing");
                check(!Energy.sent.includes("suspend"), "nothing suspends");
                console.log("DONE");
                Qt.quit();
            }
        } catch (e) { console.log("FAIL: " + e); Qt.quit(); }
    } }
}
'''


with tempfile.TemporaryDirectory(prefix='energy-idle-test-') as folder:
    target = Path(folder)
    copy_shell(target)
    (target / 'src/services/FakeIdle.qml').write_text(FAKE_IDLE)
    energy = target / 'src/services/Energy.qml'
    source = energy.read_text()
    assert source.count('    IdleMonitor {\n') == 2
    source = source.replace('    IdleMonitor {\n', '    FakeIdle {\n        id: displayIdle\n', 1)
    source = source.replace('    IdleMonitor {\n', '    FakeIdle {\n        id: sleepIdle\n', 1)
    source = source.replace('Hyprland.dispatch(', 'root.send(').replace('Power.run("--suspend")', 'root.send("suspend")')
    source = source.replace('    id: root\n', '    id: root\n    readonly property var idle: [displayIdle, sleepIdle]\n'
                            '    property var sent: []\n    function send(what) { root.sent = [...root.sent, what]; }\n', 1)
    energy.write_text(source)
    (target / 'shell.qml').write_text(SHELL)
    result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=shell_env(target),
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    print('\n'.join(line for line in output.splitlines() if 'PASS' in line or 'FAIL' in line or 'rror' in line))
    raise SystemExit(0 if result.returncode == 0 and 'DONE' in output and 'FAIL' not in output else 1)
