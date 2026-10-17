#!/usr/bin/env python3
"""Check clock casing, AM/PM token sizing, spacing and rendered baselines."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import Quickshell
import qs
import qs.components
ShellRoot {
    id: test
    readonly property date stamp: new Date(2026, 9, 13, 20, 5, 9)
    property int phase: 0
    function check(ok, why) { if (!ok) throw Error(why); }
    function display(format, mode, small) {
        Settings.user = { timeFormat: format, timeCase: mode, smallAmPm: small, reduceMotion: true };
        return Settings.clockDisplay(test.stamp);
    }
    FloatingWindow {
        implicitWidth: 240; implicitHeight: 60
        RollingText {
            id: clock
            height: 30
            tightWidth: true
            fontSize: Theme.textSize
            readonly property var display: Settings.clockDisplay(test.stamp)
            text: display.text
            smallRanges: display.smallRanges
        }
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) {
                    check(Settings.dateCase === "normal" && Settings.timeCase === "uppercase" && !Settings.smallAmPm, "default case and size");
                    for (const [mode, expected] of [
                        ["normal", "tue 13 OCT"], ["capitalize", "Tue 13 Oct"],
                        ["uppercase", "TUE 13 OCT"], ["lowercase", "tue 13 oct"]
                    ]) check(Settings.applyCase("tue 13 OCT", mode) === expected, "case: " + mode);
                    check(Settings.applyCase("τρίτη 13 οκτωβρίου", "capitalize") === "Τρίτη 13 Οκτωβρίου", "Unicode capitalization");
                    check(Settings.applyCase("Tue", "unknown") === "Tue", "unknown case preserves text");
                    for (const [format, mode, small, expected, ranges] of [
                        ["h:mm AP", "normal", false, "8:05 PM", []],
                        ["h:mm ap", "lowercase", true, "8:05pm", [{start: 4, end: 6}]],
                        ["h:mm AP", "lowercase", true, "8:05pm", [{start: 4, end: 6}]],
                        ["h:mm ap", "uppercase", true, "8:05PM", [{start: 4, end: 6}]],
                        ["h:mm AP", "capitalize", true, "8:05PM", [{start: 4, end: 6}]],
                        ["h:mm:ss AP", "normal", true, "8:05:09PM", [{start: 7, end: 9}]],
                        ["hh:mmAP", "normal", true, "08:05PM", [{start: 5, end: 7}]],
                        ["AP h:mm", "normal", true, "PM 8:05", [{start: 0, end: 2}]],
                        ["h:mm 'AP' ap", "uppercase", true, "8:05 APPM", [{start: 7, end: 9}]],
                        ["h:mm AP 'and' ap", "uppercase", true, "8:05PM ANDPM", [{start: 4, end: 6}, {start: 10, end: 12}]],
                        ["'straße' h:mm AP", "uppercase", true, "STRASSE 8:05PM", [{start: 12, end: 14}]],
                        ["HH:mm 'AP'", "normal", true, "20:05 AP", []],
                        ["HH:mm", "normal", true, "20:05", []]
                    ]) {
                        const result = test.display(format, mode, small);
                        check(result.text === expected, format + " / " + mode + ": " + result.text);
                        check(JSON.stringify(result.smallRanges) === JSON.stringify(ranges), "AM/PM ranges: " + format);
                    }
                    Settings.set("dateCase", "lowercase");
                    Settings.set("timeCase", "lowercase");
                    Settings.set("smallAmPm", true);
                    Settings.set("timeFormat", "h:mm AP");
                } else if (test.phase === 1 || test.phase === 2) {
                    check(clock.text === "8:05pm", "clock binding updates");
                    check(Settings.applyCase(Qt.formatDate(test.stamp, Settings.dateFormat), Settings.dateCase) === "tue 13 oct", "date binding updates");
                    const columns = clock.children.find(child => typeof child.itemAt === "function");
                    const label = index => columns.itemAt(index).children.find(child => child.fontSize !== undefined);
                    const full = label(2);
                    for (const index of [0, 1]) {
                        const small = label(index);
                        check(small.fontSize === Math.round(clock.fontSize * 2 / 3), "two-thirds-size AM/PM");
                        check(Math.abs(small.baselineOffset - full.baselineOffset) <= 0.5, "AM/PM baseline: " + small.baselineOffset + " vs " + full.baselineOffset);
                    }
                    check(full.fontSize === clock.fontSize, "digits remain full size");
                    check(columns.itemAt(2).x + columns.itemAt(2).width === columns.itemAt(1).x, "AM/PM touches the preceding character column");
                    if (test.phase === 1) clock.fontSize = 16;
                    else Settings.set("smallAmPm", false);
                } else {
                    check(clock.text === "8:05 pm" && clock.smallRanges.length === 0, "turning option off restores original spacing and size");
                    console.log("PASS: clock casing, token ranges, two-thirds-size AM/PM and baselines");
                    Qt.quit();
                }
                test.phase++;
            } catch (error) {
                console.log("FAIL: " + error + "\\n" + error.stack);
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-clock-display-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(
            ["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, LC_ALL="C.UTF-8"),
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        print(output)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign")
        assert result.returncode == 0 and "PASS: clock casing" in output
        assert not any(error in output for error in errors)


if __name__ == "__main__":
    main()
