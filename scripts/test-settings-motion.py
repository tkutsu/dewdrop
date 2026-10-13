#!/usr/bin/env python3
"""Keep settings content width and wrapping stable while the window animates."""

from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.modules
ShellRoot {
    SettingsMenu { id: menu }
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
        function words(item) {
            if (item.wrapMode === Text.Wrap && item.text) return item;
            for (const child of item.children) { const found = words(child); if (found) return found; }
            return null;
        }
        function run() {
            menu.contentAlpha = 1;
            tryVerify(() => words(menu.auditContent) !== null, 1000);
            const description = words(menu.auditContent);
            const before = description.height;
            for (const ratio of [1.05, 0.95, 0.99, 1.03, 1]) {
                menu.widthRatio = ratio; wait(20);
                check(menu.auditContent.width === menu.boxWidth, 'settings content stays at its resting width: ' + ratio);
                check(Math.abs(menu.auditContent.x + menu.auditContent.width / 2 - menu.auditBox.width / 2) <= 0.5, 'content stays centred: ' + ratio);
                check(description.height === before, 'description wrapping stays fixed: ' + ratio);
            }
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-settings-motion-') as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / 'modules/SettingsMenu.qml').read_text()
        start = source.index('    // --- the pages ')
        end = source.index('    // --- the box ', start)
        description = 'Settings descriptions keep their line breaks while the surrounding window expands and contracts. ' * 4
        data = '    readonly property var pages: [{title: "Fixture"}]\n    readonly property var entries: [{id: "#fixture", heading: "Fixture", text: "' + description + '"}]\n\n'
        source = source[:start] + data + source[end:]
        source = source.replace('id: root', 'id: root\n    property alias auditContent: content\n    property alias auditBox: box', 1)
        (target / 'modules/SettingsMenu.qml').write_text(source)
        (target / 'services/Preferences.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool shown: false; property int dismissMs: 260; function hide() { shown = false; } }')
        (target / 'components/OverlayWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / 'components/BackdropProbe.qml').write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property real luma: 0.5 }')
        (target / 'components/SettingRow.qml').write_text('import QtQuick\nItem { required property var setting }')
        (target / 'components/Glyph.qml').write_text('import QtQuick\nItem { property string text; property real fontSize; property color color }')
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 15 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
