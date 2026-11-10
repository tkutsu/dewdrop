#!/usr/bin/env python3
"""Hold the text cursor to its Settings: each animation, each shape, and staying
solid while typing and deleting."""

from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    Window {
        visible: true; width: 400; height: 80
        TextInput {
            id: input
            width: 300; text: "Wi a"; cursorVisible: true; font.pixelSize: 20
            cursorDelegate: TextCaret { textInput: input }
        }
        TextEdit {
            id: edit
            y: 40; width: 300; text: "x"; cursorVisible: true; font.pixelSize: 20
            cursorDelegate: TextCaret { textInput: edit }
        }
    }
    FontMetrics { id: metrics; font: input.font }
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
        function caretOf(field) {
            for (const child of field.children) if (child.covered !== undefined) return child;
            throw Error('no caret in field');
        }
        function samples(caret, count) {
            const seen = [];
            for (let i = 0; i < count; i++) { wait(70); seen.push(caret.opacity); }
            return seen;
        }
        function run() {
            const caret = caretOf(input);

            check(Settings.caretAnimation === 'phase' && Settings.caretShape === 'line', 'defaults to a phasing line');
            check(caret.width === 2, 'a line is two pixels wide');

            tryVerify(() => caret.opacity < 0.05, 1500);
            check(true, 'phase fades right out');
            input.cursorPosition = 1;
            wait(30);
            check(caret.opacity === 1, 'a move brings the cursor back at once');
            let held = [];
            for (let i = 0; i < 10; i++) { input.cursorPosition = i % 2 ? 1 : 2; held = held.concat(samples(caret, 2)); }
            check(held.every(o => o === 1), 'it stays solid through a burst of moves');
            check(samples(caret, 14).some(o => o > 0.1 && o < 0.9), 'phase passes through partial opacity once idle');

            Settings.set('caretAnimation', 'blink');
            wait(30);
            wait(500);
            const blinks = samples(caret, 20);
            check(blinks.every(o => o === 0 || o === 1) && blinks.includes(0) && blinks.includes(1), 'blink is hard on and off');
            input.cursorPosition = 2;
            wait(30);
            check(caret.opacity === 1, 'a move holds a blink solid too');

            Settings.set('caretAnimation', 'static');
            wait(30);
            check(samples(caret, 20).every(o => o === 1), 'static never changes');

            Settings.set('caretShape', 'block');
            wait(30);
            input.cursorPosition = 0;
            wait(30);
            check(caret.covered === 'W' && caret.width === Math.ceil(metrics.advanceWidth('W')), 'a block covers the letter under it');
            input.cursorPosition = 2;
            wait(30);
            check(caret.covered === '' && caret.width === Math.ceil(metrics.averageCharacterWidth), 'a block on a space takes an average width');
            input.cursorPosition = input.text.length;
            wait(30);
            check(caret.covered === '' && caret.width === Math.ceil(metrics.averageCharacterWidth), 'a block at the end of the text takes an average width');
            check(caretOf(edit).block && caretOf(edit).covered === 'x', 'a TextEdit takes the same cursor');

            Settings.set('caretAnimation', 'sparkle');
            Settings.set('caretShape', 'star');
            wait(30);
            check(Settings.caretAnimation === 'phase' && Settings.caretShape === 'line', 'unknown values fall back to the defaults');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-text-caret-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 14 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop', '@components/TextCaret')), output


if __name__ == '__main__':
    main()
