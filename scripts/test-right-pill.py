#!/usr/bin/env python3
"""Test order logic, saved state, and the real pill's pointer and layout behavior."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

LOGIC = r"""
const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), context);
const normalise = context.normalise;
const move = context.move;
const defaults = Array.from(normalise([]));
const equal = (actual, expected) => assert.equal(JSON.stringify(actual), JSON.stringify(expected));
equal(normalise(['network', 'audio', 'audio', 'obsolete', null]), ['network', 'audio', ...defaults.filter(k => !['network', 'audio'].includes(k))]);
for (const bad of [null, {}, 'audio', 42]) equal(normalise(bad), defaults);
const visible = ['audio', 'tasks', 'network'];
const moved = Array.from(move(defaults, 'audio', null, visible));
const expected = [...defaults];
expected[0] = 'tasks'; expected[2] = 'network'; expected[12] = 'audio';
equal(moved, expected);
equal(move(moved, 'audio', 'tasks', visible), defaults);
equal(move(defaults, 'audio', 'tasks', visible), defaults);
equal(move(defaults, 'audio', 'audio', visible), defaults);
equal(move(defaults, 'email', null, visible), defaults);
equal(move(defaults, 'audio', 'email', visible), defaults);
equal(move(defaults, 'audio', null, ['audio']), defaults);
equal(move(defaults, 'audio', null, ['network', 'audio', 'tasks', 'tasks', 'obsolete']), expected);
for (let source = 0; source < defaults.length; source++) {
    for (let slot = 0; slot <= defaults.length; slot++) {
        const before = defaults[slot] ?? null;
        const result = Array.from(move(defaults, defaults[source], before, defaults));
        const wanted = [...defaults];
        if (before !== defaults[source]) {
            wanted.splice(source, 1);
            wanted.splice(before === null ? wanted.length : wanted.indexOf(before), 0, defaults[source]);
        }
        equal(result, wanted);
    }
}
console.log('PASS: normalisation, visible slots and moves in both directions');
"""

POINTER = r"""
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    id: root
    property int clicks: 0
    property int rights: 0
    function check(ok, message) { if (!ok) throw new Error(message); }
    Window {
        visible: true; width: 1000; height: 250
        Item {
            id: host
            width: 850; height: 100; x: 30; y: 30
            Pill {
                id: pill
                order: RightPillOrder.keys
                drawsSlab: false
                BarItem { id: drawer; Rectangle { implicitWidth: 12; implicitHeight: 20 } }
                BarItem {
                    id: audio
                    pinKey: 'audio'
                    tooltip: 'Audio'
                    popup: Component { Item {} }
                    actions: ({ [Qt.RightButton]: () => root.rights++ })
                    Rectangle { implicitWidth: 30; implicitHeight: 20 }
                }
                BarItem {
                    id: email
                    pinKey: 'email'
                    actions: ({ [Qt.LeftButton]: () => root.clicks++, [Qt.RightButton]: () => root.rights++ })
                    Rectangle { implicitWidth: 40; implicitHeight: 20 }
                }
                BarItem {
                    id: tasks
                    pinKey: 'tasks'
                    Rectangle { implicitWidth: 22; implicitHeight: 20 }
                }
                BarItem {
                    id: network
                    settingsKey: 'network'
                    ClickArea {
                        id: trayClick
                        implicitWidth: 42; implicitHeight: 20
                        actions: ({ [Qt.LeftButton]: () => root.clicks++, [Qt.RightButton]: () => root.rights++ })
                    }
                }
                BarItem { id: language; pinKey: 'language'; Rectangle { implicitWidth: 15; implicitHeight: 20 } }
                BarItem { id: launcher; actions: ({ [Qt.LeftButton]: () => root.clicks++ }); Rectangle { implicitWidth: 12; implicitHeight: 20 } }
            }
        }
        TestCase {
            id: test
            name: 'RightPill'
            when: false
            function drag(item, point) {
                mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton);
                mouseMove(pill, point.x, point.y, 20);
                mouseMove(pill, point.x, point.y, 20);
                root.check(pill.dragging, 'drag takes over the child');
                root.check(item.reordering, 'source dims');
                mouseRelease(pill, point.x, point.y, Qt.LeftButton);
                root.check(!pill.dragging, 'release ends the drag');
                wait(30);
            }
            function run() {
                root.check(audio.x < email.x && email.x < tasks.x && tasks.x < network.x, 'default layout');
                mouseClick(audio, audio.width / 2, 20, Qt.LeftButton);
                root.check(OpenPopup.owner === audio, 'popup opener gets a plain left click');
                mouseClick(audio, audio.width / 2, 20, Qt.MiddleButton);
                root.check(DrawerPins.pinned('audio'), 'middle click pins');
                mouseClick(audio, audio.width / 2, 20, Qt.RightButton);
                root.check(root.rights === 1, 'right click reaches module');
                mouseClick(email, email.width / 2, 20, Qt.LeftButton);
                mouseClick(trayClick, trayClick.width / 2, 10, Qt.LeftButton);
                root.check(root.clicks === 2, 'module and nested tray-style clicks');
                drag(audio, Qt.point(language.x + language.width, 20));
                root.check(OpenPopup.owner === null, 'drag dismisses popup');
                root.check(audio.x > language.x && audio.x < launcher.x, 'first module moves to the last slot');
                root.check(RightPillOrder.keys[0] === 'email', 'drop updates order');
                root.check(RightPillOrder.keys[3] === 'updater', 'hidden key keeps its slot');
                const saved = JSON.stringify(RightPillOrder.keys);
                const clicks = root.clicks;
                drag(network, Qt.point(-30, 20));
                root.check(JSON.stringify(RightPillOrder.keys) === saved, 'outside release leaves order unchanged');
                root.check(root.clicks === clicks, 'nested tray-style drag suppresses click');
                mousePress(email, email.width / 2, 20, Qt.LeftButton);
                mouseMove(pill, launcher.x - 1, 20, 20);
                mouseMove(pill, launcher.x - 1, 20, 20);
                root.check(pill.dragging, 'module drag starts');
                Settings.disabled = ['email']; wait(30);
                root.check(!pill.dragging, 'disabled source cancels');
                mouseRelease(pill, launcher.x - 1, 20, Qt.LeftButton);
                root.check(JSON.stringify(RightPillOrder.keys) === saved, 'cancelled source writes nothing');
                Settings.disabled = []; wait(30);
                drag(audio, Qt.point(email.x, 20));
                root.check(audio.x < email.x, 'last module moves back to first');
                mousePress(tasks, tasks.width / 2, 20, Qt.LeftButton);
                mouseMove(pill, network.x + network.width, 20, 20);
                mouseMove(pill, network.x + network.width, 20, 20);
                root.check(pill.dragging, 'middle module drag starts');
                tasks.present = false; wait(30);
                root.check(!pill.dragging, 'removed source cancels');
                mouseRelease(pill, 10, 20, Qt.LeftButton);
                tasks.present = true; wait(30);
                const beforeNoop = JSON.stringify(RightPillOrder.keys);
                mousePress(email, email.width / 2, 20, Qt.LeftButton);
                mouseMove(pill, launcher.x - 1, 20, 20); mouseMove(pill, launcher.x - 1, 20, 20);
                root.check(pill.dragging, 'drag starts before controller is disabled');
                pill.order = []; mouseMove(pill, launcher.x - 2, 20, 20); wait(30);
                root.check(!pill.dragging, 'disabling the controller cancels the drag');
                mouseRelease(pill, launcher.x - 1, 20, Qt.LeftButton);
                pill.order = Qt.binding(() => RightPillOrder.keys); wait(30);
                root.check(JSON.stringify(RightPillOrder.keys) === beforeNoop, 'disabled controller writes nothing');
                root.check(!RightPillOrder.move('audio', 'email', pill._movable.map(m => m.settingsKey)), 'own slot does not write');
                root.check(JSON.stringify(RightPillOrder.keys) === beforeNoop, 'own slot preserves order');
                const own = email.x + email.width - 1;
                mousePress(email, email.width / 2, 20, Qt.LeftButton);
                mouseMove(pill, own, 20, 20); mouseMove(pill, own, 20, 20);
                root.check(pill.dragging && !pill.dropMoves, 'own slot shows no drop line');
                mouseRelease(pill, own, 20, Qt.LeftButton);
                root.check(JSON.stringify(RightPillOrder.keys) === beforeNoop, 'own slot drop writes nothing');
                mousePress(launcher, launcher.width / 2, 20, Qt.LeftButton);
                mouseMove(pill, email.x, 20, 20); mouseMove(pill, email.x, 20, 20);
                root.check(!pill.dragging, 'launcher stays fixed');
                mouseRelease(pill, email.x, 20, Qt.LeftButton);
                console.log('PASS: pill pointer, popup, pin, order and cancellation');
            }
        }
    }
    Timer { interval: 200; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
}
"""

STUBS = {
    'Settings.qml': "pragma Singleton\nimport QtQuick\nQtObject { property var disabled: []; function moduleOn(key) { return !disabled.includes(key); } }",
    'DrawerPins.qml': "pragma Singleton\nimport QtQuick\nQtObject { property var pins: ({}); function pinned(k) { return pins[k] === true; } function toggle(k) { const next = Object.assign({}, pins); next[k] = !pinned(k); pins = next; } }",
    'OpenPopup.qml': "pragma Singleton\nimport QtQuick\nQtObject { property Item owner: null; function dismiss() { owner = null; } function toggle(item) { owner = owner === item ? null : item; } function browse(item, hovered) {} }",
    'Theme.qml': """pragma Singleton
import QtQuick
QtObject {
    property int gap: 10; property int barHeight: 30; property int barInset: 4
    property int barMargin: 5; property int pillPad: 6; property int pillRadius: 15
    property real pillTrack: 1; property real pillTrackFoot: 1; property real pillTrackRest: 0.2
    property color fg: 'white'; property color backdrop: 'black'; property color tint: 'black'; property color barBg: 'black'
    property real foldSpring: 3; property real foldDamping: 0.4
    property int startMs: 10000; property int foldMs: 100; property int fadeMs: 120
    property int pressDip: 1; property int pinMarkSize: 6; property int pinGlyphSize: 6
    property color markRimTop: 'white'; property int iconSize: 12
    property var glyph: ({pin: 'p'})
    function pillTop(height) { return (height - barHeight) / 2; }
    function mix(a, b, c) { return a; }
    function badgeBg(item) { return 'black'; }
    property color badgeFg: 'white'
} """,
    'Paths.qml': "pragma Singleton\nimport Quickshell\nSingleton { function state(name) { return Quickshell.shellPath('state/' + name); } }",
    'components/Liquid.qml': "import QtQuick\nItem { property var backdrop; property vector4d box0; property real rimFrom; property real rimTo }",
    'components/Rim.qml': "import QtQuick\nItem { property real radius; property real lineWidth; property color topColor; property color bottomColor }",
    'components/Glyph.qml': "import QtQuick\nItem { property string text; property int fontSize; property color color }",
    'components/Badge.qml': "import QtQuick\nItem {}",
    'components/HoverPopup.qml': "import QtQuick\nItem { property Item anchorItem; property bool hovered; property bool pressed; property bool open; property string text; property Component popup; property var item: null }",
}


def run_shell(target, source):
    (target / 'shell.qml').write_text(source)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(target / 'runtime'))
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end='')
    assert result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output, output
    for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration', 'Cannot assign', 'Unable to assign'):
        assert error not in output, output
    return output


def main():
    subprocess.run(['node', '-e', LOGIC, str(ROOT / 'RightPillOrder.js')], check=True)
    with tempfile.TemporaryDirectory(prefix='quickshell-right-pill-test-') as folder:
        target = Path(folder)
        (target / 'components').mkdir()
        (target / 'state').mkdir()
        (target / 'runtime').mkdir(mode=0o700)
        for name in ('RightPillOrder.qml', 'RightPillOrder.js', 'components/Pill.qml', 'components/BarItem.qml', 'components/ClickArea.qml', 'components/DropLine.qml'):
            shutil.copyfile(ROOT / name, target / name)
        for name, text in STUBS.items():
            (target / name).write_text(text)
        # Loading absent or malformed state must not repair it until a changed drop.
        state = target / 'state/right-pill.json'
        load = """import QtQuick
import Quickshell
import qs
ShellRoot { Timer { interval: 150; running: true; onTriggered: {
    if (RightPillOrder.keys[0] !== 'audio' || RightPillOrder.keys.length !== 15) console.log('FAIL: defaults');
    else if (RightPillOrder.move('audio', 'tasks', ['audio', 'tasks'])) console.log('FAIL: no-op');
    else console.log('PASS: defaults and no-op');
    Qt.quit();
} } }"""
        run_shell(target, load)
        assert not state.exists(), 'missing state was rewritten on load or no-op'
        for malformed in ('{ broken json', '{"order": "audio"}'):
            state.write_text(malformed)
            run_shell(target, load)
            assert state.read_text() == malformed, 'malformed state was rewritten'
        state.unlink()  # This is the fixture's exact file inside its temporary directory.
        run_shell(target, POINTER)
        saved = json.loads(state.read_text())['order']
        restart = """import QtQuick
import Quickshell
import qs
ShellRoot { Timer { interval: 150; running: true; onTriggered: {
    console.log('ORDER:' + JSON.stringify(RightPillOrder.keys));
    console.log('PASS: saved order reloaded'); Qt.quit();
} } }"""
        output = run_shell(target, restart)
        assert 'ORDER:' + json.dumps(saved, separators=(',', ':')) in output, output
        print('PASS: order survives a fresh shell process')


if __name__ == '__main__':
    main()
