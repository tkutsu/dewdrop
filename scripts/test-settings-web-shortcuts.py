#!/usr/bin/env python3
"""Edit web shortcuts through Settings and reopen the persisted list."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    SettingsMenu { id: menu }
    TestCase {
        id: test
        when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children ?? []) {
                const found = find(child, predicate);
                if (found) return found;
            }
            return null;
        }
        function editor() { return find(menu.contentItem, i => i.setting?.id === "webShortcuts" && i.commit !== undefined); }
        function field(index, label) {
            return find(editor(), i => i.Accessible?.name === "Web Shortcut " + (index + 1) + " " + label);
        }
        function draft(index, label, value) {
            const input = field(index, label);
            check(!!input, "shortcut field exists");
            input.forceActiveFocus(); input.text = value; input.textEdited();
        }
        function enter(index, label, value) { draft(index, label, value); keyClick(Qt.Key_Return); wait(30); }
        function click(name) {
            const button = find(editor(), i => i.name === name && i.tapped !== undefined);
            check(!!button, "shortcut button exists");
            // Activate the control even when it is below the scroll viewport.
            button.tapped(); wait(30);
        }
        function run() {
            Preferences.shown = true;
            menu.requestActivate();
            menu.query = "web shortcuts"; wait(150);
            check(editor()?.values().length === 7, "default shortcuts load as separate entries");
            check(editor().width > 400 && field(0, "URL").width > 300, "URLs use the settings width");
            enter(1, "Character", "z");
            enter(1, "Name", "  My Search  ");
            enter(1, "URL", "  https://example.com/search?q=%s&limit=5  ");
            check(Settings.webShortcuts[1].key === "z" && Settings.webShortcuts[1].name === "My Search"
                && Settings.webShortcuts[1].url === "https://example.com/search?q=%s&limit=5", "character, name and URL save with whitespace trimmed");
            enter(1, "Character", "c");
            check(Settings.webShortcuts[1].key === "z", "duplicate characters are rejected");
            keyClick(Qt.Key_Escape);
            check(field(1, "Character").text === "z", "Escape restores the saved character");
            enter(1, "Character", "zz");
            check(Settings.webShortcuts[1].key === "z", "multi-character shortcuts are rejected");
            keyClick(Qt.Key_Escape);
            enter(1, "Character", "");
            check(Settings.webShortcuts[1].key === "z", "duplicate default shortcuts are rejected");
            keyClick(Qt.Key_Escape);
            enter(1, "URL", "broken");
            check(Settings.webShortcuts[1].url.includes("example.com"), "invalid URL preserves saved value");
            keyClick(Qt.Key_Escape);

            click("Add Web Shortcut");
            check(field(7, "Name")?.activeFocus && Settings.webShortcuts.length === 7, "Add focuses an unsaved entry");
            draft(7, "Name", "Example");
            draft(7, "Character", "e");
            enter(7, "URL", "https://example.org/");
            check(Settings.webShortcuts.length === 8 && Settings.webShortcuts[7].key === "e", "new shortcut saves when all fields are valid");
            click("Remove Web Shortcut 1");
            check(Settings.webShortcuts.length === 7 && Settings.webShortcuts[0].key === "z", "Remove deletes only its entry");
            enter(0, "Character", "");
            check(Settings.webShortcuts[0].key === "", "blank character selects a new default");

            draft(0, "URL", "https://example.com/updated?q=%s");
            field(0, "Name").forceActiveFocus(); wait(30);
            check(Settings.webShortcuts[0].url.includes("updated"), "focus loss saves valid changes");
            draft(0, "Name", "Saved On Exit");
            menu.query = "terminal"; wait(100);
            check(Settings.webShortcuts[0].name === "Saved On Exit", "leaving the page saves a valid draft");
            menu.query = "web shortcuts"; wait(100);
            draft(0, "URL", "invalid");
            menu.query = "terminal"; wait(100);
            check(Settings.webShortcuts[0].url.includes("updated"), "leaving the page discards invalid drafts");
            menu.query = "web shortcuts"; wait(100);
            click("Add Web Shortcut"); keyClick(Qt.Key_Escape); wait(30);
            check(!field(7, "Name") && Settings.webShortcuts.length === 7, "Escape cancels a new entry");
            console.log("PASS: web shortcut settings complete"); Qt.quit();
        }
    }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\n" + e.stack); Qt.quit(); }
    } }
}'''


def run(target, expected):
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end="")
    errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "Invalid property assignment")
    assert result.returncode == 0 and expected in output and not any(error in output for error in errors), output


def main():
    with tempfile.TemporaryDirectory(prefix="qs-settings-web-shortcuts-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "services/Keyboard.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [] }')
        (target / "services/Power.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: [] }')
        (target / "services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
        menu = target / "modules/SettingsMenu.qml"
        menu.write_text(menu.read_text().replace("layer.enabled: contentHeight + topMargin + bottomMargin > height", "layer.enabled: false"))
        (target / "shell.qml").write_text(QML)
        run(target, "PASS: web shortcut settings complete")
        (target / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs
ShellRoot { Timer { interval: 150; running: true; onTriggered: {
    const list = Settings.webShortcuts;
    console.log(list.length === 7 && list[0].key === "" && list[0].name === "Saved On Exit"
        && list[0].url === "https://example.com/updated?q=%s" && list[6].key === "e"
        ? "PASS: shortcuts reopen" : "FAIL: shortcuts reopen"); Qt.quit();
} } }''')
        run(target, "PASS: shortcuts reopen")


if __name__ == "__main__":
    main()
