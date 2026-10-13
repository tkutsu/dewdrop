#!/usr/bin/env python3
"""Exercise MPD's two connections against a private, delayed protocol fixture."""

import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading

from test_support import copy_shell, shell_env


SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    property var player: Mpd
    TestCase { id: test; when: false }
    function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
    function until(predicate, message) {
        const deadline = Date.now() + 2000;
        while (!predicate() && Date.now() < deadline) test.wait(10);
        check(predicate(), message);
    }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            check(!Mpd.connected && !Mpd.auditCommand.active && Mpd.auditCommand.tries === 0,
                "absent MPD retries only its status connection");
            Mpd.run(["play"]);
            check(Mpd.outbox.includes("play") && Mpd.auditCommand.tries === 0,
                "a command queues while MPD is absent");
            until(() => Mpd.connected && Mpd.auditCommand.connected && Mpd.outbox === "",
                "status recovery opens the command connection and flushes its outbox");
            Mpd.run(["fixture_disconnect"]);
            until(() => !Mpd.connected && !Mpd.auditCommand.active,
                "losing MPD deactivates the command connection");
            check(!Mpd.auditCommand.auditRetry.running, "command retries stop while the status connection is down");
            Mpd.run(["pause"]);
            until(() => Mpd.connected && Mpd.auditCommand.connected && Mpd.outbox === "",
                "a second recovery also delivers its queued command");
            console.log("PASS: MPD reconnects");
        } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-mpd-reconnect-") as folder:
        target = Path(folder)
        copy_shell(target)
        path = target / "mpd.sock"
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string mpdSocket: ' + json.dumps(str(path)) + '; property string musicDir: ""; property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }')
        (target / "services/Audio.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: true; function level(value, muted) { return ""; } }')
        source = (target / "services/Mpd.qml").read_text().replace("id: root", "id: root\n    property alias auditStatus: link\n    property alias auditCommand: cmdLink", 1)
        (target / "services/Mpd.qml").write_text(source)
        source = (target / "components/MpdLink.qml").read_text().replace("id: root", "id: root\n    property alias auditRetry: retry", 1).replace("5000", "50").replace("5 * 60000", "200")
        (target / "components/MpdLink.qml").write_text(source)
        (target / "shell.qml").write_text(SHELL)
        stop = threading.Event()
        disconnect = threading.Event()
        clients = []
        received = []

        def reply(client):
            try:
                client.sendall(b"OK MPD 0.24.0\n")
                for raw in client.makefile("rb"):
                    line = raw.decode().strip()
                    received.append(line)
                    if line == "fixture_disconnect":
                        disconnect.set()
                        return
                    if line == "command_list_end":
                        client.sendall(b"OK\n")
            except OSError:
                pass

        def serve():
            if stop.wait(0.5):
                return
            while not stop.is_set():
                with socket.socket(socket.AF_UNIX) as listener:
                    listener.bind(str(path))
                    listener.listen()
                    listener.settimeout(0.05)
                    while not stop.is_set() and not disconnect.is_set():
                        try:
                            client, _ = listener.accept()
                        except TimeoutError:
                            continue
                        clients.append(client)
                        threading.Thread(target=reply, args=(client,), daemon=True).start()
                path.unlink()
                for client in clients:
                    try:
                        client.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    client.close()
                clients.clear()
                disconnect.clear()
                stop.wait(0.4)

        server = threading.Thread(target=serve)
        server.start()
        try:
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=8)
        finally:
            stop.set()
            server.join(timeout=2)
        output = result.stdout + result.stderr
        print(output, end="")
        assert received.count("play") == 1 and received.count("pause") == 1, received
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop")
        return 0 if result.returncode == 0 and "PASS: MPD reconnects" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
