#!/usr/bin/env python3
"""Real-time audio spectrum for the GPS dashboard.

Captures the default PipeWire sink's monitor stream with parec and prints one
line per frame: N normalized band levels (0..1, space separated).

Real signal only - no synthetic or random heights. When the monitored output
is silent (nothing playing, or muted), the levels decay to zero and the bars
in the UI settle. Bands use logarithmic spacing so low and high content is
visible at the same time.

Usage: audio-spectrum.py [band_count]
"""

import shutil
import signal
import subprocess
import sys

import numpy as np

RATE = 48000
FRAME = 2048          # ~43 ms per frame at 48 kHz
FLOOR_DB = -72.0      # band level 0.0
CEIL_DB = -18.0       # band level 1.0
SILENCE_DB = -55.0    # overall RMS below this counts as silence
DECAY = 0.75          # per-frame decay factor while silent
ATTACK = 1.0          # new peaks take effect immediately

BARS = 18
if len(sys.argv) > 1:
    try:
        BARS = max(4, min(64, int(sys.argv[1])))
    except ValueError:
        pass

if shutil.which("parec") is None:
    sys.stderr.write("audio-spectrum: parec not found\n")
    sys.exit(1)

proc = subprocess.Popen(
    [
        "parec",
        "--device=@DEFAULT_MONITOR@",
        "--rate=%d" % RATE,
        "--format=s16le",
        "--channels=1",
        "--latency-msec=40",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)


def _terminate(_signum, _frame):
    try:
        proc.terminate()
        proc.wait(timeout=1)
    except Exception:
        proc.kill()
    sys.exit(0)


signal.signal(signal.SIGTERM, _terminate)
signal.signal(signal.SIGINT, _terminate)

window = np.hanning(FRAME).astype(np.float32)
freqs = np.fft.rfftfreq(FRAME, 1.0 / RATE)
edges = np.geomspace(40.0, 16000.0, BARS + 1)
band_masks = [(freqs >= edges[i]) & (freqs < edges[i + 1]) for i in range(BARS)]
bands = np.zeros(BARS, dtype=np.float32)

frame_bytes = FRAME * 2
buf = bytearray()

while True:
    chunk = proc.stdout.read(frame_bytes - len(buf))
    if not chunk:
        break
    buf.extend(chunk)
    if len(buf) < frame_bytes:
        continue

    samples = np.frombuffer(bytes(buf), dtype=np.int16).astype(np.float32) / 32768.0
    del buf[:]

    rms_db = 20.0 * np.log10(float(np.sqrt(np.mean(samples * samples))) + 1e-9)

    if rms_db < SILENCE_DB:
        bands *= DECAY
        if bands.max() < 0.02:
            bands[:] = 0.0
    else:
        spec = np.abs(np.fft.rfft(samples * window)) / (FRAME * 0.5)
        db = 20.0 * np.log10(spec + 1e-9)
        for i, mask in enumerate(band_masks):
            peak = float(db[mask].max()) if mask.any() else FLOOR_DB
            level = (peak - FLOOR_DB) / (CEIL_DB - FLOOR_DB)
            level = 0.0 if level < 0.0 else (1.0 if level > 1.0 else level)
            bands[i] = max(level * ATTACK, bands[i] * DECAY)

    print(" ".join("%.2f" % v for v in bands), flush=True)

_terminate(None, None)
