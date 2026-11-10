#!/usr/bin/env python3
"""Change the launcher's mode symbols through Settings and see the launcher follow."""

from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.modules
import qs.src.services
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
        function row(key) { return find(menu.contentItem, i => i.setting?.id === "launcherPrefix:" + key && i.note !== undefined); }
        function input(key) { return find(row(key), i => i.cursorPosition !== undefined); }
        function enter(key, value) {
            const field = input(key);
            field.forceActiveFocus(); field.text = value; field.textEdited();
            keyClick(Qt.Key_Return); wait(30);
        }
        function run() {
            Preferences.shown = true;
            menu.requestActivate();
            menu.query = "mode symbols"; wait(150);
            check(input("music").text === "#", "the field starts on the default");
            const before = row("music");

            enter("music", "~");
            check(Settings.launcherPrefixes.music === "~" && Launcher.musicPrefix === "~", "a symbol saves");
            check(row("music") === before && input("music").activeFocus, "saving keeps the field and its focus");
            check(Settings.launcherPrefixes.mail === "@", "the other modes keep theirs");
            check(Launcher.classifyQuery("~ queen").mode === "~" && Launcher.classifyQuery("~ queen").text === "queen", "the new symbol selects the mode");
            check(Launcher.classifyQuery("# queen").mode === "main", "the old symbol starts nothing");
            check(Launcher.modes.some(m => m.prefix === "~" && m.hint === "music"), "the query line's hints follow");

            for (const bad of ["m", "μ", "7", "##", "@"]) {
                enter("music", bad);
                check(Settings.launcherPrefixes.music === "~" && row("music").trouble !== "", "refused: " + bad);
                keyClick(Qt.Key_Escape); wait(30);
                check(input("music").text === "~" && row("music").trouble === "", "Escape restores after: " + bad);
            }

            const field = input("music");
            field.forceActiveFocus(); field.text = "x"; field.textEdited();
            menu.query = "terminal"; wait(100);
            check(Settings.launcherPrefixes.music === "~", "leaving the page discards a refused draft");

            menu.query = "mode symbols"; wait(100);
            enter("music", "");
            check(Settings.launcherPrefixes.music === "#", "clearing a field restores the default");

            enter("files", "~");
            check(Launcher.classifyQuery("~/notes").text === "~/notes", "a typed path stays whole under a path symbol that starts one");
            check(Launcher.classifyQuery("~notes").text === "notes", "the symbol still searches");
            check(Launcher.classifyQuery("/usr/lib").mode === "~" && Launcher.classifyQuery("/usr/lib").text === "/usr/lib", "a slash path is still inferred");
            enter("files", "/");

            enter("web", "^");
            check(Launcher.classifyQuery("^y lofi").mode === "^", "web search moves");
            check(Launcher.engineResults(Launcher.enginePrefix, "y lofi")[0].badge === "^y", "engine badges carry the new symbol");
            enter("help", "|");
            check(Launcher.helpPrefix === "|" && Launcher.classifyQuery("|").mode === "|", "help moves too");
            check(Launcher.classifyQuery(".5*2").math, "a dot decimal is still a sum");

            console.log("PASS: mode symbols complete"); Qt.quit();
        }
    }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\n" + e.stack); Qt.quit(); }
    } }
}'''


def run(target, expected):
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    print(output, end="")
    errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "Invalid property assignment")
    assert result.returncode == 0 and expected in output and not any(error in output for error in errors), output


def main():
    with tempfile.TemporaryDirectory(prefix="qs-launcher-mode-symbols-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "src/components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "src/services/Keyboard.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [] }')
        (target / "src/services/Power.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: [] }')
        (target / "src/services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
        menu = target / "src/modules/SettingsMenu.qml"
        menu.write_text(menu.read_text().replace("layer.enabled: contentHeight + topMargin + bottomMargin > height", "layer.enabled: false"))
        (target / "shell.qml").write_text(QML)
        run(target, "PASS: mode symbols complete")


if __name__ == "__main__":
    main()
