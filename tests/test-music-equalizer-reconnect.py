#!/usr/bin/env python3
"""Apply the real EQ to a private MPD while its real music popup stays open."""

import importlib.util
import json
from pathlib import Path
from test_support import fixture_root
import socket
import subprocess
import tempfile
import threading
import time

from test_support import copy_shell, shell_env


SPEC = importlib.util.spec_from_file_location('eq_test', Path(__file__).with_name('test-mpd-equalizer.py'))
fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture)

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.modules
import qs.src.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 100
        SidePill {
            id: pill; control: music; side: Pill.Side.Right; edgeOffset: 30
            closeWhenEmpty: true
            empty: MUSIC_EMPTY
            Music { id: music }
        }
    }
    TestCase {
        id: test; when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function run() {
            tryVerify(() => Mpd.connected && Mpd.loaded && Mpd.state === "play", 3000);
            wait(800);
            OpenPopup.set(music);
            tryVerify(() => music.popupItem !== null);
            const popup = music.popupItem;
            popup.equalizerOpen = true;
            tryVerify(() => MpdEqualizer.ready && !MpdEqualizer.busy, 3000);
            for (let attempt = 0; attempt < 2; attempt++) {
                MpdEqualizer.choose(attempt === 0 ? "Rock" : "Flat");
                MpdEqualizer.apply();
                let disconnected = false;
                const deadline = Date.now() + 3500;
                while (Date.now() < deadline) {
                    disconnected = disconnected || !Mpd.connected;
                    check(OpenPopup.owner === music && music.popupItem === popup
                        && popup.equalizerOpen && !music.stowed && pill.visible,
                        "EQ apply preserves popup, equalizer view and music pill");
                    if (disconnected && !MpdEqualizer.busy && Mpd.connected && !(Mpd.reconfiguring ?? false)) break;
                    wait(20);
                }
                check(disconnected, "private MPD actually disconnects during Apply");
                check(!MpdEqualizer.busy && MpdEqualizer.error === "" && Mpd.connected && Mpd.state === "play",
                    "Apply reconnects promptly and restores playback");
            }
            Mpd.stopServer();
            tryVerify(() => !Mpd.connected, 3000);
            tryVerify(() => OpenPopup.owner === null && music.stowed, 2000);
            check(true, "a real stop still dismisses music");
            console.log("DONE: equalizer reconnect");
        }
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log("FAIL: " + error); }
        OpenPopup.dismiss(); Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='qs-eq-reconnect-') as directory:
        target = fixture_root(directory)
        copy_shell(target)
        player = fixture.Player(target)
        control = target / 'control.sock'
        # Only systemctl is substituted: graph validation, restart, restore and UI are real.
        implementation = target / 'scripts/equalizer_impl.py'
        implementation.write_text((target / 'scripts/mpd-equalizer.py').read_text())
        (target / 'scripts/mpd-equalizer.py').write_text('''import importlib.util, json, socket
from pathlib import Path
spec = importlib.util.spec_from_file_location("implementation", Path(__file__).with_name("equalizer_impl.py"))
eq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(eq)
def systemctl(*args):
    with socket.socket(socket.AF_UNIX) as client:
        client.connect(''' + repr(str(control)) + ''')
        client.sendall(json.dumps(args).encode())
        if client.recv(1024) != b"OK": raise OSError("private MPD control failed")
eq.systemctl = systemctl
raise SystemExit(eq.main())
''')
        source = target / 'src/services/Mpd.qml'
        source.write_text(source.read_text().replace(
            'Quickshell.execDetached(["systemctl", "--user", "stop", "mpd.service"]);',
            'Quickshell.execDetached(["python3", "-c", ' + json.dumps(
                f'import socket; s=socket.socket(socket.AF_UNIX); s.connect({str(control)!r}); s.sendall(b\'["stop"]\'); s.recv(1024)') + ']);'))
        (target / 'settings.json').write_text(json.dumps({'mpdConfig': str(player.config), 'mpdSocket': player.socket}))
        (target / 'src/services/Audio.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: true; function level(v, m) { return ""; } }')
        empty = next(line.split('empty:', 1)[1].strip() for line in
                     (target / 'src/bar/Bar.qml').read_text().splitlines() if 'empty: !Services.Mpd.connected' in line)
        (target / 'shell.qml').write_text(SHELL.replace('MUSIC_EMPTY', empty.replace('Services.Mpd', 'Mpd')))
        stop = threading.Event()
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(control))
            listener.listen()
            listener.settimeout(0.1)

            def serve():
                while not stop.is_set():
                    try:
                        client, _ = listener.accept()
                    except TimeoutError:
                        continue
                    with client:
                        args = tuple(json.loads(client.recv(1024)))
                        if args == ('stop',):
                            player.stop()
                        else:
                            if args == ('restart',):
                                player.stop()
                                time.sleep(0.15)
                            player.systemctl(*args)
                        try:
                            client.sendall(b'OK')
                        except BrokenPipeError:
                            pass  # The UI may exit while a failing Apply is still unwinding.

            try:
                player.start()
                player.command('update')
                deadline = time.monotonic() + 3
                while 'updating_db' in player.command('status'):
                    assert time.monotonic() < deadline
                    time.sleep(0.02)
                player.command('add "test.wav"')
                player.command('play')
                server = threading.Thread(target=serve)
                server.start()
                result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target),
                                        capture_output=True, text=True, timeout=15)
            finally:
                stop.set()
                if 'server' in locals():
                    server.join(timeout=5)
                player.stop()
        output = result.stdout + result.stderr
        lines = [line for line in output.splitlines() if any(s in line for s in ('PASS:', 'FAIL:', 'DONE:', 'Error:', 'Binding loop'))]
        print('\n'.join(dict.fromkeys(lines)))
        if 'DONE: equalizer reconnect' not in output:
            print(output[-5000:])
        return 0 if result.returncode == 0 and 'DONE: equalizer reconnect' in output and not any(
            error in output for error in ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign')) else 1


if __name__ == '__main__':
    raise SystemExit(main())
