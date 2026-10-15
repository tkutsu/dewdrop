#!/usr/bin/env python3
"""Build every bar popup and hold it to popup-standards.md: no warnings from its
own code, and the list and control popups at one width."""

import os
from pathlib import Path
import re
import subprocess
import tempfile

from test_support import copy_shell, shell_env

# The menu extras: one width, so browsing from one to the next only changes
# what is in the box. Updates is at least that wide.
STANDARD = ["LanguagePopup", "NetworkPopup", "BluetoothPopup", "AudioPopup", "DisplayPopup",
            "DrivesPopup", "PrivacyPopup", "TimerPopup"]
AT_LEAST = ["UpdatesPopup"]
WIDE = ["NotificationsPopup", "TasksPopup", "EmailPopup"]
OWN = ["WeatherPopup", "WallpaperPopup", "MusicPopup", "SysPopup", "Calendar"]
ALL = STANDARD + AT_LEAST + WIDE + OWN

# The window chrome is Popup.qml's business; here the body is all there is.
POPUP = '''import QtQuick
import qs
Item {
    id: root
    property var screen: ({width: 1920, height: 1080})
    property Item anchorItem: null
    property real padding: Theme.popupPadding
    property real hPadding: padding
    property real vPadding: padding
    property real bottomPadding: Theme.popupBottomPadding
    property int radius: Theme.popupRadius
    property real reserveHeight: 0
    property bool requestedVisible: true
    property bool acceptsKeyboard: false
    property bool probes: true
    property bool grows: true
    property bool fadesIn: true
    property bool morphs: false
    property bool morphRun: false
    property bool landed: true
    property bool takesKeys: true
    property bool keyFromStart: false
    property Item keyInput: null
    property Item keyItem: null
    property var closeKey: () => {}
    property var backKey: null
    property int shadowBlur: 0
    property int shadowY: 0
    readonly property int shadowSide: 0
    readonly property int shadowTop: 0
    readonly property bool opened: true
    readonly property bool hovered: false
    readonly property int exitMs: 0
    readonly property point windowOnScreen: Qt.point(0, 0)
    property real devicePixelRatio: 1
    readonly property real chromeHeight: body.implicitHeight
    readonly property Item chromeItem: chrome
    readonly property real bodyWidth: body.implicitWidth
    property alias spacing: body.spacing
    default property alias content: body.data
    function setKey(item) {}
    function showKey(item) {}
    function keyTargets() { return []; }
    width: body.implicitWidth; height: body.implicitHeight
    Rectangle {
        id: chrome
        radius: root.radius
        color: "transparent"
        width: body.implicitWidth; height: body.implicitHeight
        Column { id: body; spacing: Theme.popupSpacing }
    }
}
'''

SHELL = '''import QtQuick
import Quickshell
import qs
ShellRoot {
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 800
        Repeater {
            model: %s
            delegate: Loader {
                required property string modelData
                source: Qt.resolvedUrl("components/" + modelData + ".qml")
            }
        }
        Timer {
            interval: 1500; running: true
            onTriggered: {
                const loaders = parent.children.filter(c => c.source !== undefined);
                for (const l of loaders)
                    console.log("WIDTH " + l.source.toString().split("/").pop().replace(".qml", "") + " " + (l.item ? l.item.bodyWidth : -1));
                console.log("POPUP WIDTH " + Theme.popupWidth + " " + Theme.popupWideWidth);
                Qt.quit();
            }
        }
    }
}'''


MENU_SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 400
        component Entry: QtObject {
            property string text: ""
            property bool isSeparator: false
            property int buttonType: QsMenuButtonType.None
            property int checkState: Qt.Unchecked
            property bool enabled: true
            property bool hasChildren: false
            property string icon: ""
            signal triggered
        }
        MenuPopup {
            id: ticks
            fake: [
                Entry { text: "Plain" },
                Entry { text: "Checked"; buttonType: QsMenuButtonType.CheckBox; checkState: Qt.Checked },
                Entry { isSeparator: true },
                Entry { text: "Unchecked radio"; buttonType: QsMenuButtonType.RadioButton }
            ]
        }
        MenuPopup {
            id: plain
            y: 200
            fake: [Entry { text: "Open" }, Entry { text: "Quit" }]
        }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function find(item, test) {
                if (test(item)) return item;
                for (const child of item.children) { const f = find(child, test); if (f) return f; }
                return null;
            }
            function label(menu, text) { return find(menu, i => i.text === text && i.font !== undefined); }
            function run() {
                const rows = ["Plain", "Checked", "Unchecked radio"].map(t => label(ticks, t));
                check(rows.every(r => r), "every row has its label");
                check(rows.every(r => r.mapToItem(ticks, 0, 0).x === rows[0].mapToItem(ticks, 0, 0).x), "a menu with a check item starts every label in one column");
                check(rows[0].x === Theme.popupInset + 26, "the labels start past the tick column, as a list's names do");
                const tick = find(ticks, i => i.text === Theme.glyph.check && i.visible);
                check(tick && Math.abs(tick.mapToItem(ticks, 0, 0).y - rows[1].mapToItem(ticks, 0, 0).y) < 8, "the checked row is ticked");
                check(!find(ticks, i => typeof i.text === "string" && (i.text.includes("●") || i.text.includes("○"))), "no row spells its state in its text");
                const line = find(ticks, i => i.color !== undefined && i.height === Theme.pillBorder && i.visible && i.width > 50);
                const row = rows[0].parent;
                check(line && line.width === row.width, "the separator is as wide as the rows' highlight");
                const open = label(plain, "Open");
                check(open && open.x === Theme.popupInset, "a menu without check items keeps its labels at the inset");
            }
        }
        Timer { interval: 300; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''


def menus():
    """The tray menu with its DBus rows stood in for by plain objects."""
    with tempfile.TemporaryDirectory(prefix="quickshell-popup-menus-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "components/Popup.qml").write_text(POPUP)
        menu = (target / "components/MenuPopup.qml").read_text()
        opener = "    QsMenuOpener {\n        id: opener\n        menu: root.handle\n    }"
        assert opener in menu and "required property QsMenuEntry modelData" in menu
        menu = menu.replace(opener, "    property list<QtObject> fake\n    QtObject {\n        id: opener\n        property var children: ({values: root.fake})\n    }")
        menu = menu.replace("required property QsMenuEntry modelData", "required property var modelData")
        (target / "components/MenuPopup.qml").write_text(menu)
        (target / "shell.qml").write_text(MENU_SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        own = [line for line in output.splitlines() if re.search(r"components/\w+\.qml[\[:]\d+", line) and ("WARN" in line or "ERROR" in line)]
        if os.environ.get("VERBOSE") or "FAIL:" in output or own or output.count("PASS:") != 7:
            print(output)
        assert "FAIL:" not in output and output.count("PASS:") == 7 and not own, "\n".join(own) or output
        print("PASS: tray menus tick in the list's column")


def main():
    menus()
    with tempfile.TemporaryDirectory(prefix="quickshell-popup-standards-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "components/Popup.qml").write_text(POPUP)
        (target / "shell.qml").write_text(SHELL % repr(ALL).replace("'", '"'))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        widths = {m[0]: float(m[1]) for m in re.findall(r"WIDTH (\w+) (-?[\d.]+)", output)}
        standard, wide = (int(x) for x in re.search(r"POPUP WIDTH (\d+) (\d+)", output).groups())
        failures = []
        for name in ALL:
            if widths.get(name, -1) <= 0:
                failures.append(f"{name} did not build")
        for name in STANDARD:
            if widths.get(name) != standard:
                failures.append(f"{name} is {widths.get(name)} wide, not {standard}")
        for name in AT_LEAST:
            if widths.get(name, 0) < standard:
                failures.append(f"{name} is narrower than {standard}")
        for name in WIDE:
            if widths.get(name) != wide:
                failures.append(f"{name} is {widths.get(name)} wide, not {wide}")
        # The popups' own warnings, not the fixture's: services find no
        # D-Bus, network or MPD in here and say so.
        own = [line for line in output.splitlines()
               if re.search(r"components/\w+\.qml[\[:]\d+", line) and ("WARN" in line or "ERROR" in line)]
        failures += own
        print(output if failures or os.environ.get("VERBOSE") else "\n".join(f"{n}: {widths.get(n)}" for n in ALL))
        assert not failures, "\n".join(failures)
        print("PASS: popups build without warnings, at the standard widths")


if __name__ == "__main__":
    main()
