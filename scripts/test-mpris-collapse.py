#!/usr/bin/env python3
"""Exercise MPRIS pill hover, playback clicks and central app-icon restore."""

from pathlib import Path
import runpy
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


PLAYER = '''import QtQuick
import Quickshell.Services.Mpris
QtObject {
    property string identity: "First app"
    property string desktopEntry: "first-app"
    property string trackTitle: "A video"
    property int playbackState: MprisPlaybackState.Playing
    readonly property bool isPlaying: playbackState === MprisPlaybackState.Playing
    property bool positionSupported: false
    property bool lengthSupported: false
    property real length: 120
    property real position: 30
    property bool canTogglePlaying: true
    property bool canPlay: true
    property bool canSeek: false
    property int toggles: 0
    property int plays: 0
    signal trackChanged()
    function togglePlaying() {
        toggles++;
        playbackState = isPlaying ? MprisPlaybackState.Paused : MprisPlaybackState.Playing;
    }
    function play() { plays++; playbackState = MprisPlaybackState.Playing; }
}
'''

SHELL = '''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import Quickshell.Services.Mpris
import qs
import qs.components
import qs.modules
import qs.services as Services
ShellRoot {
    TestPlayer { id: first }
    TestPlayer { id: second; identity: "Second app"; desktopEntry: "second-app"; playbackState: MprisPlaybackState.Paused }
    FloatingWindow {
        id: window; implicitWidth: 1000; implicitHeight: 100
        SidePill {
            id: playerPill; control: nowPlaying; side: Pill.Side.Right; edgeOffset: 30; slidesContent: true
            NowPlaying { id: nowPlaying; foldDuration: Theme.dropMs; foldEasing: Easing.Linear }
        }
        SidePill {
            id: musicPill; control: music; side: Pill.Side.Right; edgeOffset: 350; slidesContent: true
            Music { id: music; foldDuration: Theme.dropMs; foldEasing: Easing.Linear }
        }
        Pill {
            id: centrePill; side: Pill.Side.Centre; centreOn: centreAnchor; drawsSlab: false; order: ["clock"]
            APP_NOTE
            MUSIC_NOTE
            BarItem { id: centreAnchor; settingsKey: "clock"; BarText { text: "Clock" } }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            function appIcon(item) {
                if (item.windowClass !== undefined) return item;
                for (const child of item.children || []) {
                    const found = appIcon(child);
                    if (found) return found;
                }
                return null;
            }
            function run() {
                Settings.user = Object.assign({}, Settings.user, {showMpris: true});
                nowPlaying.testPlayers = [first];
                wait(Theme.startMs + 100);
                check(nowPlaying.player === first && nowPlaying.reveal === 1 && !nowPlayingNote.visible,
                      "playing MPRIS player shows the full pill");
                const centreX = centreAnchor.mapToItem(window.contentItem, centreAnchor.width / 2, 0).x;
                const room = nowPlaying.keyBox.children[0];
                const title = room.children.find(item => item.travel !== undefined);
                const pause = room.children.find(item => item.text === Theme.glyph.paused);
                mouseMove(window.contentItem, 950, 90); wait(250);
                check(pause && pause.opacity === 0, "pause icon is hidden away from the pill");
                const restingWidth = playerPill.width;
                const restingTitleWidth = title.width;
                mouseMove(nowPlaying, nowPlaying.width / 2, nowPlaying.height / 2);
                let fixedWidth = true;
                for (let frame = 0; frame < 20; frame++) {
                    wait(16);
                    fixedWidth = fixedWidth && playerPill.width === restingWidth;
                }
                check(fixedWidth, "hover keeps the pill width fixed throughout the transition");
                check(pause.opacity === 1 && title.width < restingTitleWidth && title.rightFade > 0 && title.layer.enabled,
                      "hover reveals pause over a shortened title with a gradient");
                Settings.user = Object.assign({}, Settings.user, {scrollMusicTitles: false, reduceMotion: true}); wait(100);
                check(!title.scrolling && title.rightFade > 0 && title.layer.enabled,
                      "hover keeps the gradient with title scrolling and motion disabled");
                Settings.user = Object.assign({}, Settings.user, {scrollMusicTitles: true, reduceMotion: false});
                mouseMove(window.contentItem, 950, 90); wait(250);
                check(pause.opacity === 0 && title.width === restingTitleWidth && playerPill.width === restingWidth,
                      "leaving hides pause and restores the title without resizing");
                for (const target of [appIcon(nowPlaying), pause, nowPlaying]) {
                    const before = first.toggles;
                    // The root target exercises the trailing pill padding.
                    mouseClick(target, target === nowPlaying ? target.width - 1 : target.width / 2, 0); wait(80);
                    check(first.toggles === before + 1 && !first.isPlaying,
                          "app icon, hover icon and padding each pause exactly once");
                    first.playbackState = MprisPlaybackState.Playing; wait(1100);
                }
                const beforeAccessible = first.toggles;
                nowPlaying.Accessible.pressAction(); wait(80);
                check(first.toggles === beforeAccessible + 1 && !first.isPlaying,
                      "accessible pill action toggles playback exactly once");
                first.playbackState = MprisPlaybackState.Playing; wait(1100);
                first.toggles = 0;
                const titleX = title.mapToItem(nowPlaying, title.width / 2, 0).x;
                mousePress(nowPlaying, titleX, 0); wait(200);
                check(title.scale < 1 && pause.scale < 1, "title and pause shrink while the pill is held at the top edge");
                mouseRelease(nowPlaying, titleX, 0); wait(80);
                check(first.toggles === 1 && !first.isPlaying, "a held top-edge click pauses MPRIS exactly once");
                check(nowPlaying.stowed && nowPlaying.reveal > 0 && nowPlaying.reveal < 1,
                      "pausing MPRIS starts collapsing its pill");
                const travellingIcon = appIcon(nowPlaying);
                let followedGlass = true;
                let sawGradient = false;
                let frames = 0;
                let stayedHidden = nowPlayingNote.stowed && !nowPlayingNote.visible;
                while (!nowPlaying.iconInCentre && frames++ < 200) {
                    stayedHidden = stayedHidden && nowPlayingNote.stowed && !nowPlayingNote.visible;
                    sawGradient = sawGradient || (title.width > 0 && title.travel > 1 && title.leftFade > 0);
                    const iconX = travellingIcon.mapToItem(playerPill, travellingIcon.width / 2, 0).x;
                    followedGlass = followedGlass && travellingIcon.visible && travellingIcon.opacity === 1
                        && playerPill.contentOpacity === 1 && playerPill.contentZoom === 1
                        && travellingIcon.scale === playerPill.iconScale
                        && Math.abs(iconX - playerPill.foldBox.x - nowPlaying.iconInset - travellingIcon.width / 2) < 1;
                    wait(10);
                }
                check(sawGradient, "contracting title slides behind the icon through the marquee gradient");
                check(followedGlass, "opaque app icon follows the contracting edge with its scale bounce");
                check(stayedHidden && nowPlaying.iconInCentre && !nowPlayingNote.stowed,
                      "central icon waits until the bead has been absorbed");
                wait(30);
                check(nowPlayingNote.reveal === 1 && !travellingIcon.visible,
                      "handoff shows exactly the central icon after absorption");
                wait(1000);
                check(!playerPill.visible && nowPlayingNote.visible && appIcon(nowPlayingNote).windowClass === first.desktopEntry,
                      "paused MPRIS leaves its app icon in the central pill");
                check(nowPlayingNote.x < centreAnchor.x && Math.abs(centreAnchor.mapToItem(window.contentItem, centreAnchor.width / 2, 0).x - centreX) <= 1,
                      "app icon sits left of the central anchor without moving it");
                Services.Mpd.state = "pause"; wait(80);
                check(!music.iconInCentre && centrePill.leadingOrder[0] === nowPlayingNote,
                      "starting a music collapse leaves the central icon order alone");
                while (!music.iconInCentre) wait(10);
                wait(1000);
                check(musicNote.visible && nowPlayingNote.visible && musicNote.x < nowPlayingNote.x,
                      "music takes the outside slot when its icon is absorbed last");
                check(Math.abs(centreAnchor.mapToItem(window.contentItem, centreAnchor.width / 2, 0).x - centreX) <= 1,
                      "reordering the two icons keeps the central anchor fixed");
                mouseClick(nowPlayingNote, nowPlayingNote.width / 2, 0); wait(80);
                check(nowPlaying.reveal > 0 && nowPlaying.reveal < 0.3 && nowPlayingNote.visible && !travellingIcon.visible,
                      "central icon stays while expansion begins inside the central pill");
                while (nowPlaying.iconInCentre) wait(10);
                wait(30);
                check(!nowPlayingNote.visible && travellingIcon.visible,
                      "expansion hands the icon back to the emerging pill");
                wait(1100);
                check(playerPill.visible && playerPill.enabled && nowPlaying.reveal === 1 && !nowPlayingNote.visible,
                      "clicking the app icon at the top edge restores the MPRIS pill");
                check(musicNote.visible && centrePill.leadingOrder[0] === musicNote,
                      "expanding the inner MPRIS icon preserves the resting music order");
                check(first.plays === 1 && first.toggles === 1 && first.isPlaying, "expanding MPRIS resumes playback once");
                nowPlaying.expand();
                check(first.plays === 1, "expanding an already playing MPRIS player does not repeat the play command");
                first.playbackState = MprisPlaybackState.Playing; wait(50);
                first.playbackState = MprisPlaybackState.Paused; wait(1100);
                check(!nowPlaying.expanded && !playerPill.visible && nowPlayingNote.visible, "the next MPRIS pause collapses again");
                check(nowPlayingNote.x < musicNote.x && musicNote.x < centreAnchor.x,
                      "MPRIS takes the outside slot when its icon is absorbed last");
                first.playbackState = MprisPlaybackState.Playing; wait(1100);
                check(nowPlaying.reveal === 1 && !nowPlayingNote.visible, "resuming MPRIS restores the full pill");
                mouseClick(nowPlaying, nowPlaying.width / 2, nowPlaying.height / 2, Qt.RightButton); wait(80);
                check(first.toggles === 2 && !first.isPlaying, "right-clicking the pill still pauses MPRIS exactly once");
                first.playbackState = MprisPlaybackState.Playing; wait(1100);
                check(nowPlaying.reveal === 1 && !nowPlayingNote.visible, "a quick MPRIS pause and resume cancels the icon entrance");
                first.playbackState = MprisPlaybackState.Paused; wait(1100);
                mouseClick(nowPlayingNote, nowPlayingNote.width / 2, nowPlayingNote.height / 2); wait(1100);
                nowPlaying.testPlayers = [second]; wait(1100);
                check(!nowPlaying.expanded && !playerPill.visible && nowPlayingNote.visible && appIcon(nowPlayingNote).windowClass === second.desktopEntry,
                      "switching paused players resets expansion and updates the app icon");
                Settings.user = Object.assign({}, Settings.user, {showMpris: false}); wait(1100);
                check(!playerPill.visible && !nowPlayingNote.visible, "disabling MPRIS hides the pill and central icon");
                Settings.user = Object.assign({}, Settings.user, {showMpris: true}); wait(1100);
                check(nowPlayingNote.visible, "re-enabling a paused player restores its central icon");
                second.playbackState = MprisPlaybackState.Stopped; wait(1100);
                check(nowPlaying.player === null && !playerPill.visible && !nowPlayingNote.visible, "stopped MPRIS players leave no pill or icon");
                console.log("DONE: MPRIS collapse");
            }
        }
    }
    Timer { interval: 300; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-mpris-collapse-") as folder:
        target = Path(folder)
        copy_shell(target)
        player = target / "modules/NowPlaying.qml"
        # Substitute the external player objects while keeping selection and UI bindings.
        player.write_text(player.read_text().replace("    id: root\n", "    id: root\n    property var testPlayers: []\n", 1)
                          .replace("Mpris.players.values", "root.testPlayers").replace("property MprisPlayer", "property QtObject"))
        bar = (ROOT / "Bar.qml").read_text()
        start = bar.rfind("        BarItem {", 0, bar.index("id: nowPlayingNote"))
        end = bar.rfind("        BarItem {", 0, bar.index("id: musicNote"))
        (target / "TestPlayer.qml").write_text(PLAYER)
        stubs = runpy.run_path(str(ROOT / "scripts/test-pill-top-edge.py"))["STUBS"]
        (target / "services/Mpd.qml").write_text(stubs["services/Mpd.qml"])
        music_end = bar.index("        Clock {", end)
        (target / "shell.qml").write_text(SHELL.replace("APP_NOTE", bar[start:end]).replace("MUSIC_NOTE", bar[end:music_end]))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=45)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "DONE: MPRIS collapse" in output and not any(error in output for error in errors)
        print("\n".join(line for line in output.splitlines() if "qml:" in line or any(error in line for error in errors)))
        if not ok:
            print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
