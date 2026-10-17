#!/usr/bin/env python3
"""Render Wi-Fi variants and keep their layout fixed as signal strength changes."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
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
                layoutSource: Theme.glyph.wifiStrength[4]
                text: index % 6 === 5 ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[index % 6]
            }
        }
        TestCase {
            id: test
            when: false

            function check(ok, message) { if (!ok) throw Error(message); }

            function geometry(icon) {
                const art = icon.children[1];
                return [icon.width, art.x, art.y, art.item.drawn, art.item.inkX, art.item.inkWidth];
            }

            function test_geometry() {
                const ready = () => {
                    for (let index = 0; index < 12; index++) {
                        const icon = icons.itemAt(index);
                        const art = icon.children[1];
                        if (icon.shown !== icon.text || !art.item || art.item.extent <= 0
                                || art.item.status !== Image.Ready)
                            return false;
                    }
                    return true;
                };
                for (let attempt = 0; !ready() && attempt < 100; attempt++) wait(50);
                check(ready(), 'Wi-Fi drawings loaded and measured');
                for (let group = 0; group < 2; group++) {
                    const icon = icons.itemAt(group * 6);
                    const expected = geometry(icon);
                    check(expected[0] > 0, 'Measured Wi-Fi width');
                    for (let index = 0; index < 6; index++)
                        check(JSON.stringify(geometry(icons.itemAt(group * 6 + index))) === JSON.stringify(expected),
                                'Identical geometry for strength ' + index + ' at size ' + icon.fontSize);
                    for (let index of [4, 0, 3, 5, 1, 2]) {
                        icon.text = index === 5 ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[index];
                        wait(20);
                        check(icon.shown === icon.text && icon.children[1].item.status === Image.Ready, 'New strength shown');
                        check(JSON.stringify(geometry(icon)) === JSON.stringify(expected), 'Signal changes preserve geometry');
                    }
                }
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
        target = Path(folder)
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
