#!/usr/bin/env python3
"""Check immediate scroll feedback against the real service and slow fake DDC."""

import json
import os
from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SHELL = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.src.services
ShellRoot {
    property var service: NightMode
    FileView { id: calls; path: Quickshell.shellPath('ddc-calls'); printErrors: false }
    FileView { id: failure; path: Quickshell.shellPath('fail-ddc'); printErrors: false }
    TestCase { id: test; when: false }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log('PASS: ' + message);
    }
    function until(predicate, message) {
        const deadline = Date.now() + 2000;
        while (!predicate() && Date.now() < deadline) test.wait(10);
        check(predicate(), message);
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                until(() => NightMode.brightness === 43 && NightMode.committed === 43 && NightMode.restored,
                    'real service starts from the fixture brightness');
                NightMode.nudge(true);
                check(NightMode.brightness === 45 && NightMode.committed === 43,
                    'scroll snaps upward immediately before the slow monitor write completes');
                NightMode.nudge(true);NightMode.nudge(true);NightMode.nudge(false);
                check(NightMode.brightness === 50,
                    'rapid scrolling accumulates on the requested level without waiting for hardware');
                const deadline = Date.now() + 2000;
                let stable = true;
                while (NightMode.committed !== 50 && Date.now() < deadline) {
                    test.wait(10);
                    stable = stable && NightMode.brightness === 50;
                }
                check(stable, 'older hardware replies do not pull the readout backwards');
                check(NightMode.committed === 50, 'monitor eventually reaches the last requested brightness');
                calls.reload();calls.waitForJob();
                const writes = calls.text().trim().split('\n');
                check(writes.join(',') === '45,50', 'scroll burst coalesces into the active write and the final level');
                failure.setText('fail');failure.waitForJob();
                NightMode.nudge(false);
                check(NightMode.brightness === 45, 'the next request also updates immediately');
                until(() => NightMode.brightness === 50 && NightMode.wanted < 0,
                    'failed monitor write restores the last confirmed brightness');
                failure.setText('ok');failure.waitForJob();
                NightMode.setBrightness(53);
                NightMode.nudge(false);
                check(NightMode.brightness === 50, 'scroll down snaps an arbitrary level to the next multiple of five');
                until(() => NightMode.committed === 50 && NightMode.wanted < 0,
                    'snapped request reaches the monitor');
                NightMode.setBrightness(99);
                NightMode.nudge(true);NightMode.nudge(true);
                check(NightMode.brightness === 100, 'scroll up snaps and clamps at full brightness');
                until(() => NightMode.committed === 100 && NightMode.wanted < 0,
                    'full brightness reaches the monitor');
                NightMode.setMode('on');
                until(() => NightMode.on && NightMode.committed === 0 && NightMode.asked === '',
                    'night mode still darkens the monitor through the shared display helper');
                NightMode.setSchedule('00:00', '23:59');
                WallClock.sample(new Date(2026, 9, 22, 12, 0).getTime());
                NightMode.setAutomatic(true);
                NightMode.nudge(true);
                check(NightMode.brightness === 5, 'scrolling out of night mode updates the readout immediately');
                until(() => NightMode.committed === 5 && !NightMode.on,
                    'scrolling to a positive level also clears night mode');
                WallClock.sample(WallClock.now + 5000);test.wait(250);
                check(NightMode.automatic && !NightMode.on,
                    'manual scroll keeps Auto enabled without immediately reapplying night mode');
                NightMode.setAutomatic(false);
                NightMode.nudge(false);
                until(() => NightMode.committed === 0, 'scrolling down can still reach zero brightness');
                check(!NightMode.on, 'manual zero brightness does not enable night mode');
                NightMode.nudge(false);
                check(NightMode.brightness === 0, 'scroll down clamps at zero brightness');
                console.log('DONE: brightness scroll');
            } catch (error) { console.log('FAIL: ' + error); }
            test.wait(500);
            Qt.quit();
        }
    }
}'''

DDC = '''#!/usr/bin/env python3
from pathlib import Path
import sys
import time

folder = Path(__file__).parent.parent
if 'getvcp' in sys.argv:
    print('current value = 43')
else:
    with (folder / 'ddc-calls').open('a') as log:
        print(sys.argv[-1], file=log)
    time.sleep(0.2)
    failure = folder / 'fail-ddc'
    sys.exit(1 if failure.exists() and failure.read_text() == 'fail' else 0)
'''


def main():
    """Run the real display helper with private flags and fake monitor tools."""
    with tempfile.TemporaryDirectory(prefix='qs-brightness-scroll-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        helper = (Path(__file__).resolve().parents[1] / "scripts/display.sh").read_text()
        helper = helper.replace('"${XDG_RUNTIME_DIR:-$HOME/.cache}/quickshell"', f'"{target}"')
        (target / 'scripts/display.sh').write_text(helper)
        (target / 'scripts/display.sh').chmod(0o700)
        service = target / 'src/services/NightMode.qml'
        service.write_text(service.read_text().replace('Paths.runtime("brightness")', f'"{target}/brightness"')
                           .replace('Paths.runtime("night-mode")', f'"{target}/night-mode"'))
        (target / 'brightness').write_text('43\n')
        (target / 'ddc-calls').write_text('')
        (target / 'bin').mkdir()
        (target / 'bin/ddcutil').write_text(DDC)
        (target / 'bin/hyprctl').write_text('#!/bin/sh\nexit 0\n')
        for name in ('ddcutil', 'hyprctl'):
            (target / 'bin' / name).chmod(0o700)
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(
            ['qs', '-p', str(target), '--no-color'],
            env=shell_env(target, PATH=str(target / 'bin') + os.pathsep + os.environ['PATH']),
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Unable to assign', 'Cannot assign',
                  'Binding loop', 'Failed to load configuration')
        print('\n'.join(line for line in output.splitlines()
                        if any(marker in line for marker in ('PASS:', 'DONE:', *errors))))
        return 0 if result.returncode == 0 and 'DONE: brightness scroll' in output \
            and not any(error in output for error in errors) else 1


if __name__ == '__main__':
    raise SystemExit(main())
