#!/usr/bin/env python3
"""Render the calendar's real marks and verify their cutout preserves alpha."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
QML = '''//@ pragma Env QSG_RENDER_LOOP=threaded
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "."
ShellRoot {
    PanelWindow {
        implicitWidth: 80; implicitHeight: 28
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region {}
        color: "transparent"
        Item {
            id: root; anchors.fill: parent
            readonly property real cell: 28
            readonly property int dotSize: 3
            property int phase: 0
            Item {
                id: dayCell; width: 28; height: 28
                property bool isToday: root.phase < 2
                property bool thisMonth: true
                property bool busy: root.phase !== 1
                property date day: new Date(2026, 9, root.phase === 1 ? 8 : 14)
                BLOCK
            }
            REFERENCE
            Timer {
                id: capture; interval: 150; running: true
                onTriggered: dayCell.grabToImage(result => {
                    result.saveToFile(PATH + "/cell-" + root.phase + ".png");
                    reference.grabToImage(mask => {
                        mask.saveToFile(PATH + "/marks-" + root.phase + ".png");
                        if (++root.phase === 3) Qt.quit();
                        else capture.start();
                    });
                })
            }
        }
    }
}'''


def main():
    """Compare GPU-rendered cutouts with the same unmasked glyph and event dot."""
    source = (ROOT / "components/Calendar.qml").read_text()
    start = source.index('                    Item {\n                        anchors.fill: parent\n                        visible: dayCell.isToday')
    end = source.index('\n                }\n            }\n        }', start)
    block = source[start:end]
    reference = block[block.index('                    Item {\n                        id: marks'):]
    reference = reference.replace('id: marks', 'id: reference', 1).replace(
        'anchors.fill: parent', 'width: 28; height: 28; x: 40', 1)
    with tempfile.TemporaryDirectory(prefix="qs-calendar-mask-") as folder:
        target = Path(folder)
        (target / "PopupText.qml").write_text((ROOT / "components/PopupText.qml").read_text().replace('import qs', 'import "."'))
        (target / "Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property string bodyFont: "Inter"
    readonly property int popupTextSize: 12
    readonly property var figures: ({"tnum": 1})
    readonly property color calToday: "white"
    readonly property color fg: "white"
    readonly property color label2: "grey"
    readonly property color label3: "grey"
}''')
        (target / "qmldir").write_text('singleton Theme 1.0 Theme.qml\nPopupText 1.0 PopupText.qml\n')
        (target / "shell.qml").write_text(QML.replace('BLOCK', block).replace(
            'REFERENCE', reference).replace('PATH', json.dumps(folder)))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        # Keep the Wayland connection while isolating Quickshell's writable state.
        display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        if not os.path.isabs(display):
            display = str(Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))) / display)
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="rhi",
                   WAYLAND_DISPLAY=display, XDG_RUNTIME_DIR=str(runtime),
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"),
                   XDG_DATA_HOME=str(target / "data"))
        result = subprocess.run(["qs", "-p", folder, "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        if result.returncode or not (target / "cell-2.png").exists():
            print(result.stdout + result.stderr)
            return 1
        checks = {}
        for phase, name in enumerate(("two-digit numeral and event dot", "single-digit numeral without events")):
            cell = Image.open(target / f"cell-{phase}.png").getchannel("A")
            marks = Image.open(target / f"marks-{phase}.png").getchannel("A")
            # These regions are fully inside the disc, including the raised dot.
            errors = [abs(cell.getpixel((x, y)) - (255 - marks.getpixel((x, y))))
                      for region in ((7, 6, 21, 21), (12, 21, 16, 24))
                      for y in range(region[1], region[3]) for x in range(region[0], region[2])]
            checks[name + " keep smooth alpha"] = max(errors) <= 1
            checks[name + " retain the disc and transparent exterior"] = (
                cell.getpixel((4, 14)) == 255 and cell.getpixel((0, 0)) == 0)
            print(f"Maximum alpha error ({name}): {max(errors)}/255")
        normal = Image.open(target / "cell-2.png")
        marks = Image.open(target / "marks-2.png")
        checks["ordinary days still draw their numeral and event dot directly"] = ImageChops.difference(normal, marks).getbbox() is None
        for name, passed in checks.items():
            print(("PASS: " if passed else "FAIL: ") + name)
        return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
