#!/usr/bin/env python3
"""Check that caffeine comes back as it was left after the bar restarts."""

import datetime
import json
import os
from pathlib import Path
import time
from test_support import fixture_root
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

# Reads the switch the moment the shell starts, as a bar does, so a value that
# only arrives a moment later fails here.
QML = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    id: test
    property bool first
    Component.onCompleted: test.first = Caffeine.active
    Timer {
        interval: 200; running: true
        onTriggered: {
            console.log("ENDS " + JSON.stringify(Caffeine.endsAt));
            console.log(test.first === %(expected)s ? "PASS" : "FAIL: came up " + test.first);
            Caffeine.turn(%(then)s);
            quit.running = true;
        }
    }
    Timer { id: quit; interval: 200; onTriggered: Qt.quit() }
}
'''

# What the file holds before the run, what the switch should come up as, and
# what the run leaves it at for the next one. None keeps the previous file.
RUNS = (
    ("no file yet", "absent", "false", "true"),
    ("left on", None, "true", "false"),
    ("left off", None, "false", "true"),
    ("left on again", None, "true", "true"),
    ("unreadable file", "not json", "false", "false"),
    ("timed, still running", '{"active": true, "minutes": 60, "until": 4102444800}', "true", "false"),
    ("timed, ran out while away", '{"active": true, "minutes": 60, "until": 1}', "false", "false"),
)

# A turn's end, read back as the words after "until": the time alone today,
# and the day too once it is tomorrow, so a day's hold never reads as now.
NOW = int(time.time())
ENDS = (
    ("ends later today", NOW + 120, lambda ends: "at" not in ends and ends != ""),
    ("ends tomorrow", NOW + 86400, lambda ends: ends.startswith("tomorrow at ")),
)
if datetime.date.fromtimestamp(NOW + 120) != datetime.date.fromtimestamp(NOW):
    ENDS = ENDS[1:]


def main():
    failed = False
    with tempfile.TemporaryDirectory(prefix="qs-caffeine-") as folder:
        target = fixture_root(folder)
        for name in ("src/core/Settings.qml", "src/core/Paths.qml", "settings.default.json", "src/services/Caffeine.qml"):
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        (target / "settings.json").write_text("{}\n")
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        state = target / "state/quickshell"
        state.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        for name, content, expected, then in RUNS:
            if content not in (None, "absent"):
                (state / "caffeine.json").write_text(content)
            (target / "shell.qml").write_text(QML % {"expected": expected, "then": then})
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=10)
            log = result.stdout + result.stderr
            if "PASS" in log:
                print(f"PASS: {name}")
            else:
                failed = True
                print(f"FAIL: {name}\n{log}")
        for name, until, ok in ENDS:
            (state / "caffeine.json").write_text(json.dumps({"active": True, "minutes": 1440, "until": until}))
            (target / "shell.qml").write_text(QML % {"expected": "true", "then": "false"})
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=10)
            log = result.stdout + result.stderr
            ends = next((json.loads(line.split("ENDS ", 1)[1]) for line in log.splitlines() if "ENDS " in line), None)
            if ends is not None and ok(ends):
                print(f"PASS: {name}: until {ends}")
            else:
                failed = True
                print(f"FAIL: {name}: until {ends!r}\n{log}")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
