#!/usr/bin/env python3
"""Verify Bluetooth power refreshes against isolated adapters and busctl replies."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


BUSCTL = r'''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import time

folder = Path(__file__).parent
args = sys.argv[1:]
if 'wait' in args:
    with (folder / 'commands.jsonl').open('a') as log:
        print(json.dumps(args), file=log)
    sys.exit(1)
state = json.loads((folder / 'power.json').read_text())
with (folder / 'commands.jsonl').open('a') as log:
    print(json.dumps(args), file=log)
operation = next(word for word in args if word in ('get-property', 'set-property'))
path = args[args.index(operation) + 2]
if operation == 'get-property':
    value = state['adapters'][path]
    time.sleep(state.get('delay', 0.03))
    if state.get('probeFail', False):
        sys.exit(1)
    print('invalid' if state.get('malformed', False) else 'b ' + str(value).lower())
else:
    time.sleep(0.03)
    if state.get('setterFail', False):
        sys.exit(1)
    state['adapters'][path] = args[-1] == 'true'
    (folder / 'power.json').write_text(json.dumps(state))
'''

SHELL = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    property var service: Bluetooth
    FileView { id: power; path: Quickshell.shellPath('power.json'); printErrors: false }
    FileView { id: commands; path: Quickshell.shellPath('commands.jsonl'); printErrors: false }
    TestCase { id: test; when: false }
    Component {
        id: adapterFactory
        QtObject {
            property string dbusPath
            property bool enabled: true
            property bool discovering: false
            property QtObject devices: QtObject { property var values: [] }
        }
    }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log('PASS: ' + message);
    }
    function until(predicate, message) {
        const end = Date.now() + 1500;
        while (!predicate() && Date.now() < end) test.wait(10);
        check(predicate(), message);
    }
    function backend(state) {
        power.setText(JSON.stringify(state));
        power.waitForJob();
    }
    function log() {
        commands.reload();commands.waitForJob();
        return commands.text().trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    }
    function probes() { return log().filter(args => args.includes('get-property')).length; }
    function idle() {
        const end = Date.now() + 1500;
        do { test.wait(20); }
        while ((Bluetooth.auditProbe.running || Bluetooth.auditSetter.running || Bluetooth.powerRefreshPending)
            && Date.now() < end);
        if (Bluetooth.auditProbe.running || Bluetooth.auditSetter.running || Bluetooth.powerRefreshPending)
            throw Error('power commands did not finish');
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(!Bluetooth.present && !Bluetooth.on, 'missing adapter starts off');
                check(log().length === 0, 'missing adapter starts no power commands');
                Bluetooth.toggle();WallClock.wokeUp();idle();
                check(log().length === 0, 'toggle and wake do nothing without an adapter');

                const one = adapterFactory.createObject(root, {dbusPath:'/org/bluez/hci0'});
                const two = adapterFactory.createObject(root, {dbusPath:'/org/bluez/hci1'});
                MockBluetooth.defaultAdapter = one;
                until(() => Bluetooth.powered === false, 'startup probe overrides a stale enabled cache');
                check(!Bluetooth.on && Bluetooth.icon === 'off', 'powered-off radio keeps its off state and icon');
                idle();

                let before = probes();
                backend({adapters:{'/org/bluez/hci0':true,'/org/bluez/hci1':false}});
                WallClock.wokeUp();
                until(() => Bluetooth.powered === true, 'wake refreshes power without an adapter enabled event');
                check(probes() > before && Bluetooth.on, 'wake starts a direct power probe');
                idle();

                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':false}});
                one.enabled = false;
                until(() => !Bluetooth.on, 'external power-off follows the adapter enabled event');
                idle();
                backend({adapters:{'/org/bluez/hci0':true,'/org/bluez/hci1':false}});
                one.enabled = true;
                until(() => Bluetooth.on, 'external power-on follows the adapter enabled event');
                idle();

                Bluetooth.toggle();Bluetooth.toggle();
                until(() => !Bluetooth.on, 'toggle uses the direct setter and refreshes its result');
                idle();
                check(log().filter(args => args.includes('set-property')).length === 1,
                    'repeated toggles during a setter spawn only one command');
                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':false},setterFail:true});
                Bluetooth.toggle();idle();
                check(!Bluetooth.on, 'failed setter preserves the directly probed state');

                backend({adapters:{'/org/bluez/hci0':true,'/org/bluez/hci1':false},delay:0.25});
                before = probes();Bluetooth.refreshPower();
                until(() => probes() > before, 'delayed probe started on the old adapter');
                MockBluetooth.defaultAdapter = two;
                until(() => Bluetooth.powered === false, 'adapter replacement discards the old reply and probes the new adapter');
                check(!Bluetooth.on && Bluetooth.adapter === two, 'old adapter reply cannot power on the replacement');
                two.enabled = false;idle();

                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':false},delay:0.25});
                before = probes();Bluetooth.refreshPower();
                until(() => probes() > before, 'delayed probe starts before an external toggle');
                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':true}});
                two.enabled = true;
                until(() => Bluetooth.powered === true, 'enabled change during an active probe queues a fresh reply');
                idle();

                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':true},delay:0.25});
                before = probes();Bluetooth.refreshPower();
                until(() => probes() > before, 'delayed probe starts before wake');
                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':false}});
                WallClock.wokeUp();WallClock.wokeUp();
                until(() => Bluetooth.powered === false, 'wake during an active probe refreshes after its stale reply');
                idle();
                check(probes() === before + 2, 'overlapping wakes coalesce into one follow-up probe');

                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':true},probeFail:true});
                before = probes();Bluetooth.refreshPower();idle();
                check(probes() === before + 1 && !Bluetooth.on, 'failed probe preserves state without a retry loop');
                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':true},malformed:true});
                Bluetooth.refreshPower();idle();
                check(!Bluetooth.on, 'malformed power reply preserves state');
                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':true}});
                WallClock.wokeUp();
                until(() => Bluetooth.on, 'next wake recovers after failed probes');
                idle();

                backend({adapters:{'/org/bluez/hci0':false,'/org/bluez/hci1':false},delay:0.25});
                before = probes();Bluetooth.refreshPower();
                until(() => probes() > before, 'probe starts before adapter removal');
                MockBluetooth.defaultAdapter = null;
                test.wait(400);
                check(!Bluetooth.present && !Bluetooth.on && Bluetooth.powered === null,
                    'adapter removal discards the outstanding reply');
                before = probes();WallClock.wokeUp();Bluetooth.toggle();idle();
                check(probes() === before, 'removed adapter starts no further probes');
                check(!log().some(args => args.includes('wait')), 'no event-listener process is spawned');
                console.log('PASS: Bluetooth power lifecycle');
            } catch (error) { console.log('FAIL: ' + error + '\n' + error.stack); }
            Qt.quit();
        }
    }
}'''


STARTUP = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    property var service: Bluetooth
    TestCase { id: test; when: false }
    FileView { id: commands; path: Quickshell.shellPath('commands.jsonl'); printErrors: false }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            test.tryVerify(() => Bluetooth.powered === false, 1500);
            if (!Bluetooth.present || Bluetooth.on) throw Error('existing adapter startup state is wrong');
            commands.reload();commands.waitForJob();
            const log = commands.text().trim().split('\n').map(line => JSON.parse(line));
            if (!log.some(args => args.includes('get-property')) || log.some(args => args.includes('wait')))
                throw Error('startup must probe without an event listener');
            console.log('PASS: existing adapter startup');
        } catch (error) { console.log('FAIL: ' + error); }
        MockBluetooth.defaultAdapter = null;test.wait(100);Qt.quit();
    } }
}'''


def run_case(shell, adapter, expected):
    with tempfile.TemporaryDirectory(prefix='quickshell-bluetooth-power-') as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / 'services/Bluetooth.qml').read_text()
        source = source.replace('import Quickshell.Bluetooth as BlueZ', 'import qs.services as BlueZ')
        source = source.replace('BlueZ.Bluetooth.defaultAdapter', 'BlueZ.MockBluetooth.defaultAdapter')
        source = source.replace('id: root', 'id: root\n    property alias auditProbe: powerProbe\n    property alias auditSetter: powerSetter', 1)
        (target / 'services/Bluetooth.qml').write_text(source)
        (target / 'services/MockBluetooth.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property var defaultAdapter: ' + adapter + ' }\n')
        (target / 'Theme.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { readonly property var glyph: ({bluetooth:"on",bluetoothOff:"off"}) }\n')
        (target / 'power.json').write_text(json.dumps({'adapters': {
            '/org/bluez/hci0': False, '/org/bluez/hci1': False}}))
        (target / 'commands.jsonl').write_text('')
        (target / 'busctl').write_text(BUSCTL)
        (target / 'busctl').chmod(0o700)
        (target / 'shell.qml').write_text(shell)
        env = shell_env(target, PATH=str(target) + os.pathsep + os.environ['PATH'])
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign',
                  'Unable to assign', 'Failed to load configuration')
        return 0 if result.returncode == 0 and expected in output \
            and not any(error in output for error in errors) else 1


def main():
    lifecycle = run_case(SHELL, 'null', 'PASS: Bluetooth power lifecycle')
    startup = run_case(STARTUP, '''QtObject {
        property string dbusPath: "/org/bluez/hci0"
        property bool enabled: true
        property bool discovering: false
        property QtObject devices: QtObject { property var values: [] }
    }''', 'PASS: existing adapter startup')
    return max(lifecycle, startup)


if __name__ == '__main__':
    raise SystemExit(main())
