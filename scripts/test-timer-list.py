#!/usr/bin/env python3
"""Format the timer IPC list on demand while keeping its text and ordering."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.services
import "TimerAuditCounter.js" as Count
ShellRoot {
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
        function run() {
            tryVerify(() => Timers.restored, 1000);
            Timers._commit([
                {id:'paused', kind:'countdown', label:'rest', running:false, total:90000, left:90000},
                {id:'live', kind:'countdown', label:'live', running:true, total:120000, endsAt:Timers.now + 120000},
                {id:'alarm', kind:'alarm', label:'alarm', running:false, hour:8, minute:30, days:[], endsAt:Timers.now + 86400000}
            ]);
            Count.reset();
            Timers.now += 1000;
            check(Count.read() === 0, 'clock ticks do not format the unrequested IPC list');
            const listed = Timers.auditIpc.list();
            check(listed === '1:59  ·  live\\n1:30  ·  rest  ·  paused\\n08:30  ·  alarm', 'IPC list preserves running, paused and alarm order');
            check(Count.read() === 3, 'IPC request formats every entry once');
            Timers.ringing = [{id:'ring', kind:'countdown', label:'tea', total:30000, firedAt:Timers.now}];
            check(Timers.auditIpc.list() === 'tea — click to dismiss', 'ringing entries retain their dismissal text');
            Timers.ringing = []; Timers._commit([]);
            check(Timers.auditIpc.list() === 'No timers', 'empty IPC list retains its message');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-timer-list-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'TimerAuditCounter.js').write_text('.pragma library\nvar calls = 0;\nfunction bump() { calls++; }\nfunction read() { return calls; }\nfunction reset() { calls = 0; }\n')
        source = (target / 'services/Timers.qml').read_text()
        source = source.replace('import QtQuick', 'import "../TimerAuditCounter.js" as Count\nimport QtQuick', 1)
        source = source.replace('id: root', 'id: root\n    property alias auditIpc: auditIpc', 1)
        source = source.replace('IpcHandler {', 'IpcHandler {\n        id: auditIpc', 1)
        source = source.replace('function describe(e: var): string {', 'function describe(e: var): string {\n        Count.bump();', 1)
        source = source.replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]')
        (target / 'services/Timers.qml').write_text(source)
        (target / 'services/Pushover.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string phoneWarning: ""; signal failed(string reason); signal acknowledged(string id, double firedAt); function notifyPhone(title, body, entry) {} function dismiss() {} }')
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 5 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
