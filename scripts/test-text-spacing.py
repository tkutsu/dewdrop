#!/usr/bin/env python3
"""Measure rendered gaps between collapsed player icons, date, weather and time."""

import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

from test_support import ROOT, copy_shell, shell_env


QML = '''import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
ShellRoot {
    id: test
    property int phase: 0
    QtObject {
        id: nowPlaying
        property bool paused: true
        property bool expanded: false
        property real reveal: 0
        property string appName: "Fixture player"
        property string shownApp: ""
        function expand() {}
    }
    QtObject {
        id: music
        property bool paused: true
        property bool expanded: false
        property real reveal: 0
        function expand() {}
    }
    property var cases: [
        {date: "Fri 16 Oct", time: "11:11", small: []},
        {date: "MON 1 JUN", time: "20:58", small: []},
        {date: "Τρίτη 13 Οκτωβρίου", time: "8:05pm", small: [{start: 4, end: 6}]},
        {date: "Wed 30 Sep", time: "PM 8:05", small: [{start: 0, end: 2}]},
        {date: "Fri 16 Oct", time: "1", small: []},
        {date: "Fri 16 Oct", time: "9:59:59", small: []},
        {date: "Fri 16 Oct", time: "10:00:00", small: []}
    ]
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 70
        Item {
            id: scene
            width: 800; height: 70
            Pill {
                moduleGap: Theme.gap + 3
                drawsSlab: false
                PLAYER_NOTES
                BarItem { id: date; DATE_MARGINS; BarText { text: test.cases[test.phase].date; tightWidth: true; inkColor: "white" } }
                BarItem { id: weather; present: test.phase !== 4; Glyph { text: Theme.glyph.weather; inkColor: "white" } }
                BarItem {
                    id: time
                    TIME_MARGINS
                    RollingText {
                        Layout.fillHeight: true
                        tightWidth: true
                        color: "white"
                        text: test.cases[test.phase].time
                        smallRanges: test.cases[test.phase].small
                    }
                }
            }
        }
    }
    Timer {
        interval: Theme.rollMs * 1.45 + 250; running: true; repeat: true
        onTriggered: {
            const boxes = [nowPlayingNote, musicNote, date, weather, time].filter(item => item.visible).map(item => ({
                x: item.keyBox.mapToItem(scene, 0, 0).x,
                width: item.keyBox.width,
                text: item === date || item === time
            }));
            const phase = test.phase;
            scene.grabToImage(result => {
                result.saveToFile(Quickshell.shellPath("spacing-" + phase + ".png"));
                console.log("FRAME:" + JSON.stringify({phase, boxes}));
                if (test.phase + 1 === test.cases.length) Qt.quit();
                else test.phase++;
            });
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-text-spacing-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "fixture-player.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
            '<rect x="16" y="0" width="32" height="64" fill="white"/></svg>'
        )
        bar = (ROOT / "Bar.qml").read_text()
        start = bar.rfind("        BarItem {", 0, bar.index("id: nowPlayingNote"))
        end = bar.rfind("        Clock {", 0, bar.index("id: clock\n"))
        notes = bar[start:end].replace("AppIcon {", 'AppIcon {\n                source: test.phase < 4 ? Qt.resolvedUrl("fixture-player.svg") : ""', 1)
        date_source = (ROOT / "modules/Clock.qml").read_text()
        time_source = bar[bar.index("id: timeClock"):bar.index("RollingText {", bar.index("id: timeClock"))]
        qml = QML.replace("PLAYER_NOTES", notes)
        for token, source in [("DATE_MARGINS", date_source), ("TIME_MARGINS", time_source)]:
            margins = [line.strip() for line in source.splitlines()
                       if line.strip().startswith(("Layout.leftMargin:", "Layout.rightMargin:"))]
            qml = qml.replace(token, "; ".join(margins))
        (target / "shell.qml").write_text(qml)
        result = subprocess.run(
            ["qs", "-p", str(target), "--no-color"],
            env=shell_env(target), capture_output=True, text=True, timeout=15,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert not any(error in output for error in (
            "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Failed to load configuration",
        )), output
        frames = [json.loads(line.split("FRAME:", 1)[1]) for line in output.splitlines() if "FRAME:" in line]
        assert len(frames) == 7, output
        for frame in frames:
            image = Image.open(target / f"spacing-{frame['phase']}.png").convert("RGBA")
            bounds = []
            for box in frame["boxes"]:
                start = round(box["x"])
                end = start + round(box["width"])
                ink = [x for x in range(start - 4, end + 4)
                       if any(image.getpixel((x, y))[3] > 24 for y in range(image.height))]
                assert ink, (frame, box)
                bounds.append((min(ink), max(ink)))
                assert bounds[-1] == (start, end - 1), (frame, box, bounds[-1])
            gaps = [bounds[i + 1][0] - bounds[i][1] - 1 for i in range(len(bounds) - 1)]
            expected = [19 - frame["boxes"][i]["text"] - frame["boxes"][i + 1]["text"]
                        for i in range(len(bounds) - 1)]
            assert gaps == expected, (frame, gaps, expected)
        print("PASS: icon gaps stay at 19px; each date/time edge removes 1px, including adjacent text modules")


if __name__ == "__main__":
    main()
