#!/usr/bin/env python3
"""A stopped mpd is not dialled, so it fills no log with socket errors; and
an mpd that comes up is still found."""

import socket
import subprocess
import tempfile
import threading
import time

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.components
ShellRoot {
    MpdLink { id: a; path: Quickshell.shellPath("mpd.sock") }
    MpdLink { id: b; path: Quickshell.shellPath("mpd.sock") }
    // The quick retries come every five seconds: two of them pass with no
    // socket, then one appears and dialNow finds it.
    Timer { interval: 11500; running: true; onTriggered: { a.dialNow(); b.dialNow(); } }
    Timer { interval: 13000; running: true; onTriggered: {
        console.log("CONNECTED " + a.connected + " " + b.connected);
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-mpd-quiet-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        path = target / "mpd.sock"

        def serve():
            time.sleep(11)
            server = socket.socket(socket.AF_UNIX)
            server.bind(str(path))
            server.listen(4)
            server.settimeout(5)
            held = []
            try:
                while True:
                    connection, _ = server.accept()
                    connection.sendall(b"OK MPD 0.24.0\n")
                    held.append(connection)
            except OSError:
                time.sleep(5)

        threading.Thread(target=serve, daemon=True).start()
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        warnings = output.count("quickshell.io.socket")
        print(f"socket warnings while mpd was away: {warnings}")
        print("\n".join(line for line in output.splitlines() if "CONNECTED" in line))
        assert warnings == 0, output
        assert "CONNECTED true true" in output, output


if __name__ == "__main__":
    main()
