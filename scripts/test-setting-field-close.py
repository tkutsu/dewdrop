#!/usr/bin/env python3
"""Edit real settings fields through the settings loader and close lifecycle."""

from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    id: suite
    LazyLoader { id: menuLoader; active: Preferences.active; SettingsMenu {} }
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
        function editor(item) {
            if (item.stored !== undefined && item.selectByMouse !== undefined) return item;
            for (const child of item.children) { const found = editor(child); if (found) return found; }
            return null;
        }
        function open() {
            Preferences.toggle();
            tryVerify(() => menuLoader.item !== null && editor(menuLoader.item.auditContent) !== null, 1000);
            const input = editor(menuLoader.item.auditContent);
            wait(20);
            input.forceActiveFocus();
            check(input.activeFocus, 'settings text field owns focus');
            return input;
        }
        function press(input, key) {
            const host = test.parent;
            test.parent = input.parent;
            try { keyClick(key, Qt.NoModifier, 0); }
            finally { test.parent = host; }
        }
        function type(input, text) {
            input.selectAll();
            for (const character of text) press(input, character);
            if (input.text !== text) throw Error('typing did not reach the focused settings field');
        }
        function closed() { tryVerify(() => !Preferences.active && menuLoader.item === null, 1000); }
        function run() {
            let input = open();
            type(input, 'yyyy-MM-dd');
            Preferences.hide(); closed();
            check(Settings.dateFormat === 'yyyy-MM-dd', 'closing settings saves the focused draft');

            input = open(); type(input, 'dd/MM/yyyy');
            press(input, Qt.Key_Return); wait(20);
            check(Settings.dateFormat === 'dd/MM/yyyy', 'Enter saves a field');
            Preferences.hide(); closed();
            check(Settings.dateFormat === 'dd/MM/yyyy', 'closing an already saved field keeps its value');

            input = open(); type(input, 'MM-dd');
            press(input, Qt.Key_Escape); wait(20);
            check(Preferences.shown && input.text === 'dd/MM/yyyy', 'first Escape restores the edited field');
            press(input, Qt.Key_Escape); closed();
            check(Settings.dateFormat === 'dd/MM/yyyy', 'second Escape closes without saving the discarded draft');

            input = open(); type(input, 'ddd d MMM');
            menuLoader.item.auditFilter.forceActiveFocus(); wait(20);
            check(Settings.dateFormat === 'ddd d MMM', 'leaving a field saves its draft');
            Preferences.hide(); closed();

            input = open();
            Settings.set('dateFormat', 'yyyy/MM/dd'); wait(20);
            Preferences.hide(); closed();
            check(Settings.dateFormat === 'yyyy/MM/dd', 'an untouched focused field preserves external setting changes');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-field-close-') as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / 'modules/SettingsMenu.qml').read_text()
        start = source.index('    // --- the pages ')
        end = source.index('    // --- the box ', start)
        data = '''    readonly property var pages: [{title: "Fixture"}]
    readonly property var entries: [{id: "date", setting: {type: "text", title: "Date", get: () => Settings.dateFormat, set: value => Settings.set("dateFormat", value)}}]
'''
        source = source[:start] + data + source[end:]
        source = source.replace('id: root', 'id: root\n    property alias auditContent: content\n    property alias auditFilter: filter', 1)
        (target / 'modules/SettingsMenu.qml').write_text(source)
        # Substitute the Wayland surface; retain real field, row, menu and Preferences timing.
        (target / 'components/OverlayWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / 'components/BackdropProbe.qml').write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property real luma: 0.5 }')
        (target / 'components/HoverPopup.qml').write_text('import QtQuick\nItem { property Item anchorItem; property real anchorHeight; property bool hovered; property string text; property var item: null }')
        (target / 'components/Glyph.qml').write_text('import QtQuick\nItem { property string text; property real fontSize; property color color }')
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 12 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output
        assert '"dateFormat": "yyyy/MM/dd"' in (target / 'settings.json').read_text()


if __name__ == '__main__':
    main()
