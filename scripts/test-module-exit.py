#!/usr/bin/env python3
"""Keep a module's exit visible long enough to read as motion.

The right pill folds a module under its closing edge, into the drawer; the
centre pill's modules fade and shrink in place while the gap closes round
them, without running past.
"""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

QML = '''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 500; implicitHeight: 100
        Column {
            Pill {
                side: Pill.Side.Right
                drawsSlab: false
                BarItem {
                    id: folding; _started: true
                    Glyph { id: foldIcon; Layout.fillHeight: true; text: "X" }
                }
            }
            Pill {
                drawsSlab: false
                BarItem {
                    id: leaving; _started: true
                    Glyph { id: leaveIcon; Layout.fillHeight: true; text: "X" }
                }
            }
        }
        TestCase {
            id: test; when: false
            function finish(module, name) {
                for (let i = 0; i < 160 && module.animating; i++) wait(10);
                if (module.visible || module.animating)
                    throw Error(name + " did not finish exiting");
            }
            function run() {
                folding.stowed = true;
                wait(120);
                const alpha = folding.keyBox.opacity;
                if (!folding.visible)
                    throw Error("folding module was hidden during its fade");
                const bounds = foldIcon.mapToItem(folding, 0, 0, foldIcon.width, foldIcon.height);
                if (bounds.width <= 0 || bounds.width > foldIcon.width)
                    throw Error("icon lost its geometry during exit");
                if (alpha < 0.35)
                    throw Error("folding icon is almost gone after 120 ms (opacity=" + alpha.toFixed(3) + ")");
                if (bounds.width / foldIcon.width > 0.96)
                    throw Error("folding icon has not visibly shrunk at 120 ms");
                if (!folding.clip || folding.reveal <= 0 || folding.reveal >= 1 || folding.keyBox.x >= 0)
                    throw Error("right pill contents did not slide behind a clipped edge");
                finish(folding, "folding module");

                const start = leaving.width;
                leaving.stowed = true;
                let overran = false, centred = true;
                for (let i = 0; i < 60 && leaving.animating; i++) {
                    wait(5);
                    if (leaving._sprung < -0.001)
                        overran = true;
                    const box = leaving.keyBox;
                    const middle = box.x + box.width / 2;
                    if (leaving.width > 4 && Math.abs(middle - leaving.width / 2) > 1.5)
                        centred = false;
                    if (i === 15) {
                        if (leaving.clip)
                            throw Error("centre module clipped its icon on the way out");
                        if (leaving.keyBox.opacity >= 1 || leaving.keyBox.opacity <= 0)
                            throw Error("centre icon is not fading at 75 ms");
                        if (leaving.appearanceScale >= 1)
                            throw Error("centre icon is not shrinking at 75 ms");
                        if (leaving.width >= start)
                            throw Error("centre gap has not started closing at 75 ms");
                    }
                }
                if (leaving._ink > 0)
                    throw Error("centre icon is still inked after the quick fade");
                if (!centred)
                    throw Error("centre icon left the middle of its slot");
                if (overran)
                    throw Error("centre gap ran past shut");
                finish(leaving, "centre module");
                console.log("PASS: module exit folds in the right pill and leaves in place in the centre");
            }
        }
        Timer { interval: 300; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-module-exit-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: module exit" in output and not any(e in output for e in errors)
        print("\n".join(line for line in output.splitlines() if "qml:" in line) if result.returncode == 0 else output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
