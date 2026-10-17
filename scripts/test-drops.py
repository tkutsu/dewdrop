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
                    [g.lip(reveal, leaving), g.dropReach(reveal, leaving), g.contents(reveal), g.iconScale(reveal)]
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
        // Skipping an empty pill's content fade preserves its starting box,
        // then shrinks the glass from the first movement of its reveal.
        const emptyStart = g.drop(100, 1, 84, g.emptyReveal(1), true);
        const emptyMoving = g.drop(100, 1, 84, g.emptyReveal(0.99), true);
        if (emptyStart.x !== 116 || emptyStart.z !== 84 || emptyStart.w !== 30
            || emptyMoving.z >= emptyStart.z || g.emptyReveal(0) !== 0)
            failures.push("empty exit pauses or jumps at its handoff");
        // An impact has one soft swell and one smaller rebound, easing to rest.
        const lip = phase => g.lip(0.38 * (1 - phase), true);
        const samples = Array.from({length: 101}, (_, i) => lip(i / 100));
        if (Math.max(...samples) > 3 || Math.max(...samples) < 1 || Math.min(...samples) >= 0
            || Math.abs(Math.min(...samples)) > Math.max(...samples) / 4)
            failures.push("impact amplitude or rebound");
        let crossings = 0;
        for (let i = 1; i < 100; i++)
            if (samples[i - 1] > 0 && samples[i] <= 0) crossings++;
        if (crossings !== 1)
            failures.push("impact repeats instead of settling");
        const epsilon = 0.0001;
        if (Math.abs(lip(epsilon) / epsilon) > 0.02
            || Math.abs(lip(1 - epsilon) / epsilon) > 0.02 || Math.abs(lip(1)) > 0.00001)
            failures.push("impact snaps at an endpoint");
        const earlyBulge = g.bulge(100, 1, 0.36 - 0.12 * epsilon, true);
        if (Math.abs((earlyBulge.w - theme.barHeight) / epsilon) > 0.02)
            failures.push("bulge snaps into view");
        // A forward spring always lifts first, dips, rebounds less, and settles.
        const scales = Array.from({length: 101}, (_, i) => g.iconScale(i / 100));
        const rebound = Math.max(...scales.slice(67));
        if (g.iconScale(0.05) <= 1 || g.iconScale(0.15) < 1.15 || g.iconScale(0.5) >= 0.96
            || rebound < 1.015 || rebound > 1.04
            || Math.max(...scales) > 1.20 || Math.min(...scales) < 0.92
            || g.iconScale(0) !== 1 || g.iconScale(1) !== 1
            || g.iconScale(-1) !== 1 || g.iconScale(2) !== 1
            || Math.abs((g.iconScale(epsilon) - 1) / epsilon) > 0.02
            || Math.abs((g.iconScale(1 - epsilon) - 1) / epsilon) > 0.02)
            failures.push("icon spring must lift immediately, dip and rebound gently before settling");
        theme.reduceMotion = true;
        if (g.lip(0.3, true) !== 0 || g.lip(0.65, false) !== 0 || g.bulge(100, 1, 0.3, true).z !== 0)
            failures.push("reduced motion still wobbles");
        if (g.iconScale(0.85) !== 1 || g.iconScale(0.65) !== 1)
            failures.push("reduced motion still scales icons");
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
