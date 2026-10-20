#!/usr/bin/env python3
"""Live Hyprland regression for module dragging after a popup opens on press.

Requires a desktop session and ydotool. Uses an isolated bar and saved state,
releases held input on failure, and restores the original pointer position.
QtTest's synthetic mouse events do not reproduce Wayland's lost pointer grab.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from test_support import copy_shell

QML = '''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
ShellRoot {
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        margins.top: 70
        exclusiveZone: 0
        implicitHeight: 60
        color: "#444444"
        WlrLayershell.namespace: "qs-reorder-fixture"
        WlrLayershell.layer: WlrLayer.Top
        KEYBOARD
        Pill { id: clockPill; visible: false }
        Pill {
            id: rightPill
            order: RightPillOrder.keys
            drawsSlab: false
            BarItem {
                id: audio; pinKey: "audio"
                popup: Popup { probes: false; Rectangle { implicitWidth: 180; implicitHeight: 80 } }
                Rectangle { implicitWidth: 60; implicitHeight: 20; color: "red" }
            }
            BarItem {
                id: email; pinKey: "email"
                popup: Popup { probes: false; Rectangle { implicitWidth: 180; implicitHeight: 80 } }
                Rectangle { implicitWidth: 60; implicitHeight: 20; color: "green" }
            }
            BarItem {
                id: network; pinKey: "network"
                popup: Popup { probes: false; Rectangle { implicitWidth: 180; implicitHeight: 80 } }
                Rectangle { implicitWidth: 60; implicitHeight: 20; color: "blue" }
            }
        }
        MouseArea {
            anchors.fill: parent
            z: 1
            enabled: OpenPopup.owner !== null
            onPressed: mouse => {
                mouse.accepted = false;
                const owner = OpenPopup.owner;
                if (owner && !owner.contains(mapToItem(owner, mouse.x, mouse.y)))
                    OpenPopup.close(owner);
            }
        }
    }
    IpcHandler {
        target: "fixture"
        function state(): string {
            return JSON.stringify({order: RightPillOrder.keys, dragging: rightPill.dragging,
                open: OpenPopup.owner !== null,
                items: [audio, email, network].map(item => ({key: item.settingsKey,
                    x: item.mapToItem(bar.contentItem, item.width / 2, 0).x,
                    y: item.mapToItem(bar.contentItem, 0, item.height / 2).y}))});
        }
    }
}'''


def command(*args):
    return subprocess.check_output(args, text=True, timeout=5).strip()


def move(x, y):
    """Deliver a real pointer update at the requested desktop coordinates."""
    command("hyprctl", "dispatch", f"hl.dsp.cursor.move({{x = {x}, y = {y}}})")
    command("ydotool", "mousemove", "-x", "1", "-y", "1")
    command("hyprctl", "dispatch", f"hl.dsp.cursor.move({{x = {x}, y = {y}}})")
    assert json.loads(command("hyprctl", "-j", "cursorpos")) == {"x": x, "y": y}


def main():
    with tempfile.TemporaryDirectory(prefix="qs-module-drag-") as folder:
        target = Path(folder)
        copy_shell(target)
        bar = (Path(__file__).resolve().parents[1] / "Bar.qml").read_text()
        start = bar.index("    readonly property bool keyed:")
        end = bar.index("    // Selection mode", start)
        (target / "shell.qml").write_text(QML.replace("KEYBOARD", bar[start:end]))
        env = dict(os.environ, XDG_STATE_HOME=str(target / "state"),
                   XDG_CACHE_HOME=str(target / "cache"), XDG_DATA_HOME=str(target / "data"),
                   XDG_CONFIG_HOME=str(target / "config"))
        original = json.loads(command("hyprctl", "-j", "cursorpos"))
        with (target / "log").open("w+") as log:
            process = subprocess.Popen(["qs", "-p", str(target), "--no-color"],
                                       env=env, stdout=log, stderr=log)
            held = False
            try:
                time.sleep(1)
                layers = json.loads(command("hyprctl", "-j", "layers"))
                panel = next(item for monitor in layers.values() for items in monitor["levels"].values()
                             for item in items if item["namespace"] == "qs-reorder-fixture")

                def state():
                    return json.loads(command("qs", "ipc", "-p", str(target), "call", "fixture", "state"))

                # Move right, then left: both drags begin by opening a real popup.
                for direction in (1, -1):
                    before = state()
                    source = next(item for item in before["items"] if item["key"] == "audio")
                    others = [item for item in before["items"] if item["key"] != "audio"]
                    x = panel["x"] + round(source["x"])
                    y = panel["y"] + round(source["y"])
                    end = panel["x"] + round(max(item["x"] for item in others) + 24 if direction == 1
                                            else min(item["x"] for item in others) - 24)
                    move(x, y)
                    time.sleep(0.1)
                    command("ydotool", "click", "0x40")
                    held = True
                    time.sleep(0.2)
                    assert state()["open"], "popup must open on press before dragging"
                    for step in range(1, 16):
                        move(round(x + (end - x) * step / 15), y)
                        time.sleep(0.015)
                    during = state()
                    assert during["dragging"], "module drag lost pointer input before release"
                    assert during["order"] == before["order"], "drag saved before release"
                    command("ydotool", "click", "0x80")
                    held = False
                    time.sleep(0.3)
                    after = state()
                    assert not after["dragging"] and not after["open"], "release must finish drag and dismiss popup"
                    visible = [key for key in after["order"] if key in ("audio", "email", "network")]
                    assert visible[-1 if direction == 1 else 0] == "audio", "module did not move to the dropped slot"
                    saved = json.loads((target / "state/quickshell/right-pill.json").read_text())
                    assert saved["order"] == after["order"], "drop was not persisted"
                    print("PASS: real Wayland popup and module drag", "right" if direction == 1 else "left", flush=True)
                before = state()
                source = next(item for item in before["items"] if item["key"] == "audio")
                move(panel["x"] + round(source["x"]), panel["y"] + round(source["y"]))
                command("ydotool", "click", "0x40")
                held = True
                time.sleep(0.2)
                assert state()["open"], "normal click must open popup on mouse-down"
                command("ydotool", "click", "0x80")
                held = False
                time.sleep(0.2)
                assert state()["open"], "normal release must keep popup open"
                command("ydotool", "key", "1:1", "1:0")
                time.sleep(0.2)
                assert not state()["open"], "released popup must still receive Escape"
                assert state()["order"] == before["order"], "plain click must not reorder modules"
                print("PASS: mouse-down opens popup; release preserves it; Escape closes it", flush=True)
            finally:
                try:
                    if held:
                        command("ydotool", "click", "0x80")
                finally:
                    process.terminate()
                    process.wait(timeout=5)
                    move(original["x"], original["y"])
                    log.seek(0)
                    output = log.read()
                    if sys.exc_info()[0] or any(error in output for error in ("ERROR", "Error:", "Binding loop")):
                        print(output)


if __name__ == "__main__":
    main()
