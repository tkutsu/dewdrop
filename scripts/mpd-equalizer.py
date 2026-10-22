#!/usr/bin/env python3
"""Read or replace an existing MPD FFmpeg EQ, with backup and restart recovery."""

import argparse
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import tempfile


FREQUENCIES = (31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\#[^\n]*|[^\s{}"#]+|[{}]')
BAND = re.compile(r'c([01]) f=([\d.]+) w=([\d.]+) g=(-?[\d.]+) t=0')


def blocks(text):
    """Retain source spans so replacing one graph preserves the rest of mpd.conf."""
    tokens = [m for m in TOKEN.finditer(text) if not m.group().startswith('#')]
    result, index = [], 0
    while index < len(tokens):
        key = tokens[index].group()
        if index + 1 >= len(tokens):
            raise ValueError("Incomplete MPD configuration.")
        if tokens[index + 1].group() != '{':
            index += 2
            continue
        index += 2
        fields = {}
        while index < len(tokens) and tokens[index].group() != '}':
            if index + 1 >= len(tokens) or tokens[index + 1].group() in ('{', '}'):
                raise ValueError("Unsupported nested or incomplete MPD configuration.")
            name, value = tokens[index:index + 2]
            if name.group() in fields:
                raise ValueError("Duplicate MPD configuration field: " + name.group())
            fields[name.group()] = (shlex.split(value.group())[0], value.span())
            index += 2
        if index >= len(tokens):
            raise ValueError("Unclosed MPD configuration block.")
        result.append((key, fields))
        index += 1
    return result


def target_graph(text):
    """Require one EQ filter attached to an output rather than guessing a target."""
    entries = blocks(text)
    attached = {name.strip() for kind, fields in entries if kind == 'audio_output'
                for name in fields.get('filters', ('', None))[0].split(',')}
    candidates = [fields for kind, fields in entries if kind == 'filter'
                  and fields.get('plugin', ('', None))[0] == 'ffmpeg'
                  and fields.get('name', ('', None))[0] in attached
                  and 'graph' in fields
                  and fields['graph'][0].startswith(('anequalizer=', 'volume='))]
    if len(candidates) != 1:
        raise ValueError("Expected one FFmpeg equalizer filter attached to an MPD output.")
    return candidates[0]['graph']


def checked_gains(value):
    """Accept exactly ten finite half-decibel values in the visible slider range."""
    if not isinstance(value, list) or len(value) != 10:
        raise ValueError("The equalizer needs ten gains.")
    if any(type(g) not in (int, float) or not math.isfinite(g) or not -12 <= g <= 12
           or abs(g * 2 - round(g * 2)) > 1e-6 for g in value):
        raise ValueError("Gains must be between -12 and +12 dB in half-decibel steps.")
    return value


def graph_for(gains):
    """Leave boost headroom and limit overlapping peaks without auto makeup gain."""
    checked_gains(gains)
    preamp = -(max(0, *gains) + 1) if any(gains) else 0
    filters = [f'volume={preamp:g}dB']
    filters.extend(f'equalizer=f={f:g}:t=o:w=1:g={g:g}' for f, g in zip(FREQUENCIES, gains))
    filters.append('alimiter=limit=1:level=false:latency=true')
    return ','.join(filters)


def read_gains(graph):
    """Recognize our ten bands or preview the existing stereo anequalizer curve."""
    if graph.startswith('volume='):
        pieces = graph.split(',')
        if len(pieces) != 12:
            raise ValueError("The existing FFmpeg graph is not a supported ten-band EQ.")
        gains = []
        for frequency, piece in zip(FREQUENCIES, pieces[1:-1]):
            prefix = f'equalizer=f={frequency:g}:t=o:w=1:g='
            if not piece.startswith(prefix):
                raise ValueError("The existing EQ uses different frequency bands.")
            gains.append(float(piece[len(prefix):]))
        checked_gains(gains)
        if graph_for(gains) != graph:
            raise ValueError("The existing EQ has other processing; it was left unchanged.")
        return gains, False
    channels = ({}, {})
    for piece in graph.removeprefix('anequalizer=').split('|'):
        match = BAND.fullmatch(piece)
        if not match:
            raise ValueError("The existing FFmpeg graph is not a supported stereo EQ.")
        channel, frequency, width, gain = map(float, match.groups())
        if frequency <= 0 or width <= 0 or not math.isfinite(gain) or not -12 <= gain <= 12:
            raise ValueError("The existing EQ has unsupported band values.")
        if frequency in channels[int(channel)]:
            raise ValueError("The existing EQ has duplicate bands.")
        channels[int(channel)][frequency] = (width, gain)
    if not channels[0] or channels[0] != channels[1]:
        raise ValueError("The existing EQ must use the same bands in both channels.")
    points = sorted((f, pair[1]) for f, pair in channels[0].items())
    gains = []
    for frequency in FREQUENCIES:
        gain = points[0][1] if frequency < points[0][0] else points[-1][1]
        for (a, ga), (b, gb) in zip(points, points[1:]):
            if a <= frequency <= b:
                gain = ga + (gb - ga) * math.log(frequency / a) / math.log(b / a)
                break
        gains.append(round(gain * 2) / 2)
    return gains, True


def snapshot(text):
    graph, _ = target_graph(text)
    gains, legacy = read_gains(graph)
    return dict(gains=gains, legacy=legacy, fingerprint=hashlib.sha256(text.encode()).hexdigest())


def atomic_write(path, text, mode):
    """Replace a file only after its complete contents have reached disk."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.' + path.name,
                                         delete=False) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), mode)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


class Mpd:
    """Use the local socket to preserve playback without adding an MPD library."""
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(path)
        self.stream = self.socket.makefile('rwb', buffering=0)
        if not self.stream.readline().startswith(b'OK MPD '):
            raise ValueError("MPD did not send its greeting.")

    def close(self):
        self.stream.close()
        self.socket.close()

    def command(self, command):
        self.stream.write((command + '\n').encode())
        reply = {}
        while True:
            line = self.stream.readline().decode().rstrip('\n')
            if line == 'OK':
                return reply
            if not line or line.startswith('ACK '):
                raise ValueError("MPD refused an equalizer playback command: " + line)
            key, _, value = line.partition(': ')
            reply[key] = value


def systemctl(*args):
    return subprocess.run(['systemctl', '--user', *args, 'mpd.service'], check=True,
                          capture_output=True, text=True, timeout=25)


def restore_playback(path, status, song):
    """Resume the same song and preserve pause/stop even with restore_paused set."""
    with contextlib.closing(Mpd(path)) as player:
        current = player.command('currentsong')
        if status['state'] == 'stop':
            player.command('stop')
            return
        if not song.get('file') or current.get('file') != song['file']:
            raise ValueError("MPD did not restore the same song after restarting.")
        player.command('pause 1')
        if float(status.get('duration', '0')) > 0:
            player.command('seekcur ' + str(float(status.get('elapsed', '0'))))
        if status['state'] == 'play':
            player.command('pause 0')


def apply(config, socket_path, gains, fingerprint):
    """Validate before saving; restore the config and playback if restart fails."""
    original = config.read_text()
    if snapshot(original)['fingerprint'] != fingerprint:
        raise ValueError("MPD config changed. Reset to reload it before applying.")
    graph = graph_for(gains)
    _, (start, end) = target_graph(original)
    replacement = original[:start] + json.dumps(graph) + original[end:]
    # Validate the actual DSP graph without touching the running player.
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
                    '-af', graph, '-t', '0.02', '-f', 'null', '-'], check=True,
                   capture_output=True, timeout=10)
    systemctl('is-active', '--quiet')
    with contextlib.closing(Mpd(socket_path)) as player:
        status, song = player.command('status'), player.command('currentsong')
    # MPD needs its own state file to restore the queue on restart.
    state_fields = [m for m in TOKEN.finditer(original) if not m.group().startswith('#')]
    if not any(t.group() == 'state_file' for t in state_fields):
        raise ValueError("MPD needs a state_file to preserve the queue across EQ changes.")
    if config.read_text() != original:
        raise ValueError("MPD config changed while applying. Reset to reload it.")
    mode = config.stat().st_mode & 0o777
    atomic_write(config.with_name(config.name + '.quickshell-eq.bak'), original, mode)
    atomic_write(config, replacement, mode)
    try:
        systemctl('restart')
        restore_playback(socket_path, status, song)
    except Exception as error:
        if config.read_text() != replacement:
            raise ValueError("EQ failed and MPD config changed again. The current file was left untouched; the previous config is in .quickshell-eq.bak.") from error
        atomic_write(config, original, mode)
        try:
            systemctl('restart')
            restore_playback(socket_path, status, song)
        except Exception:
            raise ValueError("EQ failed. The config was restored, but MPD could not recover. Check mpd.service.") from error
        raise ValueError("EQ failed. The previous config and playback were restored.") from error
    return snapshot(replacement)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['read', 'apply'])
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--socket', required=True)
    parser.add_argument('--gains')
    parser.add_argument('--fingerprint')
    args = parser.parse_args()
    try:
        config = args.config.expanduser().resolve(strict=True)
        if args.action == 'read':
            result = snapshot(config.read_text())
        else:
            result = apply(config, args.socket, checked_gains(json.loads(args.gains)), args.fingerprint)
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
        message = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            message = "Equalizer command failed: " + error.cmd[0] + ". " + (error.stderr or '').strip()[:400]
        print(json.dumps({'error': message}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
