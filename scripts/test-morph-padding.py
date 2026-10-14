#!/usr/bin/env python3
"""Render pill morphs across the bar's bottom padding without unclipping joins."""

import os
from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
QML = '''import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
import "Drops.js" as Drops
ShellRoot {
    id: bar
    MORPH
    PanelWindow {
        implicitWidth: 480; implicitHeight: Theme.barHeight + 2 * Theme.barInset
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:lab"
        mask: Region {}
        color: "transparent"
        Item {
            id: capture; anchors.fill: parent
            property int phase: 0
            readonly property real progress: [0.5, 0.75, 1, 1.75, 2, 1][Math.min(phase, 5)]
            Liquid {
                id: glass; anchors.fill: parent
                box0: Qt.vector4d(200, Theme.barInset, 50, Theme.barHeight)
                box1: bar.morph(Qt.vector4d(80, Theme.barInset, 100, Theme.barHeight), capture.progress)
                box2: bar.morph(Qt.vector4d(360, Theme.barInset, 100, Theme.barHeight), capture.progress)
                box3: Qt.vector4d(250, Theme.barInset, 50, Theme.barHeight)
                reaches: Qt.vector4d(0, 0, 0, 16)
                fill: Qt.vector4d(1,0,0,1)
                rimTop: Qt.vector4d(1,0,0,1); rimBottom: rimTop
                Component.onCompleted: if ("overflow" in glass) glass.overflow = OVERFLOW
            }
            Timer {
                interval: 120; running: true; repeat: true
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("frame-" + capture.phase + ".png"));
                    if (++capture.phase === 5) {
                        if ("overflow" in glass) glass.overflow = Qt.vector4d(0,0,0,0);
                    } else if (capture.phase === 6) Qt.quit();
                })
            }
        }
    }
}
'''


def main():
    source = (ROOT / "Bar.qml").read_text()
    morph = "    readonly property var drops: Drops.geometry(Theme)\n    function morph(box, s) { return bar.drops.morph(box, s); }"
    overflow = re.search(r"        overflow: ([^\n]+)", source)
    binding = overflow.group(1) if overflow else "Qt.vector4d(0,0,0,0)"
    with tempfile.TemporaryDirectory(prefix="quickshell-morph-padding-") as folder:
        target = Path(folder)
        for item in ROOT.iterdir():
            if item.name not in (".git", "settings.json", "shell.qml"):
                (target / item.name).symlink_to(item)
        (target / "settings.json").write_text("{}\n")
        # The last frame checks the component's default clipping with a sunk pill.
        qml = QML.replace("MORPH", morph).replace("OVERFLOW", binding)
        (target / "shell.qml").write_text(qml)
        env = dict(os.environ, QT_QUICK_BACKEND="rhi", QT_QPA_PLATFORM="wayland",
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"),
                   XDG_DATA_HOME=str(target / "data"))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        if result.returncode or not (target / "frame-5.png").exists():
            print(result.stdout + result.stderr)
            return 1
        frames = {i: Image.open(target / f"frame-{i}.png").convert("RGBA") for i in range(6)}
        y = 37
        checks = {
            "recording and music stay above padding before sinking": all(frames[0].getpixel((x, y))[3] == 0 for x in (130, 410)),
            "recording and music cross padding while still gathering": all(frames[1].getpixel((x, y))[3] > 200 for x in (130, 410)),
            "formed drops remain visible in padding": all(frames[2].getpixel((x, y))[3] > 200 for x in (130, 410)),
            "drops continue through padding before disappearing": all(frames[3].getpixel((x, y))[3] > 200 for x in (130, 410)),
            "completed morph removes both drops": all(frames[4].getpixel((x, y))[3] == 0 for x in (130, 410)),
            "stationary smooth joins stay clipped": all(frame.getpixel((250, y))[3] == 0 for frame in frames.values()),
            "overflow stays disabled by default": all(frames[5].getpixel((x, y))[3] == 0 for x in (130, 410)),
        }
        for name, passed in checks.items():
            print(("PASS: " if passed else "FAIL: ") + name)
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
