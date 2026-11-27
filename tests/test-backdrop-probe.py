#!/usr/bin/env python3
"""The backdrop probe reads stills taken in Stills' own window, never in its own.

A grab of an item that unloads mid-grab frees the result under the render
thread, so the probe holds nothing that is grabbed: a probe that goes while its
still is out leaves the still to land in Stills. Stills never captures a screen
that is gone or nameless.
"""
import subprocess
import tempfile
from pathlib import Path
from test_support import fixture_root, offscreen_meters, shell_env

ROOT = Path(__file__).resolve().parents[1]

probe_source = (ROOT / 'src/components/BackdropProbe.qml').read_text()
assert 'grabToImage' not in probe_source and 'ScreencopyView' not in probe_source, 'the probe grabs in its own window'

THEME = 'pragma Singleton\nimport Quickshell\nSingleton { readonly property int shadowPad: 20 }\n'

# Only screens Stills may capture: one gone from the model, and the offscreen
# platform's nameless one, as Hyprland's stand-in is.
REFUSED = '''import QtQuick
import QtTest
import Quickshell
import qs.src.components
import qs.src.services
ShellRoot {
 id: root
 QtObject { id: gone; property string name: "DP-9"; property int width: 640; property int height: 480 }
 Component { id: probe; BackdropProbe { area: Qt.rect(0, 0, 100, 100) } }
 TestCase { id: test; when: false }
 function check(ok, message) { if (!ok) throw Error(message); }
 Timer { interval: 100; running: true; onTriggered: {
  try {
   const standIn = Quickshell.screens[0];
   check(standIn.name === '' && Quickshell.screens.includes(standIn), 'the fixture has a nameless screen in the model');
   const answers = [];
   Stills.taken.connect((ticket, still) => answers.push(still));
   for (const [screen, what] of [[gone, 'a screen gone from the model'], [standIn, 'the nameless stand-in screen']]) {
    check(!Stills.capturable(screen), what + ' is not capturable');
    answers.length = 0;
    const p = probe.createObject(root, { screen: screen, active: true });
    test.wait(200);
    check(answers.length === 1 && answers[0] === null, what + ' is asked for once and answered with nothing, got ' + JSON.stringify(answers));
    check(p.ticket === 0, what + ' is answered');
    check(p.luma === -1, what + ' leaves luma unread');
    p.destroy();
   }
   console.log('PASS: Stills only captures live, named screens');
  } catch (e) { console.log('FAIL: ' + e); }
  Qt.quit();
 } }
}'''

# The capture swapped for a white box that "captures" a tick after its source
# is set, so the offscreen platform can take stills of its one screen.
FAKE_VIEW = '''Rectangle {
                color: "white"
                property var captureSource: null
                property bool live
                property bool hasContent: false
                onCaptureSourceChanged: {
                    hasContent = false;
                    if (captureSource)
                        Qt.callLater(() => hasContent = !!captureSource);
                }'''

TAKEN = '''import QtQuick
import QtTest
import Quickshell
import qs.src.components
import qs.src.services
ShellRoot {
 id: root
 Component { id: probe; BackdropProbe { area: Qt.rect(0, 0, 100, 100) } }
 TestCase { id: test; when: false }
 function check(ok, message) { if (!ok) throw Error(message); }
 Timer { interval: 100; running: true; onTriggered: {
  try {
   const screen = Quickshell.screens[0];
   let answered = 0;
   Stills.taken.connect((ticket, still) => { if (still) answered++; });

   // A probe that goes the moment it asked, as a popup closing mid-read.
   const early = probe.createObject(root, { screen: screen, active: true });
   test.wait(1);
   check(early.ticket !== 0 && Stills._job !== null, 'the first probe has a still under way');
   early.destroy();
   test.wait(500);
   check(answered === 1, 'the still the closed popup asked for still lands, in Stills, and only once');
   check(Stills._job === null, 'Stills is free again');

   const p = probe.createObject(root, { screen: screen, active: true });
   test.wait(500);
   check(p.ticket === 0 && Math.abs(p.luma - 1) < 0.01, 'the next probe reads white as 1, got ' + p.luma);
   p.destroy();
   console.log('PASS: a probe that goes mid-read leaves its still to land in Stills');
  } catch (e) { console.log('FAIL: ' + e); }
  Qt.quit();
 } }
}'''


def run(shell, stills):
    with tempfile.TemporaryDirectory(prefix='backdrop-probe-test-') as folder:
        target = fixture_root(folder)
        (target / 'src/components').mkdir(parents=True)
        (target / 'src/services').mkdir(parents=True)
        (target / 'src/components/BackdropProbe.qml').write_text(probe_source)
        (target / 'src/services/Stills.qml').write_text(stills)
        offscreen_meters(target)
        (target / 'src/core/Theme.qml').write_text(THEME)
        (target / 'shell.qml').write_text(shell)
        result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign', 'Failed to load configuration', 'Capture source', 'Cannot capture')
        return result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output and not any(e in output for e in errors)


stills = (ROOT / 'src/services/Stills.qml').read_text()
faked = stills.replace('            ScreencopyView {', '            ' + FAKE_VIEW, 1).replace('!!screen?.name && ', '', 1)
assert faked.count('FAKE') == 0 and 'ScreencopyView {' not in faked and '!!screen?.name' not in faked
ok = run(REFUSED, stills)
ok = run(TAKEN, faked) and ok
raise SystemExit(0 if ok else 1)
