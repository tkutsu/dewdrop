"""Decode a local song into a waveform and three audio reaction envelopes."""

import json
import math
from pathlib import Path
import signal
import subprocess
import sys

RATE = 24000
WINDOW = 512
BARS = 256
STEP = WINDOW / RATE
SWELL_INTERVAL = 0.5


def summarize(levels, frames, duration):
    """Keep the song shape and follow normalized bass, mid and treble flux."""
    bars = []
    for index in range(BARS):
        start = index * len(levels) // BARS
        end = max(start + 1, (index + 1) * len(levels) // BARS)
        values = levels[start:end]
        bars.append(math.sqrt(sum(value * value for value in values) / len(values)) if values else 0)
    highest = max(bars, default=0)
    bars = [round((value / highest) ** 1.25, 4) if highest else 0 for value in bars]
    reactions = []
    peaks = [0.0] * 3
    flux_peaks = [0.0] * 3
    previous = [0.0] * 3
    envelope = [0.0] * 3
    last_swell = [-math.inf] * 3
    floor = max(0.001, max(levels, default=0) * 0.015)
    for index, frame in enumerate(frames):
        for band, (level, flux) in enumerate(frame):
            peaks[band] = max(floor, level, peaks[band] * math.exp(-STEP / 1.5))
            flux_peaks[band] = max(0.00001, flux, flux_peaks[band] * math.exp(-STEP / 1.5))
            # Flux includes falling edges; only animate audible, non-falling energy.
            onset = flux / flux_peaks[band] if level >= previous[band] * 0.95 else 0
            audible = level >= max(floor, levels[index] * 0.1)
            # Space out new attacks independently; let existing swells fade normally.
            at = index * STEP
            if audible and onset > 0.35 and at - last_swell[band] >= SWELL_INTERVAL:
                last_swell[band] = at
            if at - last_swell[band] > 0.04:
                onset = 0
            target = min(1, 0.15 * level / peaks[band] + 0.85 * onset) if audible else 0
            seconds = 0.008 if target > envelope[band] else (0.18, 0.12, 0.08)[band]
            envelope[band] += (target - envelope[band]) * (1 - math.exp(-STEP / seconds))
            previous[band] = level
        reactions.append([round(value, 4) for value in envelope])
    return {"bars": bars, "reactions": reactions, "step": STEP, "duration": duration}


def read_frames(lines):
    """Read native FFmpeg spectral flux and RMS measurements per analysis hop."""
    frame = {}
    for line in lines:
        if line.startswith("frame:"):
            if frame:
                yield frame
            frame = {}
        elif "=" in line:
            key, value = line.strip().split("=", 1)
            number = float(value)
            frame[key] = number if math.isfinite(number) else -math.inf if key.endswith("RMS_level") else 0
    if frame:
        yield frame


def main():
    """Decode without playback and reap ffmpeg when the popup cancels work."""
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_file():
        return 2
    # Keep the full-band RMS for the seek waveform; analyze three crossover bands
    # with Hann-windowed, 50%-overlapping FFTs in FFmpeg rather than Python.
    filters = (
        f"[0:a:0]aformat=channel_layouts=mono,aresample={RATE},asplit=2[dry][bands];"
        "[bands]acrossover=split='250 4000':order=4th[bass][mid][treble];"
        "[dry][bass][mid][treble]join=inputs=4:channel_layout=4.0:"
        "map=0.0-FL|1.0-FR|2.0-FC|3.0-BC,"
        f"aspectralstats=win_size={WINDOW * 2}:overlap=0.5:measure=flux,"
        "astats=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=Number_of_samples,"
        "ametadata=print:file='pipe\\:1'[analysis]"
    )
    decoder = subprocess.Popen([
        "ffmpeg", "-v", "error", "-nostdin", "-threads", "1", "-i", sys.argv[1],
        "-filter_complex_threads", "1", "-filter_complex", filters,
        "-map", "[analysis]", "-vn", "-f", "null", "-"
    ], stdout=subprocess.PIPE, text=True)

    def stop(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    levels = []
    frames = []
    total = 0
    try:
        for frame in read_frames(decoder.stdout):
            levels.append(10 ** (frame["lavfi.astats.1.RMS_level"] / 20))
            frames.append([
                (10 ** (frame[f"lavfi.astats.{channel}.RMS_level"] / 20), frame[f"lavfi.aspectralstats.{channel}.flux"])
                for channel in (2, 3, 4)
            ])
            total += frame["lavfi.astats.Overall.Number_of_samples"]
        if decoder.wait() != 0:
            return 1
        print(json.dumps(summarize(levels, frames, total / RATE), separators=(",", ":")))
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
