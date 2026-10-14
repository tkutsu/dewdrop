#!/usr/bin/env python3
"""Exercise title scrolling and width transitions in the real music UI."""

from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


MPD = '''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true
    property string title: "A very long track title that overflows both the pill and the music player header by a comfortable margin"
    property string label: title
    property string cover: ""; property string state: "play"
    property string artist: "Artist"; property string album: "Album"
    property real duration: 120; property real elapsed: 30
    property real playbackElapsed: elapsed; property real playbackSampledAt: Date.now()
    property string file: ""; property string musicDir: ""
    property int volume: 50; property int premute: 50
    property string volumeIcon: "V"; property string stateIcon: "P"
    property string repeatIcon: "R"; property string repeatMode: "off"
    property bool randomOn: false
    property var playlists: []; property bool playlistsOpen: false
    property string armedPlaylist: ""; property var queue: []; property int songPos: 0
    signal queueChanging()
    function clock(seconds) { return "0:30"; }
    function toggle() {} function prev() {} function next() {} function seek(amount) {}
}
'''

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
ShellRoot {
    FloatingWindow {
        id: win; implicitWidth: 900; implicitHeight: 180
        Pill { side: Pill.Side.Left; edgeOffset: 30; drawsSlab: false; Music { id: music } }
        Item { id: anchor; y: 60; width: 40; height: 20 }
        SettingRow { id: setting; y: 100; width: 650; setting: (SETTING) }
        Marquee {
            id: cycle; x: 750; width: 88; height: 20; contentWidth: 100
            PopupText { text: "End to end" }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw new Error(message);
                console.log("PASS: " + message);
            }
            function named(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found) return found;
                }
                return null;
            }
            function checkWidthTransition(label, reduced) {
                const room = named(music, "titleRoom");
                const title = named(music, "title");
                const from = room.implicitWidth;
                Mpd.title = label;
                wait(1);
                const target = title.implicitWidth;
                const delta = target - from;
                check(delta !== 0, "track change changes the title width");
                const values = [];
                const started = Date.now();
                while (Date.now() - started < 1000) {
                    values.push((room.implicitWidth - from) / delta);
                    wait(16);
                }
                const peaks = [];
                let direction = 1;
                for (let i = 1; i < values.length; i++) {
                    const change = values[i] - values[i - 1];
                    if (Math.abs(change) < 0.00001) continue;
                    const next = change > 0 ? 1 : -1;
                    if (direction === 1 && next === -1 && values[i - 1] > 1.0001)
                        peaks.push(i - 1);
                    direction = next;
                }
                check(peaks.length === (reduced ? 0 : 1), "track width has " + (reduced ? "no" : "one soft") + " bounce (got " + peaks.length + ")");
                check(Math.max(...values) <= (reduced ? 1.00001 : 1.121), "track width keeps the overshoot understated");
                check(Math.abs(room.implicitWidth - target) < 0.001 && !music.contentAnimating, "track width settles exactly within one second");
                for (let i = (peaks.length ? peaks[0] : 0) + 1; i < values.length; i++) {
                    if (reduced) {
                        if (values[i] < values[i - 1] - 0.00001 || values[i] > 1.00001)
                            throw new Error("reduce motion reverses or overshoots");
                    }
                    else if (values[i] > values[i - 1] + 0.00001 || values[i] < 0.99999)
                        throw new Error("final settle reverses or undershoots");
                }
                check(true, "final width settles smoothly without extra reversals");
            }
            function checkHoverFades(pill, expanded) {
                const from = music.width;
                if (expanded)
                    mouseMove(pill, pill.width / 2, pill.height / 2);
                else
                    mouseMove(win.contentItem, 850, 150);
                wait(16);
                check(music.handsOut === expanded && music.contentAnimating, "hover starts " + (expanded ? "expanding" : "contracting") + " the pill");
                let frames = 0;
                while (music.contentAnimating && frames < 100) {
                    check(!pill.scrolling && pill.offset === 0, "title stays still during the hover transition");
                    check(pill.overflow > 0 && pill.rightFade > 0 && pill.layer.enabled, "overflowing title keeps its right fade during the hover transition");
                    frames++;
                    wait(16);
                }
                check(frames > 1 && !music.contentAnimating && pill.scrolling, "hover transition settles and resumes title scrolling");
                check(expanded ? music.width > from : music.width < from, "hover changes the pill width in the expected direction");
            }
            function run() {
                wait(3500);
                Mpd.queue = [{pos: 0, title: "Queue first", artist: "First artist", duration: 60},
                    {pos: 1, title: "Queue second", artist: "Second artist", duration: 90}];
                wait(100);
                function painters(item, title) {
                    let found = item.song?.title === title && item.tailWidth !== undefined ? [item] : [];
                    for (const child of item.children || []) found = found.concat(painters(child, title));
                    return found;
                }
                check(painters(popup.contentItem, "Queue first").some(item => item.number === 1 && item.current),
                    "queue readout marks the playing track");
                popup.auditReorder.rows = Mpd.queue;popup.auditReorder.from = 1;popup.auditReorder.to = 0;
                popup.auditReorder.dragging = true;wait(50);
                check(painters(popup.contentItem, "Queue second").some(item => item.number === 1 && !item.current),
                    "lifted queue preview keeps its song and displays the drop position");
                popup.auditReorder.dragging = false;Mpd.queue = [];
                const pill = named(music, "title");
                const header = named(popup.contentItem, "songTitle");
                const headerText = named(popup.contentItem, "songTitleText");
                check(pill && header && headerText, "real pill and popup titles found");
                check(Settings.scrollMusicTitles && pill.scrolling && header.scrolling, "overflow scrolls by default in both titles");
                check(pill.width <= Theme.mediaTitleWidth, "long title keeps the pill width capped");
                mouseMove(win.contentItem, 850, 150);
                tryCompare(music, "contentAnimating", false, 1500);
                checkHoverFades(pill, true);
                checkHoverFades(pill, false);
                pill.restart(); header.restart(); cycle.restart();
                check(pill.leftFade === 0 && header.leftFade === 0 && pill.rightFade > 0 && header.rightFade > 0, "start stays clear while overflowing right edges fade");
                wait(1800);
                check(pill.offset === 0 && header.offset === 0 && cycle.offset === 0, "titles hold the beginning longer before scrolling");
                wait(900);
                check(pill.offset > 0 && header.offset > 0, "both titles move after the reading pause (pill " + pill.offset + ", popup " + header.offset + ", cycle " + cycle.offset + ")");
                check(cycle.offset === cycle.overflow, "scroll pauses with the end fully visible");
                check(pill.leftFade > 0 && pill.rightFade > 0 && header.leftFade > 0 && header.rightFade > 0, "both edges fade while text passes through");
                check(cycle.leftFade > 0 && cycle.rightFade === 0, "end stays clear while overflowing left edge fades");
                wait(2500);
                check(cycle.offset === 0, "scroll returns to the beginning and pauses");

                mouseClick(setting, setting.width / 2, setting.height / 2); wait(50);
                check(!Settings.scrollMusicTitles && !pill.scrolling && !header.scrolling, "settings toggle stops both titles");
                check(pill.offset === 0 && header.offset === 0 && headerText.elide === Text.ElideRight, "disabled scrolling resets and restores truncation");
                check(!pill.layer.enabled && !header.layer.enabled, "disabled scrolling removes edge fades");
                mouseClick(setting, setting.width / 2, setting.height / 2);
                tryCompare(music, "contentAnimating", false, 6000); wait(2200);
                check(Settings.scrollMusicTitles && pill.offset > 0 && header.offset > 0, "settings toggle restarts both titles");

                Settings.set("reduceMotion", true); wait(50);
                check(!pill.scrolling && !header.scrolling && pill.offset === 0 && header.offset === 0, "reduce motion stops and resets both titles");
                Settings.set("reduceMotion", false);
                tryCompare(music, "contentAnimating", false, 6000); wait(2200);
                Mpd.title = Mpd.title.replace("A very", "A new "); wait(50);
                check(pill.offset === 0 && header.offset === 0, "new track restarts at the beginning");
                Mpd.title = "Short"; wait(700);
                check(!pill.scrolling && !header.scrolling && pill.offset === 0 && header.offset === 0, "fitting titles stay still");
                check(!pill.layer.enabled && !header.layer.enabled, "fitting titles have no edge fades");
                Mpd.title = "A very long track title that overflows both the pill and the music player header by a comfortable margin";
                wait(50); tryCompare(music, "contentAnimating", false, 6000); wait(2200);
                check(pill.offset > 0 && header.offset > 0, "long title starts scrolling again");
                popup.visible = false; wait(50);
                check(!header.scrolling && header.offset === 0, "hidden player stops scrolling");
                popup.visible = true; wait(50);
                check(header.scrolling && header.offset === 0, "reopened player starts from the beginning");
                cycle.width = cycle.contentWidth; wait(50);
                check(!cycle.scrolling && cycle.offset === 0, "resizing to fit stops scrolling");

                Settings.set("scrollMusicTitles", false);
                tryCompare(music, "contentAnimating", false, 1500);
                checkWidthTransition("Short", false);
                checkWidthTransition("Shorter", false);
                checkWidthTransition("A much longer title for the music pill", false);
                Settings.set("reduceMotion", true); wait(50);
                checkWidthTransition("Short", true);
                console.log("DONE: music title scrolling");
            }
        }
    }
    MusicPopup { id: popup; visible: true; anchorItem: anchor }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}
'''


def main():
    source = (ROOT / "modules/SettingsMenu.qml").read_text()
    start = source.index('{ type: "toggle", id: "scrollMusicTitles"')
    setting = source[start:source.index("\n", start)].strip()
    with tempfile.TemporaryDirectory(prefix="qs-music-titles-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/Mpd.qml").write_text(MPD)
        (target / "services/Launcher.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string musicPrefix: "#"; function openWith(prefix) {} }\n')
        for name, ids in (("modules/Music.qml", ("title", "titleRoom")), ("components/MusicPopup.qml", ("songTitle", "songTitleText"))):
            path = target / name
            content = path.read_text()
            if name == "components/MusicPopup.qml":
                content = content.replace("id: root", "id: root\n    property alias auditReorder: reorder", 1)
            for ident in ids:
                content = content.replace("id: " + ident + "\n", 'id: ' + ident + '\n                    objectName: "' + ident + '"\n')
            path.write_text(content)
        (target / "shell.qml").write_text(SHELL.replace("SETTING", setting))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=40)
        output = result.stdout + result.stderr
        print(output)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        return 0 if result.returncode == 0 and "DONE: music title scrolling" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
