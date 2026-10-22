#!/usr/bin/env python3
"""Exercise the display scroll readout without changing monitor brightness."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


NIGHT_MODE = '''pragma Singleton
import QtQuick
import Quickshell
import qs
Singleton {
    property bool on: false
    property int brightness: 53
    property int pending: 53
    property var nudges: []
    property string mode: "off"
    property int startMinute: 1320
    property int endMinute: 420
    readonly property string icon: on ? Theme.glyph.nightOn : Theme.glyph.nightOff
    readonly property string tooltip: "Brightness " + brightness + "%"
    function nudge(up) {
        nudges = nudges.concat([up]);
        pending = Math.max(0, Math.min(100, pending + (up ? 5 : -5)));
        apply.restart();
    }
    function toggle() { on = !on; }
    function setBrightness(value) { brightness = value; }
    function setMode(value) { mode = value; }
    function formatTime(minute) { return Math.floor(minute / 60) + ":00"; }
    Timer { id: apply; interval: 50; onTriggered: brightness = pending }
}'''

SHELL = r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules as Modules
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 150
        Modules.NightMode {
            id: display
            x: 100; y: 20; width: implicitWidth; height: implicitHeight
            folds: false
        }
    }
    TestCase { id: test; when: false }
    Connections {
        id: opening
        target: null
        property int changes: 0
        function onOpenedChanged() { changes++; }
    }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log("PASS: " + message);
    }
    function scroll(delta) {
        test.mouseWheel(display, display.width / 2, display.height / 2, 0, delta);
    }
    function level() {
        return display.children.find(child => child.item && child.item.takesKeys === false);
    }
    function slider(item) {
        if (item.name === 'Brightness' && item.value !== undefined) return item;
        for (const child of item.children || []) {
            const found = slider(child);
            if (found) return found;
        }
        return null;
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(!level(), "brightness feedback starts hidden");
                scroll(-60);
                check(NightMode.nudges.length === 0 && !level(), "partial wheel notch waits without adjusting brightness");
                scroll(-60);test.wait(80);
                const hud = level();
                const first = hud?.item;
                const track = first && slider(first.contentItem);
                check(hud?.open && NightMode.nudges[0] === true && track.value === 0.58,
                    "scroll down raises the tracker, which follows delayed brightness updates");
                check(first.anchorItem === display && !first.takesKeys && !first.probes && !display.tooltipEnabled,
                    "brightness feedback anchors under Display and suppresses the plain tooltip");
                const size = Qt.size(track.width, track.height);
                const row = track.parent;
                const position = row.mapToItem(first.chromeItem, 0, 0);
                const top = position.y;
                const bottom = first.chromeHeight - position.y - row.height;
                const left = position.x + row.leftPadding;
                const right = first.chromeItem.width - position.x - row.width + row.rightPadding;
                check(Math.max(top, right, bottom, left) - Math.min(top, right, bottom, left) < 0.01,
                    "brightness row has equal padding on all sides (" + [top, right, bottom, left].join(', ') + ")");
                opening.target = first;
                test.wait(700);scroll(120);test.wait(80);
                check(hud.item === first && opening.changes === 0 && track.value === 0.53 && NightMode.nudges[1] === false,
                    "scroll up lowers brightness without replaying the opening animation");
                test.wait(500);
                check(hud.open, "repeated scrolling extends the display time");
                test.wait(900);
                check(!hud.open && !hud.item && display.tooltipEnabled,
                    "idle feedback fades away and releases its surface");
                scroll(-120);test.wait(80);
                display.togglePopup();test.wait(30);
                check(display.popupOpen && !hud.open, "the full Display popup dismisses mini feedback");
                const fullTrack = slider(display.popupItem.contentItem);
                check(size.width === fullTrack.width && size.height === fullTrack.height,
                    "mini brightness slider matches the full Display popup");
                scroll(120);test.wait(80);
                check(!hud.open && NightMode.brightness === 53,
                    "scrolling with the full popup open adjusts brightness without a second popup");
                OpenPopup.dismiss();test.wait(200);
                Settings.user = Object.assign({}, Settings.user, {reduceMotion:true});
                scroll(-120);test.wait(80);
                check(hud.open && hud.item.growX === 1 && hud.item.growY === 1,
                    "brightness feedback respects Reduce Motion");
                test.mouseClick(display, display.width / 2, display.height / 2, Qt.RightButton);
                check(NightMode.on, "right click still toggles Night Mode");
                console.log("DONE: display feedback");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}'''


def main():
    """Use the real module and popups with an isolated brightness service."""
    with tempfile.TemporaryDirectory(prefix="qs-display-feedback-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/NightMode.qml").write_text(NIGHT_MODE)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(
            ["qs", "-p", str(target), "--no-color"], env=shell_env(target),
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: display feedback" in output \
            and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
