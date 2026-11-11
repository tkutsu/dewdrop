#!/usr/bin/env python3
"""Keep timer text attached to its glass during collapse and expansion."""

from pathlib import Path
from test_support import fixture_root
import runpy
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

block = runpy.run_path(str(ROOT / 'tests/test-datetime-modules.py'))['block']

QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.modules
import qs.src.services as Services
ShellRoot {
    FloatingWindow {
        id: bar
        implicitWidth: 600; implicitHeight: 80
        readonly property real clockRight: clockPill.x + clockPill.width
        Item { id: wallpaperImage }
        QtObject { id: drawer; property bool out: false }
        QtObject {
            id: timerModule
            property bool wantsExpansion: true
            property bool popupOpen: false
            property Item pill: clockPill
            property Item icon: mergedIcon
        }
        Pill {
            id: clockPill
            drawsSlab: false
            BarItem { BarText { text: "Clock" } }
            BarItem { Glyph { id: mergedIcon; text: Theme.glyph.timer } }
        }
        Morph { id: countdownMorph; open: countdown.popupOpen }
        TIMER_PILL
        TestCase {
            id: test
            when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function run() {
                countdown.foldDuration = 0;
                countdown._eased = 1; wait(300);
                const text = countdown.testLabel;
                const fullGlass = countdownPill.foldBox.z;
                const fullText = text.width;
                check(fullText > 20 && fullGlass > fullText, 'timer has a visible readout');
                countdown.collapse();
                let changing = 0;
                for (const reveal of [0.95, 0.9, 0.85, 0.8, 0.75, 0.65, 0.5, 0.4, 0.3, 0.15, 0]) {
                    countdown._eased = reveal; wait(20);
                    if (reveal === 0) {
                        check(!countdownPill.visible, 'fully collapsed pill is hidden');
                        continue;
                    }
                    const glassLoss = Math.max(0, fullGlass - countdownPill.foldBox.z);
                    const textLoss = fullText - text.width;
                    check(!(textLoss > 1 && glassLoss < 1), 'text retracts before glass at reveal ' + reveal
                        + ': text=' + text.width.toFixed(2) + '/' + fullText.toFixed(2)
                        + ', glass=' + countdownPill.foldBox.z.toFixed(2) + '/' + fullGlass.toFixed(2));
                    check(Math.abs(textLoss - Math.min(fullText, glassLoss)) <= 1,
                        'text and glass retract together at reveal ' + reveal);
                    if (textLoss > 1 && text.width > 1) changing++;
                }
                check(changing > 0, 'readout retracts gradually with its glass');
                check(countdown.iconInCentre && countdown.iconHandoff.progress === 1, 'icon still completes its central merge');
                countdown.expand();
                countdown._eased = 0.1; wait(20);
                check(text.width === 0, 'early entry keeps the readout covered');
                let growing = 0;
                for (const reveal of [0.2, 0.3, 0.4, 0.5, 0.525, 0.55, 0.575, 0.6, 0.65, 0.75, 0.85, 0.95, 1]) {
                    countdown._eased = reveal; wait(20);
                    check(!(countdownPill.foldBox.z >= fullGlass - 1 && text.width < fullText - 1),
                        'text waits after glass expands at reveal ' + reveal
                        + ': text=' + text.width.toFixed(2) + '/' + fullText.toFixed(2)
                        + ', glass=' + countdownPill.foldBox.z.toFixed(2) + '/' + fullGlass.toFixed(2));
                    if (text.width > 1 && text.width < fullText - 1) growing++;
                }
                check(growing > 0, 'readout expands gradually with its glass');
                check(countdown.reveal === 1 && Math.abs(text.width - fullText) <= 1, 're-expansion restores the readout');
                check(!countdown.iconInCentre && countdown.iconHandoff.progress === 0, 'expanded pill completes its icon handoff');
                console.log('PASS: timer text and glass move together in both directions; central icon merge remains intact');
            }
        }
        Timer { interval: 150; running: true; onTriggered: {
            try { test.run(); } catch (error) { console.log('FAIL: ' + error); }
            Qt.quit();
        } }
    }
}
'''


def main():
    qml = QML.replace('TIMER_PILL', block((ROOT / 'src/bar/Bar.qml').read_text(), 'id: countdownPill', 'SidePill {'))
    with tempfile.TemporaryDirectory(prefix='qs-timer-collapse-motion-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        countdown = target / 'src/modules/Countdown.qml'
        countdown.write_text(countdown.read_text().replace('id: root\n', 'id: root\n    readonly property alias testLabel: labelText\n', 1))
        (target / 'src/services/Timers.qml').write_text('''pragma Singleton
import QtQuick
import qs.src.core
QtObject {
    property bool loaded: true
    property var focus: ({id: 'test', running: true, total: 600000, label: 'Tea'})
    property var entries: [focus]
    property var ringing: []
    property var nextAlarm: null
    property real progress: 0.5
    property int beatMs: 3000
    property string label: '10:00'
    property string glyph: Theme.glyph.timer
}
''')
        (target / 'shell.qml').write_text(qml)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'PASS: timer text and glass move together in both directions' in output, output
        assert not any(error in output for error in ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign')), output


if __name__ == '__main__':
    main()
