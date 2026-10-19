#!/usr/bin/env python3
"""The real mail popup in a scratch shell: rows, verbs, the next mail opening,
undo, the Other row, and pointer routing in open mail.
Pass a directory to keep screenshots of it."""

from pathlib import Path
import subprocess
import sys
import tempfile

from test_support import copy_shell, shell_env


SHELL = '''import QtQuick
import Quickshell
import QtTest
import qs
import qs.components
import qs.services
ShellRoot {
    id: test
    property string shots: "%(shots)s"

    FloatingWindow {
        implicitWidth: 400; implicitHeight: 60
        Item { id: anchor; width: 40; height: 20 }
        TestCase {
            id: pointerTests
            when: false

            function message(item) {
                if (item instanceof TextEdit)
                    return item;
                for (const child of item.children) {
                    const found = message(child);
                    if (found) return found;
                }
                return null;
            }

            function run() {
                const p = test.popup;
                function open() { p.expanded = "a"; wait(400); }
                open();
                let row = test.list(p).itemAt(0);
                let text = message(row);
                row = text;
                while (row && row.swipe === undefined) row = row.parent;
                const first = text.positionToRectangle(0);
                const x = first.x + 2, y = first.y + first.height / 2;
                mouseClick(text, x, y);
                test.check(p.expanded === "a", "clicking text keeps mail open");
                mousePress(text, x, y);
                wait(500);
                mouseMove(text, text.width - 2, y);
                mouseRelease(text, text.width - 2, y);
                test.check(text.selectedText !== "" && row.swipe === 0 && p.expanded === "a", "holding text selects across empty space without swiping: selection=" + text.selectedText + ", swipe=" + row.swipe + ", expanded=" + p.expanded);

                mouseClick(text, text.width - 2, y);
                test.check(p.expanded === "", "trailing space closes mail");
                open();
                text = message(row);
                const blankAt = text.getText(0, text.length).search(/[\\n\\u2028\\u2029]/);
                test.check(blankAt >= 0, "fixture has a blank line");
                const blank = text.positionToRectangle(blankAt + 1);
                mouseClick(text, 40, blank.y + blank.height / 2);
                test.check(p.expanded === "", "blank line closes mail");
                open();
                text = message(row);
                const selection = text.selectedText;
                mousePress(text, text.width - 2, y);
                wait(500);
                mouseMove(text, text.width - 62, y);
                test.check(row.tracking && row.swipe < -40 && text.selectedText === selection, "holding empty space drags the mail: tracking=" + row.tracking + ", swipe=" + row.swipe);
                mouseRelease(text, text.width - 62, y);
                tryCompare(row, "swipe", 0, 4000);
                wait(Theme.fadeMs + 50);
                test.check(p.expanded === "a" && !row.tracking && row.swipe === 0, "short drag springs back without closing");

                mouseClick(row, 4, row.height - 4);
                test.check(p.expanded === "", "open mail gutter closes on click");
                open();
                const star = test.find(row, "Star");
                mousePress(star, star.width / 2, star.height / 2);
                wait(500);
                mouseRelease(star, star.width / 2, star.height / 2);
                test.check(Email.threads[0].starred && p.expanded === "a" && Math.abs(row.swipe) < 1, "held header button acts without closing or dragging: starred=" + Email.threads[0].starred + ", expanded=" + p.expanded + ", swipe=" + row.swipe);
                Email.undo();

                wait(400);
                text = message(test.list(p).itemAt(0));
                row = text;
                while (row && row.swipe === undefined) row = row.parent;
                const at = text.getText(0, text.length).indexOf("example.com");
                const link = text.positionToRectangle(at);
                mouseClick(text, link.x + 2, link.y + link.height / 2);
                test.check(p.auditLink === "https://example.com" && p.expanded === "a", "link receives its click");

                const code = test.find(row, "Copy code 654321");
                mouseClick(code, code.width / 2, code.height / 2);
                test.check(Email.pending.length === 1 && p.expanded === "b", "footer button acts and opens next mail: pending=" + Email.pending.length + ", expanded=" + p.expanded);
                Email.undo();
                test.check(p.expanded === "a", "undo restores mail after pointer action");
                wait(400);
                text = message(test.list(p).itemAt(0));
                row = text;
                while (row && row.swipe === undefined) row = row.parent;
                mousePress(row, row.width - 4, row.height - 4);
                wait(500);
                mouseMove(row, 4, row.height - 4);
                mouseRelease(row, 4, row.height - 4);
                wait(600);
                test.check(Email.pending.length === 1 && Email.pending[0].kind === "archive" && p.expanded === "b", "full drag from empty space archives and opens next mail");
                Email.undo();
                p.expanded = "";
                wait(400);
                console.log("PASS: mail popup pointer routing");
            }
        }
    }

    function mail(id, at, from, subject, starred) {
        return Email.rowOf({id: id, snippet: "The opening of " + subject.toLowerCase() + ", and on it goes"}, {messages: [{
            id: "m" + id, internalDate: String(at),
            labelIds: starred ? ["UNREAD", "STARRED"] : ["UNREAD"],
            payload: {headers: [{name: "From", value: from}, {name: "Subject", value: subject}, {name: "List-Unsubscribe", value: id === "b" ? "<https://list.example/u>" : ""}, {name: "List-Unsubscribe-Post", value: "List-Unsubscribe=One-Click"}]}
        }]});
    }

    function check(ok, message) {
        if (!ok) throw new Error(message);
    }

    function find(item, name) {
        for (const child of item.children) {
            if (child.name === name && child.glyph !== undefined)
                return child;
            const found = find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function shoot(name, then) {
        if (test.shots === "") {
            then();
            return;
        }
        popup.chromeItem.grabToImage(result => {
            result.saveToFile(test.shots + "/" + name + ".png");
            then();
        });
    }

    property var popup: null

    function setUp() {
        const now = Date.now();
        Email.polling = false;
        Email.threads = [
            mail("a", now - 60000, "Ann Example <ann@example.com>", "Lunch on Friday?", false),
            mail("b", now - 3600000, "Γιώργος Παπαδόπουλος <g@example.gr>", "Τα κλειδιά", true),
            mail("c", now - 86400000 * 2, "GitHub <noreply@github.com>", "Your verification code", false)
        ];
        Email.bodies = {ma: "Shall we? Twelve thirty at the usual place. Code 654321.\\n\\nhttps://example.com", mb: "Τα άφησα στο γραφείο.", mc: "Code 123456"};
        Email.files = {mb: [{id: "f1", name: "κλειδιά-φωτογραφία.jpg", size: 1843200, type: "image/jpeg"}, {id: "f2", name: "notes.txt", size: 812, type: "text/plain"}]};
        Email.total = 3;
        Email.otherThreads = [mail("x", now - 7200000, "Shop <news@shop.example>", "Autumn sale", false)];
        Email.other = 1;
        Email.loaded = true;
        test.popup = component.createObject(test, {anchorItem: anchor});
        test.popup.visible = true;
    }

    function run() {
        const p = test.popup;
        const row = i => p.contentItem && list(p).itemAt(i);
        check(list(p).count === 3, "three rows: " + list(p).count);
        for (const name of ["Archive", "Mark read", "Star"])
            check(find(row(0), name) !== null, "row has " + name);
        check(find(row(1), "Unstar") !== null, "a starred row offers unstar");

        p.expanded = "b";
        p.act("archive", Email.threads[1]);
        check(Email.threads.map(t => t.id).join() === "a,c", "archived row left");
        check(p.expanded === "c", "the next mail opened, not " + p.expanded);
        check(Email.pending.length === 1, "the archive waits");
        Email.undo();
        check(Email.threads.map(t => t.id).join() === "a,b,c" && p.expanded === "b", "undo put it back open");

        p.act("star", Email.threads[0]);
        check(Email.threads[0].starred && Email.pending.length === 1, "star turned at once");
        p.otherOpen = true;
        check(Email.otherWanted, "unfolding asks for the other rows");
    }

    function list(p) {
        // The first Repeater in the popup: the Primary rows.
        const walk = item => {
            for (const child of item.children) {
                if (child instanceof Repeater)
                    return child;
                const found = walk(child);
                if (found)
                    return found;
            }
            return null;
        };
        return walk(p.contentItem);
    }

    Component {
        id: component
        EmailPopup {}
    }

    Timer {
        interval: 200; running: true
        onTriggered: {
            try { test.setUp(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); Qt.quit(); }
        }
    }
    Timer {
        interval: 900; running: true
        onTriggered: {
            try {
                pointerTests.run();
                test.run();
                console.log("PASS: mail popup verbs, next mail, undo and other");
            } catch (error) {
                console.log("FAIL: " + error + "\\n" + error.stack);
                Qt.quit();
                return;
            }
            test.shoot("open", () => {
                test.popup.expanded = "";
                test.popup.act("archive", Email.threads[0]);
                shotTimer.start();
            });
        }
    }
    Timer {
        id: shotTimer
        interval: 600
        onTriggered: test.shoot("undo", () => {
            // Held part way, as a hand would: one row armed, one not yet.
            const rows = test.list(test.popup);
            rows.itemAt(0).track(-170);
            rows.itemAt(1).track(60);
            swipeTimer.start();
        })
    }
    Timer {
        id: swipeTimer
        interval: 300
        onTriggered: test.shoot("swipe", () => Qt.quit())
    }
    // A grab that never answers must not hang the run.
    Timer {
        interval: 20000; running: true
        onTriggered: Qt.quit()
    }
}
'''


def main():
    shots = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else ""
    with tempfile.TemporaryDirectory(prefix="quickshell-email-popup-") as folder:
        target = Path(folder)
        copy_shell(target)
        popup = target / "components/EmailPopup.qml"
        popup.write_text(popup.read_text().replace("id: root", 'id: root\n    property string auditLink: ""', 1)
                         .replace("Qt.openUrlExternally(url);", "root.auditLink = url;"))
        (target / "shell.qml").write_text(SHELL % {"shots": shots})
        try:
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
        except subprocess.TimeoutExpired as hung:
            output = "FAIL: timed out\n" + (hung.stdout or b"").decode() + (hung.stderr or b"").decode()
        print(output, end="")
        ok = ("PASS: mail popup pointer routing" in output
              and "PASS: mail popup verbs, next mail, undo and other" in output
              and "FAIL:" not in output)
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "is not a type"):
            ok = ok and error not in output
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
