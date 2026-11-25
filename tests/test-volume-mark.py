#!/usr/bin/env python3
"""Draw the speaker at every level and muted: one box per size, the waves lit in turn."""

from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 500; implicitHeight: 160
        Repeater {
            id: icons
            // Levels 0 to 6, then muted, at the bar's and the popup's sizes.
            model: 16
            Glyph {
                x: (index % 8) * 50; y: Math.floor(index / 8) * 50
                height: 40
                fontSize: index < 8 ? Theme.glyphSize : Theme.popupTextSize
                text: index % 8 === 7 ? Theme.glyph.muted : Theme.glyph.vol[index % 8]
            }
        }
        TestCase {
            id: test
            when: false

            function check(ok, message) { if (!ok) throw Error(message); }

            function mark(icon) {
                return icon.children.find(child => child.item instanceof VolumeMark);
            }

            function geometry(icon) {
                const art = mark(icon);
                return [icon.width, art.x, art.y, art.width, art.height];
            }

            // Body, inner wave, outer wave, as quarters of the ink's alpha.
            function quarters(icon) {
                const art = mark(icon).item;
                return [0, 1, 2].map(part => Math.round(4 * art.ink(part).a / icon.inkColor.a));
            }

            function expected(index) {
                const level = index === 7 ? -1 : index;
                return [4, 1 + Math.min(3, Math.max(0, level)), 1 + Math.min(3, Math.max(0, level - 3))];
            }

            function test_mark() {
                for (let index = 0; index < 16; index++) {
                    const icon = icons.itemAt(index);
                    check(icon.shown === icon.text && mark(icon), 'Speaker drawn in code for ' + icon.text);
                }
                for (let group = 0; group < 2; group++) {
                    const icon = icons.itemAt(group * 8);
                    const box = geometry(icon);
                    check(box[3] > 0 && box[4] > 0, 'The speaker has a box: ' + box);
                    for (let index = 0; index < 8; index++) {
                        const other = icons.itemAt(group * 8 + index);
                        check(JSON.stringify(geometry(other)) === JSON.stringify(box),
                                'Identical geometry for ' + other.text + ' at size ' + icon.fontSize);
                        check(JSON.stringify(quarters(other)) === JSON.stringify(expected(index)),
                                other.text + ' lights ' + expected(index) + ', not ' + quarters(other));
                        check(mark(other).item.pieces[1].length > 0 === (index === 7),
                                'Only muted cuts the body in two: ' + other.text);
                    }
                    for (let index of [6, 0, 7, 3, 1, 5]) {
                        icon.text = index === 7 ? Theme.glyph.muted : Theme.glyph.vol[index];
                        check(icon.shown === icon.text, 'New level shown at once');
                        check(JSON.stringify(geometry(icon)) === JSON.stringify(box), 'Level changes preserve geometry');
                        check(JSON.stringify(quarters(icon)) === JSON.stringify(expected(index)), 'Level changes relight the waves');
                    }
                }
                check(geometry(icons.itemAt(0))[4] === 12, 'Twelve pixels of ink at the bar size, as the font drew it');
                check(Theme.glyph.audioOff === Theme.glyph.muted, 'No output is the muted speaker');
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.test_mark();
                console.log('PASS: volume mark keeps its box at every level and lights its waves in turn');
            } catch (error) { console.log('FAIL: ' + error); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-volume-mark-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(QML)
        result = subprocess.run(
            ['qs', '-p', folder, '--no-color'], env=shell_env(target),
            capture_output=True, text=True, timeout=15,
        )
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'PASS: volume mark' in output and 'FAIL:' not in output, output
        for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration',
                      'Cannot assign', 'Unable to assign'):
            assert error not in output, output


if __name__ == '__main__':
    main()
