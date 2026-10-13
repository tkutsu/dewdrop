#!/usr/bin/env python3
"""Check live launcher/settings dismissal and delivery to a separate window."""

import json
import os
from pathlib import Path
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


def overlay_up():
    layers = json.loads(command("hyprctl", "-j", "layers"))
    return any(item["namespace"] == "quickshell:launcher" for monitor in layers.values()
               for items in monitor["levels"].values() for item in items)


def main():
    assert not overlay_up(), "Close the existing launcher/settings window first"
    original = json.loads(command("hyprctl", "-j", "cursorpos"))
    with tempfile.TemporaryDirectory(prefix="qs-overlay-dismiss-") as folder:
        target = Path(folder)
        (target / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: receiver
    property int clicks: 0
    FloatingWindow {
        title: "QS overlay click receiver"
        implicitWidth: 500; implicitHeight: 300; color: "#333333"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: receiver.clicks++
        }
    }
    IpcHandler {
        target: "receiver"
        function count(): int { return receiver.clicks; }
    }
}
''')
        with (target / "log").open("w+") as log:
            process = subprocess.Popen(["qs", "-p", str(target), "--no-color"], stdout=log, stderr=log)
            try:
                time.sleep(1)
                clients = json.loads(command("hyprctl", "-j", "clients"))
                window = next(w for w in clients if w["title"] == "QS overlay click receiver")
                x = window["at"][0] + 30
                y = window["at"][1] + window["size"][1] // 2

                def count():
                    return int(command("qs", "ipc", "-p", str(target), "call", "receiver", "count"))

                failures = []
                move(x, y)
                command("ydotool", "click", "0xC0")
                time.sleep(0.2)
                assert count() == 1, "A plain click did not reach the receiver"
                for name in ("launcher", "settings"):
                    for action in ("escape", "left", "held-left", "right"):
                        move(x, y)
                        baseline = count()
                        command("qs", "ipc", "-p", str(ROOT), "call", name, "toggle")
                        time.sleep(1.5)
                        assert overlay_up(), f"{name} did not open"
                        move(x, y)
                        time.sleep(0.1)
                        if action == "escape":
                            command("ydotool", "key", "1:1", "1:0")
                        elif action == "held-left":
                            command("ydotool", "click", "0x40")
                            time.sleep(0.4)
                            if not overlay_up():
                                failures.append(f"{name} closed before release")
                            command("ydotool", "click", "0x80")
                        else:
                            command("ydotool", "click", "0xC0" if action == "left" else "0xC1")
                        time.sleep(0.6)
                        closed = not overlay_up()
                        delivered = action == "escape" or count() == baseline + 1
                        print(name, action, "closed:", closed, "click delivered:", delivered, flush=True)
                        if not closed or not delivered:
                            failures.append(f"{name} {action}: closed={closed}, delivered={delivered}")
                        if not closed:
                            command("qs", "ipc", "-p", str(ROOT), "call", name, "toggle")
                            time.sleep(0.4)
                for failure in failures:
                    print("FAIL:", failure)
                if not failures:
                    print("PASS: launcher and settings Escape and outside click-through")
                return bool(failures)
            finally:
                process.terminate()
                process.wait(timeout=5)
                move(original["x"], original["y"])


if __name__ == "__main__":
    raise SystemExit(main())
