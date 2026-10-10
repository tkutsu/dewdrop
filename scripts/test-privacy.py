#!/usr/bin/env python3
"""Check what counts as listening and sharing, against a made-up PipeWire graph."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

# Flags as Quickshell builds them: Audio|Source is a microphone, an app's
# capture is Audio|Stream|Source, the portal's share is Video|Source.
MOCKS = {
    "Pipewire": '''property QtObject linkGroups: QtObject { property var values: [] }
    property var commands: []
    function recordCommand(command) { commands = [...commands, command]; }''',
    "PwNodeType": '''enum Flag { Audio = 1, Video = 2, Stream = 4, Source = 8, Sink = 16, AudioSource = 9, AudioSink = 17, AudioInStream = 13, AudioOutStream = 21, VideoSource = 10 }''',
    "PwLinkState": '''enum Enum { Paused = 5, Active = 6 }''',
}

SHELL = '''import QtQuick
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
import qs.testing

ShellRoot {
    id: test

    // Plain objects: a QML object cannot have a property called `id`, and
    // PipeWire's nodes do.
    function node(id, type, extra) {
        return Object.assign({ id: id, type: type, name: "", description: "", properties: {}, audio: { muted: false } }, extra);
    }
    function link(source, target, state) {
        return { source: source, target: target, state: state ?? PwLinkState.Active };
    }
    readonly property int videoStream: PwNodeType.Video | PwNodeType.Stream | PwNodeType.Sink
    readonly property var mic: node(1, PwNodeType.AudioSource, { name: "alsa_input.mic", description: "USB Mic" })
    readonly property var speakers: node(2, PwNodeType.AudioSink, { name: "alsa_output" })
    readonly property var firefox: node(3, PwNodeType.AudioInStream, { properties: {"application.name": "Firefox"} })
    readonly property var discord: node(4, PwNodeType.AudioInStream, { properties: {"application.name": "Discord"} })
    readonly property var btInternal: node(5, PwNodeType.AudioInStream, { properties: {"media.class": "Stream/Input/Audio/Internal"} })
    readonly property var meter: node(6, PwNodeType.AudioInStream, { properties: {"application.name": "pavucontrol", "stream.monitor": "true"} })
    readonly property var recorder: node(7, PwNodeType.AudioInStream, { properties: {"application.name": "OBS"} })
    readonly property var portal: node(8, PwNodeType.VideoSource, { name: "xdph-streaming-0" })
    readonly property var chromium: node(9, videoStream, { properties: {"application.name": "Chromium"} })
    readonly property var obsVideo: node(10, videoStream, { properties: {"application.name": "OBS"} })
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
        implicitWidth: 300; implicitHeight: 60
        Item { id: spot; width: 40; height: 20 }
        Recording { id: pill }
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
        check(!Privacy.active && pill.stowed, "nothing linked, nothing recording, pill stowed");

        links([held, internal, metering, desktopAudio, camera]);
        check(!Privacy.active, "paused, internal, metering, desktop audio and camera links do not count");

        links([listening, held]);
        check(Privacy.listening && !Privacy.sharing && Privacy.mics.length === 1, "an active capture of a microphone counts once");
        check(Privacy.mics[0].app === "Firefox" && Privacy.mics[0].source === mic, "the app and the microphone are named");
        check(Privacy.summary === "Firefox using the microphone", "summary names the app: " + Privacy.summary);
        check(!pill.stowed, "the pill comes out");

        Privacy.toggleApp(firefox);
        check(firefox.audio.muted, "muting an app mutes its own stream");
        Privacy.toggleApp(firefox);

        links([listening, share, shareToo, camera]);
        check(Privacy.sharing && Privacy.shares.length === 1, "one share, however many apps take it");
        check(Privacy.shares[0].apps.join() === "Chromium,OBS", "every app the share goes to is listed");
        check(Privacy.summary === "Firefox using the microphone · Chromium and OBS sharing the screen", "summary: " + Privacy.summary);
        check(Privacy.names(["A", "B", "C", "D"]) === "A, B and 2 more", "long lists are cut short");

        Privacy.stopShare(portal);
        check(Pipewire.commands.length === 1 && Pipewire.commands[0].join(" ") === "pw-cli destroy 8", "stopping destroys the portal's node");

        popupLoader.active = true;
        check(popupLoader.status === Loader.Ready, "the popup builds");
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
        files = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True)
        for name in files.splitlines():
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        service = target / "services/Privacy.qml"
        source = service.read_text().replace("import Quickshell.Services.Pipewire", "import qs.testing")
        source = source.replace('Quickshell.execDetached(["pw-cli"', 'Pipewire.recordCommand(["pw-cli"')
        start = source.index("    PwObjectTracker {")
        source = source[:start] + source[source.index("    }\n", start) + 6:]
        service.write_text(source)
        (target / "testing").mkdir(exist_ok=True)
        for name, body in MOCKS.items():
            (target / "testing" / (name + ".qml")).write_text("pragma Singleton\nimport QtQuick\nQtObject {\n    " + body + "\n}\n")
        (target / "settings.json").write_text("{}\n")
        (target / "shell.qml").write_text(SHELL)
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
