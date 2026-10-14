#!/usr/bin/env python3
"""Check full-track envelopes and detected onsets without changing playback."""

import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/music-waveform.py"


def analyze(path):
    """Run the same decoder command the popover uses."""
    result = subprocess.run(["python3", "-I", str(HELPER), str(path)], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def write_song(path, sound):
    """Make a known local waveform with 20 ms analysis boundaries."""
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(struct.pack("<16000h", *[round(sound(index / 8000) * 32767) for index in range(16000)]))


def main():
    """Prove the bars retain dynamics, beat times and silence."""
    with tempfile.TemporaryDirectory(prefix="qs-waveform-analysis-") as folder:
        song = Path(folder) / "track #1.wav"
        hits = [0.5, 1.0, 1.5]
        write_song(song, lambda at: 0.8 * math.sin(2 * math.pi * 200 * at) if any(hit <= at < hit + 0.08 for hit in hits) else 0)
        result = analyze(song)
        assert len(result["bars"]) == 256 and result["duration"] == 2
        assert min(result["bars"]) == 0 and max(result["bars"]) == 1
        assert all(0 <= value <= 1 for value in result["bars"])
        assert len(result["beats"]) == len(hits), result["beats"]
        assert all(abs(actual - expected) <= 0.02 for actual, expected in zip(result["beats"], hits)), result["beats"]
        write_song(song, lambda at: (0.2 if at < 1 else 0.8) * math.sin(2 * math.pi * 200 * at))
        dynamics = analyze(song)["bars"]
        assert 0.1 < dynamics[32] < 0.25 and dynamics[224] > 0.95, dynamics
        write_song(song, lambda at: 0)
        silence = analyze(song)
        assert silence["bars"] == [0] * 256 and silence["beats"] == []
        missing = subprocess.run(["python3", "-I", str(HELPER), str(Path(folder) / "missing.wav")], capture_output=True, timeout=2)
        assert missing.returncode == 2 and not missing.stdout
        print("PASS: full-song bars, detected onset timing, silence, special filenames and missing-file fallback")


if __name__ == "__main__":
    main()
