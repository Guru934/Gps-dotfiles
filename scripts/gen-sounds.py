#!/usr/bin/env python3
"""Deterministic Sound Asset Generator for GPS Desktop.

Generates original, mathematical sound waveforms using Python stdlib and encodes
them via FFmpeg to clean, compact OGG Vorbis files under assets/sounds/default/.
Measures peak amplitude and RMS loudness, guaranteeing:
1. Every sound is strictly under 700 ms
2. Peak-normalized to -1.0 dBFS (no clipping)
3. Deterministic and reproducible across runs
"""

import json
import math
import os
import shutil
import struct
import subprocess
import wave
from pathlib import Path
from typing import Dict, List, Tuple

SAMPLE_RATE = 48000
TARGET_PEAK_DB = -1.0  # Safe headroom below 0 dBFS to prevent clipping


def clamp(val: float, low: float = -1.0, high: float = 1.0) -> float:
    return max(low, min(high, val))


def sine(freq: float, t: float) -> float:
    return math.sin(2.0 * math.pi * freq * t)


def triangle(freq: float, t: float) -> float:
    # Normalized triangle wave
    return 2.0 * abs(2.0 * (t * freq - math.floor(t * freq + 0.5))) - 1.0


def exp_decay(t: float, decay_rate: float) -> float:
    return math.exp(-decay_rate * t)


def adsr(
    t: float,
    duration: float,
    attack: float = 0.01,
    decay: float = 0.05,
    sustain_level: float = 0.7,
    release: float = 0.05,
) -> float:
    if t < 0.0 or t > duration:
        return 0.0
    if t < attack:
        return t / attack
    if t < attack + decay:
        dt = t - attack
        return 1.0 - (1.0 - sustain_level) * (dt / decay)
    if t < duration - release:
        return sustain_level
    dt = t - (duration - release)
    return sustain_level * max(0.0, 1.0 - (dt / release))


# ==============================================================================
# Sound Waveform Synthesizers
# ==============================================================================


def synth_notification(sr: int = SAMPLE_RATE) -> List[float]:
    """Soft warm chime (A5 + harmonics, gentle exponential decay)."""
    duration = 0.38
    num_samples = int(duration * sr)
    samples = []
    f0 = 880.0  # A5
    for i in range(num_samples):
        t = i / sr
        env = exp_decay(t, 10.0)
        # Fundamental + octave + 5th harmonic
        val = 0.7 * sine(f0, t) + 0.25 * sine(f0 * 2.0, t) + 0.05 * sine(f0 * 3.0, t)
        samples.append(val * env)
    return samples


def synth_critical(sr: int = SAMPLE_RATE) -> List[float]:
    """Double bright chime (C6 then E6, urgent and crisp)."""
    duration = 0.42
    num_samples = int(duration * sr)
    samples = []
    t_gap = 0.16
    for i in range(num_samples):
        t = i / sr
        if t < t_gap:
            f = 1046.50  # C6
            env = exp_decay(t, 18.0)
            val = (0.75 * sine(f, t) + 0.25 * sine(f * 2.0, t)) * env
        else:
            t2 = t - t_gap
            f = 1318.51  # E6
            env = exp_decay(t2, 14.0)
            val = (0.75 * sine(f, t2) + 0.25 * sine(f * 2.0, t2)) * env
        samples.append(val)
    return samples


def synth_agent_permission(sr: int = SAMPLE_RATE) -> List[float]:
    """Clearly distinct futuristic rising two-tone (D5 to A5 with distinct harmonic shimmer)."""
    duration = 0.45
    num_samples = int(duration * sr)
    samples = []
    t_split = 0.18
    for i in range(num_samples):
        t = i / sr
        if t < t_split:
            f = 587.33  # D5
            env = adsr(t, t_split, attack=0.015, decay=0.04, sustain_level=0.8, release=0.03)
            # Rich triangle + sine texture
            val = (0.6 * sine(f, t) + 0.3 * triangle(f * 2.0, t) + 0.1 * sine(f * 3.0, t)) * env
        else:
            t2 = t - t_split
            f = 880.0  # A5
            rem = duration - t_split
            env = adsr(t2, rem, attack=0.01, decay=0.08, sustain_level=0.6, release=0.10) * exp_decay(t2, 6.0)
            val = (0.65 * sine(f, t2) + 0.25 * sine(f * 2.0, t2) + 0.1 * triangle(f * 1.5, t2)) * env
        samples.append(val)
    return samples


def synth_agent_permission_reminder(sr: int = SAMPLE_RATE) -> List[float]:
    """Softer, gentler reminder variant of the rising signature."""
    duration = 0.35
    num_samples = int(duration * sr)
    samples = []
    t_split = 0.14
    for i in range(num_samples):
        t = i / sr
        if t < t_split:
            f = 587.33
            env = math.sin(math.pi * (t / t_split)) * 0.7
            val = (0.8 * sine(f, t) + 0.2 * sine(f * 2.0, t)) * env
        else:
            t2 = t - t_split
            f = 880.0
            env = exp_decay(t2, 10.0) * 0.7
            val = (0.85 * sine(f, t2) + 0.15 * sine(f * 2.0, t2)) * env
        samples.append(val)
    return samples


def synth_agent_done(sr: int = SAMPLE_RATE) -> List[float]:
    """Pleasant descending chime (C6 -> G5 -> C5)."""
    duration = 0.48
    num_samples = int(duration * sr)
    samples = []
    n1, n2, n3 = 0.12, 0.12, duration - 0.24
    for i in range(num_samples):
        t = i / sr
        if t < n1:
            f = 1046.50
            env = exp_decay(t, 16.0)
        elif t < n1 + n2:
            t_rel = t - n1
            f = 783.99
            env = exp_decay(t_rel, 16.0)
        else:
            t_rel = t - n1 - n2
            f = 523.25
            env = exp_decay(t_rel, 9.0)
        val = (0.75 * sine(f, t) + 0.25 * sine(f * 2.0, t)) * env
        samples.append(val)
    return samples


def synth_reminder(sr: int = SAMPLE_RATE) -> List[float]:
    """Resonant desk bell (G5 with metallic harmonic partials)."""
    duration = 0.58
    num_samples = int(duration * sr)
    samples = []
    f0 = 783.99  # G5
    partials = [(1.0, 0.6, 7.0), (2.76, 0.25, 9.0), (5.40, 0.15, 14.0)]
    for i in range(num_samples):
        t = i / sr
        val = sum(amp * sine(f0 * ratio, t) * exp_decay(t, dec) for ratio, amp, dec in partials)
        samples.append(val)
    return samples


def synth_download_done(sr: int = SAMPLE_RATE) -> List[float]:
    """Crisp organic bubble pop (downward frequency slide with fast attack)."""
    duration = 0.14
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        # Pitch slides rapidly from 550 Hz down to 280 Hz
        f = 550.0 - 270.0 * (t / duration)
        env = (t / 0.015) if t < 0.015 else exp_decay(t - 0.015, 32.0)
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_error(sr: int = SAMPLE_RATE) -> List[float]:
    """Low warning blip (A3 fundamental with slight pitch drop)."""
    duration = 0.26
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 220.0 - 40.0 * (t / duration)
        env = exp_decay(t, 12.0)
        val = (0.7 * sine(f, t) + 0.3 * triangle(f * 1.5, t)) * env
        samples.append(val)
    return samples


def synth_tick(sr: int = SAMPLE_RATE) -> List[float]:
    """Subtle mechanical haptic tick."""
    duration = 0.035
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 1800.0 - 800.0 * (t / duration)
        env = math.exp(-120.0 * t)
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_shutter(sr: int = SAMPLE_RATE) -> List[float]:
    """Mechanical camera shutter click-click."""
    duration = 0.16
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        val = 0.0
        # Click 1
        if t < 0.04:
            val += sine(1600.0, t) * math.exp(-150.0 * t)
        # Click 2
        if t >= 0.05 and t < 0.12:
            t2 = t - 0.05
            val += sine(1200.0, t2) * math.exp(-100.0 * t2)
        samples.append(val)
    return samples


def synth_record_start(sr: int = SAMPLE_RATE) -> List[float]:
    """Short rising chirp (440 to 880 Hz)."""
    duration = 0.18
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 440.0 + 440.0 * (t / duration)
        env = math.sin(math.pi * (t / duration)) ** 0.8
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_record_stop(sr: int = SAMPLE_RATE) -> List[float]:
    """Short falling chirp (880 to 440 Hz)."""
    duration = 0.18
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 880.0 - 440.0 * (t / duration)
        env = math.sin(math.pi * (t / duration)) ** 0.8
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_lock(sr: int = SAMPLE_RATE) -> List[float]:
    """Solid mechanical lock click."""
    duration = 0.15
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 400.0 - 150.0 * (t / duration)
        env = math.exp(-45.0 * t)
        val = (0.7 * sine(f, t) + 0.3 * triangle(f * 2.0, t)) * env
        samples.append(val)
    return samples


def synth_unlock(sr: int = SAMPLE_RATE) -> List[float]:
    """Crisp unlock click followed by light chime."""
    duration = 0.22
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        if t < 0.06:
            val = sine(500.0, t) * math.exp(-80.0 * t)
        else:
            t2 = t - 0.06
            val = sine(1200.0, t2) * math.exp(-25.0 * t2) * 0.7
        samples.append(val)
    return samples


def synth_battery_low(sr: int = SAMPLE_RATE) -> List[float]:
    """Pulsing battery warning tone."""
    duration = 0.34
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        pulse = 0.5 * (1.0 + math.sin(2.0 * math.pi * 8.0 * t))
        f = 370.0
        env = exp_decay(t, 5.0)
        val = sine(f, t) * pulse * env
        samples.append(val)
    return samples


def synth_plug(sr: int = SAMPLE_RATE) -> List[float]:
    """Ascending charger plug chirp (A4 -> C#5 -> E5)."""
    duration = 0.25
    num_samples = int(duration * sr)
    samples = []
    dt = duration / 2.0
    for i in range(num_samples):
        t = i / sr
        if t < dt:
            f = 440.0
            env = exp_decay(t, 18.0)
        else:
            f = 659.25
            env = exp_decay(t - dt, 12.0)
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_unplug(sr: int = SAMPLE_RATE) -> List[float]:
    """Descending charger unplug chirp (E5 -> A4)."""
    duration = 0.25
    num_samples = int(duration * sr)
    samples = []
    dt = duration / 2.0
    for i in range(num_samples):
        t = i / sr
        if t < dt:
            f = 659.25
            env = exp_decay(t, 18.0)
        else:
            f = 440.0
            env = exp_decay(t - dt, 12.0)
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_device_connect(sr: int = SAMPLE_RATE) -> List[float]:
    """Device connect arpeggio."""
    duration = 0.22
    num_samples = int(duration * sr)
    samples = []
    dt = duration / 2.0
    for i in range(num_samples):
        t = i / sr
        f = 523.25 if t < dt else 659.25
        t_part = t if t < dt else (t - dt)
        env = exp_decay(t_part, 16.0)
        val = (0.8 * sine(f, t) + 0.2 * sine(f * 2.0, t)) * env
        samples.append(val)
    return samples


def synth_device_disconnect(sr: int = SAMPLE_RATE) -> List[float]:
    """Device disconnect descending arpeggio."""
    duration = 0.22
    num_samples = int(duration * sr)
    samples = []
    dt = duration / 2.0
    for i in range(num_samples):
        t = i / sr
        f = 659.25 if t < dt else 523.25
        t_part = t if t < dt else (t - dt)
        env = exp_decay(t_part, 16.0)
        val = (0.8 * sine(f, t) + 0.2 * sine(f * 2.0, t)) * env
        samples.append(val)
    return samples


def synth_dnd_on(sr: int = SAMPLE_RATE) -> List[float]:
    """Gentle descending chime (DND activated)."""
    duration = 0.28
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 620.0 - 220.0 * (t / duration)
        env = exp_decay(t, 9.0)
        val = sine(f, t) * env
        samples.append(val)
    return samples


def synth_dnd_off(sr: int = SAMPLE_RATE) -> List[float]:
    """Gentle ascending chime (DND deactivated)."""
    duration = 0.28
    num_samples = int(duration * sr)
    samples = []
    for i in range(num_samples):
        t = i / sr
        f = 400.0 + 220.0 * (t / duration)
        env = exp_decay(t, 9.0)
        val = sine(f, t) * env
        samples.append(val)
    return samples


SYNTHESIZERS = {
    "notification": ("chime.ogg", synth_notification),
    "critical": ("critical.ogg", synth_critical),
    "agent-permission": ("agent-permission.ogg", synth_agent_permission),
    "agent-permission-reminder": ("agent-permission-reminder.ogg", synth_agent_permission_reminder),
    "agent-done": ("agent-done.ogg", synth_agent_done),
    "reminder": ("bell.ogg", synth_reminder),
    "download-done": ("pop.ogg", synth_download_done),
    "error": ("blip.ogg", synth_error),
    "tick": ("tick.ogg", synth_tick),
    "shutter": ("shutter.ogg", synth_shutter),
    "record-start": ("record-start.ogg", synth_record_start),
    "record-stop": ("record-stop.ogg", synth_record_stop),
    "lock": ("lock.ogg", synth_lock),
    "unlock": ("unlock.ogg", synth_unlock),
    "battery-low": ("battery-low.ogg", synth_battery_low),
    "plug": ("plug.ogg", synth_plug),
    "unplug": ("unplug.ogg", synth_unplug),
    "device-connect": ("device-connect.ogg", synth_device_connect),
    "device-disconnect": ("device-disconnect.ogg", synth_device_disconnect),
    "dnd-on": ("dnd-on.ogg", synth_dnd_on),
    "dnd-off": ("dnd-off.ogg", synth_dnd_off),
}


def normalize_peak(samples: List[float], target_db: float = TARGET_PEAK_DB) -> List[float]:
    """Peak-normalizes audio samples to target_db (default -1.0 dBFS)."""
    if not samples:
        return []
    max_amp = max(abs(s) for s in samples)
    if max_amp <= 1e-6:
        return samples
    target_amp = 10.0 ** (target_db / 20.0)
    scale = target_amp / max_amp
    return [clamp(s * scale, -1.0, 1.0) for s in samples]


def compute_metrics(samples: List[float]) -> Tuple[float, float, float]:
    """Computes duration in ms, peak in dBFS, and RMS in dBFS."""
    duration_ms = (len(samples) / SAMPLE_RATE) * 1000.0
    max_amp = max(abs(s) for s in samples) if samples else 0.0
    peak_db = 20.0 * math.log10(max_amp) if max_amp > 1e-6 else -99.0
    mean_sq = sum(s * s for s in samples) / len(samples) if samples else 0.0
    rms_amp = math.sqrt(mean_sq)
    rms_db = 20.0 * math.log10(rms_amp) if rms_amp > 1e-6 else -99.0
    return duration_ms, peak_db, rms_db


def write_wav(samples: List[float], path: Path, sr: int = SAMPLE_RATE):
    """Writes 16-bit PCM mono WAV file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        raw = bytearray()
        for s in samples:
            val = int(clamp(s) * 32767.0)
            raw.extend(struct.pack("<h", val))
        wf.writeframes(raw)


def encode_to_ogg(wav_path: Path, ogg_path: Path):
    """Encodes WAV to OGG Vorbis using FFmpeg."""
    ogg_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(wav_path),
        "-c:a",
        "libvorbis",
        "-q:a",
        "4",
        "-f",
        "ogg",
        str(ogg_path),
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def generate_all(output_dir: Path) -> List[Dict[str, Any]]:
    output_dir.mkdir(parents=True, exist_ok=True)
    tmp_wav_dir = output_dir / ".tmp_wav"
    tmp_wav_dir.mkdir(parents=True, exist_ok=True)

    report: List[Dict[str, Any]] = []
    theme_mapping: Dict[str, str] = {}

    try:
        for event, (filename, synth_fn) in SYNTHESIZERS.items():
            raw_samples = synth_fn(SAMPLE_RATE)
            samples = normalize_peak(raw_samples, TARGET_PEAK_DB)
            dur_ms, peak_db, rms_db = compute_metrics(samples)

            # Assert constraints
            assert dur_ms < 700.0, f"Event {event} exceeds 700 ms limit ({dur_ms:.1f} ms)!"
            assert peak_db <= 0.0, f"Event {event} is clipping ({peak_db:.2f} dBFS)!"

            wav_file = tmp_wav_dir / f"{event}.wav"
            ogg_file = output_dir / filename

            write_wav(samples, wav_file, SAMPLE_RATE)
            encode_to_ogg(wav_file, ogg_file)

            theme_mapping[event] = filename
            report.append({
                "event": event,
                "file": filename,
                "duration_ms": round(dur_ms, 1),
                "peak_db": round(peak_db, 2),
                "rms_db": round(rms_db, 2),
            })

        # Add event aliases to theme.json
        theme_mapping["notification-critical"] = "critical.ogg"
        theme_mapping["download-failed"] = "blip.ogg"
        theme_mapping["agent-error"] = "blip.ogg"

        theme_json_path = output_dir / "theme.json"
        with open(theme_json_path, "w", encoding="utf-8") as f:
            json.dump(theme_mapping, f, indent=2)

    finally:
        shutil.rmtree(tmp_wav_dir, ignore_errors=True)

    return report


def main():
    repo_root = Path(__file__).resolve().parent.parent
    sounds_dir = repo_root / "assets" / "sounds" / "default"
    print(f"Generating default sound theme in: {sounds_dir}")

    report = generate_all(sounds_dir)

    print("\n" + "=" * 70)
    print(f"{'Event':<26} {'File':<28} {'Duration':<10} {'Peak':<9} {'RMS'}")
    print("-" * 70)
    for r in report:
        print(
            f"{r['event']:<26} {r['file']:<28} {r['duration_ms']:>5.1f} ms  "
            f"{r['peak_db']:>5.2f} dB  {r['rms_db']:>5.2f} dB"
        )
    print("=" * 70)
    print(f"All {len(report)} sounds generated successfully under 700 ms, peak-normalized, no clipping.\n")


if __name__ == "__main__":
    main()
