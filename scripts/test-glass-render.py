#!/usr/bin/env python3
"""Render the real track and contents; compare the right cap to Liquid's curve."""
import math
import os
import re
from pathlib import Path
import subprocess
import tempfile
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
QML = '''//@ pragma Env QSG_RENDER_LOOP=threaded
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
import "Drops.js" as Drops
ShellRoot {
    id: bar
    BULGE
    PanelWindow {
        implicitWidth: 360; implicitHeight: 80
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:lab"
        mask: Region {}
        color: "black"
        Item {
            id: capture; anchors.fill: parent
            Rectangle { id: ground; anchors.fill: parent; color: "black" }
            ShaderEffectSource { id: texture; property real glassWeight: 0; sourceItem: ground; visible: false }
            Liquid {
                anchors.fill: parent; backdrop: texture; takesPress: true
                press: Qt.vector4d(0,0,1,0); hover: Qt.vector4d(0,0,1,0)
                fill: Qt.vector4d(1,0,0,1); rimTop: Qt.vector4d(1,0,0,1); rimBottom: rimTop
                sheen: Qt.vector4d(0,-1,0,0)
                box0: Qt.vector4d(-200, Theme.barInset, 224, 30)
                box1: Qt.vector4d(pill.x, Theme.barInset, pill.width, 30)
                bulge1: bar.bulge(pill.x + pill.width, 1, 0, true)
                reaches: Qt.vector4d(0,16,3.2,16)
            }
            Pill {
                id: pill; drawsSlab: false; progress: 1; trackColor: "blue"
                BarItem { id: button; implicitWidth: 280; BarText { text: "Timer preview     05:00" } }
            }
            Timer {
                interval: 300; running: true
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("rest.png"));
                    GlassPress.press(button.keyBox, button.mapToItem(null, button.width / 2, 15));
                    peak.start();
                })
            }
            Timer {
                id: peak; interval: 220
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("pressed.png"));
                    GlassPress.release(button.keyBox);
                    pill.progress = 0.55;
                    partial.start();
                })
            }
            Timer {
                id: partial; interval: 400
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("partial.png"));
                    pill.progress = 1;
                    pill.trackWidth = 3;
                    thick.start();
                })
            }
            Timer {
                id: thick; interval: 60
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("thick.png"));
                    pill.trackReady = false;
                    fadeBegin.start();
                })
            }
            Timer { id: fadeBegin; interval: 40; onTriggered: { pill.trackReady = true; fadeEarly.start(); } }
            Timer {
                id: fadeEarly; interval: 60
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("fade-early.png")); fadeMiddle.start();
                })
            }
            Timer {
                id: fadeMiddle; interval: 80
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("fade-middle.png")); fadeEnd.start();
                })
            }
            Timer {
                id: fadeEnd; interval: 160
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("fade-end.png"));
                    Qt.quit();
                })
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-glass-render-") as folder:
        target = Path(folder)
        for source in ROOT.iterdir():
            if source.name not in (".git", "settings.json", "shell.qml"):
                (target / source.name).symlink_to(source)
        (target / "settings.json").write_text("{}\n")
        source = (ROOT / "Bar.qml").read_text()
        bulge = "    readonly property var drops: Drops.geometry(Theme)\n    function bulge(end, dir, reveal, leaving) { return bar.drops.bulge(end, dir, reveal, leaving); }"
        (target / "shell.qml").write_text(QML.replace("BULGE", bulge))
        env = dict(os.environ, QT_QUICK_BACKEND="rhi", QT_QPA_PLATFORM="wayland",
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"),
                   XDG_DATA_HOME=str(target / "data"))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        if result.returncode or not (target / "rest.png").exists():
            print(result.stdout + result.stderr)
            return 1
        rest = Image.open(target / "rest.png").convert("RGB")
        pressed = Image.open(target / "pressed.png").convert("RGB")
        partial = Image.open(target / "partial.png").convert("RGB")
        thick = Image.open(target / "thick.png").convert("RGB")
        inset = int(re.search(r"property int barInset: (\d+)", (ROOT / "Theme.qml").read_text()).group(1))
        centre_y = inset + 15
        errors = []
        thick_errors = []
        for y in range(inset - 1, inset + 31):
            for x in range(305, 322):
                d = math.hypot(x + .5 - 305, y + .5 - centre_y) - 15
                coverage = max(0, min(1, .5 - d)) - max(0, min(1, .5 - d - 1.5))
                expected = coverage * (1 - .7 * (y + .5 - inset + 1) / 32)
                errors.append(abs(rest.getpixel((x, y))[2] / 255 - expected))
                wide = max(0, min(1, .5 - d)) - max(0, min(1, .5 - d - 3))
                expected_wide = wide * (1 - .7 * (y + .5 - inset + 1) / 32)
                thick_errors.append(abs(thick.getpixel((x, y))[2] / 255 - expected_wide))
        fade = [Image.open(target / ("fade-" + step + ".png")).convert("RGB").getpixel((319, centre_y))[2]
                for step in ("early", "middle", "end")]
        checks = {
            "press keeps the glass and progress outline geometry unchanged": all(
                ImageChops.difference(rest.crop(region), pressed.crop(region)).getbbox() is None
                for region in ((0, 0, 360, 9), (0, 29, 360, 80), (305, 0, 360, 80))),
            "track renders a gradual fade through intermediate brightness": 0 < fade[0] < fade[1] < fade[2],
            "shared glass stops at the same right edge as the timer track": all(rest.getpixel((x, centre_y))[0] == 0 for x in range(321, 327)),
            "right cap matches the glass contour within 1% alpha": max(errors) < .01,
            "hover-thickened cap also matches the glass": max(thick_errors) < .01,
            "clockwise progress includes the right cap": partial.getpixel((319, centre_y))[2] > 100,
            "clockwise progress leaves the bottom middle dim": partial.getpixel((180, inset + 29))[2] < 30,
        }
        for name, passed in checks.items():
            print(("PASS: " if passed else "FAIL: ") + name)
        print(f"Maximum cap coverage error: {max(errors):.4f}")
        print("Rendered fade brightness:", fade)
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
