#!/usr/bin/env python3
"""Exercise timer resume, clock corrections and native alarm deadlines in isolation."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SIMULATED = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int wakes: 0
    TestCase { id: test; when: false }
    Connections { target: WallClock; function onWokeUp() { root.wakes++; } }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log('PASS: ' + message);
    }
    function jump(at) { AuditClock.now = at;WallClock.sample(at); }
    function reset() { Timers.hush();Timers._commit([]);Pushover.sent = []; }
    function alarm(id, endsAt, running = true, days = []) {
        return {id,kind:'alarm',label:id,running,endsAt,hour:8,minute:0,days};
    }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            test.tryVerify(() => Timers.restored, 1000);
            WallClock.auditSampler.stop();
            WallClock.now = AuditClock.read();
            let base = AuditClock.now;
            Timers._commit([alarm('resume', base + 3600000)]);
            jump(base + 3602000);
            check(Timers.entries.length === 0 && Timers.ringing.length === 1,
                'WallClock wake expires an alarm immediately after resume');
            check(wakes === 1 && Pushover.sent.length === 1, 'resume announces the alarm once; wakes=' + wakes + ', sends=' + Pushover.sent.length);
            WallClock.wokeUp();jump(AuditClock.now + 1000);
            check(Pushover.sent.length === 1, 'overlapping clock and wake events cannot fire the same alarm twice');
            jump(AuditClock.now + Timers.ringMs + 1);
            check(Timers.ringing.length === 0, 'wall-clock changes expire an unanswered ring');

            reset();base = AuditClock.now;
            Timers._commit([alarm('future', base + 7200000)]);
            check(Timers.auditAlarm.running && Timers.auditAlarm.interval === 7200000,
                'future alarm gets one full deadline instead of minute polling');
            jump(base + 3600000);
            check(Timers.auditAlarm.interval === 3600000 && Timers.entries.length === 1,
                'resume re-aims a future alarm without changing its deadline');
            const ordinary = wakes;
            jump(AuditClock.now + 5000);
            check(wakes === ordinary && Timers.auditAlarm.interval === 3595000,
                'ordinary clock samples preserve the precise remaining deadline');
            jump(AuditClock.now - 5000);
            check(wakes === ordinary && Timers.auditAlarm.interval === 3600000,
                'small backward correction re-aims the alarm even without a wake signal');
            jump(AuditClock.now - 20000);
            check(wakes === ordinary + 1 && Timers.auditAlarm.interval === 3620000,
                'large backward correction preserves the alarm instant');

            reset();base = AuditClock.now;
            Timers.countdown(45000, 'running');
            Timers._add(alarm('alongside', base + 20000));
            check(Timers.counting && !Timers.auditAlarm.running, 'running countdown owns the one-second tick');
            jump(base + 25000);
            check(Timers.timers.length === 1 && Timers.leftMs === 20000 && Timers.ringing.length === 1,
                'resume expires the alarm and preserves the running countdown remainder');
            jump(base + 46000);
            check(Timers.entries.length === 0 && Pushover.sent.length === 2,
                'overdue running countdown fires once on the shared clock');

            reset();base = AuditClock.now;
            Timers.countdown(90000, 'paused');
            const paused = Timers.timers[0].id;Timers.pause(paused);
            const left = Timers.timers[0].left;
            Timers._add(alarm('disabled', base + 1000, false));
            jump(base + 7200000);
            check(Timers.timers[0].left === left && Timers.alarms.length === 1 && Pushover.sent.length === 0,
                'resume preserves paused countdowns and disabled alarms');
            Timers.resume(paused);
            check(Timers.timers[0].endsAt === AuditClock.now + left && Timers.counting,
                'resuming a paused countdown starts from the current wall clock');

            reset();base = AuditClock.now;
            Timers._commit([alarm('old', base + 1000)]);
            jump(base + 1000 + Timers.graceMs + 1);
            check(Timers.entries.length === 0 && Pushover.sent.length === 0,
                'alarm outside the existing grace period is dropped quietly');
            reset();base = AuditClock.now;
            Timers._commit([alarm('boundary', base + 1000)]);
            jump(base + 1000 + Timers.graceMs);
            check(Pushover.sent.length === 1, 'the grace-period boundary remains inclusive');

            reset();base = AuditClock.now;
            Timers._commit([alarm('repeat', base + 1000, true, [0,1,2,3,4,5,6])]);
            jump(base + 2000);
            check(Timers.entries.length === 1 && Timers.entries[0].endsAt > AuditClock.now && Pushover.sent.length === 1,
                'saved repeating alarms retain their next occurrence after resume');
            jump(AuditClock.now + 1000);
            check(Pushover.sent.length === 1, 'the rescheduled repeating alarm cannot fire twice');

            reset();const ticks = Timers.auditTicks;
            jump(AuditClock.now + 5000);
            check(Timers.auditTicks === ticks && !Timers.auditAlarm.running,
                'empty timer service does no expiry work on clock samples');
            console.log('PASS: timer resume and clock changes');
        } catch (error) { console.log('FAIL: ' + error + '\n' + error.stack); }
        reset();Qt.quit();
    } }
}'''

NATIVE = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    TestCase { id: test; when: false }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            test.tryVerify(() => Timers.restored, 1000);
            WallClock.auditSampler.stop();
            const due = Date.now() + 350;
            Timers._commit([{id:'native',kind:'alarm',label:'native',running:true,endsAt:due,hour:8,minute:0,days:[]}]);
            test.tryVerify(() => Timers.ringing.length === 1, 1200);
            const late = Timers.ringing[0].firedAt - due;
            if (late < 0 || late > 250 || Pushover.sent.length !== 1)
                throw Error('native deadline late=' + late + ', sends=' + Pushover.sent.length);
            test.wait(150);
            if (Pushover.sent.length !== 1 || Timers.auditAlarm.running)
                throw Error('native alarm fired again or left its deadline armed');
            console.log('PASS: native alarm deadline without WallClock polling; lateness=' + late + 'ms');
        } catch (error) { console.log('FAIL: ' + error); }
        Timers.hush();Timers._commit([]);Qt.quit();
    } }
}'''


def run_case(shell, live, expected):
    with tempfile.TemporaryDirectory(prefix='quickshell-timer-wake-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'services/AuditClock.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property double now: Date.now(); '
            'property bool live: ' + str(live).lower() + '; function read() { return live ? Date.now() : now; } }\n')
        source = (target / 'services/Timers.qml').read_text().replace('Date.now()', 'AuditClock.read()')
        source = source.replace('id: root', 'id: root\n    property alias auditAlarm: wake\n    property int auditTicks: 0', 1)
        source = source.replace('function tick(): void {', 'function tick(): void {\n        root.auditTicks++;', 1)
        source = source.replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]')
        (target / 'services/Timers.qml').write_text(source)
        source = (target / 'services/WallClock.qml').read_text().replace('Date.now()', 'AuditClock.read()')
        source = source.replace('id: root', 'id: root\n    property alias auditSampler: sampler', 1)
        source = source.replace('    Timer {', '    Timer {\n        id: sampler', 1)
        (target / 'services/WallClock.qml').write_text(source)
        (target / 'services/Pushover.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var sent: []
    property string phoneWarning: ""
    signal failed(string reason)
    signal acknowledged(string id, double firedAt)
    function notifyPhone(title, body, entry) { sent = [...sent, entry]; }
    function dismiss() {}
}''')
        (target / 'shell.qml').write_text(shell)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target),
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign', 'Failed to load configuration')
        return 0 if result.returncode == 0 and expected in output and not any(error in output for error in errors) else 1


def main():
    resume = run_case(SIMULATED, False, 'PASS: timer resume and clock changes')
    native = run_case(NATIVE, True, 'PASS: native alarm deadline without WallClock polling')
    return max(resume, native)


if __name__ == '__main__':
    raise SystemExit(main())
