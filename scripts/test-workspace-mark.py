#!/usr/bin/env python3
"""Render both workspace marks and verify selection, motion and shared sheen."""

import os
import json
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
ShellRoot {
    PanelWindow {
        implicitWidth: 360; implicitHeight: 46
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:lab"
        mask: Region {}
        color: "black"
        Item {
            id: capture; anchors.fill: parent
            property int phase: 0
            property int failures: 0
            Rectangle {
                id: ground; anchors.fill: parent; color: "#34383e"
                Repeater {
                    model: 60
                    Rectangle {
                        required property int index
                        x: index * 6; width: 3; height: ground.height
                        color: index % 2 ? "#788d9a" : "#a4a099"
                    }
                }
            }
            ShaderEffectSource {
                id: texture; property real glassWeight: 1
                width: ground.width; height: ground.height
                sourceItem: ground; visible: false
            }
            Item {
                id: pill; anchors.fill: parent
                Liquid {
                    id: slab; anchors.fill: parent; backdrop: texture
                    box0: Qt.vector4d(20, 8, 320, 30)
                    hover: Qt.vector4d(0, 0, 1, 0); press: Qt.vector4d(0, 0, 1, 0)
                }
                Row {
                    x: 54; y: 14; spacing: 48
                    Repeater {
                        model: ["A", "B", "C", "D"]
                        Text { required property string modelData; text: modelData; color: "white"; font.pixelSize: 18 }
                    }
                }
            }
            FlowMark {
                id: mark; opacity: 0; anchors.fill: parent
                slabY: 8; slabHeight: 30; wallLeft: 21; wallRight: 339
                wantLeft: 104; wantRight: 155
            }
            BeadMark {
                id: bead; anchors.fill: parent
                mark: mark; pillItem: pill; wallpaperItem: texture
            }
            function check(ok, message) {
                console.log((ok ? "PASS: " : "FAIL: ") + message);
                if (!ok) failures++;
            }
            function next() {
                if (phase < 2) {
                    Settings.user = {workspaceMark: phase === 0 ? "bead" : "grey"};
                    check(bead.sheen.x === slab.sheen.x && bead.sheen.y === slab.sheen.y
                        && bead.sheen.z === slab.sheen.z && bead.sheen.w === slab.sheen.w,
                        "shared Wide satin border for " + Settings.workspaceMark);
                    check(Math.abs(slab.sheen.x + 0.707) < 0.0001 && Math.abs(slab.sheen.y + 0.707) < 0.0001
                        && Math.abs(slab.sheen.z - 0.10) < 0.0001 && Math.abs(slab.sheen.w - 0.075) < 0.0001,
                        "Wide satin border values for " + Settings.workspaceMark);
                } else if (phase === 2) {
                    Settings.user = {workspaceMark: "grey"}; mark.held = true;
                } else if (phase === 3) {
                    check(bead.clear > 0.9 && bead.h === mark.thickness && bead.stretch === 0,
                        "held grey glass keeps the mark's low geometry");
                    Settings.user = {workspaceMark: "bead"};
                } else if (phase === 4) {
                    check(bead.h > mark.thickness + 4, "held bead expands above the pill");
                    Settings.user = {workspaceMark: "grey", reduceMotion: true}; mark.held = false;
                } else if (phase === 5) {
                    check(bead.clear === 0 && bead.h === mark.thickness, "Reduce motion settles grey glass");
                    Settings.user = {workspaceMark: "grey", reduceTransparency: true};
                    check(!bead.active, "Reduce transparency uses the plain selection");
                    Settings.user = {workspaceMark: "invalid"};
                    check(Settings.workspaceMark === "bead", "unknown choice falls back to bead");
                    mark.wantLeft = 80; mark.wantRight = 280; mark.held = true;
                } else if (phase >= 6 && phase < 14) {
                    Settings.user = {workspaceMark: phase < 10 ? "bead" : "grey"};
                    mark.held = (phase - 6) % 4 >= 2;
                    bead.fragmentShader = phase % 2 === 0
                        ? Qt.resolvedUrl("shaders/mark.frag.qsb") : Qt.resolvedUrl("flat.frag.qsb");
                } else if (phase === 14) {
                    console.log("RESULT: " + failures + " failures"); Qt.quit(); return;
                }
                delay.start();
            }
            Timer {
                id: delay; interval: 1500
                onTriggered: capture.grabToImage(result => {
                    result.saveToFile(Quickshell.shellPath("mark-" + capture.phase + ".png"));
                    if (capture.phase >= 6)
                        console.log("BOX: " + JSON.stringify([bead.box.x, bead.box.y, bead.box.z, bead.box.w]));
                    capture.phase++; capture.next();
                })
            }
            Component.onCompleted: Qt.callLater(next)
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-mark-render-") as folder:
        target = Path(folder)
        for source in ROOT.iterdir():
            if source.name not in (".git", "settings.json", "shell.qml"):
                (target / source.name).symlink_to(source)
        (target / "settings.json").write_text("{}\n")
        (target / "shell.qml").write_text(QML)
        # Disable only optical displacement; retain the real tint and border.
        shader = (ROOT / "shaders/mark.frag").read_text()
        shader = shader.replace("vec3 glass =", "shift = vec2(0.0); seen = p;\n    vec3 glass =")
        (target / "flat.frag").write_text(shader)
        subprocess.run(["/usr/lib/qt6/bin/qsb", "--qt6", "-o", str(target / "flat.frag.qsb"),
                        str(target / "flat.frag")], check=True)
        env = dict(os.environ, QT_QUICK_BACKEND="rhi", QT_QPA_PLATFORM="wayland",
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"),
                   XDG_DATA_HOME=str(target / "data"))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end="")
        if result.returncode or "RESULT: 0 failures" not in output:
            return 1
        frames = [Image.open(target / f"mark-{i}.png").convert("RGB") for i in range(2)]
        checks = {
            "grey glass renders differently from the bead": ImageChops.difference(frames[0], frames[1]).getbbox() is not None,
            "mark leaves distant pill content unchanged": ImageChops.difference(
                frames[0].crop((240, 10, 300, 36)), frames[1].crop((240, 10, 300, 36))).getbbox() is None,
        }
        boxes = [json.loads(line.split("BOX: ", 1)[1]) for line in output.splitlines() if "BOX: " in line]
        for start, style in ((6, "bead"), (10, "grey")):
            for offset, state in ((0, "rest"), (2, "held")):
                actual = Image.open(target / f"mark-{start + offset}.png").convert("RGB")
                flat = Image.open(target / f"mark-{start + offset + 1}.png").convert("RGB")
                x, y, width, height = boxes[start + offset - 6]
                radius = min(width, height) / 2
                centre = (int(x + radius + 2), int(y + 2), int(x + width - radius - 2), int(y + height - 2))
                delta = ImageChops.difference(actual, flat)
                checks[f"{style} at {state} leaves the entire straight center undistorted"] = delta.crop(centre).getbbox() is None
                for side, left, right in (("left", x + 2, x + radius), ("right", x + width - radius, x + width - 2)):
                    cap = (int(left), int(y + 2), int(right), int(y + height - 2))
                    checks[f"{style} at {state} distorts its {side} rounded cap"] = delta.crop(cap).getbbox() is not None
        if destination := os.environ.get("MARK_PREVIEW_DIR"):
            preview = Path(destination)
            preview.mkdir(parents=True, exist_ok=True)
            for i, frame in enumerate(frames):
                frame.save(preview / f"mark-{i}.png")
        for message, ok in checks.items():
            print(("PASS: " if ok else "FAIL: ") + message)
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
