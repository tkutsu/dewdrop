#!/usr/bin/env python3
"""With no Pulse server the event feed backs off, and a boosted level is never
cut back by a step up."""

import os
import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

SHELL = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    // The singleton comes up when first touched: here, at the start.
    readonly property bool started: Audio.connected || true
    function check(ok, message) {
        console.log((ok ? "PASS: " : "FAIL: ") + message);
    }
    QtObject { id: node; property QtObject audio: QtObject { property real volume: 1.55; property bool muted: true } }
    Timer {
        interval: 7000; running: true
        onTriggered: {
            Audio.stepNode(node, true);
            check(Math.round(node.audio.volume * 100) === 155 && !node.audio.muted, "up from 155% stays at 155% (and unmutes)");
            Audio.stepNode(node, false);
            check(Math.round(node.audio.volume * 100) === 150, "down from 155% goes to 150%");
            node.audio.volume = 0.98;
            Audio.stepNode(node, true);
            check(Math.round(node.audio.volume * 100) === 100, "up from 98% stops at 100%");
            Qt.quit();
        }
    }
}
'''

# A pactl that answers nothing, as with no server: `list` prints nothing and
# `subscribe` exits at once. Each run is logged.
PACTL = '''#!/bin/sh
echo "$*" >> "$(dirname "$0")/pactl.log"
exit 1
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-audio-retry-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SHELL)
        (target / "pactl").write_text(PACTL)
        (target / "pactl").chmod(0o700)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target, PATH=str(target) + os.pathsep + os.environ["PATH"]),
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line))
        log = (target / "pactl.log").read_text().splitlines() if (target / "pactl.log").exists() else []
        subscribes = sum(line == "subscribe" for line in log)
        print(f"pactl subscribe ran {subscribes} times in 7 s")
        # 1 s, 2 s, 4 s: four runs at most, where a fixed second gave seven.
        assert 2 <= subscribes <= 4, f"subscribe ran {subscribes} times: no backoff"
        assert output.count("PASS:") == 3 and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
