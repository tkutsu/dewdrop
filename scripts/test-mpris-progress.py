#!/usr/bin/env python3
"""Check MPRIS seek timing changes against the real pill's outline."""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env


PLAYER = '''import QtQuick
import Quickshell.Services.Mpris
QtObject {
    property string identity: "Test player"
    property string desktopEntry: "test-player"
    property string trackTitle: "A track"
    property int playbackState: MprisPlaybackState.Playing
    readonly property bool isPlaying: playbackState === MprisPlaybackState.Playing
    property bool positionSupported: true
    property bool lengthSupported: false
    property real length: 0
    property real position: 0
    property real rate: 1
    property bool canTogglePlaying: true
    property bool canSeek: true
    signal trackChanged()
    function seek(amount) { position += amount; }
    function togglePlaying() {}
}
'''

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
ShellRoot {
    TestPlayer { id: player }
    TestPlayer { id: other }
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 100
        SidePill {
            id: pill; control: media; side: Pill.Side.Left; edgeOffset: 30
            progress: media.progress; rate: media.rate
            NowPlaying { id: media }
        }
        TestCase {
            id: test; when: false
            property int failures: 0
            function check(ok, message) {
                if (!ok) failures++;
                console.log((ok ? "PASS: " : "FAIL: ") + message);
            }
            function run() {
                Settings.user = Object.assign({}, Settings.user, {showMpris: true});
                media.testPlayers = [player]; wait(1100);
                const track = pill.children.find(c => c.played !== undefined);
                check(track && !track.visible, "untimed media has no progress outline");
                // Seeking an untimed video can briefly expose a duration.
                for (const amount of [10, -10]) {
                    player.length = 120; player.lengthSupported = true;
                    player.seek(amount); wait(100);
                    check(!track.visible, "brief timing during seek " + amount + " does not flash an outline");
                    player.lengthSupported = false; player.length = 0; wait(600);
                    check(!track.visible, "untimed outline stays hidden after seek " + amount);
                }
                player.position = 30; player.length = 120; player.lengthSupported = true; wait(650);
                check(track.visible && media.progress === 0.25, "stable timing shows accurate progress");
                for (const amount of [10, -10]) {
                    const before = media.progress;
                    player.lengthSupported = false; player.length = 0;
                    player.seek(amount); wait(100);
                    check(track.visible && media.progress === before && media.rate === 0,
                          "brief timing loss during seek " + amount + " holds the outline without drifting");
                    player.length = 120; player.lengthSupported = true; wait(50);
                    check(track.visible && Math.abs(media.progress - player.position / player.length) < 0.001,
                          "seek " + amount + " immediately updates progress when timing returns");
                    wait(600);
                }
                const retained = media.progress;
                player.lengthSupported = false; player.length = 0; wait(1200);
                check(track.visible && media.progress === retained && media.rate === 0,
                      "a longer seek timing gap holds the same track's outline without drifting");
                player.trackChanged(); wait(50);
                check(!track.visible && media.progress === -1,
                      "changing tracks clears retained progress before reading new timing");
                player.length = 120; player.lengthSupported = true; wait(650);
                player.positionSupported = false; wait(1200);
                check(track.visible && media.rate === 0, "longer position support loss also holds the outline");
                player.positionSupported = true; wait(650);
                media.testPlayers = [other]; wait(50);
                check(media.progress === -1 && !track.visible, "switching to an untimed player clears old progress immediately");
                other.length = 120; other.lengthSupported = true; other.position = 60; wait(650);
                check(track.visible && media.progress === 0.5, "a new timed player gets its own progress");
                media.testPlayers = []; wait(1100);
                check(!pill.visible, "player removal still dismisses the pill");
                if (!failures) console.log("DONE: MPRIS progress");
            }
        }
        Timer { interval: 200; running: true; onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    """Use isolated players to exercise real outline visibility during seeks."""
    with tempfile.TemporaryDirectory(prefix="qs-mpris-progress-") as folder:
        target = Path(folder)
        copy_shell(target)
        module = target / "modules/NowPlaying.qml"
        module.write_text(module.read_text().replace("    id: root\n", "    id: root\n    property var testPlayers: []\n", 1)
                          .replace("Mpris.players.values", "root.testPlayers").replace("property MprisPlayer", "property QtObject"))
        (target / "TestPlayer.qml").write_text(PLAYER)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "DONE: MPRIS progress" in output and not any(error in output for error in errors)
        print("\n".join(line for line in output.splitlines() if "qml:" in line or any(error in line for error in errors)))
        if not ok:
            print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
