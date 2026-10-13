#!/usr/bin/env python3
"""Clear real timer rows and assert Wayland popup placement stays fixed.

Requires a desktop session. Timer state is isolated; mouse clicks are injected
by QtTest into the temporary popup without moving the desktop pointer.
"""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
QML = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
import qs.modules
import qs.services
ShellRoot {
    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        margins.top: 80
        implicitHeight: Theme.barHeight + 2 * Theme.barInset
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "qs-timer-position-test"
        function contents(reveal) { return 1; }
        FUNCTIONS
        Item { id: ordinary; width: 30; height: 30 }
        Morph { id: countdownMorph; open: countdown.popupOpen }
        Pill {
            id: countdownPill
            drawsSlab: false
            side: Pill.Side.Left
            edgeOffset: 300
            visible: countdown.reveal > 0
            BINDINGS
            Countdown { id: countdown }
        }
        TestCase {
            id: test
            when: false
            function clear(popup, label, remaining) {
                const row = popup.keyTargets().find(item => item.name === "Cancel " + label);
                if (!row) throw Error("cancel row missing: " + label);
                mouseClick(row, 40, row.height / 2);
                wait(700);
                if (Timers.timers.length !== remaining)
                    throw Error("row click did not cancel " + label);
                if (!popup.opened || OpenPopup.owner !== countdown)
                    throw Error("clearing timer closed popup");
            }
            function run() {
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: REDUCED});
                Timers.countdown(600000, "Tea");
                Timers.countdown(1200000, "Bread");
                wait(800);
                if (BROWSED) {
                    OpenPopup.set(ordinary);
                    OpenPopup.browse(countdown, true);
                    wait(OpenPopup.browseDelayMs + 80);
                } else {
                    countdown.togglePopup();
                }
                wait(1000);
                const popup = countdown.popupItem;
                if (!popup?.opened) throw Error("popup did not open");
                clear(popup, "Tea", 1);
                clear(popup, "Bread", 0);
                OpenPopup.dismiss();
                wait(900);
                console.log("PASS: timer row clearing complete");
            }
        }
        Timer {
            interval: 300
            running: true
            onTriggered: {
                try { test.run(); } catch (e) { console.log("FAIL: " + e); }
                Qt.quit();
            }
        }
    }
}
'''


def run_case(functions, bindings, mode):
    with tempfile.TemporaryDirectory(prefix="qs-timer-position-") as folder:
        target = Path(folder)
        for item in ROOT.iterdir():
            if item.name not in (".git", "settings.json", "shell.qml"):
                (target / item.name).symlink_to(item)
        (target / "settings.json").write_text("{}\n")
        qml = QML.replace("FUNCTIONS", functions).replace("BINDINGS", bindings)
        qml = qml.replace("REDUCED", str(mode == "reduced").lower())
        qml = qml.replace("BROWSED", str(mode == "browsed").lower())
        (target / "shell.qml").write_text(qml)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        display = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
        if not display.startswith("/"):
            display = str(Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / display)
        env = dict(os.environ, WAYLAND_DEBUG="1", QT_QPA_PLATFORM="wayland",
                   XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=display,
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"),
                   XDG_DATA_HOME=str(target / "data"))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        configs = [tuple(map(int, values)) for values in re.findall(
            r"xdg_popup[^.]*\.configure\((-?\d+), (-?\d+), (\d+), (\d+)\)", output)]
        errors = ("FAIL:", "ERROR", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign")
        ok = result.returncode == 0 and "PASS: timer row clearing complete" in output
        ok = ok and not any(error in output for error in errors)
        # All frames must stay put, including intermediate resize configurations.
        ok = ok and len({config[3] for config in configs}) == 3
        ok = ok and len({config[1] for config in configs}) == 1
        print(("PASS: " if ok else "FAIL: ") + mode + " timer popup configurations: " + str(configs))
        if not ok:
            print("\n".join(line for line in output.splitlines()
                            if "qml:" in line or any(error in line for error in errors)))
        return ok


def main():
    source = (ROOT / "Bar.qml").read_text()
    functions = "\n".join(re.search(
        r"    function " + name + r"\([^\n]+\) \{.*?\n    }", source, re.S).group()
        for name in ("morph", "morphContents"))
    block = source.split("id: countdownPill", 1)[1].split("id: countdown\n", 1)[0]
    bindings = "\n".join(line for line in block.splitlines() if re.match(
        r"\s*(contentOpacity|contentScale|contentSink|interactive):", line))
    results = [run_case(functions, bindings, mode) for mode in ("direct", "browsed", "reduced")]
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
