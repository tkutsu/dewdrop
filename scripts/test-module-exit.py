#!/usr/bin/env python3
"""Keep a module's exit visible long enough to read as motion."""

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
        Pill {
            drawsSlab: false
            BarItem {
                id: module; _started: true
                Glyph { id: icon; Layout.fillHeight: true; text: "X" }
            }
        }
        TestCase {
            id: test; when: false
            function run() {
                module.stowed = true;
                wait(120);
                const alpha = module.keyBox.opacity;
                if (!module.visible)
                    throw Error("module was hidden during its fade");
                const bounds = icon.mapToItem(module, 0, 0, icon.width, icon.height);
                if (bounds.width <= 0 || bounds.width > icon.width)
                    throw Error("icon lost its geometry during exit");
                if (alpha < 0.35)
                    throw Error("icon is already almost gone after 120 ms (opacity=" + alpha.toFixed(3) + ")");
                if (bounds.width / icon.width > 0.96)
                    throw Error("icon has not visibly shrunk at 120 ms");
                if (!module.clip || module.reveal <= 0 || module.reveal >= 1 || module.keyBox.x >= 0)
                    throw Error("module contents did not slide behind a clipped edge");
                for (let i = 0; i < 160 && module.animating; i++) wait(10);
                if (module.visible || module.animating)
                    throw Error("module did not finish exiting");
                console.log("PASS: module exit remains visible after 120 ms (opacity=" + alpha.toFixed(3) + ") and finishes cleanly");
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
