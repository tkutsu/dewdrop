#!/usr/bin/env python3
"""The real mail popup in a scratch shell: rows, verbs, the next mail opening,
undo, the Other row. Pass a directory to keep screenshots of it."""

from pathlib import Path
import subprocess
import sys
import tempfile

from test_support import copy_shell, shell_env


SHELL = '''import QtQuick
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    id: test
    property string shots: "%(shots)s"

    FloatingWindow {
        implicitWidth: 400; implicitHeight: 60
        Item { id: anchor; width: 40; height: 20 }
    }

    function mail(id, at, from, subject, starred) {
        return Email.rowOf({id: id, snippet: "The opening of " + subject.toLowerCase() + ", and on it goes"}, {messages: [{
            id: "m" + id, internalDate: String(at),
            labelIds: starred ? ["UNREAD", "STARRED"] : ["UNREAD"],
            payload: {headers: [{name: "From", value: from}, {name: "Subject", value: subject}]}
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
        Email.bodies = {ma: "Shall we? Twelve thirty at the usual place.", mb: "Τα άφησα στο γραφείο.", mc: "Code 123456"};
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
        check(list(p).count === 3, "three rows");
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
                test.run();
                console.log("PASS: mail popup verbs, next mail, undo and other");
            } catch (error) {
                console.log("FAIL: " + error + "\\n" + error.stack);
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
        onTriggered: test.shoot("undo", () => Qt.quit())
    }
    // A grab that never answers must not hang the run.
    Timer {
        interval: 4000; running: true
        onTriggered: Qt.quit()
    }
}
'''


def main():
    shots = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else ""
    with tempfile.TemporaryDirectory(prefix="quickshell-email-popup-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SHELL % {"shots": shots})
        try:
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
        except subprocess.TimeoutExpired as hung:
            output = "FAIL: timed out\n" + (hung.stdout or b"").decode() + (hung.stderr or b"").decode()
        print(output, end="")
        ok = "PASS: mail popup" in output and "FAIL:" not in output
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "is not a type"):
            ok = ok and error not in output
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
