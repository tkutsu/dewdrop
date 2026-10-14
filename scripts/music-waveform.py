"""Decode a local song into a compact waveform and audio onset times."""

import json
import math
from pathlib import Path
import signal
import struct
import subprocess
import sys

RATE = 8000
WINDOW = 160
BARS = 256


def summarize(levels, duration):
    """Preserve the song's envelope and detect strong rises for beat pulses."""
    bars = []
    for index in range(BARS):
        start = index * len(levels) // BARS
        end = max(start + 1, (index + 1) * len(levels) // BARS)
        values = levels[start:end]
        bars.append(math.sqrt(sum(value * value for value in values) / len(values)) if values else 0)
    highest = max(bars, default=0)
    bars = [round((value / highest) ** 1.25, 4) if highest else 0 for value in bars]
    beats = []
    baseline = 0
    previous = 0
    threshold = max(0.008, max(levels, default=0) * 0.035)
    for index, level in enumerate(levels):
        at = index * WINDOW / RATE
        if level > max(0.01, baseline * 1.4) and level - previous > threshold and (not beats or at - beats[-1] >= 0.18):
            beats.append(round(at, 3))
        baseline += (level - baseline) * 0.08
        previous = level
    return {"bars": bars, "beats": beats, "duration": duration}


def main():
    """Decode without playback and reap ffmpeg when the popup cancels work."""
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_file():
        return 2
    decoder = subprocess.Popen([
        "ffmpeg", "-v", "error", "-nostdin", "-threads", "1", "-i", sys.argv[1],
        "-map", "0:a:0", "-vn", "-ac", "1", "-ar", str(RATE), "-f", "f32le", "pipe:1"
    ], stdout=subprocess.PIPE)

    def stop(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    levels = []
    total = 0
    try:
        while data := decoder.stdout.read(WINDOW * 4):
            count = len(data) // 4
            if not count:
                break
            samples = struct.unpack(f"<{count}f", data[:count * 4])
            samples = [value if math.isfinite(value) else 0 for value in samples]
            levels.append(math.sqrt(sum(value * value for value in samples) / count))
            total += count
        if decoder.wait() != 0:
            return 1
        print(json.dumps(summarize(levels, total / RATE), separators=(",", ":")))
    finally:
        if decoder.poll() is None:
            decoder.terminate()
        try:
            decoder.wait(timeout=1)
        except subprocess.TimeoutExpired:
            decoder.kill()
            decoder.wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
