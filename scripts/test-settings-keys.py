#!/usr/bin/env python3
"""Walk the settings window by keys: tabs with Up and Down, the page with Right and Left."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    SettingsMenu { id: menu }
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
        function press(key) {
            const host = test.parent;
            test.parent = menu.auditContent;
            try { keyClick(key, Qt.NoModifier, 0); }
            finally { test.parent = host; }
            wait(20);
        }
        function on(kind) { return menu.keyItem !== null && kind(menu.keyItem); }
        function isSwitch(t) { return t.standalone !== undefined; }
        function isSegment(t) { return t.isShown !== undefined; }
        function isDropdown(t) { return t.popup !== undefined; }
        function isField(t) { return t.edited !== undefined; }
        function run() {
            Preferences.shown = true;
            menu.requestActivate();
            tryVerify(() => menu.active, 1000);
            wait(100);
            const filter = menu.auditFilter;
            check(filter.activeFocus, 'the search has the keys on opening');

            press(Qt.Key_Down); check(menu.page === 1, 'Down opens the next tab');
            press(Qt.Key_Down); press(Qt.Key_Down);
            check(menu.page === 2, 'Down stops at the last tab');
            press(Qt.Key_Up); press(Qt.Key_Up); press(Qt.Key_Up);
            check(menu.page === 0 && filter.activeFocus, 'Up stops at the first tab, keys still in the search');

            press(Qt.Key_Right);
            check(on(isSwitch) && menu.auditContent.activeFocus, 'Right goes over to the page, onto its first control');
            press(Qt.Key_Return);
            check(menu.store.flag === true, 'Return flips a switch');
            press(Qt.Key_Space);
            check(menu.store.flag === false, 'Space flips it back');

            press(Qt.Key_Down);
            check(on(isSegment), 'Down reaches the capsule');
            const before = menu.store.mode;
            press(Qt.Key_Left); press(Qt.Key_Return);
            check(menu.store.mode !== before, 'Left walks the capsule and Return picks');
            for (let i = 0; i < 3 && !filter.activeFocus; i++)
                press(Qt.Key_Left);
            check(filter.activeFocus && menu.keyItem === null, 'Left past the capsule comes back to the tabs');

            press(Qt.Key_Right); press(Qt.Key_Down); press(Qt.Key_Down);
            check(on(isDropdown), 'Down reaches the pop-up button');
            const dropdown = menu.keyItem;
            press(Qt.Key_Return);
            tryVerify(() => dropdown.popup.visible, 1000);
            check(dropdown.popup.visible, 'Return opens the pop-up button');
            press(Qt.Key_Down); press(Qt.Key_Return);
            tryVerify(() => !dropdown.popup.visible, 2000);
            wait(50);
            check(menu.store.pick === 'p2' && Preferences.shown, 'its menu takes the arrows and Return');
            press(Qt.Key_Down);
            check(on(isField) && menu.store.pick === 'p2', 'the page has the keys back once the menu closes');

            press(Qt.Key_Return);
            check(!menu.auditContent.activeFocus && !filter.activeFocus, 'Return hands a field the keys');
            for (const c of 'hey') press(c);
            press(Qt.Key_Return);
            check(menu.store.name === 'hey' && menu.auditContent.activeFocus, 'Return in the field saves and hands the keys back');
            press(Qt.Key_Return); press(Qt.Key_Escape);
            check(menu.auditContent.activeFocus && Preferences.shown, 'Escape in an untouched field goes back to the page');

            press('w');
            check(filter.activeFocus && filter.text === 'w', 'typing on the page goes to the search');
            press(Qt.Key_Left); press(Qt.Key_Right);
            check(filter.activeFocus && filter.cursorPosition === 1, 'with words in the search, Left and Right move its caret');
            press(Qt.Key_Down);
            check(menu.auditContent.activeFocus && menu.keyItem !== null, 'Down goes over to what the search found');

            press(Qt.Key_Escape);
            check(!Preferences.shown, 'Escape on the page closes the window');
            console.log('PASS: settings keys complete');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\\n' + e.stack); } Qt.quit(); } }
}'''

PAGES = '''    property var store: ({ flag: false, mode: "a", pick: "p1", name: "" })
    function put(key, value) { const next = Object.assign({}, root.store); next[key] = value; root.store = next; }
    readonly property var pages: [
        { title: "One", sections: [{ title: "Things", rows: [
            { type: "toggle", id: "flag", title: "Flag", get: () => root.store.flag, set: v => root.put("flag", v) },
            { type: "choice", id: "mode", title: "Mode", options: [{ value: "a", label: "A" }, { value: "b", label: "B" }, { value: "c", label: "C" }], get: () => root.store.mode, set: v => root.put("mode", v) },
            { type: "choice", id: "pick", title: "Pick", options: [1, 2, 3, 4].map(n => ({ value: "p" + n, label: "Pick " + n })), get: () => root.store.pick, set: v => root.put("pick", v) },
            { type: "text", id: "name", title: "Name", get: () => root.store.name, set: v => root.put("name", v) }
        ] }] },
        { title: "Two", sections: [{ title: "More", rows: [{ type: "toggle", id: "two", title: "Two", get: () => false, set: v => {} }] }] },
        { title: "Three", sections: [{ title: "Most", rows: [{ type: "toggle", id: "wide", title: "Wide", get: () => false, set: v => {} }] }] }
    ]

'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-settings-keys-') as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / 'modules/SettingsMenu.qml').read_text()
        start = source.index('    // --- the pages ')
        end = source.index('    // The list as drawn', start)
        source = source[:start] + PAGES + source[end:]
        source = source.replace('id: root', 'id: root\n    property alias auditContent: content\n    property alias auditFilter: filter', 1)
        source = source.replace('layer.enabled: contentHeight + topMargin + bottomMargin > height', 'layer.enabled: false')
        (target / 'modules/SettingsMenu.qml').write_text(source)
        # Substitute the Wayland surface; keep the real menu, rows and controls.
        (target / 'components/OverlayWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; property Item dropdown: null; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / 'components/BackdropProbe.qml').write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property real luma: 0.5 }')
        (target / 'components/HoverPopup.qml').write_text('import QtQuick\nItem { property Item anchorItem; property real anchorHeight; property bool hovered; property string text; property var item: null }')
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'PASS: settings keys complete' in output and not any(
            error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
