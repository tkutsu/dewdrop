#!/usr/bin/env python3
"""Run Drops.js through every reveal, arriving and leaving, in Quickshell's engine."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SHELL = '''import QtQuick
import Quickshell
import "Drops.js" as Drops
ShellRoot {
    Component.onCompleted: {
        const theme = {barHeight: 30, pillSpread: 16, barInset: 4};
        const g = Drops.geometry(theme);
        const failures = [];
        for (let step = 0; step <= 20; step++) {
            const reveal = step / 20;
            for (const leaving of [false, true]) {
                try {
                    for (const dir of [-1, 1]) {
                        const box = g.drop(100, dir, 60, reveal, leaving);
                        if ([box.x, box.y, box.z, box.w].some(v => !isFinite(v)))
                            failures.push(`drop ${reveal} ${leaving} ${dir}: ${box}`);
                    }
                    [g.lip(reveal, leaving), g.dropReach(reveal, leaving), g.contents(reveal)]
                        .forEach(v => { if (!isFinite(v)) failures.push(`scalar ${reveal} ${leaving}`); });
                    g.bulge(100, 1, reveal, leaving);
                    g.morph(Qt.vector4d(0, 0, 60, 30), reveal * 2);
                    g.morphContents(reveal);
                } catch (e) {
                    failures.push(`${reveal} ${leaving}: ${e}`);
                }
            }
        }
        // At rest a pill sits a spread from its neighbour, at its own width.
        try {
            const rest = g.drop(100, 1, 60, 1, false);
            if (rest.x !== 116 || rest.y !== 4 || rest.z !== 60 || rest.w !== 30)
                failures.push(`rest box ${rest}`);
        } catch (e) {
            failures.push(`rest box: ${e}`);
        }
        console.warn(failures.length ? "DROPS FAIL " + failures.slice(0, 5).join(" | ") : "DROPS OK");
    }
}
'''


def main():
    with tempfile.TemporaryDirectory() as tmp:
        shell = Path(tmp) / "shell"
        shell.mkdir()
        shutil.copy(ROOT / "Drops.js", shell / "Drops.js")
        (shell / "shell.qml").write_text(SHELL)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=tmp)
        # Quickshell keeps running after the check, so read what it said by then.
        try:
            output = subprocess.run(["quickshell", "-p", str(shell / "shell.qml")], env=env,
                                    capture_output=True, text=True, timeout=10).stdout
        except subprocess.TimeoutExpired as e:
            output = e.stdout.decode() if isinstance(e.stdout, bytes) else e.stdout or ""
    result = next((line.strip() for line in output.splitlines() if "DROPS " in line), "")
    print(result or "no result from the fixture")
    if "DROPS OK" not in result:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
