#!/usr/bin/env python3
"""Exercise MPRIS focus, playback controls and central app-icon handoff."""

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
    property bool canRaise: true
    property int raises: 0
    signal trackChanged()
    function raise() { raises++; }
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
                const originalTitle = first.trackTitle;
                first.trackTitle = "A very long video title that overflows the Now Playing pill by a comfortable margin";
                Settings.user = Object.assign({}, Settings.user, {scrollMusicTitles: false}); wait(1000);
                const titleText = title.children[0].children.find(item => item.maxWidth !== undefined);
                check(!title.scrolling && title.offset === 0 && title.overflow > 0 && title.rightFade > 0
                      && title.leftFade === 0 && title.layer.enabled && titleText.maxWidth === 0,
                      "static Now Playing title keeps its full text and fades the cut-off edge without an ellipsis");
                mouseMove(title, title.width / 2, title.height / 2); wait(600);
                check(title.scrolling && title.offset > 0, "hover promptly scrolls Now Playing with automatic scrolling disabled");
                mouseMove(window.contentItem, 950, 90); wait(250);
                check(!title.scrolling && title.offset === 0 && title.rightFade > 0,
                      "leaving Now Playing restores the static title and gradient");
                first.trackTitle = originalTitle; wait(1000);
                check(!title.scrolling && title.overflow === 0 && !title.layer.enabled,
                      "fitting static Now Playing title has no gradient");
                Settings.user = Object.assign({}, Settings.user, {scrollMusicTitles: true});
                for (const target of [appIcon(nowPlaying), title, nowPlaying]) {
                    const before = first.raises;
                    // The root target exercises the trailing pill padding.
                    mouseClick(target, target === nowPlaying ? target.width - 1 : target.width / 2, 0); wait(80);
                    check(first.raises === before + 1 && first.toggles === 0 && first.isPlaying,
                          "app icon, title and padding focus the player without changing playback");
                }
                const beforeAccessible = first.raises;
                nowPlaying.Accessible.pressAction(); wait(80);
                check(first.raises === beforeAccessible + 1 && first.toggles === 0 && first.isPlaying,
                      "accessible pill action focuses the player without changing playback");
                first.canRaise = false;
                nowPlaying.testWindows = [
                    {address: "aaa", wayland: {appId: first.desktopEntry}, lastIpcObject: {focusHistoryID: 5}},
                    {address: "bbb", lastIpcObject: {class: first.desktopEntry, focusHistoryID: 1}},
                    {address: "ccc", wayland: {appId: second.desktopEntry}, lastIpcObject: {focusHistoryID: 0}}
                ];
                mouseClick(title, title.width / 2, 0); wait(80);
                check(nowPlaying.testDispatches.length === 1
                      && nowPlaying.testDispatches[0] === 'hl.dsp.focus({ window = "address:0xbbb" })'
                      && first.raises === beforeAccessible + 1 && first.isPlaying,
                      "a player without Raise focuses its most recent matching window");
                nowPlaying.testWindows = [
                    {address: "aaa", title: "A VIDEO — Browser", wayland: {appId: first.desktopEntry}, lastIpcObject: {focusHistoryID: 5}},
                    {address: "bbb", title: "Other tab", wayland: {appId: first.desktopEntry}, lastIpcObject: {focusHistoryID: 0}},
                    {address: "ccc", title: first.trackTitle, wayland: {appId: second.desktopEntry}, lastIpcObject: {focusHistoryID: 0}}
                ];
                mouseClick(title, title.width / 2, 0); wait(80);
                check(nowPlaying.testDispatches.length === 2
                      && nowPlaying.testDispatches[1] === 'hl.dsp.focus({ window = "address:0xaaa" })',
                      "media title picks the playing window ahead of a more recent unrelated window");
                nowPlaying.testWindows = [];
                mouseClick(title, title.width / 2, 0); wait(80);
                check(nowPlaying.testDispatches.length === 2 && first.isPlaying,
                      "a player without Raise or a matching window leaves playback alone");
                first.canRaise = true;
                mouseMove(title, title.width / 2, title.height / 2); wait(250);
                mouseClick(pause, pause.width / 2, 0); wait(80);
                check(first.toggles === 1 && !first.isPlaying,
                      "hover playback control pauses exactly once without focusing");
                first.playbackState = MprisPlaybackState.Playing; wait(1100);
                first.toggles = 0;
                const titleX = title.mapToItem(nowPlaying, title.width / 2, 0).x;
                mousePress(nowPlaying, titleX, 0); wait(200);
                check(title.scale < 1 && pause.scale < 1, "title and pause shrink while the pill is held at the top edge");
                mouseRelease(nowPlaying, titleX, 0); wait(80);
                check(first.toggles === 0 && first.isPlaying, "a held top-edge title click keeps playback running");
                mouseClick(nowPlaying, nowPlaying.width / 2, 0, Qt.RightButton); wait(80);
                check(first.toggles === 1 && !first.isPlaying, "right-click pauses MPRIS exactly once");
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
                        && travellingIcon.scale === 1
                        && Math.abs(iconX - playerPill.foldBox.x - nowPlaying.iconInset - travellingIcon.width / 2) < 1;
                    wait(10);
                }
                check(sawGradient, "contracting title slides behind the icon through the marquee gradient");
                check(followedGlass, "opaque app icon follows the contracting edge at its fixed size");
                check(stayedHidden && nowPlaying.iconInCentre && !nowPlayingNote.stowed,
                      "central icon waits until the bead has been absorbed");
                while (nowPlaying.iconHandoff.progress < 1) wait(10);
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
                const beforeCollapsed = first.raises;
                mouseClick(nowPlayingNote, nowPlayingNote.width / 2, 0); wait(80);
                check(first.raises === beforeCollapsed && first.isPlaying && first.plays === 1,
                      "central app icon resumes playback without focusing a window");
                check(nowPlaying.reveal > 0 && nowPlaying.reveal < 0.3 && nowPlayingNote.visible && !travellingIcon.visible,
                      "central icon stays while expansion begins inside the central pill");
                while (nowPlaying.iconInCentre) wait(10);
                wait(30);
                check(!nowPlayingNote.visible && travellingIcon.visible,
                      "expansion hands the icon back to the emerging pill");
                wait(1100);
                check(playerPill.visible && playerPill.enabled && nowPlaying.reveal === 1 && !nowPlayingNote.visible,
                      "clicking the app icon restores the MPRIS pill");
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
                mouseClick(nowPlayingNote, nowPlayingNote.width / 2, nowPlayingNote.height / 2); wait(80);
                check(second.raises === 0 && second.isPlaying && second.plays === 1 && second.toggles === 0,
                      "central icon resumes the newly selected player without focusing it");
                second.playbackState = MprisPlaybackState.Paused; wait(1100);
                Settings.user = Object.assign({}, Settings.user, {showMpris: false}); wait(1100);
                check(!playerPill.visible && !nowPlayingNote.visible, "disabling MPRIS hides the pill and central icon");
                Settings.user = Object.assign({}, Settings.user, {showMpris: true}); wait(1100);
                check(nowPlayingNote.visible, "re-enabling a paused player restores its central icon");
                second.playbackState = MprisPlaybackState.Stopped; wait(1100);
                check(nowPlaying.player === null && !playerPill.visible && !nowPlayingNote.visible, "stopped MPRIS players leave no pill or icon");
                nowPlaying.focusPlayer();
                check(nowPlaying.testDispatches.length === 2 && second.raises === 0,
                      "focusing with no active player is harmless");
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
        player.write_text(player.read_text().replace("    id: root\n", "    id: root\n    property var testPlayers: []\n"
                                                   "    property var testWindows: []\n    property var testDispatches: []\n"
                                                   "    function testDispatch(command) { testDispatches.push(command); }\n", 1)
                          .replace("Mpris.players.values", "root.testPlayers").replace("property MprisPlayer", "property QtObject")
                          .replace("Hyprland.toplevels.values", "root.testWindows").replace("Hyprland.dispatch(", "root.testDispatch("))
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
