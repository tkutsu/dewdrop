#!/usr/bin/env python3
"""Exercise EQ writes and recovery against an isolated MPD with a null output."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import time
import wave


SPEC = importlib.util.spec_from_file_location('equalizer', Path(__file__).with_name('mpd-equalizer.py'))
eq = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(eq)
LEGACY = 'anequalizer=' + '|'.join(
    f'c{channel} f={f} w={w} g={gain} t=0'
    for f, w, gain in [(60, 80, -2), (200, 200, 2.5), (800, 600, -1.5),
                        (3000, 2000, 3.5), (8000, 4000, 2), (14000, 4000, -1)]
    for channel in (0, 1))


class Player:
    """Restart only a private MPD process, never the user's service."""
    def __init__(self, folder):
        self.folder = folder
        self.config = folder / 'mpd.conf'
        self.socket = str(folder / 'mpd.sock')
        self.process = None
        self.fail_once = False
        self.restarts = 0
        self.config.write_text(f'''music_directory "{folder}"
playlist_directory "{folder}"
db_file "{folder}/database"
state_file "{folder}/state"
bind_to_address "{self.socket}"
restore_paused "yes"
filter {{
    plugin "ffmpeg"
    name "rock_eq"
    graph "{LEGACY}"
}}
audio_output {{
    type "null"
    name "Test output"
    mixer_type "software"
    filters "rock_eq"
}}
''')
        with wave.open(str(folder / 'test.wav'), 'wb') as audio:
            audio.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
            audio.writeframes(b'\0' * 48000 * 4 * 20)

    def start(self):
        self.process = subprocess.Popen(['mpd', '--no-daemon', str(self.config)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError(self.process.stderr.read().decode())
            try:
                with eq.contextlib.closing(eq.Mpd(self.socket)):
                    return
            except (OSError, ValueError):
                time.sleep(0.02)
        raise AssertionError('Private MPD did not start')

    def stop(self):
        if self.process is not None:
            self.process.terminate()
            self.process.wait(timeout=5)
            self.process.stderr.close()
            self.process = None

    def systemctl(self, *args):
        if args == ('is-active', '--quiet'):
            assert self.process.poll() is None
        elif args == ('restart',):
            self.restarts += 1
            if self.fail_once:
                self.fail_once = False
                raise subprocess.CalledProcessError(1, ['systemctl'])
            self.stop()
            self.start()
        else:
            raise AssertionError(args)

    def command(self, command):
        with eq.contextlib.closing(eq.Mpd(self.socket)) as player:
            return player.command(command)


def rejects(action, expected):
    try:
        action()
    except ValueError as error:
        assert expected.lower() in str(error).lower(), str(error)
    else:
        raise AssertionError('Expected rejection: ' + expected)


def main():
    for gains in ([0] * 9, [float('nan')] * 10, [True] * 10, [13] * 10, [0.1] * 10):
        rejects(lambda: eq.checked_gains(gains), 'gain' if len(gains) == 10 else 'ten')
    gains = [4, 3, 2, 0, -2, -1, 1, 3, 4, 3]
    assert eq.read_gains(eq.graph_for(gains)) == (gains, False)
    rejects(lambda: eq.read_gains(eq.graph_for(gains) + ',volume=1'), 'supported')
    print('PASS: gain limits and exact graph round trips')
    with tempfile.TemporaryDirectory(prefix='qs-mpd-equalizer-') as directory:
        player = Player(Path(directory))
        original_systemctl = eq.systemctl
        eq.systemctl = player.systemctl
        try:
            player.start()
            original = player.config.read_text()
            initial = eq.snapshot(original)
            assert initial['legacy'] and len(initial['gains']) == 10
            player.command('update')
            deadline = time.monotonic() + 5
            while 'updating_db' in player.command('status'):
                assert time.monotonic() < deadline, 'Private library update timed out'
                time.sleep(0.02)
            player.command('add "test.wav"')
            player.command('setvol 57')
            player.command('play')
            player.command('seekcur 5')
            result = eq.apply(player.config, player.socket, gains, initial['fingerprint'])
            status = player.command('status')
            assert status['state'] == 'play' and float(status['elapsed']) >= 5, status
            assert status['playlistlength'] == '1' and status['volume'] == '57', status
            assert result['gains'] == gains and not result['legacy']
            assert player.config.with_name('mpd.conf.quickshell-eq.bak').read_text() == original
            _, (a, b) = eq.target_graph(original)
            _, (c, d) = eq.target_graph(player.config.read_text())
            assert original[:a] == player.config.read_text()[:c]
            assert original[b:] == player.config.read_text()[d:]
            print('PASS: legacy migration, backup, unchanged config fields, playing song, position, queue and volume')

            player.command('pause 1')
            result = eq.apply(player.config, player.socket, [0] * 10, result['fingerprint'])
            status = player.command('status')
            assert status['state'] == 'pause' and float(status['elapsed']) >= 5, status
            print('PASS: applying Flat preserves pause and position')

            before = player.config.read_text()
            restarts = player.restarts
            rejects(lambda: eq.apply(player.config, player.socket, gains, 'old'), 'config changed')
            assert player.config.read_text() == before and player.restarts == restarts
            player.fail_once = True
            rejects(lambda: eq.apply(player.config, player.socket, gains, result['fingerprint']), 'were restored')
            assert player.config.read_text() == before
            assert player.command('status')['state'] == 'pause'
            print('PASS: stale config refuses writes; failed restart restores config and paused playback')

            player.command('stop')
            eq.apply(player.config, player.socket, gains, result['fingerprint'])
            assert player.command('status')['state'] == 'stop'
            player.command('clear')
            eq.apply(player.config, player.socket, [0] * 10, eq.snapshot(player.config.read_text())['fingerprint'])
            assert player.command('status')['playlistlength'] == '0'
            print('PASS: stopped and empty queues stay stopped')
        finally:
            eq.systemctl = original_systemctl
            player.stop()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
