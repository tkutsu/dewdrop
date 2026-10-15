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
WIDE = ["TasksPopup", "EmailPopup"]
OWN = ["NotificationsPopup", "WeatherPopup", "WallpaperPopup", "MusicPopup", "SysPopup", "Calendar"]
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


def main():
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
