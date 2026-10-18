#!/usr/bin/env python3
"""Check what counts as listening and sharing, against a made-up PipeWire graph."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import copy_shell


ROOT = Path(__file__).resolve().parents[1]

# Flags as Quickshell builds them: Audio|Source is a microphone, an app's
# capture is Audio|Stream|Source, the portal's share is Video|Source.
# Video capture streams currently have type Untracked; use their media.class.
MOCKS = {
    "Pipewire": '''property QtObject linkGroups: QtObject { property var values: [] }
    property var tracked: []
    property var commands: []
    function recordCommand(command) { commands = [...commands, command]; }''',
    "PwNodeType": '''enum Flag { Untracked = 0, Audio = 1, Video = 2, Stream = 4, Source = 8, Sink = 16, AudioSource = 9, AudioSink = 17, AudioInStream = 13, AudioOutStream = 21, VideoSource = 10 }''',
    "PwLinkState": '''enum Enum { Unlinked = -1, Paused = 3, Active = 4 }''',
}

SHELL = '''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
import qs.services as Services
import qs.testing

ShellRoot {
    id: test
    TestCase { id: readiness; when: false }

    // Plain objects: a QML object cannot have a property called `id`, and
    // PipeWire's nodes do.
    Component {
        id: audioFactory
        QtObject { property bool muted: false; property real volume: 0.75 }
    }
    function node(id, type, extra) {
        return Object.assign({ id: id, type: type, name: "", description: "", properties: {}, audio: audioFactory.createObject(test) }, extra);
    }
    Component {
        id: linkFactory
        QtObject {
            id: group
            property var source
            property var target
            property int liveState
            // Real PipeWire links expose their state only while tracked.
            readonly property int state: Pipewire.tracked.includes(group) ? liveState : PwLinkState.Unlinked
        }
    }
    function link(source, target, state) {
        return linkFactory.createObject(test, { source: source, target: target, liveState: state ?? PwLinkState.Active });
    }
    readonly property var mic: node(1, PwNodeType.AudioSource, { name: "alsa_input.mic", description: "USB Mic" })
    readonly property var speakers: node(2, PwNodeType.AudioSink, { name: "alsa_output" })
    readonly property var firefox: node(3, PwNodeType.AudioInStream, { properties: {"application.name": "Firefox"} })
    readonly property var discord: node(4, PwNodeType.AudioInStream, { properties: {"application.name": "Discord"} })
    readonly property var btInternal: node(5, PwNodeType.AudioInStream, { properties: {"media.class": "Stream/Input/Audio/Internal"} })
    readonly property var meter: node(6, PwNodeType.AudioInStream, { properties: {"application.name": "pavucontrol", "stream.monitor": "true"} })
    readonly property var recorder: node(7, PwNodeType.AudioInStream, { properties: {"application.name": "OBS"} })
    readonly property var portal: node(8, PwNodeType.VideoSource, { name: "xdph-streaming-0" })
    readonly property var chromium: node(9, PwNodeType.Untracked, { properties: {"application.name": "Chromium", "media.class": "Stream/Input/Video"} })
    readonly property var obsVideo: node(10, PwNodeType.Untracked, { properties: {"application.name": "OBS", "media.class": "Stream/Input/Video"} })
    readonly property var webcam: node(11, PwNodeType.VideoSource, { properties: {"device.api": "v4l2"} })

    readonly property var listening: link(mic, firefox)
    readonly property var held: link(mic, discord, PwLinkState.Paused)
    readonly property var internal: link(mic, btInternal)
    readonly property var metering: link(mic, meter)
    readonly property var desktopAudio: link(speakers, recorder)
    readonly property var share: link(portal, chromium)
    readonly property var shareToo: link(portal, obsVideo)
    readonly property var camera: link(webcam, chromium)

    FloatingWindow {
        id: window
        implicitWidth: 800; implicitHeight: 60
        Item { id: spot; width: 40; height: 20 }
        SidePill {
            id: recordingPill
            control: recording
            slidesContent: true
            side: Pill.Side.Right
            edgeOffset: window.width - centrePill.x + Theme.pillSpread
            Recording { id: recording; foldDuration: Theme.dropMs; foldEasing: Easing.Linear }
        }
        Pill {
            id: centrePill
            side: Pill.Side.Centre
            order: ["clock"]
            centreOn: clock.keyBox
            RECORDING_NOTE
            BarItem { id: clock; settingsKey: "clock"; BarText { text: "Clock" } }
        }
    }

    Loader { id: popupLoader; active: false; sourceComponent: PrivacyPopup { anchorItem: spot; visible: true } }

    function check(ok, message) {
        if (!ok) throw new Error(message);
    }
    function links(list) {
        Pipewire.linkGroups.values = list;
    }

    function run() {
        links([]);
        check(!Privacy.active && recording.stowed, "nothing linked, nothing recording, pill stowed");
        check(recordingNote.stowed && !recordingNote.visible, "no captures at startup leave no central icon");

        links([held, internal, metering, desktopAudio, camera]);
        check(!Privacy.active, "paused, internal, metering, desktop audio and camera links do not count");

        links([listening, held]);
        check(Privacy.listening && !Privacy.sharing && Privacy.mics.length === 1, "an active capture of a microphone counts once");
        check(Privacy.mics[0].app === "Firefox" && Privacy.mics[0].source.id === mic.id, "the app and the microphone are named");
        check(Privacy.summary === "Firefox using the microphone", "summary names the app: " + Privacy.summary);
        check(!recording.stowed, "the pill comes out");
        listening.liveState = PwLinkState.Paused;
        check(!Privacy.listening && recording.stowed, "pausing a tracked capture stows the pill");
        listening.liveState = PwLinkState.Active;
        check(Privacy.listening && !recording.stowed, "resuming the same capture reveals the pill");
        check(recording.testPulse.running, "an active recording pulses with normal motion");
        Settings.user = {reduceMotion: true};
        check(!recording.testPulse.running && recording.testDot.opacity === 1, "Reduce motion stops the recording pulse at full opacity");
        Settings.user = {};
        check(recording.testPulse.running, "restoring motion resumes the active recording pulse");
        links([]);
        check(!Privacy.active && recording.stowed, "ending a capture stows the pill");
        check(!recording.testPulse.running && recording.testDot.opacity === 1, "ending a recording stops its pulse");
        links([listening, held]);

        Privacy.toggleApp(firefox);
        check(firefox.audio.muted, "muting an app mutes its own stream");
        check(!Privacy.recording && !recording.testDot.visible && !recording.testPulse.running, "muted captures do not pulse the recording dot");
        check(Privacy.microphonesMuted && recording.testMicIcon.text === Theme.glyph.micMuted, "muting the only app changes the pill icon");
        check(Privacy.summary === "Firefox using the microphone (muted)", "the tooltip reports mute state");
        check(recording.stowed, "a muted capture merges into the central pill");
        links([listening, link(mic, discord)]);
        check(!Privacy.microphonesMuted && recording.testMicIcon.text === Theme.glyph.mic, "one unmuted app keeps the live icon");
        check(Privacy.recording && recording.testPulse.running, "one audible capture keeps the recording dot pulsing");
        check(Privacy.inputs.length === 1, "apps sharing an input get one device control");
        Privacy.toggleInput(mic);
        check(Privacy.microphonesMuted && recording.testMicIcon.text === Theme.glyph.micMuted, "input mute changes the pill for every capturing app");
        check(!Privacy.recording, "muting the input clears recording activity for all apps");
        Privacy.toggleInput(mic);
        Privacy.toggleApp(firefox);

        links([share]);
        check(Privacy.sharing && !Privacy.listening && !recording.stowed, "a screen share alone reveals the pill");
        share.liveState = PwLinkState.Paused;
        check(!Privacy.active && recording.stowed, "pausing a screen share stows the pill");
        share.liveState = PwLinkState.Active;
        check(Privacy.sharing && !recording.stowed, "resuming a screen share reveals the pill");
        share.target = null;
        check(!Privacy.sharing && recording.stowed, "a disconnected capture target safely removes its indicator");
        share.target = chromium;
        check(Privacy.sharing, "reconnecting the capture target restores its indicator");
        links([]);
        check(!Privacy.active && recording.stowed, "ending a screen share stows the pill");

        links([listening, share, shareToo, camera]);
        check(Privacy.sharing && Privacy.shares.length === 1, "one share, however many apps take it");
        check(Privacy.shares[0].apps.join() === "Chromium,OBS", "every app the share goes to is listed");
        check(Privacy.summary === "Firefox using the microphone · Chromium and OBS sharing the screen", "summary: " + Privacy.summary);
        check(Privacy.names(["A", "B", "C", "D"]) === "A, B and 2 more", "long lists are cut short");

        Privacy.stopShare(portal);
        check(Pipewire.commands.length === 1 && Pipewire.commands[0].join(" ") === "pw-cli destroy 8", "stopping destroys the portal's node");

        popupLoader.active = true;
        check(popupLoader.status === Loader.Ready, "the popup builds");
        readiness.wait(20);
        const popup = popupLoader.item;
        const micRow = popup.testMicRows.itemAt(0);
        const inputRow = popup.testInputRows.itemAt(0);
        const shareRow = popup.testShareRows.itemAt(0);
        const deviceRow = inputRow.children[0];
        const volume = inputRow.children[1].children[0];
        const micButton = micRow.control[micRow.control.length - 1];
        const inputButton = deviceRow.control[deviceRow.control.length - 1];
        check(!micRow.muted && micRow.recording && micRow.detail === "USB Mic", "microphone rows show a recording dot and the actual input");
        check(volume.value === 0.75 && deviceRow.detail === "1 app using this input", "input devices show their gain track and app count");
        readiness.mouseMove(micRow, 60, micRow.height / 2);
        readiness.wait(20);
        check(micRow.content[0].color.a === 0, "non-clickable capture entries keep a transparent hover background");
        volume.moved(0.4);
        check(mic.audio.volume === 0.4 && volume.value === 0.4, "the microphone track writes through to its input device");
        check(volume.wheelStep === 0.05 && volume.wheelSnap, "the microphone wheel uses five-percent steps");
        readiness.mouseWheel(volume, volume.width / 2, volume.height / 2, 0, -120);
        check(Math.abs(mic.audio.volume - 0.45) < 0.001, "scrolling the microphone track increases volume by five percent");
        readiness.mouseWheel(volume, volume.width / 2, volume.height / 2, 0, 120);
        check(Math.abs(mic.audio.volume - 0.4) < 0.001, "scrolling back decreases volume by five percent");
        check(shareRow.recording && shareRow.detail === "Screen capture", "share rows show a recording dot and readable capture detail");
        check(popup.testDivider.visible, "microphone and screen-share sections are separated by a rule");
        check(micRow.testDot.x === micRow.testTitle.x + micRow.testTitle.width + 6, "recording dots sit immediately after the title");
        check(Math.abs(micRow.testDot.y + micRow.testDot.height / 2 - micRow.testTitle.y - micRow.testTitle.height / 2) <= 0.5, "recording dots align vertically with title text");
        const originalTitle = micRow.title;
        micRow.title = "A microphone application with a very long title that must be shortened";
        readiness.wait(20);
        check(micRow.testDot.x + micRow.testDot.width < micButton.mapToItem(micRow, 0, 0).x, "long titles leave room for the recording dot and mute control");
        micRow.title = originalTitle;
        check(micRow.height === deviceRow.height && deviceRow.height === shareRow.height, "both lists use the same row geometry");
        micButton.tapped();
        check(micRow.muted && Privacy.microphonesMuted && micButton.label === "Unmute", "the app row mutes only its own capture and updates its action");
        inputButton.tapped();
        check(micRow.muted && deviceRow.muted && inputButton.label === "Unmute", "input mute updates both rows and the device action");
        check(deviceRow.testTitle.color.toString() === Theme.label2.toString() && deviceRow.testIcon.color.toString() === Theme.label2.toString(), "muted device names and icons use the same grey as muted apps");
        check(micRow.control.length === 1 && deviceRow.control.length === 1, "only the action button appears in each trailing column");
        check(shareRow.testDot.visible && shareRow.testPulse.running && !micRow.testDot.visible, "only the screen share pulses while every microphone is muted");
        links([listening]);
        check(!popup.testDivider.visible, "the rule disappears when there is no screen-share section");
        check(!micRow.testDot.visible && !micRow.testPulse.running, "the microphone row dot stops while muted");
        inputButton.tapped();
        micButton.tapped();
        check(micRow.testDot.visible && micRow.testPulse.running, "unmuting the microphone restores its row dot");
        volume.moved(0);
        check(!Privacy.recording && !micRow.testDot.visible, "zero input volume does not count as active recording");
        volume.moved(0.75);
        Settings.user = {reduceMotion: true};
        check(micRow.testDot.visible && !micRow.testPulse.running && micRow.testDot.opacity === 1, "the popup recording dot respects Reduce motion");
        Settings.user = {};
        links([listening, share, shareToo, camera]);
        const currentShare = popup.testShareRows.itemAt(0);
        const stopButton = currentShare.control[currentShare.control.length - 1];
        check(stopButton.name === "Stop sharing with Chromium and OBS" && stopButton.label === "Stop", "screen rows expose a labelled stop control");
        check(stopButton.framed && micButton.framed && inputButton.framed && stopButton.width === micButton.width && inputButton.width === stopButton.width && stopButton.height === micButton.height, "mute and stop controls share the same style and dimensions");
        check(Math.abs(micButton.mapToItem(micRow, 0, micButton.height / 2).y - micRow.height / 2) < 0.01, "mute buttons are vertically centered in their entries");
        check(micRow.name === "" && currentShare.name === "", "capture rows expose actions only on their buttons");
        stopButton.tapped();
        check(Pipewire.commands.length === 2 && Pipewire.commands[1].join(" ") === "pw-cli destroy 8", "the screen row's stop button ends the selected share");
        const recordingPopup = recording.popup.createObject(test, {anchorItem: spot, visible: false});
        check(recordingPopup.morphs, "the recording popup enables the shared pill morph");
        recordingPopup.destroy();
        popupLoader.active = false;

        links([listening]);
        readiness.wait(Theme.dropMs + 100);
        check(recording.reveal === 1 && recordingNote.stowed, "live capture has only a side pill");
        const centreX = clock.keyBox.mapToItem(window.contentItem, clock.keyBox.width / 2, 0).x;
        Privacy.toggleApp(firefox);
        let frames = 0;
        while (!recording.iconInCentre && frames++ < 200) {
            check(recordingNote.stowed && !recordingNote.visible, "central icon waits for absorption");
            check(recording.testMicIcon.opacity === 1, "travelling microphone stays opaque");
            readiness.wait(10);
        }
        check(frames > 5 && recording.iconInCentre, "muted microphone completes its animated handoff");
        readiness.wait(Theme.dropMs + 100);
        check(recordingNote.visible && !recordingPill.visible && recording.testMicIcon.opacity === 0,
              "muted capture leaves exactly the central icon");
        check(Math.abs(clock.keyBox.mapToItem(window.contentItem, clock.keyBox.width / 2, 0).x - centreX) <= 1,
              "privacy merge keeps the central anchor fixed");
        readiness.mouseClick(recordingNote, recordingNote.width / 2, 0);
        readiness.wait(400);
        check(recordingNote.popupOpen && recordingNote.popupItem.testMicRows.count === 1,
              "central icon opens controls for the muted capture");
        Privacy.toggleApp(firefox);
        readiness.wait(Theme.dropMs + 100);
        check(recording.reveal === 1 && !recordingNote.visible && !recordingNote.popupOpen,
              "unmuting returns the side pill and closes the central popup");

        OpenPopup.set(recording);
        readiness.wait(400);
        Privacy.toggleApp(firefox);
        check(recording.popupOpen && !recording.stowed, "muting keeps open controls accessible");
        OpenPopup.dismiss();
        readiness.wait(Theme.dropMs + 100);
        check(recordingNote.visible && !recordingPill.visible, "closing muted controls merges the pill");

        links([listening, share]);
        readiness.wait(Theme.dropMs + 100);
        check(recording.reveal === 1 && !recordingNote.visible, "screen sharing keeps the side pill with a muted microphone");
        links([]);
        readiness.wait(Theme.dropMs + 100);
        check(!recordingNote.visible && !recordingPill.visible, "ending all captures leaves no privacy icon");
        links([listening]);
        readiness.wait(Theme.dropMs + 100);
        readiness.mouseClick(recordingNote, recordingNote.width / 2, 0);
        readiness.wait(400);
        check(recordingNote.popupOpen, "muted capture controls can be reopened");
        links([]);
        readiness.wait(400);
        check(!recordingNote.visible && !recordingNote.popupOpen, "ending a muted capture hides its icon and closes its popup");
        Settings.user = {reduceMotion: true};
        links([share]); readiness.wait(Theme.dropMs + 100);
        check(recording.reveal === 1 && !recordingNote.visible, "active privacy restores with reduced motion");
        links([]); readiness.wait(Theme.dropMs + 100);
        check(!recordingNote.visible && !recordingPill.visible, "idle privacy stays hidden with reduced motion");
        console.log("PASS: privacy indicator counts live mics and screen shares only");
    }

    Timer {
        interval: 300; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-privacy-") as folder:
        target = Path(folder)
        copy_shell(target)
        recording = target / "modules/Recording.qml"
        source = recording.read_text().replace("id: root", "id: root\n    property alias testDot: dot\n    property alias testPulse: pulse\n    property alias testMicIcon: microphone", 1)
        source = source.replace("SequentialAnimation on opacity {", "SequentialAnimation on opacity {\n            id: pulse", 1)
        recording.write_text(source)
        popup = target / "components/PrivacyPopup.qml"
        popupSource = popup.read_text().replace("id: root", "id: root\n    property alias testMicRows: micRows\n    property alias testInputRows: inputRows\n    property alias testShareRows: shareRows\n    property alias testDivider: shareSection", 1)
        popupSource = popupSource.replace("id: entry", "id: entry\n        property alias testDot: statusDot\n        property alias testPulse: recordingPulse\n        property alias testTitle: line\n        property alias testIcon: leadingIcon", 1)
        popup.write_text(popupSource.replace("SequentialAnimation on opacity {", "SequentialAnimation on opacity {\n                id: recordingPulse", 1))
        service = target / "services/Privacy.qml"
        source = service.read_text().replace("import Quickshell.Services.Pipewire", "import qs.testing")
        source = source.replace('Quickshell.execDetached(["pw-cli"', 'Pipewire.recordCommand(["pw-cli"')
        service.write_text(source)
        (target / "testing").mkdir(exist_ok=True)
        for name, body in MOCKS.items():
            (target / "testing" / (name + ".qml")).write_text("pragma Singleton\nimport QtQuick\nQtObject {\n    " + body + "\n}\n")
        (target / "testing/PwObjectTracker.qml").write_text('''import QtQuick
QtObject {
    property var objects: []
    onObjectsChanged: Pipewire.tracked = objects
}
''')
        (target / "settings.json").write_text("{}\n")
        bar = (ROOT / "Bar.qml").read_text()
        start = bar.rfind("        BarItem {", 0, bar.index("id: recordingNote"))
        end = bar.rfind("        BarItem {", 0, bar.index("id: nowPlayingNote"))
        note = bar[start:end]
        (target / "shell.qml").write_text(SHELL.replace("RECORDING_NOTE", note))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"),
                   XDG_DATA_HOME=str(target / "data"), XDG_CACHE_HOME=str(target / "cache"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        ok = result.returncode == 0 and "PASS: privacy" in output and "FAIL:" not in output
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "is not a type"):
            ok = ok and error not in output
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
