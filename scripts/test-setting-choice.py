#!/usr/bin/env python3
"""Exercise the real choice capsule with held clicks and pointer drags."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SHELL = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.components
ShellRoot {
    Window {
        visible: true; width: 400; height: 100
        QtObject {
            id: state
            property int value: 0
            property int writes: 0
            readonly property string title: "Mode"
            readonly property var options: [{label: "Off", value: 0}, {label: "On", value: 1}, {label: "Auto", value: 2}]
            function get() { return value; }
            function set(value) { state.value = value; writes++; }
        }
        SettingChoice { id: choice; x: 20; y: 20; setting: state }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log('PASS: ' + message);
            }
            function settle(mark) {
                tryVerify(() => Math.abs(mark.width - choice.shown.width) < 0.05
                    && Math.abs(mark.x - choice.shown.parent.x - choice.shown.x) < 0.05, 1000);
            }
            function run() {
                mouseClick(choice, choice.width / 2, choice.height / 2);
                check(state.value === 1 && state.writes === 1, 'a short click selects once');
                mousePress(choice, choice.width - 10, choice.height / 2);
                wait(1200);
                check(state.value === 1, 'holding a choice waits for release');
                mouseRelease(choice, choice.width - 10, choice.height / 2);
                check(state.value === 2 && state.writes === 2, 'a held click selects once on release');

                const mark = choice.children.find(child => child.gradient && child.gradient.stops);
                settle(mark);
                const right = mark.x + mark.width;
                const originalX = mark.x;
                const originalWidth = mark.width;
                const topColor = mark.gradient.stops[0].color.toString();
                const bottomColor = mark.gradient.stops[1].color.toString();
                mousePress(choice, 10, choice.height / 2);
                wait(500);
                check(mark.gradient.stops[0].color.toString() === topColor && mark.gradient.stops[1].color.toString() === bottomColor, 'pressing preserves the highlight brightness');
                check(mark.x < originalX - 3 && mark.width > originalWidth + 3 && Math.abs(mark.x + mark.width - right) < 1, 'pressing left stretches the highlight left with its right edge fixed');
                mouseRelease(choice, 10, choice.height / 2);
                check(state.value === 0 && state.writes === 3, 'the left choice commits on release');
                settle(mark);
                const left = mark.x;
                const leftWidth = mark.width;
                mousePress(choice, choice.width - 10, choice.height / 2);
                wait(500);
                check(Math.abs(mark.x - left) < 1 && mark.width > leftWidth + 3, 'pressing right stretches the highlight right with its left edge fixed');
                mouseRelease(choice, choice.width - 10, -20);
                settle(mark);
                check(state.value === 0 && state.writes === 3 && Math.abs(mark.width - leftWidth) < 1, 'releasing outside cancels and restores the highlight');

                mousePress(choice, choice.width - 10, choice.height / 2);
                mouseMove(choice, choice.width - 12, choice.height / 2);
                wait(1200);
                mouseRelease(choice, choice.width - 12, choice.height / 2);
                check(state.value === 2 && state.writes === 4, 'a held click tolerates small pointer movement');

                mousePress(choice, choice.width - 10, choice.height / 2);
                mouseMove(choice, choice.width / 2, choice.height / 2, 30);
                mouseMove(choice, 10, choice.height / 2, 30);
                check(state.value === 2 && choice.shownIndex === 0, 'dragging previews the choice without committing');
                mouseRelease(choice, 10, choice.height / 2);
                check(state.value === 0 && state.writes === 5, 'dragging commits the final choice once');
                mouseClick(choice, 10, choice.height / 2);
                check(state.writes === 5, 'clicking the selected choice does not write again');
                choice.enabled = false;
                mouseClick(choice, choice.width - 10, choice.height / 2);
                check(state.value === 0 && state.writes === 5, 'disabled choices ignore clicks');
                choice.enabled = true;
                const cells = choice.children.find(child => child.children.some(option => option.modelData !== undefined));
                cells.children.find(option => option.index === 1).keyPress();
                check(state.value === 1 && state.writes === 6, 'keyboard selection still chooses');
                console.log('PASS: choice gestures and animation');
            }
        }
        Timer {
            interval: 100; running: true
            onTriggered: {
                try { test.run(); }
                catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); }
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-setting-choice-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(
            ['qs', '-p', str(target), '--no-color'], env=shell_env(target),
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'PASS: choice gestures and animation' in output and not any(
            error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')
        ), output


if __name__ == '__main__':
    main()
