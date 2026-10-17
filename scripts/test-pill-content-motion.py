#!/usr/bin/env python3
"""Render both pill transitions and reject ink outside the moving glass."""

import os
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

from test_support import copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
ShellRoot {
    PanelWindow {
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:lab"
        mask: Region {}
        visible: true; implicitWidth: 440; implicitHeight: 80; color: "black"
        Item {
            id: capture; anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "black" }
            Item { id: control; property real reveal: 1; property bool stowed: true }
            Liquid {
                id: glass; anchors.fill: parent
                fill: Qt.vector4d(1,0,0,1); rimTop: fill; rimBottom: fill
                sheen: Qt.vector4d(0,-1,0,0)
                box0: Qt.vector4d(10,Theme.barInset,90,Theme.barHeight)
                box1: pill.geometry.drop(100,1,pill.width,control.reveal,control.stowed)
            }
            SidePill {
                id: pill; control: control; side: Pill.Side.Left; edgeOffset: 116
                progress: 1; trackColor: "blue"
                BarItem {
                    implicitWidth: 260
                    BarText { text: "Music    A long track title    03:45"; color: "lime" }
                }
            }
            property var frames: [1,0.95,0.9,0.85,0.8,0.75,0.65,0.5,0.3,0,0.3,0.5,0.65,0.75,0.8,0.85,0.9,0.95,1]
            property int index: 0
            function shot() {
                control.stowed = index < 10;
                control.reveal = frames[index];
                delay.start();
            }
            function save(name, next) {
                grabToImage(result => { result.saveToFile(Quickshell.shellPath(name)); next(); });
            }
            Timer { interval: 300; running: true; onTriggered: capture.shot() }
            Timer {
                id: delay; interval: 60
                onTriggered: capture.save("combined-" + capture.index + ".png", () => {
                    pill.visible = false; bare.start();
                })
            }
            Timer {
                id: bare; interval: 30
                onTriggered: capture.save("glass-" + capture.index + ".png", () => {
                    pill.visible = true;
                    capture.index++;
                    if (capture.index < capture.frames.length) capture.shot();
                    else {
                        Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                        control.reveal = 0.9;
                        if (pill.contentZoom !== 1 || pill.contentBlur !== 0)
                            console.log("FAIL: Reduce motion still scales or blurs the contents");
                        Qt.quit();
                    }
                })
            }
        }
    }
}
'''

def main():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    display = str(Path(runtime) / display)
    with tempfile.TemporaryDirectory(prefix="qs-pill-motion-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                          QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=display),
            capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Cannot assign", "Unable to assign")
        if result.returncode or not (target / "combined-18.png").exists() or any(error in output for error in errors):
            print(output)
            return 1
        scenes, materials, ghosts = [], [], []
        for i in range(19):
            scene = Image.open(target / f"combined-{i}.png").convert("RGB")
            material = Image.open(target / f"glass-{i}.png").convert("RGB")
            scenes.append(scene)
            materials.append(material)
            ghosts.append(sum(1 for (_,g,b),(mr,_,_) in zip(scene.get_flattened_data(),material.get_flattened_data())
                              if mr == 0 and max(g,b) > 8))
        ink = lambda i: sum(max(g,b) for _,g,b in scenes[i].get_flattened_data())
        checks = {
            "contents and tracker stay inside the glass in both directions": not any(ghosts),
            "ink remains visible through contraction until the circle forms": ink(0) > ink(4) > ink(5) > ink(6) > ink(7) == 0,
            "ink returns gradually as the circle expands": ink(11) == 0 < ink(12) < ink(13) < ink(14) < ink(18),
            "glass keeps its rendered strength throughout the content transition": all(im.getpixel((125,15)) == (255,0,0) for im in materials[:8] + materials[11:]),
            "resting content returns sharply without a lingering effect": scenes[0].tobytes() == scenes[18].tobytes(),
        }
        for message, passed in checks.items():
            print(("PASS: " if passed else "FAIL: ") + message)
        if any(ghosts):
            print("Content pixels outside glass by frame:", ghosts)
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
