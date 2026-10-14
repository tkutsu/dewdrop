#!/usr/bin/env python3
"""Click real music and timer popup targets through their press animation."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import offscreen_ink

ROOT = Path(__file__).resolve().parents[1]
STUBS = {
    'services/Mpd.qml': '''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true
    property string label: "A track title"; property string cover: ""; property string state: "play"
    property real duration: 120; property real elapsed: 30
    property int toggles: 0; property int previous: 0; property int following: 0
    function toggle() { toggles++; } function prev() { previous++; } function next() { following++; }
    function seek(amount) {}
}
''',
    'services/Timers.qml': '''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true; property var ringing: []
    property var focus: ({id: "tea", label: "Tea", total: 30000, running: true})
    property var nextAlarm: null; property real progress: 0.5; property int beatMs: 1000
    property string glyph: "T"; property string label: "00:30"
    property int hushes: 0; property int toggles: 0; property int cancellations: 0
    function hush() { hushes++; ringing = []; } function toggle(id) { toggles++; }
    function cancel(id) { cancellations++; } function bump(id, amount) {}
}
''',
    'services/Launcher.qml': 'pragma Singleton\nimport QtQuick\nQtObject { property string taskPrefix: ""; function openWith(prefix) {} }\n',
    'components/MusicPopup.qml': 'import QtQuick\nItem { property bool morphs; property color accent }\n',
    'components/TimerPopup.qml': 'import QtQuick\nItem { property bool morphs }\n',
    'components/HoverPopup.qml': 'import QtQuick\nItem { property Item anchorItem; property bool hovered; property bool pressed; property bool open; property string text; property Component popup; property var item: null }\n',
}
SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
ShellRoot {
    FloatingWindow {
        id: window; implicitWidth: 900; implicitHeight: 100
        Pill { id: musicPill; side: Pill.Side.Left; edgeOffset: 30; drawsSlab: false; Music { id: music; objectName: "music" } }
        Pill { id: timerPill; side: Pill.Side.Left; edgeOffset: 400; drawsSlab: false; Countdown { id: countdown; objectName: "timer" } }
        TestCase {
            id: test; when: false
            property int failures: 0
            function check(ok, message) {
                console.log((ok ? "PASS: " : "FAIL: ") + message);
                if (!ok) failures++;
            }
            function named(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found) return found;
                }
                return null;
            }
            function click(item, target, y, delay) {
                OpenPopup.dismiss(); mouseMove(window.contentItem, 850, 80); wait(500);
                const center = target.mapToItem(item, target.width / 2, target.height / 2);
                mouseMove(item, center.x, y); wait(500);
                const x = target.mapToItem(item, target.width / 2, 0).x;
                mousePress(item, x, y); wait(delay);
                check(target.scale < 1, item.objectName + " target shrinks during press");
                mouseRelease(item, x, y); wait(30);
                check(OpenPopup.owner === item, item.objectName + " popup opens at y=" + y + " after " + delay + "ms press");
            }
            function run() {
                for (const item of [music, countdown]) {
                    const target = named(item, item === music ? "titleRoom" : "labelBox");
                    for (const y of [item.height / 2, 0, 1, Theme.barInset])
                        click(item, target, y, 200);
                }
                OpenPopup.dismiss(); mouseMove(music, music.width / 2, music.height / 2); wait(500);
                const next = named(music, "next");
                mouseClick(next, next.width / 2, next.height / 2); wait(30);
                check(Mpd.following === 1 && OpenPopup.owner === null, "next control acts once without opening popup");
                mouseClick(next, next.width - 1, next.height / 2); wait(30);
                check(Mpd.following === 2 && OpenPopup.owner === null, "next control's edge does not open popup");
                const play = named(music, "slot");
                mouseClick(play, play.width / 2, play.height / 2); wait(30);
                check(Mpd.toggles === 1 && OpenPopup.owner === null, "play control acts once without opening popup");
                const cancel = named(countdown, "slot");
                mouseClick(cancel, cancel.width / 2, cancel.height / 2); wait(30);
                check(Timers.cancellations === 1 && OpenPopup.owner === null, "cancel control acts once without opening popup");
                Timers.ringing = [{id: "done", label: "Tea"}]; countdown.sync(); wait(500);
                const label = named(countdown, "labelBox");
                mouseClick(label, label.width / 2, label.height / 2); wait(30);
                check(Timers.hushes === 1 && OpenPopup.owner === null, "ringing timer label dismisses without opening popup");
                console.log("DONE: " + failures + " failures");
            }
        }
    }
    Timer { interval: 300; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='qs-topedge-') as folder:
        target = Path(folder)
        files = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '--cached', '--others', '--exclude-standard'], text=True)
        for name in files.splitlines():
            if not (ROOT / name).is_file():
                continue
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        step = target / "components/MediaStep.qml"
        step.write_text(step.read_text().replace('id: icon\n', 'id: icon\n        objectName: root.previous ? "prev" : "next"\n'))
        for module, names in [('Music', ['titleRoom', 'slot', 'next']), ('Countdown', ['labelBox', 'slot'])]:
            path = target / 'modules' / (module + '.qml')
            source = path.read_text()
            for name in names:
                source = source.replace('id: ' + name + '\n', 'id: ' + name + '\n            objectName: "' + name + '"\n')
            path.write_text(source)
        for name, source in STUBS.items():
            (target / name).write_text(source)
        (target / 'settings.json').write_text('{}\n')
        offscreen_ink(target)
        (target / 'shell.qml').write_text(SHELL)
        runtime = target / 'runtime'
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / 'state'),
                   XDG_DATA_HOME=str(target / 'data'), XDG_CACHE_HOME=str(target / 'cache'))
        for key in ['WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
            env.pop(key, None)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print('\n'.join(line for line in output.splitlines() if 'qml:' in line or 'ERROR' in line))
        ok = result.returncode == 0 and 'DONE: 0 failures' in output and 'FAIL:' not in output
        for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign', 'Cannot assign', 'Failed to load configuration'):
            ok = ok and error not in output
        if not ok:
            print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
