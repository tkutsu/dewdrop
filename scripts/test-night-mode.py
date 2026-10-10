#!/usr/bin/env python3
"""Check night-mode scheduling, popup controls and display commands in isolation."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SCENARIO = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.components
ShellRoot {
    property var service: NightMode
    Window {
        visible: true
        width: 320; height: 250
        DisplayPopup { id: popup; x: 12; y: 12 }
        TestCase {
            id: test
            when: false
            function at(hour, minute) { return new Date(2026, 9, 6, hour, minute).getTime(); }
            function clock(hour, minute) { WallClock.sample(at(hour, minute)); }
            function mode(enabled) {
                tryVerify(() => NightMode.on === enabled, 2000);
                wait(30);
            }
            function controls(item, found) {
                if (item.label !== undefined && item.tapped !== undefined) found[item.label] = item;
                if (item.minute !== undefined && item.value !== undefined) found.dials.push(item);
                for (const child of item.children) controls(child, found);
            }
            function run() {
                tryVerify(() => NightMode.restored && NightMode.flagKnown, 2000);
                verify(!NightMode.automatic && !NightMode.on, 'automatic is initially off');
                compare(NightMode.startMinute, 1320);
                compare(NightMode.endMinute, 420);
                verify(!NightMode.scheduledOn(at(21, 59)), 'before overnight start');
                verify(NightMode.scheduledOn(at(22, 0)), 'start is inclusive');
                verify(NightMode.scheduledOn(at(0, 0)), 'midnight is inside overnight range');
                verify(NightMode.scheduledOn(at(6, 59)), 'before overnight end');
                verify(!NightMode.scheduledOn(at(7, 0)), 'end is exclusive');
                for (const invalid of ['24:00', '12:60', '7:00', '', 'noon'])
                    verify(!NightMode.setSchedule(invalid, '07:00'), 'invalid times rejected');
                verify(!NightMode.setSchedule('07:00', '07:00'), 'empty range rejected');
                clock(21, 59);
                NightMode.setAutomatic(true);
                mode(false);
                clock(22, 0);
                mode(true);
                clock(7, 0);
                mode(false);
                // Skip both boundaries across suspend rather than counting elapsed ticks.
                clock(12, 0);
                WallClock.sample(at(23, 0) + 86400000);
                mode(true);
                WallClock.sample(at(9, 0) + 2 * 86400000);
                mode(false);
                // A manual change (SUPER+Z runs display.sh directly) holds until the next boundary.
                clock(23, 0);
                mode(true);
                Quickshell.execDetached([Quickshell.shellPath('display.sh'), 'toggle']);
                mode(false);
                clock(23, 30);
                WallClock.wokeUp();
                wait(200);
                verify(!NightMode.on && NightMode.automatic, 'manual change survives ticks and wakes');
                clock(7, 0);
                wait(200);
                verify(!NightMode.on, 'end boundary leaves an override that already matches');
                clock(22, 0);
                mode(true);
                verify(NightMode.setSchedule('08:00', '18:00'), 'daytime range accepted');
                mode(false);
                clock(12, 0);
                mode(true);
                verify(!NightMode.scheduledOn(at(7, 59)), 'before daytime range');
                verify(!NightMode.scheduledOn(at(18, 0)), 'after daytime range');
                NightMode.setAutomatic(false);
                clock(23, 0);
                mode(true);
                NightMode.toggle();
                mode(false);
                const found = {dials: []};
                controls(popup, found);
                const scheduleToggle = found.off;
                verify(scheduleToggle && found['night mode'] && !found.apply, 'popup controls apply automatically');
                verify(!scheduleToggle.lit && scheduleToggle.glyph === '', 'off toggle is inactive');
                compare(found.dials.length, 2, 'both times use numeric dials');
                function arrows(item, found) {
                    if (item.objectName === 'increase' || item.objectName === 'decrease') found[item.objectName] = item;
                    for (const child of item.children) arrows(child, found);
                }
                const dial = found.dials[0], buttons = {};
                arrows(dial, buttons);
                const up = buttons.increase, down = buttons.decrease;
                mouseClick(up, up.width / 2, up.height / 2);
                compare(dial.value, '08:30', 'up advances half an hour');
                wait(300);
                compare(NightMode.startMinute, 480, 'dial changes wait for the debounce');
                mouseClick(up, up.width / 2, up.height / 2);
                wait(300);
                compare(NightMode.startMinute, 480, 'another edit restarts the debounce');
                tryVerify(() => NightMode.startMinute === 540, 1000);
                mouseClick(down, down.width / 2, down.height / 2);
                mouseClick(down, down.width / 2, down.height / 2);
                compare(dial.value, '08:00', 'down reverses half an hour');
                tryVerify(() => NightMode.startMinute === 480, 1000);
                dial.draftMinute = 1410;
                mouseClick(up, up.width / 2, up.height / 2);
                compare(dial.value, '00:00', 'up wraps at midnight');
                mouseClick(down, down.width / 2, down.height / 2);
                compare(dial.value, '23:30', 'down wraps at midnight');
                dial.draftMinute = 0;
                mousePress(up, up.width / 2, up.height / 2);
                compare(dial.draftMinute, 30, 'press takes one immediate step');
                wait(250);
                compare(dial.draftMinute, 30, 'hold waits before repeating');
                wait(650);
                const early = dial.draftMinute;
                verify(early > 30 && early % 30 === 0, 'held arrow repeats half-hour steps');
                wait(900);
                const middle = dial.draftMinute;
                wait(900);
                const late = dial.draftMinute;
                verify(late - middle > middle - early, 'repeat rate accelerates as the hold continues');
                compare(NightMode.startMinute, 480, 'held arrows keep postponing the save');
                mouseRelease(up, up.width / 2, up.height / 2);
                const released = dial.draftMinute;
                wait(200);
                compare(dial.draftMinute, released, 'release stops repeating');
                mousePress(down, down.width / 2, down.height / 2);
                wait(100);
                mouseMove(down, -10, down.height / 2);
                const outside = dial.draftMinute;
                wait(500);
                compare(dial.draftMinute, outside, 'leaving the arrow stops repeating');
                mouseRelease(down, -10, down.height / 2);
                compare(NightMode.startMinute, outside, 'range saves after pointer leaves the arrow');
                dial.draftMinute = 1290;
                mouseClick(up, up.width / 2, up.height / 2);
                const endButtons = {};
                arrows(found.dials[1], endButtons);
                found.dials[1].draftMinute = 1290;
                mouseClick(endButtons.increase, endButtons.increase.width / 2, endButtons.increase.height / 2);
                compare(found.dials[1].value, '22:30', 'end hops over the start instead of emptying the range');
                found.dials[1].draftMinute = 390;
                mouseClick(endButtons.increase, endButtons.increase.width / 2, endButtons.increase.height / 2);
                compare(dial.value, '22:00');
                compare(found.dials[1].value, '07:00');
                tryVerify(() => NightMode.startMinute === 1320 && NightMode.endMinute === 420, 1000);
                compare(NightMode.startMinute, 1320);
                compare(NightMode.endMinute, 420);
                mouseClick(scheduleToggle, scheduleToggle.width / 2, scheduleToggle.height / 2);
                mode(true);
                verify(scheduleToggle.label === 'on' && scheduleToggle.lit && scheduleToggle.glyph !== '', 'on toggle stays active with checkmark');
                mouseClick(scheduleToggle, scheduleToggle.width / 2, scheduleToggle.height / 2);
                verify(!NightMode.automatic && scheduleToggle.label === 'off' && !scheduleToggle.lit && scheduleToggle.glyph === '', 'toggle returns to off');
                mouseClick(scheduleToggle, scheduleToggle.width / 2, scheduleToggle.height / 2);
                mode(true);
                NightMode.setBrightness(50);
                tryVerify(() => NightMode.brightness === 50 && !NightMode.on, 2000);
                clock(23, 30);
                wait(200);
                verify(NightMode.automatic && !NightMode.on, 'manual brightness holds and keeps the schedule');
                NightMode.setAutomatic(false);
                NightMode.setAutomatic(true);
                mode(true);
                NightMode.nudge(true);
                mode(false);
                clock(23, 45);
                wait(200);
                verify(NightMode.automatic && !NightMode.on, 'manual scroll holds and keeps the schedule');
                NightMode.setAutomatic(false);
                NightMode.setAutomatic(true);
                mode(true);
                const preview = Quickshell.env('QUICKSHELL_DISPLAY_PREVIEW');
                if (preview) {
                    let saved = false;
                    popup.grabToImage(result => { saved = result.saveToFile(preview); });
                    tryVerify(() => saved, 1000);
                }
                const transient = Qt.createQmlObject('import qs.components; DisplayPopup {}', popup.parent);
                const temporary = {dials: []};
                controls(transient, temporary);
                temporary.dials[0].step(1);
                transient.destroy();
                tryVerify(() => NightMode.startMinute === 1350, 1000);
                compare(NightMode.endMinute, 420, 'pending edit survives popup destruction');
                NightMode.setSchedule('22:00', '07:00');
                console.log('PASS: time ranges, wake reconciliation, numeric dials, debounce, popup closure and manual controls');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + ' ' + e.stack); } Qt.quit(); } }
    }
}
'''

RESTART = r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    property var service: NightMode
    TestCase {
        id: test; when: false
        function run() {
            tryVerify(() => NightMode.restored, 2000);
            verify(NightMode.automatic, 'automatic restored');
            compare(NightMode.startMinute, 1320);
            compare(NightMode.endMinute, 420);
            tryVerify(() => NightMode.on === NightMode.scheduledOn(WallClock.now), 2000);
            console.log('PASS: schedule survives restart and applies current local time');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + ' ' + e.stack); } Qt.quit(); } }
}
'''

RETRY = r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    property var service: NightMode
    FileView { id: failDdc; path: Quickshell.shellPath('fail-ddc'); printErrors: false }
    FileView { id: attempts; path: Quickshell.shellPath('ddc-attempts'); printErrors: false }
    TestCase {
        id: test; when: false
        function count() { attempts.reload(); attempts.waitForJob(); return attempts.text().trim().split('\n').length; }
        function run() {
            tryVerify(() => NightMode.restored, 2000);
            NightMode.setAutomatic(false);
            NightMode.setBrightness(50);
            tryVerify(() => !NightMode.on && NightMode.committed === 50, 2000);
            wait(30);
            WallClock.sample(new Date(2026, 9, 6, 23, 0).getTime());
            failDdc.setText('fail'); failDdc.waitForJob();
            const before = count();
            NightMode.setAutomatic(true);
            tryVerify(() => count() === before + 1, 2000);
            wait(200);
            compare(count(), before + 1, 'failed command does not immediately loop');
            verify(!NightMode.on, 'failure preserves off state');
            failDdc.setText('ok'); failDdc.waitForJob();
            WallClock.sample(WallClock.now + 5000);
            tryVerify(() => NightMode.on, 2000);
            compare(count(), before + 2, 'next clock check retries successfully');
            console.log('PASS: failed scheduled change waits for next clock check before retry');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + ' ' + e.stack); } Qt.quit(); } }
}
'''


def run_shell(target, scenario, env):
    (target / 'shell.qml').write_text(scenario)
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end='')
    assert result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output, output
    for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration',
                  'Cannot assign', 'Unable to assign'):
        assert error not in output, output
    assert output.count('Could not set scheduled night mode') == (1 if scenario == RETRY else 0), output


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-night-test-') as folder:
        target = Path(folder)
        for name in ('services', 'components', 'bin', 'runtime'):
            (target / name).mkdir(mode=0o700)
        display = target / 'display.sh'
        source = (Path.home() / '_scripts/display.sh').read_text()
        for name in ('brightness', 'night-mode', 'brightness.lock'):
            source = source.replace('/tmp/flag-' + name, str(target / name))
        display.write_text(source)
        display.chmod(0o700)
        (target / 'bin/ddcutil').write_text('''#!/bin/sh
if [ "$3" = getvcp ]; then
    echo 'current value = 30'
else
    echo "$5" >> "$(dirname "$0")/../ddc-attempts"
    [ "$(cat "$(dirname "$0")/../fail-ddc" 2>/dev/null)" != fail ] || exit 1
    echo "$5" >> "$(dirname "$0")/../ddc-calls"
fi
''')
        (target / 'bin/hyprctl').write_text('#!/bin/sh\nexit 0\n')
        for command in ('ddcutil', 'hyprctl'):
            (target / 'bin' / command).chmod(0o700)
        env = dict(os.environ, PATH=str(target / 'bin') + ':' + os.environ['PATH'],
                   QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   XDG_RUNTIME_DIR=str(target / 'runtime'))
        for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'DBUS_SESSION_BUS_ADDRESS'):
            env.pop(key, None)

        # Execute the actual script with fixture hardware, including concurrent enables.
        processes = [subprocess.Popen([str(display), 'night-on'], env=env) for _ in range(2)]
        assert all(process.wait(timeout=2) == 0 for process in processes)
        assert (target / 'night-mode').exists()
        assert (target / 'ddc-calls').read_text().splitlines() == ['0']
        subprocess.run([str(display), 'night-off'], env=env, check=True)
        subprocess.run([str(display), 'night-off'], env=env, check=True)
        assert not (target / 'night-mode').exists()
        assert (target / 'ddc-calls').read_text().splitlines() == ['0', '100']
        (target / 'fail-ddc').write_text('fail')
        assert subprocess.run([str(display), 'night-on'], env=env).returncode == 1
        assert not (target / 'night-mode').exists()
        (target / 'fail-ddc').unlink()
        print('PASS: display commands are idempotent, serialized and preserve flags on DDC failure')

        for name in ('services/NightMode.qml', 'services/WallClock.qml', 'Theme.qml',
                     'components/DisplayPopup.qml', 'components/PopupHeader.qml',
                     'components/PopupButton.qml', 'components/PopupText.qml', 'components/Slider.qml'):
            shutil.copy(ROOT / name, target / name)
        # Pin the clock while pointer tests wait; samples still exercise real wake detection.
        clock = target / 'services/WallClock.qml'
        clock.write_text(clock.read_text().replace('running: true', 'running: false'))
        (target / 'Settings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }\n')
        (target / 'Paths.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
QtObject {
    function state(name) { return Quickshell.shellPath(name); }
    function script(name) { return Quickshell.shellPath(name); }
}
''')
        (target / 'components/Glyph.qml').write_text('import QtQuick\nItem { property string text: ""; property int fontSize: 12; property color color: "white"; implicitWidth: 12 }\n')
        (target / 'components/Popup.qml').write_text('''import QtQuick
Item {
    default property alias content: body.data
    property alias spacing: body.spacing
    property bool acceptsKeyboard: false
    implicitWidth: body.implicitWidth + 12
    implicitHeight: body.implicitHeight + 12
    Rectangle { anchors.fill: parent; color: '#242424'; radius: 8 }
    Column { id: body; x: 6; y: 6 }
}
''')
        service = target / 'services/NightMode.qml'
        source = service.read_text().replace('/tmp/flag-brightness', str(target / 'brightness'))
        source = source.replace('/tmp/flag-night-mode', str(target / 'night-mode'))
        service.write_text(source)
        run_shell(target, SCENARIO, env)
        saved = json.loads((target / 'night-mode.json').read_text())
        assert saved == {'automatic': True, 'startMinute': 1320, 'endMinute': 420}, saved
        run_shell(target, RESTART, env)
        run_shell(target, RETRY, env)


if __name__ == '__main__':
    main()
