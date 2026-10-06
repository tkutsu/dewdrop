#!/usr/bin/env python3
"""Click the real countdown module with isolated timer state and no alerts."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-countdown-clicks-") as folder:
        target = Path(folder)
        (target / "components").mkdir()
        (target / "services").mkdir()
        countdown = (ROOT / "modules/Countdown.qml").read_text()
        for name in ("slot", "words", "rolling", "name", "hold"):
            countdown = countdown.replace(f"id: {name}\n", f'id: {name}\n            objectName: "{name}"\n')
        (target / "Countdown.qml").write_text(countdown)
        (target / "components/ClickArea.qml").write_text((ROOT / "components/ClickArea.qml").read_text())
        (target / "components/BarItem.qml").write_text('''import QtQuick
import QtQuick.Layouts
ClickArea {
    signal scrollUp
    signal scrollDown
    property bool stowed: false; property bool folds: false; property bool dips: false
    property bool contentAnimating: false; property real reveal: 1
    property alias spacing: layout.spacing
    default property alias content: layout.data
    hoverEnabled: true; implicitWidth: layout.implicitWidth + 24; height: 36
    RowLayout { id: layout; x: 12; height: parent.height }
}
''')
        (target / "components/BarText.qml").write_text('''import QtQuick
Text { property int maxWidth: 300; font.pixelSize: 16; verticalAlignment: Text.AlignVCenter }
''')
        (target / "components/RollingText.qml").write_text('import QtQuick\nText { property bool countsDown: false; font.pixelSize: 16 }\n')
        (target / "components/Glyph.qml").write_text('import QtQuick\nText { property int fontSize: 16; font.pixelSize: fontSize }\n')
        (target / "components/Bounce.qml").write_text('import QtQuick\nQtObject { property bool running: false; property int periodMs: 1000; property real offset: 0 }\n')
        (target / "Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property int mediaGap: 8; property int pressDip: 1; property int fadeMs: 1
    property int foldMs: 1; property int mediaTitleWidth: 200; property int glyphSizeLarge: 16
    property real dimOpacity: 0.5; property color fg: "white"; property color label2: "grey"
    property var glyph: ({close: "X", paused: "pause", playing: "play"})
}
''')
        (target / "services/Timers.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true; property var ringing: []; property var focus: null
    property var nextAlarm: null; property real progress: 0.5; property int beatMs: 1000
    property string glyph: "T"; property string label: "00:30"
    property int hushes: 0; property int toggles: 0; property int cancellations: 0
    function hush() { hushes++; ringing = []; }
    function toggle(id) { toggles++; }
    function cancel(id) { cancellations++; }
    function bump(id, amount) {}
}
''')
        (target / "services/Launcher.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string taskPrefix: ""; function openWith(prefix) {} }\n')
        (target / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
    Window {
        visible: true; width: 600; height: 80
        Countdown { id: pill; width: implicitWidth }
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function named(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found) return found;
                }
                return null;
            }
            function done() {
                Timers.ringing = [{id: "done", label: "Tea"}];
                Timers.label = "Tea"; pill.sync(); wait(30);
            }
            function run() {
                Timers.focus = {id: "running", label: "Tea", total: 30000, running: true};
                pill.sync(); mouseMove(pill, 15, 15); wait(30);
                let name = named(pill, "name");
                mouseClick(name, name.width / 2, 15); wait(20);
                check(Timers.toggles === 1, "running timer name pauses exactly once");
                const rolling = named(pill, "rolling");
                mouseClick(rolling, rolling.width / 2, 15); wait(20);
                check(Timers.toggles === 1 && Timers.hushes === 0, "countdown figures do not pause or clear");
                mouseClick(pill, 3, 15); wait(20);
                check(Timers.toggles === 1, "running timer padding does not pause");
                const hold = named(pill, "hold");
                mouseClick(hold, hold.width / 2, 15); wait(20);
                check(Timers.toggles === 2, "running timer pause button works once");
                done();
                check(!hold.visible || hold.parent.width === 0, "finished timer has no play button, even with another timer running");
                const words = named(pill, "words");
                mouseClick(words, words.width / 2, 15); wait(20);
                check(Timers.hushes === 1 && Timers.ringing.length === 0, "finished timer text clears exactly once");
                check(Timers.toggles === 2 && Timers.cancellations === 0, "clear leaves the other running timer alone");
                done(); mouseClick(pill, 3, 15); wait(20);
                check(Timers.hushes === 2, "finished timer left padding clears");
                done(); mouseClick(pill, pill.width - 3, 15); wait(20);
                check(Timers.hushes === 3, "finished timer right padding clears");
                done(); const slot = named(pill, "slot");
                mouseClick(slot, slot.width / 2, 15); wait(20);
                check(Timers.hushes === 4, "finished timer icon clears exactly once");
                console.log("PASS: countdown clicks and finished timer dismissal");
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
''')
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "PASS: countdown clicks" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
