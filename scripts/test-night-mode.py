#!/usr/bin/env python3
"""Check night-mode scheduling, popup controls and display commands in isolation."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import copy_shell, shell_env

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
        width: 320; height: popup.height + 24
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
                if (item.name !== undefined && item.checked !== undefined && item.tapped !== undefined) found[item.name] = item;
                if (item.standalone === true && item.toggled !== undefined) found[item.name] = item;
                if (item.isChosen !== undefined && item.modelData !== undefined) found[item.modelData.label] = item;
                if (item.setting?.title === 'Night mode' && item.currentIndex !== undefined) found.picker = item;
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
                const off = 'off', on = 'on', auto = 'custom', picker = found.picker;
                verify(picker && !found.Schedule && !found.apply, 'one dropdown, applied at once, no switches');
                compare(picker.model.map(option => option.label).join('|'), 'Off|On|Auto|Custom');
                compare(NightMode.mode, off, 'the dropdown starts on Off');
                compare(found.dials.length, 2, 'both times use numeric dials');
                tryVerify(() => !found.dials[0].visible, 1000, 'the hours fold away off Custom');
                verify(!NightMode.tooltip.includes(':'), 'no schedule in the tooltip off Custom');
                function tap(value) { picker.activated(picker.model.findIndex(option => option.value === value)); }
                mouseClick(picker, picker.width / 2, picker.height / 2);
                tryVerify(() => picker.popup.visible, 1000);
                keyClick(Qt.Key_End);
                keyClick(Qt.Key_Return);
                verify(NightMode.mode === auto && NightMode.automatic, 'Custom hands the mode to the schedule');
                tryVerify(() => found.dials[0].visible && found.dials[0].parent.parent.opacity === 1, 1000);
                verify(NightMode.tooltip.endsWith(' · night mode off until 08:00'), NightMode.tooltip);
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
                mode(true);
                verify(NightMode.mode === auto && NightMode.automatic, 'a range around now turns night mode on');
                compare(NightMode.tooltip, 'Night mode on until 07:00');
                tap(off);
                verify(NightMode.mode === off && NightMode.on, 'Off holds while the screen catches up');
                mode(false);
                verify(NightMode.mode === off && !NightMode.automatic, 'Off takes the mode back');
                tryVerify(() => !found.dials[0].visible, 1000);
                verify(!NightMode.tooltip.includes(':'), 'Off drops the schedule from the tooltip');
                tap(on);
                verify(NightMode.mode === on, 'On holds while the screen catches up');
                mode(true);
                compare(NightMode.tooltip, 'Night mode on');
                tap(off);
                tap(on);
                mode(true);
                wait(300);
                verify(NightMode.mode === on && NightMode.on && NightMode.asked === '', 'the last pick wins over one still landing');
                tap(auto);
                mode(true);
                verify(NightMode.mode === auto, 'back on Custom');
                NightMode.setBrightness(50);
                tryVerify(() => NightMode.brightness === 50 && !NightMode.on, 2000);
                clock(23, 30);
                wait(200);
                verify(NightMode.automatic && !NightMode.on, 'manual brightness holds and keeps the schedule');
                verify(NightMode.mode === auto && NightMode.tooltip.endsWith(' · night mode off until 22:00'), NightMode.tooltip);
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
            compare(NightMode.mode, 'custom', 'legacy automatic hours restore as Custom');
            compare(NightMode.startMinute, 1320);
            compare(NightMode.endMinute, 420);
            tryVerify(() => NightMode.on === NightMode.scheduledOn(WallClock.now), 2000);
            console.log('PASS: schedule survives restart and applies current local time');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + ' ' + e.stack); } Qt.quit(); } }
}
'''

SOLAR = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.services
import qs.components
ShellRoot {
    Window {
        visible: true; width: 320; height: 280
        DisplayPopup { id: popup }
        TestCase {
            id: test; when: false
            function at(day, hour, minute = 0) { return Date.UTC(2026, 9, day, hour, minute); }
            function clock(day, hour, minute = 0) { WallClock.sample(at(day, hour, minute)); }
            function mode(on) { tryVerify(() => NightMode.on === on, 2000); wait(30); }
            function days(sunset = 18) {
                return [6, 7, 8].map(day => ({sunrise: at(day, 6) / 1000, sunset: at(day, sunset) / 1000,
                    hours: Array.from({length: 24}, (_, hour) => ({at: at(day, hour) / 1000}))}));
            }
            function run() {
                tryVerify(() => NightMode.restored && NightMode.flagKnown, 2000);
                NightMode.setMode('off'); mode(false);
                NightMode.setSchedule('22:00', '07:00');
                clock(6, 12);
                NightMode.setMode('auto');
                compare(NightMode.mode, 'auto');
                compare(NightMode.scheduledOn(at(6, 12)), null, 'no location means no solar action');
                verify(NightMode.solarInfo.includes('Settings > Weather'));
                Weather.location = {label: 'Solar fixture'};
                Weather.days = days();
                mode(false);
                compare(NightMode.scheduledOn(at(6, 5, 59)), true);
                compare(NightMode.scheduledOn(at(6, 6)), false, 'sunrise is exclusive');
                compare(NightMode.scheduledOn(at(6, 18)), true, 'sunset is inclusive');
                compare(NightMode.solar.next.at, at(6, 18) / 1000);
                verify(NightMode.solarInfo.startsWith('Sunset at '));
                clock(6, 18); mode(true);
                compare(NightMode.solar.next.at, at(7, 6) / 1000, 'next sunrise crosses city midnight');
                NightMode.toggle(); mode(false);
                clock(6, 19); WallClock.wokeUp(); wait(100);
                verify(!NightMode.on && NightMode.mode === 'auto', 'manual override holds until the boundary');
                Weather.days = days(); wait(100);
                verify(!NightMode.on, 'forecast refresh preserves the override');
                clock(7, 6); mode(false);
                clock(7, 18); mode(true);
                clock(8, 12); mode(false);
                clock(8, 19); mode(true);
                Weather.location = {label: 'Later sunset'};
                Weather.days = days(20);
                mode(false);
                compare(NightMode.solar.next.at, at(8, 20) / 1000, 'new city replaces solar times');
                clock(8, 20); mode(true);
                Weather.days = []; clock(9, 12); wait(100);
                verify(NightMode.on, 'missing data holds the current screen state');
                compare(NightMode.scheduledOn(at(9, 12)), null);
                Weather.days = days();
                compare(NightMode.scheduledOn(at(9, 12)), null, 'expired forecasts cannot drive Auto');
                NightMode.setMode('custom');
                compare(NightMode.startMinute, 1320, 'solar mode preserves custom hours');
                compare(NightMode.endMinute, 420);
                NightMode.setMode('auto');
                console.log('PASS: solar boundaries, city changes, missing data, expiry, overrides and custom hours');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + ' ' + e.stack); } Qt.quit(); } }
    }
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
            WallClock.sample(WallClock.now + 5000);
            wait(200);
            compare(count(), before + 1, 'ordinary clock ticks respect the retry delay');
            WallClock.sample(WallClock.now + 25000);
            tryVerify(() => count() === before + 2, 2000);
            wait(200);
            failDdc.setText('ok'); failDdc.waitForJob();
            WallClock.sample(WallClock.now + 30000);
            wait(200);
            compare(count(), before + 2, 'a second failure doubles the retry delay');
            WallClock.sample(WallClock.now + 30000);
            tryVerify(() => NightMode.on, 2000);
            compare(count(), before + 3, 'retry succeeds once the longer delay expires');
            failDdc.setText('fail'); failDdc.waitForJob();
            const capStart = count();
            const at = (hour) => new Date(2026, 9, 6, hour, 0).getTime();
            WallClock.sample(at(7));
            tryVerify(() => count() === capStart + 1, 2000);
            wait(200);
            for (const seconds of [30, 60, 120, 240, 300, 300]) {
                const prior = count();
                WallClock.sample(WallClock.now + (seconds - 5) * 1000);
                wait(100);
                compare(count(), prior, 'repeated failures wait through their backoff');
                WallClock.sample(WallClock.now + 5000);
                tryVerify(() => count() === prior + 1, 2000);
                wait(100);
            }
            WallClock.sample(at(22));
            wait(200);
            compare(count(), capStart + 7, 'a matching boundary needs no display command');
            WallClock.sample(at(7));
            tryVerify(() => count() === capStart + 8, 2000);
            wait(200);
            verify(NightMode.setSchedule('08:00', '18:00'), 'edited range remains valid');
            tryVerify(() => count() === capStart + 9, 2000);
            wait(200);
            failDdc.setText('ok'); failDdc.waitForJob();
            NightMode.setAutomatic(false); NightMode.setAutomatic(true);
            tryVerify(() => !NightMode.on, 2000);
            compare(count(), capStart + 10, 'explicit re-enabling retries immediately');
            console.log('PASS: scheduled failures back off, cap at five minutes, reset at boundaries and recover');
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
    assert output.count('Could not set scheduled night mode') == (11 if scenario == RETRY else 0), output


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-night-test-') as folder:
        target = Path(folder)
        copy_shell(target)
        for name in ('services', 'components', 'bin', 'runtime'):
            (target / name).mkdir(mode=0o700, exist_ok=True)
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
        env = shell_env(target, PATH=env["PATH"])
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
        (target / 'services/Weather.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var location: null; property var days: []; property bool loading: false }\n')
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
    property bool animateContents: true
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
        assert saved == {'automatic': True, 'scheduleKind': 'custom', 'startMinute': 1320, 'endMinute': 420}, saved
        del saved['scheduleKind']
        (target / 'night-mode.json').write_text(json.dumps(saved))
        run_shell(target, RESTART, env)
        run_shell(target, RETRY, env)
        run_shell(target, SOLAR, env)
        assert json.loads((target / 'night-mode.json').read_text())['scheduleKind'] == 'auto'


if __name__ == '__main__':
    main()
