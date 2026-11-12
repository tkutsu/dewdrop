#!/usr/bin/env python3
"""Exercise timer placement, visibility, badges and legacy clock migration."""

from pathlib import Path
from test_support import fixture_root
import json
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


def block(source, marker, start):
    at = source.rindex(start, 0, source.index(marker))
    opening = source.index('{', at)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[at:end]


QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.bar
import qs.src.components
import qs.src.modules
import qs.src.services as Services
ShellRoot {
    FloatingWindow {
        id: bar
        implicitWidth: 1200; implicitHeight: 100
        readonly property real clockRight: clockPill.x + clockPill.width
        QtObject { id: drawer; property bool out: false }
        Item { id: wallpaperImage }
        Morph { id: countdownMorph; open: countdown.popupOpen }
        Pill {
            id: clockPill
            drawsSlab: false
            order: CentrePillOrder.keys
            Clock { id: clock; pinKey: "datetime" }
            TIMER_MODULE
        }
        Pill { id: rightPill; side: Pill.Side.Right; drawsSlab: false; order: RightPillOrder.keys }
        COUNTDOWN_PILL
        TestCase {
            id: test
            when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function settle() { wait(Theme.dropMs + Theme.foldMs + 200); }
            function run() {
                Settings.user = {dateFormat: 'd MMM', timeFormat: 'h:mm AP', timeCase: 'lowercase', datePosition: 'right', timePosition: 'centre', reduceMotion: REDUCED};
                check(Settings.datetimeFormat === 'd MMM h:mm AP' && Settings.datetimeCase === 'lowercase', 'legacy formats combine and preserve casing');
                check(CentrePillOrder.keys.slice(0, 3).join(',') === 'datetime,weather,email', 'saved central order combines clock slots without duplicates');
                check(RightPillOrder.keys.slice(0, 2).join(',') === 'datetime,network', 'saved right order retains its clock slot');
                check(Settings.modulePosition('datetime') === 'centre', 'combined clock inherits time placement');
                DrawerPins.pins = {time: true, date: false};
                check(DrawerPins.pinned('datetime'), 'clock inherits saved time pin');
                DrawerPins.setMode('datetime', 'auto');
                check(DrawerPins.mode('datetime') === 'auto' && DrawerPins.pins.time === undefined, 'Auto removes old clock pin overrides');
                Settings.setTwelveHour(false);
                check(Settings.datetimeFormat === 'd MMM H:mm' && !Settings.twelveHour, '24h toggle retains the date');
                Settings.setTwelveHour(true);
                check(Settings.datetimeFormat === 'd MMM h:mm AP' && Settings.twelveHour, '12h toggle retains the date');
                settle();
                check(clock.settingsKey === 'datetime' && clock.visible, 'single datetime module is visible');
                mouseClick(clock, clock.width / 2, clock.height / 2); wait(450);
                check(clock.popupOpen && clock.popupItem?.opened, 'left click on datetime opens calendar');
                OpenPopup.dismiss(); settle();
                check(timerModule.quiet && timerModule.stowed && countdown.stowed, 'idle timer is hidden in Auto');
                DrawerPins.setMode('countdown', 'pinned'); settle();
                check(!timerModule.stowed && timerModule.visible && countdown.stowed, 'pinning reveals idle timer icon');
                check(timerModule.icon.glyph === Theme.glyph.timer && timerModule.icon.badge === '', 'idle icon has no badge');
                mouseClick(timerModule, timerModule.width / 2, timerModule.height / 2); wait(450);
                check(timerModule.popupOpen && timerModule.popupItem?.opened, 'idle icon opens timer popup');
                Services.Timers.countdown(600000, 'Tea'); settle();
                check(!countdown.stowed && timerModule.popupOpen, 'creating a timer keeps its open editor accessible');
                OpenPopup.dismiss(); settle();
                check(!countdown.stowed && countdown.reveal === 1 && timerModule.stowed, 'active central timer expands and replaces its icon');
                check(countdownPill.x >= bar.clockRight, 'timer pill sits to the right of centre');
                Settings.set('countdownBadgeStyle', 'badge');
                check(countdown.runningCount === 1 && timerModule.icon.badge === '1', 'one active timer is counted');
                const beforeCollapse = JSON.stringify(Services.Timers.entries);
                const sideIcon = countdown.iconHandoff.source;
                mouseClick(sideIcon, sideIcon.width / 2, sideIcon.height / 2); settle();
                check(countdown.dismissed && countdown.stowed && countdown.reveal === 0, 'icon click collapses the side pill');
                check(timerModule.visible && !timerModule.stowed && timerModule.pill === clockPill, 'collapsed timer merges into its central slot');
                check(countdown.iconInCentre && timerModule.handoffProgress === 1 && timerModule.icon.opacity === 1, 'icon handoff lands completely in the central pill');
                check(timerModule.icon.badge === '1' && JSON.stringify(Services.Timers.entries) === beforeCollapse, 'collapse retains the badge and running timer');
                Services.Timers.tick(); settle();
                check(countdown.dismissed && countdown.stowed, 'ticks do not undo manual collapse');
                mouseClick(timerModule, timerModule.width / 2, timerModule.height / 2);
                let narrowest = timerModule.width;
                for (let elapsed = 0; elapsed < Theme.dropMs + Theme.foldMs + 200; elapsed += 16) {
                    wait(16);
                    check(timerModule.width <= narrowest + 1, 'the central slot stays shut once the icon leaves it: '
                        + timerModule.width + ' after ' + narrowest + ' at reveal ' + countdown.reveal.toFixed(2));
                    narrowest = Math.min(narrowest, timerModule.width);
                }
                check(!countdown.dismissed && !countdown.stowed && timerModule.stowed && !timerModule.popupOpen, 'central icon re-expands without opening the popup');
                mouseClick(countdown, countdown.width / 2, countdown.height / 2, Qt.RightButton); settle();
                check(countdown.dismissed && timerModule.visible && JSON.stringify(Services.Timers.entries) === beforeCollapse, 'right click collapses and leaves timer state unchanged');
                mouseClick(timerModule, timerModule.width / 2, timerModule.height / 2); settle();
                const first = Services.Timers.entries[0];
                Services.Timers.toggle(first.id); settle();
                check(!countdown.stowed && timerModule.activeCount === 0, 'paused timer retains its controls without an active badge');
                Services.Timers.toggle(first.id);
                const alarm = {id: 'alarm', kind: 'alarm', hour: 20, minute: 5, label: 'Dinner', running: true, days: [], endsAt: Date.now() + 7200000};
                Services.Timers._commit([...Services.Timers.entries, alarm]); settle();
                check(timerModule.activeCount === 2 && countdown.runningCount === 2, 'timers and enabled alarms share the badge');
                OpenPopup.set(countdown); wait(450);
                check(countdown.popupOpen && countdown.popupItem?.opened, 'expanded pill opens timer controls');
                Settings.set('countdownPosition', 'right'); settle();
                check(!countdown.popupOpen, 'moving timers closes their outgoing side popup');
                check(timerModule.pill === rightPill && !timerModule.stowed && countdown.stowed && countdown.reveal === 0, 'right placement shows an icon and retracts the side pill');
                for (const style of ['badge', 'dot', 'underdot', 'hide']) {
                    Settings.set('countdownBadgeStyle', style); wait(20);
                    check(timerModule.icon.badge === (style === 'hide' ? '' : '2'), 'badge visibility: ' + style);
                    check(timerModule.icon.dot === (style === 'dot') && timerModule.icon.underdot === (style === 'underdot'), 'badge shape: ' + style);
                }
                DrawerPins.setMode('countdown', 'drawer'); settle();
                check(timerModule.stowed && countdown.stowed, 'Drawer override hides active right timers');
                drawer.out = true; settle();
                check(timerModule.visible && !timerModule.stowed, 'drawer reveals the timer icon');
                Settings.set('countdownPosition', 'centre'); settle();
                check(timerModule.visible && !countdown.stowed, 'open drawer keeps expanded timer module movable');
                drawer.out = false; settle();
                check(timerModule.stowed && countdown.stowed, 'Drawer override hides central expansion');
                DrawerPins.setMode('countdown', 'auto'); settle();
                check(!countdown.stowed && timerModule.stowed, 'Auto restores active central expansion');
                Services.Timers._commit([alarm]); settle();
                check(countdown.target.id === alarm.id && !countdown.stowed, 'alarm alone expands the pill');
                countdown.collapse(); settle();
                Services.Timers.ringing = [{id: alarm.id, kind: 'alarm', label: 'Dinner', firedAt: Date.now()}]; settle();
                check(!countdown.dismissed && !countdown.stowed, 'ringing re-expands a manually collapsed timer');
                check(timerModule.activeCount === 1 && countdown.runningCount === 1, 'a ringing recurring alarm is counted once');
                Services.Timers.ringing = [];
                Services.Timers._commit([Object.assign({}, alarm, {running: false})]); settle();
                check(timerModule.stowed && countdown.stowed, 'disabled alarms leave Auto quiet');
                Services.Timers._commit([]); settle();
                Services.Timers.countdown(600000, 'Landing'); settle();
                Services.Timers.toggle(Services.Timers.entries[0].id); settle();
                check(!countdown.stowed && timerModule.stowed, 'paused timer is open in its side pill');
                Services.Timers.cancel(Services.Timers.entries[0].id);
                let landed = false;
                for (let i = 0; i < 200 && countdown.reveal > 0; i++) {
                    wait(10);
                    landed = landed || (timerModule.visible && timerModule.icon.opacity > 0.99
                        && timerModule.icon.glyph === Theme.glyph.timerPaused);
                }
                // Reduce Motion retracts every side pill in one step, with no flight to land.
                check(landed || Theme.reduceMotion, 'the last timer lands in the central slot, as it was, before leaving');
                settle();
                check(timerModule.stowed && !timerModule.visible, 'the empty slot folds away after landing');
                drawer.out = true; wait(50);
                check(timerModule.icon.glyph === Theme.glyph.timer, 'an idle icon shown again is the plain timer');
                drawer.out = false; settle();
                Services.Timers.countdown(600000, 'Last Timer'); settle();
                OpenPopup.set(countdown); wait(450);
                const cancel = countdown.popupItem.keyTargets().find(item => item.name === 'Cancel Last Timer');
                check(cancel !== undefined, 'expanded timer exposes cancel action');
                cancel.tapped(); settle();
                check(OpenPopup.owner === null && countdown.stowed, 'last cancellation closes popup and retracts side pill');
                drawer.out = true; settle();
                check(timerModule.visible && !timerModule.stowed && countdown.stowed, 'empty timer remains reachable through drawer');
                console.log('PASS: datetime calendar click, migration, timer placement, visibility, counts and indicator styles');
            }
        }
        Timer { interval: 200; running: true; onTriggered: {
            timerModule.parent = Qt.binding(() => Settings.modulePosition('countdown') === 'centre' ? clockPill.moduleHost : rightPill.moduleHost);
            timerModule.pinKey = 'countdown';
            try { test.run(); } catch (error) { console.log('FAIL: ' + error + '\\n' + error.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    source = (ROOT / 'src/bar/Bar.qml').read_text()
    qml = QML.replace('TIMER_MODULE', block(source, 'id: timerModule', 'Timers {'))
    qml = qml.replace('COUNTDOWN_PILL', block(source, 'id: countdownPill', 'SidePill {'))
    for reduced in (False, True):
        with tempfile.TemporaryDirectory(prefix='qs-datetime-modules-') as folder:
            target = fixture_root(folder)
            copy_shell(target)
            state = target / 'state/quickshell'
            state.mkdir(parents=True, exist_ok=True)
            (state / 'centre-pill.json').write_text(json.dumps({'order': ['date', 'weather', 'time', 'email']}))
            (state / 'right-pill.json').write_text(json.dumps({'order': ['time', 'network', 'date']}))
            service = target / 'src/services/Timers.qml'
            service.write_text(service.read_text().replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]'))
            (target / 'src/core/Notify.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function send(summary, body, options) {} }\n')
            (target / 'src/services/PhoneAlarms.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string phoneWarning: ""; signal failed(string reason); signal acknowledged(string id, double firedAt); signal finished(); function hasLive(id, firedAt) { return false; } function notifyPhone(title, body, entry) {} function dismiss() {} }\n')
            (target / 'shell.qml').write_text(qml.replace('REDUCED', str(reduced).lower()))
            result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            print(output, end='')
            assert result.returncode == 0 and 'PASS: datetime calendar click' in output, output
            assert not any(error in output for error in ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign', 'Cannot assign', 'Failed to load configuration')), output


if __name__ == '__main__':
    main()
