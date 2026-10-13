#!/usr/bin/env python3
"""Exercise the tray's real menu loader through closing and rapid reopening."""

from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components as Components
ShellRoot {
    FloatingWindow {
        implicitWidth: 200; implicitHeight: 100
        Item {
            id: entry
            width: 30; height: 30
            property bool menuOpen: false
            property var modelData: ({hasMenu: true, menu: {}})
            MENU_LOADER
        }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
            function run() {
                entry.menuOpen = true; wait(20);
                let menu = testMenuLoader.item;
                check(menu && menu.requestedVisible && menu.opacity === 1, 'opening loads the visible tray menu');
                entry.menuOpen = false;
                check(testMenuLoader.item === menu && !menu.requestedVisible, 'closing keeps the menu for its exit');
                wait(60);
                check(menu.opacity > 0 && menu.opacity < 1, 'the closing menu draws its fade');
                entry.menuOpen = true; wait(20);
                check(testMenuLoader.item === menu && menu.requestedVisible, 'rapid reopening reuses the menu');
                wait(160);
                check(testMenuLoader.item === menu && menu.opacity === 1, 'reopening cancels pending unloading');
                entry.menuOpen = false; wait(180);
                check(testMenuLoader.item === null, 'closed menu unloads after its final frame');
                entry.menuOpen = true; wait(20);
                check(testMenuLoader.item && testMenuLoader.item.requestedVisible, 'menu opens again after unloading');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
    }
}'''


def main():
    source = (ROOT / 'modules/Tray.qml').read_text()
    start = source.find('            Linger {')
    if start < 0:
        start = source.index('            Loader {')
    block = source[start:].split('\n        }\n    }\n}', 1)[0]
    block = block.replace('sourceComponent: MenuPopup {', 'sourceComponent: Components.MenuPopup {')
    block = block.replace('Loader {', 'Loader {\n                objectName: "testMenuLoader"', 1)
    # Give the fixture access to the real loader without changing its behavior.
    if 'id: menuLoader' in block:
        block = block.replace('id: menuLoader', 'id: testMenuLoader')
        block = block.replace('menuLoader.', 'testMenuLoader.')
    else:
        block = block.replace('Loader {', 'Loader {\n                id: testMenuLoader', 1)
    with tempfile.TemporaryDirectory(prefix='quickshell-tray-lifetime-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'Settings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }')
        (target / 'OpenPopup.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function close(item) {} }')
        (target / 'components/MenuAnchor.qml').write_text('import QtQuick\nQtObject { property rect rect; property int edges; property int gravity }')
        (target / 'components/MenuPopup.qml').write_text('''import QtQuick
Item {
    property Item anchorItem
    property var handle
    property bool requestedVisible: true
    property int exitMs: 160
    property real shadowSide: 0
    property real shadowTop: 0
    property MenuAnchor anchor: MenuAnchor {}
    signal dismissed
    opacity: requestedVisible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }
}''')
        (target / 'shell.qml').write_text(SHELL.replace('MENU_LOADER', block))
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 7 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
