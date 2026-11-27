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
                width: 300; height: 260
                Item { id: elsewhere; activeFocusOnTab: true }
                // A field inset in its box, with a button beside it there,
                // as the settings' fields and the password capsule are.
                Rectangle {
                    id: box
                    y: 230; width: 200; height: 26
                    TextInput {
                        id: boxed
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 40
                        font.pixelSize: 14
                        selectByMouse: true
                        clip: true
                        text: "boxed words"
                        TextMenu { frame: box }
                    }
                    Rectangle {
                        id: beside
                        property int taps: 0
                        anchors.right: parent.right
                        width: 30; height: parent.height
                        TapHandler { onTapped: beside.taps++ }
                    }
                }
                PopupText {
                    x: 210; y: 230
                    textFormat: Text.StyledText
                    text: '<a href="https://example.org">link</a>'
                }
                TextInput {
                    id: other
                    x: 200; y: 40; width: 100; height: 22
                    font.pixelSize: 14
                    text: "other"
                }
                TextInput {
                    id: secret
                    y: 130; width: 300; height: 22
                    font.pixelSize: 14
                    selectByMouse: true
                    echoMode: TextInput.Password
                    text: "hunter2 hunter2"
                    TextMenu { id: secretMenu }
                }
                // A field in a list that scrolls on a drag, as the settings are.
                Flickable {
                    id: scroller
                    y: 160; width: 300; height: 60
                    contentHeight: 400
                    clip: true
                    TextEdit {
                        id: listed
                        width: 300; height: 50
                        font.pixelSize: 14
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        text: "upper words\\nlower words"
                        TextMenu { id: listedMenu }
                    }
                }
                // As the tasks editor is: editable, wrapping, plain text.
                TextEdit {
                    id: notes
                    y: 80; width: 300; height: 40
                    font.pixelSize: 14
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    text: "first line\\nsecond line"
                    TextMenu { id: notesMenu }
                }
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
                tryVerify(() => !lineMenu.open && !readerMenu.open && !notesMenu.open, 1000);
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

                check(menu.chosen === null, "a right click alone chooses nothing");
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
                check(JSON.stringify(rows(menu).map(r => r.modelData)) === JSON.stringify(["Copy", "Copy All", "", "Select All"]),
                      "read-only text offers Copy, Copy All and Select All");
                choose(menu, "Select All");
                check(reader.selectedText === "read only words", "Select All selects the message");
                // A TextEdit keeps its selection while the pointer moves on
                // the field and then onto the menu.
                notes.forceActiveFocus();
                notes.select(6, 10);
                p = middle(notes, 6, 10);
                mouseClick(notes, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(notesMenu) !== null, 1000);
                menu = menuOf(notesMenu);
                mouseMove(notes, p.x + 3, p.y + 1);
                mouseMove(notes, p.x + 6, p.y + 3);
                check(notes.selectedText === "line", "moving on the field keeps the selection");
                mouseMove(row(menu, "Copy"), 4, 4);
                mouseMove(row(menu, "Copy"), 20, 10);
                check(notes.selectedText === "line", "moving onto the menu keeps the selection");
                // Focus moving to another item in the window clears a
                // TextEdit's selection unless it is persistent.
                elsewhere.forceActiveFocus();
                check(notes.selectedText === "line", "the selection outlives the field losing focus");
                choose(menu, "Cut");
                check(notes.activeFocus, "the field has the focus back once the menu is gone");
                check(!notes.persistentSelection, "the field's own persistentSelection comes back");
                check(notes.text === "first \\nsecond line", "Cut takes a TextEdit's selection out");
                wait(300);

                // Closed by a click that went to another field, the menu
                // leaves no selection behind there.
                line.text = "one two three";
                line.forceActiveFocus();
                line.select(4, 7);
                p = middle(line, 4, 7);
                mouseClick(line, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                other.forceActiveFocus();
                lineMenu.close(false);
                check(line.selectedText === "", "a menu closed from another field leaves no stale selection");
                wait(300);

                // The keys drive the menu where they come straight to the field.
                line.forceActiveFocus();
                line.select(4, 7);
                mouseClick(line, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                menu = menuOf(lineMenu);
                keyClick(Qt.Key_X);
                check(line.text === "one two three" && lineMenu.open, "typing goes nowhere while the menu is up");
                keyClick(Qt.Key_Down);
                keyClick(Qt.Key_Down);
                check(menu.keyItem === row(menu, "Copy"), "the arrows move through the rows");
                keyClick(Qt.Key_Escape);
                check(!lineMenu.open && line.selectedText === "two" && line.activeFocus,
                      "Escape puts the menu away, keeping the selection and the focus");
                wait(300);
                mouseClick(line, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                keyClick(Qt.Key_Down);
                keyClick(Qt.Key_Return);
                tryVerify(() => !lineMenu.open, 1000);
                check(line.text === "one  three", "Return chooses the row the keys are on");
                wait(300);

                // A second right click moves the menu there.
                line.text = "one two three";
                mouseClick(line, 10, 10, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                menu = menuOf(lineMenu);
                const firstX = menu.anchor.rect.x;
                mouseClick(line, 60, 10, Qt.RightButton);
                check(lineMenu.open && menuOf(lineMenu) === menu && lineMenu.at.x === 60 && menu.anchor.rect.x === firstX + 50,
                      "a second right click moves the menu to it");
                keyClick(Qt.Key_Escape);
                wait(300);

                // Press, drag onto a row, let go: that row is chosen.
                line.deselect();
                mousePress(line, 30, 10, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                menu = menuOf(lineMenu);
                const target = row(menu, "Select All");
                const g = target.mapToGlobal(target.width / 2, target.height / 2);
                const q = line.mapFromGlobal(g.x, g.y);
                mouseMove(line, q.x - 4, q.y, -1, Qt.RightButton);
                mouseMove(line, q.x, q.y, -1, Qt.RightButton);
                check(target.lit && !row(menu, "Paste").lit, "a right press dragged onto a row lights it");
                mouseRelease(line, q.x, q.y, Qt.RightButton);
                tryVerify(() => !lineMenu.open, 1000);
                check(line.selectedText === "one two three", "letting go on a row chooses it");
                wait(300);

                // Let go off the menu after dragging, and the menu goes.
                mousePress(line, 30, 10, Qt.RightButton);
                tryVerify(() => menuOf(lineMenu) !== null, 1000);
                mouseMove(line, 200, 4, -1, Qt.RightButton);
                mouseMove(line, 280, 4, -1, Qt.RightButton);
                mouseRelease(line, 280, 4, Qt.RightButton);
                check(!lineMenu.open, "letting go off the menu after dragging puts it away");
                wait(300);

                // A password is pasted into, never read back out.
                secret.forceActiveFocus();
                secret.select(0, 7);
                p = middle(secret, 0, 7);
                mouseClick(secret, p.x, p.y, Qt.RightButton);
                tryVerify(() => menuOf(secretMenu) !== null, 1000);
                menu = menuOf(secretMenu);
                check(JSON.stringify(rows(menu).map(r => r.modelData)) === JSON.stringify(["Paste", "", "Select All"]),
                      "a password field offers only Paste and Select All");
                keyClick(Qt.Key_Escape);
                wait(300);
                secret.select(0, 7);
                mousePress(secret, p.x, p.y);
                mouseMove(secret, p.x + 20, p.y, -1, Qt.LeftButton);
                mouseMove(secret, p.x + 60, p.y, -1, Qt.LeftButton);
                mouseRelease(secret, p.x + 60, p.y);
                check(secret.text === "hunter2 hunter2" && !secretMenu.dragging, "a password's selection is not dragged");

                // In a list that scrolls on a drag, a selection dragged down
                // moves rather than scrolling the list.
                listed.forceActiveFocus();
                listed.select(0, 5);
                p = middle(listed, 0, 5);
                const low = listed.positionToRectangle(listed.length);
                mousePress(listed, p.x, p.y);
                for (let i = 1; i <= 4; i++)
                    mouseMove(listed, p.x + 4 * i, p.y + 6 * i, -1, Qt.LeftButton);
                mouseMove(listed, low.x + 2, low.y + low.height / 2, -1, Qt.LeftButton);
                mouseRelease(listed, low.x + 2, low.y + low.height / 2);
                check(listed.text === " words\\nlower wordsupper" && scroller.contentY === 0,
                      "a selection dragged in a scrolling list moves, and the list stays put");

                // The box round a field is the field's: a click in its
                // padding puts the caret at the nearest end.
                elsewhere.forceActiveFocus();
                mouseClick(box, 3, 13);
                check(boxed.activeFocus && boxed.cursorPosition === 0,
                      "a click in the box's left padding focuses the field at its start");
                mouseClick(box, 165, 13);
                check(boxed.cursorPosition === boxed.length,
                      "a click in the box's right padding puts the caret at the end");
                boxed.cursorPosition = 3;
                mouseClick(box, 185, 13);
                check(beside.taps === 1 && boxed.cursorPosition === 3,
                      "a button in the box keeps its own click");
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
