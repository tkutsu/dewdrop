#!/usr/bin/env python3
"""Check waveform dynamics and independent bass, mid and treble reactions."""

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
    """Make two seconds of known audio, including frequencies above 4 kHz."""
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes(struct.pack("<48000h", *[round(sound(index / 24000) * 32767) for index in range(48000)]))


def peak(result, band, start, end):
    """Measure the strongest response in a known event interval."""
    return max(frame[band] for index, frame in enumerate(result["reactions"]) if start <= index * result["step"] < end)


def main():
    """Prove dynamics, band separation, spaced treble attacks and silence."""
    with tempfile.TemporaryDirectory(prefix="qs-waveform-analysis-") as folder:
        song = Path(folder) / "track #1.wav"
        hits = [0.5, 1.14, 1.78]
        write_song(song, lambda at: 0.8 * math.sin(2 * math.pi * 200 * at) if any(hit <= at < hit + 0.08 for hit in hits) else 0)
        result = analyze(song)
        assert len(result["bars"]) == 256 and result["duration"] == 2
        assert min(result["bars"]) == 0 and max(result["bars"]) == 1
        assert all(0 <= value <= 1 for value in result["bars"])
        assert all(peak(result, 0, hit, hit + 0.05) > 0.6 for hit in hits), result["reactions"]
        assert all(len(frame) == 3 and all(0 <= value <= 1 for value in frame) for frame in result["reactions"])
        for band, frequency in enumerate((100, 1200, 7000)):
            write_song(song, lambda at: 0.6 * math.sin(2 * math.pi * frequency * at) if 0.5 <= at < 0.6 else 0)
            response = analyze(song)
            strengths = [peak(response, other, 0.49, 0.56) for other in range(3)]
            assert strengths[band] > 0.7, (frequency, strengths)
            assert all(strengths[other] < 0.35 for other in range(3) if other != band), (frequency, strengths)
            assert peak(response, band, 1.4, 1.6) < 0.02, "reactions settle after the sound"
        write_song(song, lambda at: 0.5 * math.sin(2 * math.pi * 100 * at)
                   + (0.08 * math.sin(2 * math.pi * 7000 * at) if any(hit <= at < hit + 0.025 for hit in (0.5, 0.62, 0.82, 0.98, 1.14)) else 0))
        layered = analyze(song)
        assert all(peak(layered, 2, hit - layered["step"], hit + 0.05) > 0.65 for hit in (0.5, 1.14)), layered["reactions"]
        assert peak(layered, 2, 0.62 - layered["step"], 0.67) < 0.4, "a nearby hit waits for the next swell window"
        assert peak(layered, 2, 0.82 - layered["step"], 0.87) < 0.3, "a hit after 320 ms still waits for the next swell"
        assert peak(layered, 2, 0.98 - layered["step"], 1.03) < 0.3, "a hit after 480 ms still waits for the 500 ms interval"
        assert peak(layered, 2, 0.25, 0.4) < 0.05, "sustained bass does not trigger treble"
        write_song(song, lambda at: (0.2 if at < 1 else 0.8) * math.sin(2 * math.pi * 200 * at))
        dynamics = analyze(song)["bars"]
        assert 0.1 < dynamics[32] < 0.25 and dynamics[224] > 0.95, dynamics
        write_song(song, lambda at: 0)
        silence = analyze(song)
        assert silence["bars"] == [0] * 256 and all(frame == [0, 0, 0] for frame in silence["reactions"])
        missing = subprocess.run(["python3", "-I", str(HELPER), str(Path(folder) / "missing.wav")], capture_output=True, timeout=2)
        assert missing.returncode == 2 and not missing.stdout
        print("PASS: waveform dynamics, independent bands, quiet treble over bass, swell spacing, decay, silence and missing-file fallback")


if __name__ == "__main__":
    main()
