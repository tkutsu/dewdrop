#!/usr/bin/env python3
"""Check MPD add commands without connecting to the live player."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SHELL = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    function check(ok, message) { if (!ok) throw Error(message); }
    function commands(expected, message) {
        check(Mpd.outbox === "command_list_begin\\n" + expected.join("\\n") + "\\ncommand_list_end\\n", message + ": " + Mpd.outbox);
    }
    Timer { interval: 10; running: true; onTriggered: {
        try {
            Mpd.queue = []; Mpd.state = "stop";
            Mpd.enqueue(["first.flac"], "queue");
            commands(['add "first.flac"', "play"], "first queued track starts playing after it is added");
            Mpd.enqueue(["first.flac", "second.flac"], "queue");
            commands(['add "first.flac"', 'add "second.flac"', "play"], "an empty queue starts after all files are added");
            Mpd.loadPlaylist("Saved", "queue");
            commands(['load "Saved"', "play"], "loading a playlist into an empty queue starts playback");
            Mpd.queue = [{pos: 0, title: "Existing"}];
            for (const state of ["stop", "pause", "play"]) {
                Mpd.state = state;
                Mpd.enqueue(["next.flac"], "queue");
                commands(['add "next.flac"'], "appending preserves existing " + state + " playback");
                Mpd.loadPlaylist("Saved", "queue");
                commands(['load "Saved"'], "appending a playlist preserves existing " + state + " playback");
            }
            Mpd.enqueue(["new.flac"], "play");
            commands(["clear", 'add "new.flac"', "play"], "explicit play still replaces the queue and starts playback");
            Mpd.loadPlaylist("Saved", "play");
            commands(["clear", 'load "Saved"', "play"], "explicit playlist play still replaces the queue");
            Mpd.outbox = ""; Mpd.queue = [];
            Mpd.enqueue([], "queue"); Mpd.loadPlaylist("", "queue");
            check(Mpd.outbox === "", "empty selections do not start playback");
            console.log("PASS: MPD empty-queue autoplay and append behavior");
        } catch (error) { console.log("FAIL: " + error); }
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-mpd-enqueue-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "components/MpdLink.qml").write_text('''import QtQuick
QtObject {
    property string path: ""
    property bool active: true
    readonly property bool connected: false
    signal line(string line)
    function write(text) {}
    function wake() {}
    function dialNow() {}
}
''')
        (target / "services/Audio.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: true; function level(value, muted) { return ""; } }\n')
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: MPD empty-queue autoplay" in output
        ok = ok and not any(error in output for error in errors)
        print("PASS: MPD empty-queue autoplay and append behavior" if ok else output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
