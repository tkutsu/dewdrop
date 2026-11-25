#!/usr/bin/env python3
"""Draw the Wi-Fi mark at every strength: one box per size, the right parts lit."""

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
        visible: true; implicitWidth: 500; implicitHeight: 120
        Repeater {
            id: icons
            model: 12
            Glyph {
                x: (index % 6) * 60; y: Math.floor(index / 6) * 50
                height: 40
                fontSize: index < 6 ? Theme.trayGlyphSize : Theme.popupGlyphSize
                text: index % 6 === 5 ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[index % 6]
            }
        }
        TestCase {
            id: test
            when: false

            function check(ok, message) { if (!ok) throw Error(message); }

            function mark(icon) {
                return icon.children.find(child => child.item instanceof WifiMark);
            }

            function geometry(icon) {
                const art = mark(icon);
                return [icon.width, art.x, art.y, art.width, art.height];
            }

            // Dot, then the arcs from the inside out: 1 lit, 0 faint.
            function lit(icon) {
                const art = mark(icon).item;
                return [0, 1, 2, 3].map(part => art.ink(part).a === icon.inkColor.a ? 1 : 0);
            }

            function expected(index) {
                return index === 5 ? [0, 0, 0, 0] : [1, index > 1 ? 1 : 0, index > 2 ? 1 : 0, index > 3 ? 1 : 0];
            }

            function test_geometry() {
                for (let index = 0; index < 12; index++) {
                    const icon = icons.itemAt(index);
                    check(icon.shown === icon.text && mark(icon), 'Wi-Fi drawn in code for ' + icon.text);
                }
                for (let group = 0; group < 2; group++) {
                    const icon = icons.itemAt(group * 6);
                    const box = geometry(icon);
                    check(box[0] > 0 && box[3] % 2 === 1, 'An odd width, for the dot to sit on a pixel: ' + box);
                    for (let index = 0; index < 6; index++) {
                        const other = icons.itemAt(group * 6 + index);
                        check(JSON.stringify(geometry(other)) === JSON.stringify(box),
                                'Identical geometry for strength ' + index + ' at size ' + icon.fontSize);
                        check(JSON.stringify(lit(other)) === JSON.stringify(expected(index)),
                                'Strength ' + index + ' lights ' + expected(index) + ', not ' + lit(other));
                    }
                    for (let index of [4, 0, 3, 5, 1, 2]) {
                        icon.text = index === 5 ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[index];
                        check(icon.shown === icon.text, 'New strength shown at once');
                        check(JSON.stringify(geometry(icon)) === JSON.stringify(box), 'Signal changes preserve geometry');
                        check(JSON.stringify(lit(icon)) === JSON.stringify(expected(index)), 'Signal changes relight the parts');
                    }
                }
                check(geometry(icons.itemAt(0))[4] === 13, 'Thirteen pixels of ink at the bar size');
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.test_geometry();
                console.log('PASS: Wi-Fi geometry identical at bar and popup sizes, including signal changes');
            } catch (error) { console.log('FAIL: ' + error); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-wifi-geometry-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(QML)
        result = subprocess.run(
            ['qs', '-p', folder, '--no-color'], env=shell_env(target),
            capture_output=True, text=True, timeout=15,
        )
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'PASS: Wi-Fi geometry identical' in output and 'FAIL:' not in output, output
        for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration',
                      'Cannot assign', 'Unable to assign'):
            assert error not in output, output


if __name__ == '__main__':
    main()
