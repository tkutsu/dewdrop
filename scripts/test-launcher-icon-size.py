#!/usr/bin/env python3
"""Measure actual launcher mode artwork across font glyphs and SVGs."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image

from test_support import ROOT, offscreen_ink, shell_env


NAMES = (
    "launcher", "launcherCalc", "clipboard", "launcherWindow", "folder",
    "tasks", "timer", "alarm", "event", "launcherMusic", "launcherWeb",
    "mailUnread", "launcherPower",
)

QML = '''import QtQuick
import Quickshell
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        implicitWidth: COUNT * 48; implicitHeight: 48
        color: "transparent"
        Item {
            id: scene
            width: COUNT * 48; height: 48
            Repeater {
                model: NAMES
                RollingGlyph {
                    required property string modelData
                    required property int index
                    x: index * 48 + 14; y: 6
                    width: 20; height: 36
                    text: Theme.glyph[modelData]
                    fontSize: 20
                    inkSize: INK_SIZE
                    color: "white"
                    animate: false
                }
            }
        }
        Timer {
            interval: 1800; running: true
            onTriggered: scene.grabToImage(result => {
                result.saveToFile(Quickshell.shellPath("mode-icons.png"));
                Qt.quit();
            })
        }
    }
}
'''


def main():
    theme = (ROOT / "Theme.qml").read_text()
    entries = []
    for name in NAMES:
        match = re.search(rf"^\s*{name}: (.*?),\s*(?://.*)?$", theme, re.MULTILINE)
        assert match, name
        entries.append(f"{name}: {match[1]}")
    assert 'launcherPower: "\\uf1e6"' in entries, "option 2 is the Font Awesome plug"
    menu = (ROOT / "modules/LauncherMenu.qml").read_text()
    ink_size = int(re.search(r"id: searchIcon\b.*?inkSize: (\d+)", menu, re.DOTALL)[1])

    with tempfile.TemporaryDirectory(prefix="qs-launcher-icons-") as folder:
        target = Path(folder)
        components = target / "components"
        components.mkdir()
        for name in ("Glyph.qml", "BarText.qml", "FittedIcon.qml", "RollingGlyph.qml", "RollingSpring.js"):
            shutil.copy2(ROOT / "components" / name, components / name)
        # Bar scaling is outside the launcher; keep the real drawing and ink meter.
        (components / "ModuleIconScale.qml").write_text("import QtQuick\nScale { property Item icon }\n")
        shutil.copytree(ROOT / "icons", target / "icons")
        services = target / "services"
        services.mkdir()
        shutil.copy2(ROOT / "services/Ink.qml", services / "Ink.qml")
        offscreen_ink(target)
        (target / "Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function cache(name) { return Quickshell.shellPath(name); } }\n')
        (target / "Theme.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
QtObject {
    property string glyphFont: "Symbols Nerd Font"
    property string bodyFont: "Inter"
    property int bodyWeight: Font.Normal
    property int textSize: 12
    property int glyphSize: 16
    property int iconSize: 20
    property real glyphInk: 0.65
    property int barHeight: 30
    property int fadeMs: 0
    property int rollMs: 100
    property bool reduceMotion: false
    property color fg: "white"
    property var figures: ({})
    function barInk(item, color, glyph) { return color; }
    function panel(name) { return "file://" + Quickshell.shellPath("icons/" + name + ".svg"); }
    property var glyph: ({ENTRIES})
}
'''.replace("ENTRIES", ",\n".join(entries)))
        qml = QML.replace("COUNT", str(len(NAMES))).replace("NAMES", json.dumps(NAMES))
        (target / "shell.qml").write_text(qml.replace("INK_SIZE", str(ink_size)))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert not any(error in output for error in ("Error:", "Binding loop", "Unable to assign", "Failed to load")), output
        path = target / "mode-icons.png"
        image = Image.open(path).convert("RGBA")
        for index, name in enumerate(NAMES):
            alpha = image.crop((index * 48, 0, (index + 1) * 48, 48)).getchannel("A")
            bounds = alpha.point(lambda value: 255 if value > 24 else 0).getbbox()
            assert bounds, f"{name}: missing artwork"
            left, top, right, bottom = bounds
            extent = max(right - left, bottom - top)
            assert abs(extent - ink_size) <= 1, f"{name}: {right-left}x{bottom-top}, target {ink_size}"
            assert abs((left + right) / 2 - 24) <= 1, f"{name}: horizontal centre {bounds}"
            assert abs((top + bottom) / 2 - 24) <= 1, f"{name}: vertical centre {bounds}"
            print(f"PASS: {name}: {right-left}x{bottom-top}, centred in its slot")
        if destination := os.environ.get("LAUNCHER_ICON_PREVIEW"):
            shutil.copy2(path, destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
