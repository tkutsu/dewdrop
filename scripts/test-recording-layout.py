#!/usr/bin/env python3
"""Check recording/music/now-playing placement using the actual Bar geometry bindings."""

import re
import subprocess
import tempfile
from pathlib import Path

from test_support import ROOT, copy_shell, shell_env


def main():
    source = (ROOT / "Bar.qml").read_text()
    names = ("clockLeft", "recordingBase", "recordingDrop", "mediaEdge", "musicEdge", "musicBase", "musicDrop", "nowPlayingEdge", "nowPlayingDrop")
    bindings = "\n".join(re.search(r"^    readonly property [^\n]+ " + name + r": [^\n]+", source, re.M).group(0) for name in names)
    pills = []
    for name, width in (("recording", 44), ("music", 120), ("nowPlaying", 150)):
        block = source.split(f"id: {name}Pill", 1)[1].split(f"id: {name}\n", 1)[0]
        layout = "\n".join(line for line in block.splitlines() if re.match(r"\s*(side|edgeOffset|morphValue):", line))
        pills.append(f'''SidePill {{
            id: {name}Pill; control: {name}
            {layout}
            Item {{
                id: {name}; implicitWidth: {width}; implicitHeight: Theme.barHeight
                property real reveal: 1
                property bool stowed: false
            }}
        }}''')
    qml = '''import QtQuick
import Quickshell
import qs
import qs.components
import "Drops.js" as Drops
ShellRoot {
    FloatingWindow {
        id: bar; implicitWidth: 800; implicitHeight: 50
        readonly property var drops: Drops.geometry(Theme)
        Item { id: clockPill; x: 500; width: 180 }
        Item { id: recordingMorph; property real value: 0 }
        Item { id: musicMorph; property real value: 0 }
        property bool mprisInside: false
        BINDINGS
        PILLS
        function check(ok, message) { if (!ok) throw Error(message); }
        Timer {
            interval: 150; running: true
            onTriggered: {
                try {
                    bar.check(recordingPill.x + recordingPill.width + Theme.pillSpread === bar.clockLeft, "recording is immediately left of the centre pill");
                    bar.check(musicPill.x + musicPill.width + Theme.pillSpread === recordingPill.x, "music is immediately left of recording");
                    bar.check(nowPlayingPill.x + nowPlayingPill.width + Theme.pillSpread === musicPill.x, "now playing is immediately left of music");
                    const musicX = musicPill.x;
                    const nowPlayingX = nowPlayingPill.x;
                    musicMorph.value = 2;
                    bar.check(nowPlayingPill.x === nowPlayingX, "music morph keeps now playing in place");
                    musicMorph.value = 0;
                    music.stowed = true; music.reveal = 0;
                    bar.check(nowPlayingPill.x + nowPlayingPill.width + Theme.pillSpread === recordingPill.x, "now playing sits beside recording without music");
                    recording.stowed = true; recording.reveal = 0;
                    bar.check(nowPlayingPill.x + nowPlayingPill.width + Theme.pillSpread === bar.clockLeft, "now playing sits beside the centre pill alone");
                    recording.stowed = false; recording.reveal = 1;
                    music.stowed = false; music.reveal = 1;
                    recordingMorph.value = 2;
                    bar.check(musicPill.x === musicX && bar.recordingDrop.z === 0, "recording morph keeps music in place");
                    recordingMorph.value = 0;
                    recording.stowed = true; recording.reveal = 0;
                    bar.check(musicPill.x + musicPill.width + Theme.pillSpread === bar.clockLeft, "music returns beside the centre pill without recording");
                    recording.stowed = false; recording.reveal = 1;
                    const recordingX = recordingPill.x;
                    music.implicitWidth = 240;
                    bar.check(recordingPill.x === recordingX && musicPill.x + musicPill.width + Theme.pillSpread === recordingX, "longer music titles grow away from recording");
                    for (let step = 0; step <= 20; step++) {
                        recording.reveal = step / 20;
                        music.reveal = step / 20;
                        bar.check([bar.nowPlayingEdge, bar.nowPlayingDrop.x, bar.nowPlayingDrop.z].every(isFinite), "music arrival keeps now playing finite");
                        bar.check([bar.musicEdge, bar.musicDrop.x, bar.musicDrop.z, bar.recordingDrop.x, bar.recordingDrop.z].every(isFinite), "arrival geometry stays finite");
                    }
                    music.implicitWidth = 120;
                    bar.mprisInside = true;
                    bar.check(nowPlayingPill.x + nowPlayingPill.width + Theme.pillSpread === recordingPill.x, "now playing opened from the clock sits beside recording");
                    bar.check(musicPill.x + musicPill.width + Theme.pillSpread === nowPlayingPill.x, "music moves out beyond now playing");
                    nowPlaying.stowed = true; nowPlaying.reveal = 0;
                    bar.check(musicPill.x + musicPill.width + Theme.pillSpread === recordingPill.x, "music closes back up when now playing goes");
                    for (let step = 0; step <= 20; step++) {
                        nowPlaying.reveal = step / 20;
                        bar.check([bar.musicEdge, bar.musicDrop.x, bar.musicDrop.z].every(isFinite), "now playing arrival keeps music finite");
                    }
                    console.log("PASS: recording/music/now playing layout");
                } catch (error) { console.log("FAIL: " + error); }
                Qt.quit();
            }
        }
    }
}'''.replace("BINDINGS", bindings).replace("PILLS", "\n".join(pills))
    with tempfile.TemporaryDirectory(prefix="recording-layout-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(qml)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines() if "PASS:" in line or any(error in line for error in errors)))
        return 0 if result.returncode == 0 and "PASS: recording/music/now playing layout" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
