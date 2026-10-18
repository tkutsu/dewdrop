#!/usr/bin/env python3
"""Keep real central and notification icons on pixels at animation endpoints."""

import runpy
import subprocess
import tempfile
from pathlib import Path

from test_support import ROOT, copy_shell, shell_env

QML = r'''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 1800; implicitHeight: 100
        Item {
            id: host; anchors.fill: parent
            Pill {
                id: clockPill; side: Pill.Side.Centre; drawsSlab: false
                order: ["time", "bell"]; moduleGap: Theme.gap + 3
                CENTRAL_ANCHOR
                BarItem {
                    id: timeClock; settingsKey: "time"; visibilityKey: "time"
                    Layout.leftMargin: -1; Layout.rightMargin: -1
                    RollingText { Layout.fillHeight: true; tightWidth: true; text: "7:15 PM"; smallRanges: [{start: 5, end: 7}] }
                }
                NotificationBell { id: bell; settingsKey: "bell"; visibilityKey: "bell"; stowed: quiet }
            }
            SidePill {
                id: noticePill; control: notice; slidesContent: true; bounceBeforeCollapse: true
                side: Pill.Side.Left; edgeOffset: clockPill.x + clockPill.width + Theme.pillSpread
                Notice { id: notice; room: 500; foldDuration: 0 }
            }
        }
        TestCase {
            id: test; when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function named(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children) { const found = named(child, name); if (found) return found; }
                return null;
            }
            function onPixel(value) { return Math.abs(value - Math.round(value)) < 0.001; }
            function settled(why) {
                tryVerify(() => !clockPill.animating, 1200);
                const image = named(notice, "alignmentImage");
                check(image !== null, "actual notification image is loaded");
                const pos = image.mapToItem(host, 0, 0);
                check(onPixel(clockPill.x) && onPixel(pos.x) && onPixel(pos.y),
                    why + ": centre=" + clockPill.x + ", icon=" + JSON.stringify(pos));
                check(Math.abs(clockPill.x - clockPill._centreLeft) < 0.001,
                    "centred anchor preserves the animated left edge exactly");
                check(noticePill.iconScale === 1 && noticePill.contentBlur === 0,
                    "notification has no residual scaling or blur");
            }
            function run() {
                DrawerPins.pins = {time: true}; wait(700);
                settled("bell hidden");
                Notifications.waiting = 1; wait(700);
                settled("bell visible with a pinned time anchor");
                const initial = clockPill.x;
                const width = clockPill.width;
                // Recentring on the whole pill needs a fractional raw target.
                DrawerPins.pins = {};
                let moving = false, fractional = false;
                for (let i = 0; i < 35; i++) {
                    wait(16);
                    moving = moving || clockPill.animating;
                    fractional = fractional || (clockPill.animating && !onPixel(clockPill.x));
                    check(Math.abs(clockPill.x-clockPill._centreLeft) < 0.001,
                        "animation follows the left edge without a rounding step");
                }
                check(moving && fractional && clockPill.x !== initial,
                    "existing transition keeps smooth fractional motion between aligned endpoints");
                settled("unpinned central group");
                check(clockPill.width === width, "pixel alignment preserves layout widths");
                const final = clockPill.x; wait(150);
                check(clockPill.x === final, "no delayed correction after settling");
                Notifications.waiting = 0; wait(700); settled("return to one central module");
                host.width -= 1; wait(700); settled("odd viewport width");
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                Notifications.waiting = 1; wait(40); settled("reduced motion");
                console.log("PASS: bell-hidden and bell-visible icons start and end on pixels, with smooth transitions and no delayed correction");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-pixel-alignment-") as folder:
        target = Path(folder)
        copy_shell(target)
        notifications = runpy.run_path(str(ROOT / "scripts/test-pill-icon-motion.py"))["NOTIFICATIONS"]
        notifications = notifications.replace("property int burst: 2", '''property int burst: 0
    property int waiting: 0
    property int count: waiting
    property string tooltip: "Notifications"
    signal centreRequested(bool toggle)''')
        (target / "services/Notifications.qml").write_text(notifications)
        (target / "services/Launcher.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string taskPrefix: ""; function openWith(prefix) {} }\n')
        (target / "components/NotificationsPopup.qml").write_text("import QtQuick\nItem {}\n")
        (target / "settings.json").write_text('{"font":"Inter","bellBadgeStyle":"hide"}')
        (target / "sender.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><path d="M0 0h16v16H0z" fill="white"/></svg>')
        icon = target / "components/FittedIcon.qml"
        icon.write_text(icon.read_text().replace("id: image", 'id: image; objectName: "alignmentImage"'))
        source = (ROOT / "Bar.qml").read_text()
        start = source.index("        readonly property var clockItems:")
        end = source.index("\n\n", source.index("        animatePosition: true", start))
        (target / "shell.qml").write_text(QML.replace("CENTRAL_ANCHOR", source[start:end]))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        if result.returncode or "PASS:" not in output or any(error in output for error in errors):
            print(output, end="")
            return 1
        print("\n".join(line for line in output.splitlines() if "PASS:" in line))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
