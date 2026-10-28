#!/usr/bin/env python3
"""Check dropdown input coverage and selection outside the Display popup box."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SERVICE = '''pragma Singleton
import QtQuick
QtObject {
    property string mode: "off"
    property int brightness: 50
    property var solar: null
    property string solarInfo: "Unavailable"
    property int startMinute: 1320
    property int endMinute: 420
    function setMode(value) { mode = value; }
    function setBrightness(value) { brightness = value; }
    function formatTime(value) { return "22:00"; }
    function queueSchedule(start, end) {}
}
'''

QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 600; implicitHeight: 40
        Item { id: owner; width: 100; height: 30 }
        DisplayPopup {
            id: popup
            visible: true; anchorItem: owner; probes: false; grows: false
            reserveHeight: RESERVED
        }
        TestCase {
            id: test; when: false
            parent: popup.contentItem
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            function find(item) {
                if (item.setting?.title === "Night mode") return item;
                for (const child of item.children ?? []) {
                    const result = find(child);
                    if (result) return result;
                }
                return null;
            }
            function contains(region, point) {
                const item = region.item;
                if (item) {
                    const p = item.mapFromItem(popup.contentItem, point.x, point.y);
                    if (p.x >= 0 && p.x < item.width && p.y >= 0 && p.y < item.height)
                        return true;
                }
                return Array.from(region.regions).some(child => contains(child, point));
            }
            function run() {
                wait(400);
                const picker = find(popup.contentItem);
                check(picker !== null, "Display uses the shared dropdown");
                const chromeHeight = popup.chromeItem.height;
                for (const index of [1, 2, 3, 0]) {
                    mouseClick(picker, picker.width / 2, picker.height / 2);
                    tryVerify(() => picker.popup.visible);
                    wait(100);
                    const option = picker.popup.contentItem.itemAtIndex(index);
                    check(option !== null, "option is rendered: " + picker.model[index].label);
                    const centre = option.mapToItem(popup.contentItem, option.width / 2, option.height / 2);
                    if (index === 1) {
                        check(centre.y > popup.chromeItem.height + popup.shadowTop,
                              "the menu extends below the visible popup box");
                        check(popup.chromeItem.height === chromeHeight, "opening the menu preserves the popup box size");
                    }
                    for (const x of [1, option.width / 2, option.width - 1]) {
                        const p = option.mapToItem(popup.contentItem, x, option.height / 2);
                        check(p.x >= 0 && p.x < popup.width && p.y >= 0 && p.y < popup.height
                              && contains(popup.mask, p), "option is inside the surface and input region");
                    }
                    mouseMove(option, option.width / 2, option.height / 2);
                    wait(30);
                    check(popup.hovered, "the menu pointer keeps the parent popup active");
                    mouseClick(option, option.width / 2, option.height / 2);
                    check(NightMode.mode === picker.model[index].value && !picker.popup.visible,
                          "click selects " + picker.model[index].label + " and closes the menu");
                    wait(500);
                }
                mouseClick(picker, picker.width / 2, picker.height / 2);
                tryVerify(() => picker.popup.visible);
                popup._backingWindow.requestActivate();
                picker.forceActiveFocus();
                wait(50);
                keyClick(Qt.Key_End);
                keyClick(Qt.Key_Return);
                check(NightMode.mode === "custom" && !picker.popup.visible, "keyboard selection still works");
                wait(500);
                mouseClick(picker, picker.width / 2, picker.height / 2);
                tryVerify(() => picker.popup.visible);
                mouseMove(popup.contentItem, popup.width - 1, popup.height - 1);
                wait(30);
                check(!popup.hovered, "leaving the menu allows outside-click dismissal");
                keyClick(Qt.Key_Escape);
                check(!picker.popup.visible && NightMode.mode === "custom", "Escape cancels without changing the setting");
                wait(100);
                const outside = Qt.point(popup.width - 1, popup.height - 1);
                check(!contains(popup.mask, outside), "closing restores click-through outside the popup box");
                console.log("PASS: dropdown bounds complete");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    """Exercise compact and previously enlarged popup surfaces with real controls."""
    for reserved in (300, 0):
        with tempfile.TemporaryDirectory(prefix="qs-dropdown-bounds-") as folder:
            target = Path(folder)
            copy_shell(target)
            (target / "services/NightMode.qml").write_text(SERVICE)
            (target / "shell.qml").write_text(QML.replace("RESERVED", str(reserved)))
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                    capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            print(f"Reserved height: {reserved}")
            messages = "\n".join(line for line in output.splitlines() if "qml:" in line)
            print(messages)
            errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Cannot assign")
            assert result.returncode == 0 and "PASS: dropdown bounds complete" in output and not any(
                error in output for error in errors), messages


if __name__ == "__main__":
    main()
