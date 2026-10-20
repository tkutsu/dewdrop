#!/usr/bin/env python3
"""Exercise notification layout through the shared popup entry/exit lifecycle."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SERVICE = '''pragma Singleton
import QtQuick
QtObject {
    property var list: []
    readonly property int count: list.length
    property var centreFocus: null
    function url(s) { return s || ""; }
    function iconFor(n) { return ""; }
    function ago(n, now) { return "now"; }
    function styled(s) { return s || ""; }
    function plain(s) { return s || ""; }
    function buttons(n) { return []; }
}
'''

QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 100
        BarItem { id: owner; width: 100; height: 30; popup: NotificationsPopup { probes: false } }
        BarItem { id: ordinary; x: 200; width: 100; height: 30
            popup: Popup { probes: false; Rectangle { implicitWidth: 200; implicitHeight: 150 } }
        }
        BarItem { id: morph; x: 400; width: 100; height: 30
            popup: Popup { probes: false; morphs: true; Rectangle { implicitWidth: 200; implicitHeight: 150 } }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            function notice(summary) {
                return {appName: "Test", summary: summary, body: "Details ".repeat(50), actions: [], image: ""};
            }
            function sampleEntry(popup, label) {
                const height = popup.chromeHeight;
                let smallest = popup.growY;
                let largest = popup.growY;
                let heightDrift = 0;
                for (let frame = 0; frame < 30; frame++) {
                    wait(20);
                    heightDrift = Math.max(heightDrift, Math.abs(popup.chromeHeight - height));
                    smallest = Math.min(smallest, popup.growY);
                    largest = Math.max(largest, popup.growY);
                }
                check(heightDrift < 1, label + " keeps its content height throughout the bounce (drift " + heightDrift + ")");
                if (!Theme.reduceMotion)
                    check(smallest < 0.95 && largest > 1.003 && Math.abs(popup.growY - 1) < 0.002,
                          label + " grows from below full scale, bounces past it, and settles");
            }
            function stableEntry(label) {
                owner.togglePopup();
                wait(20);
                const popup = owner.popupItem;
                const initial = popup.chromeHeight;
                check(!popup.animateContents, label + " defers content motion during entry");
                sampleEntry(popup, label);
                check(Math.abs(initial - popup.chromeHeight) < 1,
                      label + " opens at its final content height (" + initial + " -> " + popup.chromeHeight + ")");
                check(popup.opened && popup.revealProgress === 1, label + " completes the shared fade");
                check(popup.animateContents === !Theme.reduceMotion, label + " uses the shared content motion policy");
                return popup;
            }
            function close() {
                const popup = owner.popupItem;
                OpenPopup.dismiss();
                check(!popup.animateContents, "closing disables content motion immediately");
                wait(400);
                check(owner.popupItem === null, "the shared exit releases the popup");
            }
            function run() {
                const first = notice("Notification summary ".repeat(15));
                const second = notice("Second notification");
                Notifications.list = [first, second];
                let popup = stableEntry("Collapsed notifications");
                const collapsed = popup.chromeHeight;
                popup.expandedGroup = first.appName;
                wait(20);
                const immediateExpanded = popup.chromeHeight;
                wait(300);
                const expanded = popup.chromeHeight;
                check(expanded > collapsed && Math.abs(immediateExpanded - expanded) < 1,
                      "group expansion sets its height immediately");
                popup.expandedGroup = "";
                wait(20);
                check(Math.abs(popup.chromeHeight - collapsed) < 1, "group collapse sets its height immediately");
                wait(300);
                check(Math.abs(popup.chromeHeight - collapsed) < 1, "group collapse returns to its original height");
                Notifications.list = [first, second, {appName: "New sender", summary: "New notification ".repeat(20),
                    body: "New details ".repeat(40), actions: [], image: ""}];
                wait(20);
                const arrivalHeight = popup.chromeHeight;
                wait(300);
                check(arrivalHeight > collapsed && Math.abs(arrivalHeight - popup.chromeHeight) < 1,
                      "new cards set their height immediately in an open popup");
                Notifications.list = [first, second];
                close();

                Notifications.centreFocus = second;
                popup = stableEntry("Focused expanded notifications");
                check(popup.expandedGroup === first.appName && popup.chromeHeight > collapsed,
                      "a focused group opens fully laid out");
                close();
                Notifications.centreFocus = null;

                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                popup = stableEntry("Reduced motion notifications");
                check(popup.growX === 1 && popup.growY === 1, "reduced motion keeps the shared chrome at full scale");
                popup.expandedGroup = first.appName;
                wait(20);
                const reducedHeight = popup.chromeHeight;
                wait(300);
                check(reducedHeight > collapsed && Math.abs(reducedHeight - popup.chromeHeight) < 1,
                      "reduced motion expands content without a height animation");
                close();

                Settings.user = Object.assign({}, Settings.user, {reduceMotion: false});
                ordinary.togglePopup(); wait(20);
                sampleEntry(ordinary.popupItem, "Ordinary popup");
                check(ordinary.popupItem.animateContents, "ordinary popups share the settled content policy");
                OpenPopup.browse(owner, true);
                wait(OpenPopup.browseDelayMs + 400);
                popup = owner.popupItem;
                check(popup?.opened && popup.growX === 1 && popup.growY === 1,
                      "browsing into notifications uses the shared fade without scaling");
                check(popup.animateContents, "browsed notifications enable content motion after entry");
                close();

                morph.togglePopup(); wait(300);
                check(morph.popupItem.morphRun && !morph.popupItem.animateContents,
                      "pill morphs defer content motion until landing");
                wait(600);
                check(morph.popupItem.landed && morph.popupItem.animateContents,
                      "landed pill morphs enable the shared content policy");
                OpenPopup.dismiss();
                check(!morph.popupItem.animateContents, "closing a pill morph disables content motion");
                wait(600);
                console.log("PASS: popup motion complete");
            }
        }
        Timer { interval: 150; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-motion-") as folder:
        target = Path(folder)
        copy_shell(target)
        # Substitute retained notifications for D-Bus objects; keep real popup motion and layout.
        popup = target / "components/NotificationsPopup.qml"
        popup.write_text(popup.read_text().replace("readonly property Notification n:", "readonly property var n:"))
        (target / "services/Notifications.qml").write_text(SERVICE)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "ERROR" in line))
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign")
        ok = result.returncode == 0 and "PASS: popup motion complete" in output and not any(e in output for e in errors)
        if not ok:
            print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
