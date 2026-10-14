#!/usr/bin/env python3
"""Drive real settings wheel events and check easing, bounds and interruption."""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.components
ShellRoot {
    SettingsMenu { id: menu }
    FloatingWindow {
        visible: true; implicitWidth: 300; implicitHeight: 200
        Flickable {
            id: controls
            anchors.fill: parent; contentHeight: 1000
            boundsBehavior: Flickable.StopAtBounds
            SmoothScroll { view: controls }
            Slider {
                id: slider; width: 200; height: 30; value: 0.5; wheelStep: 0.1
                onMoved: v => value = v
            }
            Flickable {
                id: nested; y: 60; width: 200; height: 100; contentHeight: 400
                boundsBehavior: Flickable.StopAtBounds
                SmoothScroll { view: nested }
            }
        }
    }
    TestCase {
        id: test; when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function run() {
            menu.contentAlpha = 1;
            const list = menu.auditList;
            tryVerify(() => list.contentHeight > list.height * 2, 1000);
            wait(100);
            list.contentY = list.originY - list.topMargin;
            const start = list.contentY;
            const startedAt = Date.now();
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
            const immediate = list.contentY;
            wait(32);
            const first = list.contentY;
            const firstAt = Date.now();
            wait(32);
            const second = list.contentY;
            const secondAt = Date.now();
            console.log("WHEEL: " + [start, immediate, first, second]);
            check(Math.abs(immediate - start) < 1, "wheel starts without a position jump");
            check(first > start && second > first, "wheel moves across successive frames");
            check((second - first) / (secondAt - firstAt) > (first - start) / (firstAt - startedAt), "wheel accelerates after starting");
            wait(120);
            const middle = list.contentY;
            const middleAt = Date.now();
            wait(48);
            const late = list.contentY;
            const lateAt = Date.now();
            wait(48);
            check((list.contentY - late) / (Date.now() - lateAt) < (late - middle) / (lateAt - middleAt), "wheel decelerates before stopping");
            wait(500);
            check(list.contentY > second, "wheel eases into its resting position");
            const rest = list.contentY;
            check(Math.abs(rest - start - 120) < 1, "one notch reaches its full scroll distance");
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
            wait(32);
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
            wait(500);
            check(Math.abs(list.contentY - rest - 240) < 1, "successive notches accumulate without losing distance");
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
            wait(32);
            menu.page = 1;
            wait(400);
            check(Math.abs(list.contentY - (list.originY - list.topMargin)) < 1, "changing settings page cancels pending wheel motion");
            mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
            wait(80);
            const speeds = [];
            // Sample several render frames together to avoid timer/frame aliasing.
            for (let i = 0; i < 2; i++) {
                const at = list.contentY;
                const time = Date.now();
                wait(64);
                speeds.push((list.contentY - at) / (Date.now() - time));
            }
            console.log("CRUISE: " + JSON.stringify(speeds));
            check(Math.min(...speeds) > Math.max(...speeds) * 0.65, "wheel keeps a steady speed through the middle of a glide");
            wait(500);
            mouseWheel(slider, 100, 15, 0, -120);
            wait(300);
            check(Math.abs(slider.value - 0.6) < 0.001 && controls.contentY === 0, "wheel over a slider adjusts its value without scrolling");
            mouseWheel(nested, 100, 50, 0, -120);
            wait(400);
            check(nested.contentY === 120 && controls.contentY === 0, "nested reader scrolls without moving its parent");
            nested.contentY = 300;
            mouseWheel(nested, 100, 50, 0, -120);
            wait(400);
            check(nested.contentY === 300 && controls.contentY > 0, "reader at its end lets the parent scroll");
            controls.contentY = 200;
            for (let i = 0; i < 4; i++) {
                const at = controls.contentY;
                mouseWheel(controls, 250, 180, 0, -120);
                check(Math.abs(controls.contentY - at) < 1, "continued wheel input does not jump: " + i);
                wait(48);
                check(controls.contentY > at, "continued wheel input keeps moving: " + i);
            }
            wait(500);
            check(Math.abs(controls.contentY - 680) < 1, "sustained scrolling preserves every notch's travel");
            controls.contentY = 200;
            mouseWheel(controls, 250, 180, 0, -360);
            wait(32);
            const reversing = controls.contentY;
            mouseWheel(controls, 250, 180, 0, 120);
            wait(32);
            check(controls.contentY > reversing, "direction changes brake before reversing");
            wait(400);
            check(Math.abs(controls.contentY - reversing + 120) < 1, "reversing direction discards queued travel");
            controls.contentY = 780;
            mouseWheel(controls, 250, 180, 0, -120);
            wait(400);
            check(controls.contentY === 800, "scroll stops at the bottom without overshooting");
            controls.contentY = 20;
            mouseWheel(controls, 250, 180, 0, 120);
            wait(400);
            check(controls.contentY === 0, "scroll stops at the top without overshooting");
            Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
            mouseWheel(controls, 250, 180, 0, -120);
            check(controls.contentY === 120, "reduce motion scrolls immediately");
            wait(300);
            check(controls.contentY === 120, "reduce motion leaves no pending animation");
            console.log("PASS: smooth scrolling");
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-smooth-scroll-") as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / "modules/SettingsMenu.qml").read_text()
        start = source.index("    // --- the pages ")
        end = source.index("    // --- the box ", start)
        fixture = '''    readonly property var pages: [{title: "Launcher"}, {title: "Other"}]
    readonly property var entries: [
        {id: "controls", heading: "Controls", text: "Desktop controls offered by the launcher."},
        ...Array.from({length: 8}, (_, i) => ({id: "control" + i, setting: {type: "toggle", title: "Desktop control " + i, text: "Control the desktop from the launcher.", get: () => true, set: v => {}}})),
        {id: "apps", heading: "Apps", text: "Off leaves an app out of the launcher results."},
        ...Array.from({length: 100}, (_, i) => ({id: "app" + i, setting: {type: "toggle", title: "Application " + i, get: () => true, set: v => {}}}))
    ]

'''
        source = source[:start] + fixture + source[end:]
        source = source.replace("id: root", "id: root\n    property alias auditList: list", 1)
        (target / "modules/SettingsMenu.qml").write_text(source)
        (target / "services/Preferences.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool shown: false; property int dismissMs: 260; function hide() { shown = false; } }')
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property real luma: 0.5 }')
        (target / "components/HoverPopup.qml").write_text('import QtQuick\nItem { property var anchorItem; property real anchorHeight; property bool hovered; property string text; property var item }')
        (target / "components/Glyph.qml").write_text('import QtQuick\nItem { property string text; property real fontSize; property color color }')
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: smooth scrolling" in output and not any(error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")), output


if __name__ == "__main__":
    main()
