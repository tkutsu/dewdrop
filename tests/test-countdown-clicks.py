#!/usr/bin/env python3
"""Click the real countdown module with isolated timer state and no alerts."""

import os
from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-countdown-clicks-") as folder:
        target = fixture_root(folder)
        (target / "src/components").mkdir(parents=True, exist_ok=True)
        (target / "src/services").mkdir(parents=True, exist_ok=True)
        countdown = (ROOT / "src/modules/Countdown.qml").read_text()
        for name in ("slot", "slotTap", "words", "rolling", "name", "hold", "cancelTap", "cancelBox", "mark"):
            countdown = countdown.replace(f"id: {name}\n", f'id: {name}\n            objectName: "{name}"\n')
        (target / "Countdown.qml").write_text(countdown)
        (target / "src/components/Marquee.qml").write_text((ROOT / "src/components/Marquee.qml").read_text())
        (target / "assets/shaders").mkdir(parents=True, exist_ok=True)
        (target / "assets/shaders/query-edge.frag.qsb").write_bytes((ROOT / "assets/shaders/query-edge.frag.qsb").read_bytes())
        (target / "src/components/MediaIconHandoff.qml").write_text((ROOT / "src/components/MediaIconHandoff.qml").read_text())
        (target / "src/core/OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function close(owner) {} function browse(owner, hovered) {} }\n')
        (target / "src/components/ClickArea.qml").write_text((ROOT / "src/components/ClickArea.qml").read_text())
        (target / "src/components/PressGlass.qml").write_text('''import QtQuick
QtObject { required property Item icon; required property var area; property bool down: false; property bool textPress: false; property real scale: 1 }
''')
        (target / "src/components/TimerPopup.qml").write_text('import QtQuick\nItem { property bool morphs: false }\n')
        (target / "src/components/BarItem.qml").write_text('''import QtQuick
import QtQuick.Layouts
ClickArea {
    signal scrollUp
    signal scrollDown
    property bool stowed: false; property bool exitHeld: false; property bool folds: false; property bool dips: false
    property bool textPress: false
    property bool contentAnimating: false; property real reveal: 1
    property Component popup: null; property int popupButton: Qt.NoButton
    property bool popupOpen: false; property int popupOpens: 0; function togglePopup() { popupOpens++; }
    property alias spacing: layout.spacing
    default property alias content: layout.data
    hoverEnabled: true; implicitWidth: layout.implicitWidth + 24; height: 36
    RowLayout { id: layout; x: 12; height: parent.height }
}
''')
        (target / "src/components/BarText.qml").write_text('''import QtQuick
Text { property int maxWidth: 300; font.pixelSize: 16; verticalAlignment: Text.AlignVCenter }
''')
        (target / "src/components/RollingText.qml").write_text('import QtQuick\nText { property bool countsDown: false; property var smallRanges: []; font.pixelSize: 16 }\n')
        (target / "src/components/Glyph.qml").write_text('import QtQuick\nText { property int fontSize: 16; font.pixelSize: fontSize }\n')
        (target / "src/components/BadgedGlyph.qml").write_text('import QtQuick\nText { property alias glyph: icon.text; property int glyphSize: 16; property string badge: ""; property bool dot: false; property bool underdot: false; id: icon; font.pixelSize: glyphSize }\n')
        (target / "src/core/Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function badgeStyle(key) { return "badge"; } }\n')
        (target / "src/components/Bounce.qml").write_text('import QtQuick\nQtObject { property bool running: false; property int periodMs: 1000; property real offset: 0 }\n')
        (target / "src/core/Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property int mediaGap: 8; property int pressDip: 1; property int barInset: 4; property int fadeMs: 1
    property int foldMs: 1; property int mediaTitleWidth: 200; property int glyphSizeLarge: 16
    property real dimOpacity: 0.5; property color fg: "white"; property color label2: "grey"
    property var glyph: ({close: "X", paused: "pause", playing: "play"})
}
''')
        (target / "src/services/Timers.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true; property var entries: []; property var ringing: []; property var focus: null
    property var nextAlarm: null; property real progress: 0.5; property int beatMs: 1000
    property string glyph: "T"; property string label: "00:30"
    property int hushes: 0; property int toggles: 0; property int cancellations: 0
    function hush() { hushes++; ringing = []; }
    function toggle(id) { toggles++; }
    function cancel(id) { cancellations++; }
    function bump(id, amount) {}
}
''')
        (target / "src/services/Launcher.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string taskPrefix: ""; function openWith(prefix) {} }\n')
        (target / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.src.core
import qs.src.services
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
                pill.sync(); mouseMove(pill, pill.width + 100, 60); wait(30);
                check(named(pill, "hold") === null, "pill has no pause or resume button");
                const cancel = named(pill, "cancelTap");
                check(cancel.Accessible.ignored && !cancel.enabled, "folded cancel stays inactive and out of accessibility");
                cancel.Accessible.pressAction();
                check(Timers.cancellations === 0, "hidden cancel cannot activate");
                mouseMove(pill, 15, 15); wait(30);
                tryVerify(() => cancel.enabled && !cancel.Accessible.ignored, 500, "hover reveals cancel");
                const mark = named(pill, "mark");
                const rolling = named(pill, "rolling");
                check(mark.mapToItem(pill, 0, 0).x > rolling.mapToItem(pill, rolling.width, 0).x, "cancel sits to the right of the readout");
                const name = named(pill, "name");
                mouseClick(name, name.width / 2, 15); wait(20);
                check(pill.popupOpens === 1 && Timers.toggles === 0, "timer name opens its popup without pausing");
                mouseClick(rolling, rolling.width / 2, 15); wait(20);
                check(pill.popupOpens === 2 && Timers.toggles === 0, "timer figures open its popup without pausing");
                mouseClick(cancel, cancel.width / 2, 15); wait(20);
                check(Timers.cancellations === 1 && Timers.toggles === 0, "right cancel cancels exactly once");
                const slot = named(pill, "slot");
                mouseClick(slot, 5, 15); wait(20);
                check(pill.dismissed && Timers.cancellations === 1 && Timers.toggles === 0, "timer icon collapses without changing the timer");
                pill.expand();
                mouseClick(rolling, rolling.width / 2, 15, Qt.RightButton); wait(20);
                check(pill.dismissed && Timers.toggles === 0, "right click on readout collapses without pausing");
                pill.expand();
                mouseClick(slot, 5, 15, Qt.RightButton); wait(20);
                check(pill.dismissed && Timers.cancellations === 1, "right click on icon also collapses");
                done();
                check(!pill.dismissed, "new ringing expands the pill");
                mouseClick(slot, 5, 15); wait(20);
                check(pill.dismissed && Timers.hushes === 0 && Timers.ringing.length === 1, "ringing icon collapses without silencing the alarm");
                pill.expand();
                const words = named(pill, "words");
                mouseClick(words, words.width / 2, 15, Qt.RightButton); wait(20);
                check(pill.dismissed && Timers.hushes === 0, "ringing right click collapses without silencing");
                pill.expand();
                mouseClick(words, words.width / 2, 15); wait(20);
                check(Timers.hushes === 1 && Timers.ringing.length === 0, "ringing label still dismisses the ring");
                done(); mouseMove(pill, 15, 15); wait(30);
                tryVerify(() => cancel.enabled, 500);
                cancel.Accessible.pressAction();
                check(Timers.hushes === 2 && Timers.ringing.length === 0 && Timers.cancellations === 1, "right cancel dismisses ringing without cancelling another timer");
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
