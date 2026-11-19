#!/usr/bin/env python3
"""A RollingLine rolls its figures in place and leaves its words as text.

The line is cut into runs of figures and of words; a run of figures stays the
same RollingText from one value to the next (so it rolls rather than being
rebuilt), and a small run lands on the run it belongs to.
"""

import subprocess
import tempfile

from test_support import copy_shell, fixture_root, shell_env


QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    id: test
    function check(ok, why) { if (!ok) throw Error(why); }
    function rolling(line) {
        const out = [];
        const walk = item => {
            if (item.columns !== undefined && item.smallRanges !== undefined && item.visible)
                out.push(item);
            for (const child of item.children)
                walk(child);
        };
        walk(line);
        return out;
    }
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 60
        RollingLine {
            id: line
            fontSize: 18
            display: ({ text: "Friday 20 November", smallRanges: [] })
        }
    }
    Timer {
        interval: 200; running: true
        onTriggered: {
            try {
                check(JSON.stringify(line.runs.map(run => [run.text, run.figures])) === JSON.stringify([["Friday ", false], ["20", true], [" November", false]]),
                    "cut into words, figures, words: " + JSON.stringify(line.runs));
                const before = test.rolling(line);
                check(before.length === 1 && before[0].text === "20", "only the figures roll");
                line.display = { text: "Saturday 21 November", smallRanges: [] };
                const after = test.rolling(line);
                check(after.length === 1 && after[0] === before[0] && after[0].text === "21", "the same figures roll to the next day");
                line.display = { text: "9:05 pm", smallRanges: [{ start: 5, end: 7 }] };
                check(JSON.stringify(line.runs[line.runs.length - 1].smallRanges) === JSON.stringify([{ start: 1, end: 3 }]),
                    "a small run lands on its own run: " + JSON.stringify(line.runs));
                check(line.baselineOffset > 0, "has a baseline to line up on");
                console.log("PASS: rolling line");
            } catch (e) {
                console.log("FAIL: " + e);
            }
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-rolling-line-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign")
        assert "PASS: rolling line" in output
        assert not any(error in output for error in errors)


if __name__ == "__main__":
    main()
