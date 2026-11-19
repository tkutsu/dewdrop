#!/usr/bin/env python3
"""Check the text fields' edit menu and dragging a selection within a field."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, fixture_root, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 600; implicitHeight: 40
        Item { id: owner; width: 100; height: 30 }
        Popup {
            id: popup
            visible: true; anchorItem: owner; probes: false; grows: false
            Item {
                width: 300; height: 70
                TextInput {
                    id: line
                    width: 300; height: 22
                    font.pixelSize: 14
                    selectByMouse: true
                    text: "one two three"
                    TextMenu { id: lineMenu }
                }
                TextEdit {
                    id: reader
                    y: 40; width: 300; height: 22
                    font.pixelSize: 14
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    activeFocusOnPress: false
                    text: "read only words"
                    TextMenu { id: readerMenu }
                }
            }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            // The open menu's window, once it is up and can be clicked.
            function menuOf(textMenu) {
                for (const child of textMenu.children)
                    if (child.sourceComponent !== undefined)
                        return child.item?.opened && child.item.revealProgress === 1 ? child.item : null;
                return null;
            }
            function rows(menu) {
                const found = [];
                function walk(item) {
                    for (const child of item.children) {
                        if (child.modelData !== undefined && child.keyPress !== undefined)
                            found.push(child);
                        walk(child);
                    }
                }
                walk(menu.contentItem);
                return found;
            }
            function row(menu, name) {
                return rows(menu).find(r => r.modelData === name);
            }
            // The middle of the characters from start to end.
            function middle(field, start, end) {
                const a = field.positionToRectangle(start), b = field.positionToRectangle(end);
                return Qt.point((a.x + b.x) / 2, a.y + a.height / 2);
            }
            function choose(menu, name) {
                const r = row(menu, name);
                mouseMove(r, r.width / 2, r.height / 2);
                mouseClick(r, r.width / 2, r.height / 2);
                tryVerify(() => !lineMenu.open && !readerMenu.open, 1000);
                wait(300);
            }
            function run() {
                wait(300);
                popup._backingWindow.requestActivate();
                line.forceActiveFocus();
                wait(50);

                // A right click on the selection keeps it and opens the menu.
                line.select(4, 7);
                let p = middle(line, 4, 7);
                mouseClick(line, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                let menu = menuOf(lineMenu);
                check(line.selectedText === "two", "a right click on the selection keeps it");
                check(JSON.stringify(rows(menu).map(r => r.modelData)) === JSON.stringify(["Cut", "Copy", "Paste", "", "Select All"]),
                      "an editable field offers Cut, Copy, Paste and Select All");
                check(row(menu, "Cut").enabled && row(menu, "Copy").enabled, "Cut and Copy are there for a selection");
                mouseMove(row(menu, "Copy"), 5, 5);
                wait(30);
                check(PopupPointer.hovered > 0, "the menu counts as inside the popup");

                choose(menu, "Cut");
                check(line.text === "one  three", "Cut takes the selection out");

                // Away from the selection the cursor goes where you clicked.
                p = line.positionToRectangle(line.length);
                mouseClick(line, p.x + 20, p.y + 5, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null && lineMenu.open, 1000);
                menu = menuOf(lineMenu);
                check(line.cursorPosition === line.length && !row(menu, "Copy").enabled,
                      "a right click past the text moves the cursor there, and Copy has nothing");
                choose(menu, "Paste");
                check(line.text === "one  threetwo", "Paste puts the clipboard in at the cursor");

                // A press anywhere on the field puts the menu away.
                mouseClick(line, 5, 5, Qt.RightButton);
                tryVerify(() => lineMenu.open, 1000);
                mouseClick(line, 5, 5);
                check(!lineMenu.open, "a click on the field closes the menu");
                wait(300);

                // Dragging the selection moves it.
                line.text = "one two three";
                line.select(4, 7);
                p = middle(line, 4, 7);
                const end = line.positionToRectangle(line.length);
                mousePress(line, p.x, p.y);
                mouseMove(line, p.x + 20, p.y, -1, Qt.LeftButton);
                mouseMove(line, end.x + 2, p.y, -1, Qt.LeftButton);
                check(lineMenu.dropAt === line.length, "the drop point follows the pointer");
                mouseRelease(line, end.x + 2, p.y);
                check(line.text === "one  threetwo" && line.selectedText === "two",
                      "dropping moves the text and keeps it selected");

                // Dropped back on itself, nothing changes.
                line.text = "one two three";
                line.select(4, 7);
                mousePress(line, p.x, p.y);
                mouseMove(line, p.x + 4, p.y + 12, -1, Qt.LeftButton);
                mouseMove(line, p.x + 2, p.y, -1, Qt.LeftButton);
                mouseRelease(line, p.x + 2, p.y);
                check(line.text === "one two three", "a drop inside the selection changes nothing");

                // A click on the selection without moving puts the cursor there.
                line.select(4, 7);
                mouseClick(line, p.x, p.y);
                check(line.selectedText === "" && line.cursorPosition >= 4 && line.cursorPosition <= 7,
                      "a click on the selection places the cursor");

                // Off the selection, the field selects by dragging as before.
                line.select(4, 7);
                const start = line.positionToRectangle(0);
                mousePress(line, start.x + 1, p.y);
                mouseMove(line, p.x - 15, p.y, -1, Qt.LeftButton);
                mouseRelease(line, p.x - 15, p.y);
                check(line.selectionStart === 0 && line.selectionEnd > 0 && line.selectionEnd < 4,
                      "dragging off the selection selects instead");

                // Read-only text has nothing to cut or paste into.
                p = middle(reader, 0, 4);
                mouseClick(reader, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(readerMenu) !== null && readerMenu.open, 1000);
                menu = menuOf(readerMenu);
                check(JSON.stringify(rows(menu).map(r => r.modelData)) === JSON.stringify(["Copy", "", "Select All"]),
                      "read-only text offers Copy and Select All");
                choose(menu, "Select All");
                check(reader.selectedText === "read only words", "Select All selects the message");
                console.log("PASS: text menu complete");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-text-menu-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        messages = "\n".join(line for line in output.splitlines() if "qml:" in line or "TextMenu" in line)
        print(messages)
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Cannot assign")
        assert result.returncode == 0 and "PASS: text menu complete" in output and not any(
            error in output for error in errors), output[-4000:]


if __name__ == "__main__":
    main()
