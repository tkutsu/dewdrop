#!/usr/bin/env python3
"""Open a settings page without its controls springing: a switch that is on and
a capsule's chosen option are in place from the first frame, and still spring
when changed afterwards."""

import subprocess
import tempfile

from test_support import copy_shell, fixture_root, shell_env

QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    property bool on: true
    property string choice: "c"
    FloatingWindow {
        visible: true
        implicitWidth: 560; implicitHeight: 200
        Column {
            x: 20; y: 20; width: 500
            Repeater {
                id: rows
                model: []
                SettingRow { required property var modelData; width: 500; setting: modelData }
            }
        }
    }
    TestCase {
        id: test
        when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function control(index) {
            return rows.itemAt(index).children.find(c => c.toString().startsWith("QQuickLoader")).item;
        }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children ?? []) {
                const hit = find(child, predicate);
                if (hit) return hit;
            }
            return null;
        }
        function run() {
            // A page opening: its rows are made with their settings all at once.
            rows.model = [
                { type: "toggle", id: "on", title: "On", get: () => on, set: v => on = v },
                { type: "choice", id: "choice", title: "Choice",
                    options: [{ value: "a", label: "A" }, { value: "b", label: "B" }, { value: "c", label: "C" }],
                    get: () => choice, set: v => choice = v }
            ];
            const knob = control(0);
            const mark = find(control(1), item => item.placed !== undefined);
            const marks = [];
            const knobs = [];
            for (let i = 0; i < 12; i++) {
                knobs.push(knob.position);
                marks.push(mark.selectionX);
                wait(16);
            }
            check(knobs.every(p => p === 1), "a switch that is on opens on, not springing there: " + knobs.join(","));
            check(marks.every(x => x === marks[marks.length - 1]), "a capsule opens on its choice, not springing there: " + marks.join(","));
            check(mark.placed, "the capsule is ready to spring to a new choice");

            on = false;
            wait(50);
            check(knob.position > 0 && knob.position < 1, "the switch still springs when changed");
            const from = mark.selectionX;
            choice = "a";
            wait(32);
            const early = mark.selectionX;
            wait(800);
            check(early !== from && early !== mark.selectionX && mark.selectionX !== from, "the capsule still springs when changed");
            console.log("PASS: settings open still");
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-setting-open-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: settings open still" in output, output
        assert not any(error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign")), output


if __name__ == "__main__":
    main()
