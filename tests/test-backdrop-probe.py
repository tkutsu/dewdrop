#!/usr/bin/env python3
"""Verify the backdrop probe never captures a screen that is gone or nameless."""
import subprocess
import tempfile
from pathlib import Path
from test_support import fixture_root, shell_env

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix='backdrop-probe-test-') as folder:
    target = fixture_root(folder)
    (target / 'src/components').mkdir(parents=True)
    (target / 'src/components/BackdropProbe.qml').write_text((ROOT / 'src/components/BackdropProbe.qml').read_text())
    (target / 'src/core/Theme.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { readonly property int shadowPad: 20 }\n')
    (target / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import qs.src.components
ShellRoot {
 id: root
 QtObject { id: gone; property string name: "DP-9"; property int width: 640; property int height: 480 }
 Component { id: probe; BackdropProbe { area: Qt.rect(0, 0, 100, 100) } }
 TestCase { id: test; when: false }
 function check(ok, message) { if (!ok) throw Error(message); }
 Timer { interval: 100; running: true; onTriggered: {
  try {
   // The offscreen platform's one screen has no name, like Hyprland's stand-in.
   const standIn = Quickshell.screens[0];
   check(standIn.name === '' && Quickshell.screens.includes(standIn), 'the fixture has a nameless screen in the model');
   for (const [screen, what] of [[gone, 'a screen gone from the model'], [standIn, 'the nameless stand-in screen']]) {
    const p = probe.createObject(root, { screen: screen, active: true });
    test.wait(200);
    const loader = p.children[0];
    check(p.reading && !p.capturable, what + ' is not capturable');
    check(loader.status === Loader.Null && loader.item === null, what + ' loads no capture');
    check(p.luma === -1, what + ' leaves luma unread');
    p.destroy();
   }
   console.log('PASS: the probe only captures live, named screens');
  } catch (e) { console.log('FAIL: ' + e); }
  Qt.quit();
 } }
}''')
    result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    print(output, end='')
    errors = ('ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign', 'Failed to load configuration', 'ScreencopyView')
    raise SystemExit(0 if result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output and not any(e in output for e in errors) else 1)
