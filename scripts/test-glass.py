#!/usr/bin/env python3
"""Check real pill input, outline geometry and popup preparation in isolation."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def function(name):
    signatures = {"morph": "box, s", "bulge": "end, dir, reveal, leaving"}
    args = signatures[name]
    return ("    readonly property var drops: Drops.geometry(Theme)\n" if name == "morph" else "") + f"    function {name}({args}) {{ return bar.drops.{name}({args}); }}"



def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-glass-") as folder:
        target = Path(folder)
        for name in subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "--cached", "--others", "--exclude-standard"], text=True).splitlines():
            if (ROOT / name).is_file():
                destination = target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, destination)
        (target / "settings.json").write_text("{}\n")
        (target / "shell.qml").write_text('''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import "Drops.js" as Drops
ShellRoot {
    id: bar
    property int clicks: 0
    property int failures: 0
    property bool isOpen: false
    FUNCTION
    BULGE
    Morph { id: morph; open: bar.isOpen }
    FloatingWindow {
        id: barWindow
        implicitWidth: 600; implicitHeight: 80
        Pill {
            id: pill
            progress: 0.5
            trackReady: !bar.isOpen && morph.value === 0
            contentScale: bar.morph(Qt.vector4d(0, 0, width, Theme.barHeight), morph.value).z / Math.max(width, 1)
            MouseArea {
                id: button
                property int padLeft: 0; property int padRight: 0
                property bool lead: false; property bool trail: false
                implicitWidth: 180; implicitHeight: 30
                onClicked: bar.clicks++
            }
        }
        PressGlass { id: feedback; icon: button; area: button }
        Item { id: anchor; x: 140; y: 4; width: 40; height: 30 }
        TestCase { id: test; when: false }
    }
    Popup {
        id: popup
        visible: false; requestedVisible: false
        morphs: true; probes: false; anchorItem: anchor
        Rectangle { width: 180; height: 100; color: "grey" }
    }
    function check(ok, message) {
        console.log((ok ? "PASS: " : "FAIL: ") + message);
        if (!ok) failures++;
    }
    Timer {
        interval: 150; running: true
        onTriggered: {
            check(bar.bulge(200, 1, 0, true).z === 0, "a hidden neighbor contributes no phantom bulge to the timer cap");
            const gone = bar.morph(Qt.vector4d(200, 4, 180, 30), 2);
            check(gone.z === 0, "completed morph removes the glass box from the smooth union");
            test.mouseClick(button, 90, 15);
            check(bar.clicks === 1, "visible pill accepts clicks");
            pill.contentOpacity = 0;
            test.wait(20);
            test.mouseClick(button, 90, 15);
            check(bar.clicks === 1 && !pill.enabled, "hidden pill rejects clicks");
            check(!popup.landed, "unmapped morph popup has no full-size shadow to flash");
            check(popup.anchor.item === anchor && popup.anchor.item.QsWindow.window === barWindow, "bar popup anchors directly to its original window");
            check(popup.anchor.item.x === anchor.x && popup.anchor.item.y === anchor.y,
                "popup anchor keeps the original bar position");
            anchor.x = 220; anchor.width = 70; test.wait(20);
            check(popup.anchor.item.x === 220 && popup.anchor.item.width === 70,
                "popup anchor follows moving and resizing modules");
            bar.isOpen = true;
            test.wait(60);
            check(pill.trackReveal === 0, "track hides immediately before the glass morphs");
            check(pill.contentScale < 1 && pill.contentScale > 0, "contents squeeze alongside the popup morph");
            test.wait(280);
            check(morph.value === 2, "normal morph reaches the absent state");
            bar.isOpen = false; test.wait(80); bar.isOpen = true; test.wait(280);
            check(morph.value === 2, "interrupted close can reopen completely");
            bar.isOpen = false;
            test.wait(400);
            check(pill.trackReveal === 0, "track stays hidden while closing glass is squeezed");
            while (morph.value !== 0) test.wait(5);
            test.wait(40);
            check(pill.trackReveal > 0 && pill.trackReveal < 0.95, "track visibly fades through intermediate opacity after settling");
            test.wait(260);
            check(morph.value === 0 && pill.trackReveal === 1, "track fades back after the glass settles");
            Settings.user = {reduceMotion: true};
            bar.isOpen = false; test.wait(20);
            check(morph.value === 0, "Reduce motion restores the pill immediately");
            bar.isOpen = true; test.wait(20);
            check(morph.value === 2, "Reduce motion also hides the popup owner's glass");
            popup.requestedVisible = true; popup.visible = true; test.wait(40);
            check(popup.opened && popup.landed && popup.ink === 1, "Reduce motion opens a complete popup without the drop animation");
            popup.requestedVisible = false; popup.visible = false;
            bar.isOpen = false; pill.contentOpacity = 1;
            Settings.user = {}; test.wait(400);
            test.mousePress(button, 90, 15); test.wait(220);
            check(feedback.scale >= 0.92 && feedback.scale < 0.96, "held pill content shrinks slightly");
            Settings.user = {reduceMotion: true};
            check(feedback.scale === 1, "Reduce motion keeps pressed content at normal size");
            Settings.user = {};
            test.mouseRelease(button, 90, 15);
            let enlarged = false;
            for (let ms = 0; ms < 1200; ms += 20) {
                test.wait(20); enlarged = enlarged || feedback.scale > 1;
            }
            check(!enlarged && Math.abs(feedback.scale - 1) < 0.001, "release restores normal size without zooming past it");
            console.log("RESULT: " + failures + " failures");
            Qt.quit();
        }
    }
}
'''.replace("FUNCTION", function("morph")).replace("BULGE", function("bulge")))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"),
                   XDG_DATA_HOME=str(target / "data"), XDG_CACHE_HOME=str(target / "cache"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "RESULT: 0 failures" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
