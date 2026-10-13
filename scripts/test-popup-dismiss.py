#!/usr/bin/env python3
"""Live Hyprland regression for popup Escape and outside click-through.

Requires a desktop session and ydotool. Moves the pointer; inputs target only
temporary windows. The receiver is a separate application process.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def command(*args):
    return subprocess.check_output(args, text=True, timeout=5).strip()


def move(x, y):
    command("hyprctl", "dispatch", f"hl.dsp.cursor.move({{x = {x}, y = {y}}})")
    command("ydotool", "mousemove", "-x", "1", "-y", "1")
    command("hyprctl", "dispatch", f"hl.dsp.cursor.move({{x = {x}, y = {y}}})")
    actual = json.loads(command("hyprctl", "-j", "cursorpos"))
    assert actual == {"x": x, "y": y}, f"pointer missed target: {actual}"


def main():
    source = (ROOT / "Bar.qml").read_text()
    start = source.index("    readonly property bool keyed:")
    end = source.index("\n    // Selection mode", start)
    keyboard = source[start:end]
    hover = source.split("    HoverHandler {", 1)[1].split("\n    }", 1)[0]
    qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.components
ShellRoot {
    id: fixture
    property int clicks: 0
    property int escapes: 0
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        margins.top: 40
        exclusiveZone: 0
        implicitHeight: 30
        color: "#444444"
        WlrLayershell.namespace: "qs-dismiss-fixture"
        WlrLayershell.layer: WlrLayer.Top
        Linger { id: raise; shown: OpenPopup.owner !== null || barHover.hovered || PopupPointer.hovered > 0 }
        KEYBOARD
        HoverHandler { HOVER
        }
        BarItem {
            id: owner; x: 1100; width: 100; height: 30
            popup: Popup {
                probes: false
                Rectangle { implicitWidth: 150; implicitHeight: 60; color: "grey" }
            }
        }
    }
    IpcHandler {
        target: "fixture"
        function open(): void { OpenPopup.set(owner); }
        function state(): string {
            return JSON.stringify({open: OpenPopup.owner !== null, bars: PopupPointer.bars,
                hovered: PopupPointer.hovered, keyed: bar.keyed, clicks: fixture.clicks,
                escapes: fixture.escapes});
        }
    }
}
'''.replace("KEYBOARD", keyboard).replace("HOVER", hover)
    with tempfile.TemporaryDirectory(prefix="qs-popup-dismiss-") as folder:
        target = Path(folder)
        for item in ROOT.iterdir():
            if item.name not in (".git", "settings.json", "shell.qml"):
                (target / item.name).symlink_to(item)
        (target / "settings.json").write_text("{}\n")
        (target / "shell.qml").write_text(qml)
        (target / "receiver.qml").write_text('''
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot { id: fixture; property int clicks: 0; property int escapes: 0; property int keysReceived: 0
    FloatingWindow {
        title: "QS popup dismissal fixture"
        implicitWidth: 400; implicitHeight: 200
        color: "#555555"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: fixture.clicks++ }
        Item {
            focus: true
            Keys.onPressed: event => { if (event.key === Qt.Key_Escape) fixture.escapes++; else fixture.keysReceived++; }
        }
    }
 IpcHandler { target: "receiver"; function count(): int { return fixture.clicks; } function keys(): int { return fixture.keysReceived; } } }
''')
        env = dict(os.environ, XDG_STATE_HOME=str(target / "state"),
                   XDG_DATA_HOME=str(target / "data"), XDG_CACHE_HOME=str(target / "cache"))
        original = json.loads(command("hyprctl", "-j", "cursorpos"))
        with (target / "log").open("w+") as log:
            receiver = subprocess.Popen(["qs", "-p", str(target / "receiver.qml"), "--no-color"], env=env, stdout=log, stderr=log)
            process = subprocess.Popen(["qs", "-p", str(target), "--no-color"], env=env,
                                       stdout=log, stderr=log)
            try:
                time.sleep(1)
                clients = json.loads(command("hyprctl", "-j", "clients"))
                window = next(w for w in clients if w["title"] == "QS popup dismissal fixture")
                x = window["at"][0] + window["size"][0] - 30
                y = window["at"][1] + window["size"][1] // 2
                layers = json.loads(command("hyprctl", "-j", "layers"))
                panel = next(item for monitor in layers.values() for items in monitor["levels"].values()
                             for item in items if item["namespace"] == "qs-dismiss-fixture")

                def state():
                    result = json.loads(command("qs", "ipc", "-p", str(target), "call", "fixture", "state"))
                    result["clicks"] = int(command("qs", "ipc", "-p", str(target / "receiver.qml"), "call", "receiver", "count"))
                    return result

                def open_popup():
                    move(panel["x"] + 1150, panel["y"] + 15)
                    time.sleep(0.1)
                    command("ydotool", "click", "0xC0")
                    time.sleep(0.4)
                    assert state()["open"], "fixture popup did not open"
                    move(x, y)
                    time.sleep(0.3)
                    assert state()["open"], "moving to window prematurely closed popup"

                failures = []
                move(x, y)
                command("ydotool", "click", "0xC0")
                time.sleep(0.3)
                baseline = state()["clicks"]
                print("Click baseline:", state())
                assert baseline == 1, "plain click does not reach fixture; reproduction is invalid"
                move(panel["x"] + 1150, panel["y"] + 15)
                time.sleep(0.1)
                before_keys = int(command("qs", "ipc", "-p", str(target / "receiver.qml"), "call", "receiver", "keys"))
                command("ydotool", "key", "30:1", "30:0", "30:1", "30:0")
                time.sleep(0.1)
                after_keys = int(command("qs", "ipc", "-p", str(target / "receiver.qml"), "call", "receiver", "keys"))
                assert state()["bars"] > 0 and after_keys == before_keys + 2, "idle bar hover intercepts typing"
                print("PASS: typing stays with the application while hovering the idle bar")
                open_popup()
                command("ydotool", "key", "1:1", "1:0")
                time.sleep(0.3)
                result = state()
                print("Escape over window:", result)
                if result["open"]:
                    failures.append("Escape over an application window leaves popup open")

                open_popup()
                command("ydotool", "click", "0xC0")
                time.sleep(0.3)
                result = state()
                print("Click over window:", result)
                if result["clicks"] != baseline + 1:
                    failures.append("outside click does not reach the application")
                if result["open"]:
                    failures.append("click over an application window leaves popup open")
                for button in ("left", "right"):
                    open_popup()
                    baseline = state()["clicks"]
                    command("ydotool", "click", "0x40" if button == "left" else "0x41")
                    time.sleep(0.4)
                    if not state()["open"]:
                        failures.append("popup dismissed before outside button release")
                    command("ydotool", "click", "0x80" if button == "left" else "0x81")
                    time.sleep(0.3)
                    result = state()
                    print("Held", button, "click:", result)
                    if result["open"] or result["clicks"] != baseline + 1:
                        failures.append(f"held {button} click failed dismissal or delivery")
                move(x, y)
                before_ipc = state()["clicks"]
                command("qs", "ipc", "-p", str(target), "call", "fixture", "open")
                time.sleep(0.4)
                command("ydotool", "click", "0xC0")
                time.sleep(0.3)
                if state()["open"] or state()["clicks"] != before_ipc + 1:
                    failures.append("keyboard-opened popup blocks outside click delivery")
                else:
                    print("PASS: keyboard-opened popup also preserves the outside application's click")
                for failure in failures:
                    print("FAIL:", failure)
                if not failures:
                    print("PASS: popup dismissal over an application window")
                return bool(failures)
            finally:
                receiver.terminate()
                receiver.wait(timeout=5)
                process.terminate()
                process.wait(timeout=5)
                move(original["x"], original["y"])
                log.seek(0)
                output = log.read()
                if "ERROR" in output or "Error:" in output:
                    print(output)


if __name__ == "__main__":
    raise SystemExit(main())
