#!/usr/bin/env python3
"""Exercise empty-popover returns with real pills, popups and isolated timers."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


MPD = '''pragma Singleton
import QtQuick
QtObject {
    property bool loaded: true
    property string state: "play"
    property string title: "A track title"; property string label: title
    property string artist: ""; property string album: ""; property string cover: ""
    property int duration: 120; property int elapsed: 30
    property real playbackElapsed: 30; property real playbackSampledAt: Date.now()
    property int volume: -1; property string volumeIcon: ""
    property bool randomOn: false; property string repeatMode: "off"; property string repeatIcon: ""
    property var playlists: []; property bool playlistsOpen: false; property string armedPlaylist: ""
    property var queue: []; property int songPos: -1
    property int stops: 0
    signal queueChanging
    function clock(seconds) { return "0:30"; }
    function stopServer() { stops++; loaded = false; }
    function toggle() { state = state === "play" ? "pause" : "play"; }
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
        implicitWidth: 1000; implicitHeight: 100
        Morph { id: musicMorph; open: music.popupOpen }
        Morph { id: timerMorph; open: countdown.popupOpen }
        SidePill {
            id: musicPill; control: music; morphValue: musicMorph.value; slidesContent: true
            closeWhenEmpty: true; empty: !Mpd.loaded
            side: Pill.Side.Left; edgeOffset: 50
            Music { id: music; foldDuration: Theme.dropMs; foldEasing: Easing.Linear }
        }
        SidePill {
            id: timerPill; control: countdown; morphValue: timerMorph.value; slidesContent: true
            closeWhenEmpty: true
            empty: Timers.entries.length === 0 && Timers.ringing.length === 0
            emptyPopupOwner: OpenPopup.owner === timeClock ? timeClock : countdown
            side: Pill.Side.Left; edgeOffset: 400
            Countdown { id: countdown; foldDuration: Theme.dropMs; foldEasing: Easing.Linear }
        }
        Pill {
            side: Pill.Side.Left; edgeOffset: 750
            BarItem { id: timeClock; popup: TimerPopup {} BarText { text: "Clock" } }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function until(predicate, message, timeout = 2000) {
                let elapsed = 0;
                while (!predicate() && elapsed < timeout) { wait(10); elapsed += 10; }
                check(predicate(), message);
            }
            function open(owner) {
                OpenPopup.set(owner); wait(450);
                check(owner.popupItem?.opened, "real popup opens");
            }
            function cancel(label) {
                const row = OpenPopup.owner.popupItem.keyTargets().find(item => item.name === "Cancel " + label);
                check(row !== undefined, "cancel target exists: " + label);
                row.tapped(); wait(20);
            }
            function returned(pill, control, morph) {
                check(OpenPopup.owner === null, "last item closes its popup");
                check(pill.retiring, "empty pill keeps its exit shape");
                check(pill.contentOpacity === 0 && pill.trackOpacity === 0 && !pill.enabled, "empty capsule hides content, track and input");
                until(() => (morph.value <= 0.1 && control.reveal === 1
                             && Math.abs(pill.width - Math.round(Theme.barHeight * 2.8)) < 0.5) || control.stowed,
                      "popover reaches its returning capsule");
                until(() => control.stowed, "collapse overlaps the popover return without a rest", 40);
                until(() => control.stowed && control.reveal > 0 && control.reveal < 1, "capsule starts an animated collapse");
                until(() => Math.abs(pill.width - Math.round(Theme.barHeight * 2.8)) < 0.5,
                      "empty capsule reaches twice its previous width during collapse");
                wait(40);
                const earlyBox = pill.geometry.drop(0, 1, pill.width, pill.dropReveal, true);
                check(earlyBox.z < pill.width - 0.3, "empty glass shrinks immediately without waiting for a content fade");
                check(pill.contentOpacity === 0, "collapse stays blank");
                let previous = control.reveal;
                let frames = 0;
                let widest = 0;
                while (control.reveal > 0 && frames < 100) {
                    const box = pill.geometry.drop(0, 1, pill.width, pill.dropReveal, control.stowed);
                    widest = Math.max(widest, pill.geometry.morph(box, morph.value).z);
                    wait(10);
                    check(control.reveal <= previous, "collapse moves continuously towards its neighbour");
                    previous = control.reveal; frames++;
                }
                check(widest >= Theme.barHeight * 2.4, "visible empty capsule unfolds close to its doubled width");
                check(!pill.visible && !pill.retiring && control.reveal === 0 && frames > 5, "capsule finishes its fluid exit");
            }
            function run() {
                open(timeClock); wait(100);
                check(timeClock.popupOpen && !timerPill.retiring, "opening an already empty popup leaves it open");
                OpenPopup.dismiss();

                Timers.countdown(600000, "Tea"); Timers.countdown(1200000, "Bread"); wait(750);
                open(countdown); cancel("Tea");
                check(countdown.popupOpen && !timerPill.retiring, "another timer keeps popup open");
                cancel("Bread"); returned(timerPill, countdown, timerMorph);

                Timers.countdown(600000, "From Clock"); wait(750); open(timeClock); cancel("From Clock");
                returned(timerPill, countdown, timerMorph);

                Timers.countdown(600000, "Browsed"); wait(750);
                open(timeClock); open(countdown); cancel("Browsed");
                returned(timerPill, countdown, timerMorph);

                Timers.countdown(600000, "Bell"); wait(750); open(countdown);
                Timers.fire(Timers.entries[0]); wait(30);
                check(countdown.popupOpen && Timers.ringing.length === 1 && !timerPill.retiring,
                      "timer moving from entries into ringing does not close popup");
                Timers.hush(); wait(20); returned(timerPill, countdown, timerMorph);

                // Disabled alarms have no side pill, but removing the last one
                // from the clock popup still returns a capsule before leaving.
                Timers.entries = [{id: "alarm", kind: "alarm", hour: 7, minute: 30, days: [], running: false, label: "Morning"}];
                wait(50); open(timeClock); cancel("Morning");
                returned(timerPill, countdown, timerMorph);

                Timers.countdown(600000, "Old"); wait(750); open(countdown); cancel("Old");
                Timers.countdown(600000, "New"); wait(800);
                check(!timerPill.retiring && !countdown.exitHeld && countdown.reveal === 1 && timerPill.contentOpacity === 1,
                      "new timer cancels an empty return");
                Timers.cancel(Timers.entries[0].id); wait(750);
                check(!timerPill.visible && !timerPill.retiring, "clearing without an open popup uses normal exit");

                Timers.countdown(600000, "Leaving"); wait(750); open(countdown); cancel("Leaving");
                until(() => countdown.stowed && countdown.reveal < 0.8 && countdown.reveal > 0, "reach the empty collapse");
                Timers.countdown(600000, "Returned"); wait(800);
                check(!timerPill.retiring && countdown.reveal === 1 && timerPill.contentOpacity === 1,
                      "new timer reverses an in-progress empty collapse");
                Timers.cancel(Timers.entries[0].id); wait(750);

                open(music);
                const popup = music.popupItem;
                const quit = popup.keyTargets().find(item => item.name === "Quit music player");
                check(quit !== undefined, "real music popup has quit button");
                quit.tapped(); wait(20);
                check(popup.quitArmed && Mpd.stops === 0 && music.popupOpen, "first quit press only arms");
                quit.tapped(); wait(20);
                check(Mpd.stops === 1, "confirmed quit requests daemon shutdown once");
                returned(musicPill, music, musicMorph);

                Mpd.loaded = true; wait(750); open(music);
                Mpd.state = "pause"; wait(30);
                check(!music.popupOpen && music.stowed && !musicPill.retiring, "pause retains normal collapse behaviour");
                Mpd.state = "play"; wait(750); open(music);
                Mpd.loaded = false; wait(400); Mpd.loaded = true; wait(800);
                check(music.reveal === 1 && !musicPill.retiring && musicPill.contentOpacity === 1, "music reconnect cancels an empty return");

                Settings.set("reduceMotion", true);
                Timers.countdown(600000, "Calm"); wait(750); open(countdown); cancel("Calm");
                check(OpenPopup.owner === null && !countdown.exitHeld && !timerPill.retiring && timerMorph.value === 0,
                      "reduce motion closes without the extra return and rest");
                open(music); Mpd.loaded = false; wait(20);
                check(OpenPopup.owner === null && !music.exitHeld && !musicPill.retiring && musicMorph.value === 0,
                      "reduce motion skips music's extra return and rest too");
                console.log("PASS: empty timer and music pill exits");
            }
        }
        Timer {
            interval: 300; running: true
            onTriggered: {
                try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-empty-pill-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/Mpd.qml").write_text(MPD)
        (target / "services/Launcher.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property string taskPrefix: ""; function openWith(prefix) {} }
''')
        (target / "services/PhoneAlarms.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property string phoneWarning: ""
    signal failed(reason: string)
    signal acknowledged(id: string, firedAt: real)
    function notifyPhone(title, body, entry) {}
    function dismiss() {}
}
''')
        timers = target / "services/Timers.qml"
        timers.write_text(timers.read_text().replace('command: ["pw-play", root.alarmSound]', 'command: ["true"]'))
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=50)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "Failed to load configuration", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign")
        ok = result.returncode == 0 and "PASS: empty timer and music pill exits" in output
        ok = ok and not any(error in output for error in errors)
        print(output if not ok else "PASS: empty timer and music pill exits")
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
