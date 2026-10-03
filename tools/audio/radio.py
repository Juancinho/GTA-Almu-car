#!/usr/bin/env python3
"""Original radio music for Brisa de Poniente (project-generated, no samples).

Three stations, two tracks each, synthesised from scratch with numpy:
  Radio Costa Tropical - rumba flamenca (Karplus-Strong guitar, palmas, cajón)
  Poniente FM          - chill electronica (pads, sub bass, arpeggios)
  Sexi Rock            - guitar rock (distorted power chords, live kit)
Writes 22.05 kHz mono WAV then encodes OGG Vorbis with ffmpeg into
game/assets/audio/radio/. Deterministic (fixed seeds).

Usage: python3 tools/audio/radio.py [repo_root]
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

SR = 22050
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "game", "assets", "audio", "radio")
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave + 1) - 69) / 12)


def chord(root, octave, quality):
    intervals = {"m": [0, 3, 7, 12], "M": [0, 4, 7, 12], "7": [0, 4, 7, 10], "5": [0, 7, 12], "m7": [0, 3, 7, 10], "M7": [0, 4, 7, 11]}[quality]
    base = NOTE[root] + 12 * (octave + 1)
    return [440.0 * 2 ** ((base + i - 69) / 12) for i in intervals]


def env(n, attack=0.005, release=0.2, sustain=1.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((n / SR - t) / max(release, 1e-4), 0, 1)
    return a * r * sustain


def pluck(freq, dur, rng, brightness=0.5, decay=0.996):
    """Karplus-Strong string."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = np.convolve(rng.uniform(-1, 1, period + 2), [0.25, 0.5, 0.25], "valid")  # warmer pick
    out = np.zeros(n)
    idx = 0
    for i in range(n):
        out[i] = buf[idx]
        nxt = (idx + 1) % period
        buf[idx] = decay * (brightness * buf[idx] + (1 - brightness) * buf[nxt])
        idx = nxt
    return out


def osc(kind, freq, n, detune=0.0):
    t = np.arange(n) / SR
    f = freq * (1 + detune)
    phase = (t * f) % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * phase)
    if kind == "saw":
        return 2 * phase - 1
    if kind == "square":
        return np.where(phase < 0.5, 1.0, -1.0)
    if kind == "tri":
        return 4 * np.abs(phase - 0.5) - 1
    raise ValueError(kind)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    # Two cascaded one-pole filters via scipy-free recursion on blocks.
    try:
        from scipy.signal import lfilter
        a = np.exp(-2 * np.pi * cutoff / SR)
        y = lfilter([1 - a], [1, -a], x)
        return lfilter([1 - a], [1, -a], y)
    except ImportError:
        return lowpass(lowpass(x, cutoff), cutoff)


def kick(rng):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 90 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def snare(rng):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n) * np.exp(-t * 18)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)
    return 0.7 * noise + 0.4 * tone


def hat(rng, open_hat=False):
    n = int((0.25 if open_hat else 0.05) * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    noise = noise - lowpass_fast(noise, 6000)
    return noise * np.exp(-t * (10 if open_hat else 60)) * 0.6


def clap(rng):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    burst = np.zeros(n)
    for k, off in enumerate([0.0, 0.012, 0.024]):
        s = int(off * SR)
        seg = rng.uniform(-1, 1, n - s) * np.exp(-np.arange(n - s) / SR * (60 if k < 2 else 16))
        burst[s:] += seg
    burst = burst - lowpass_fast(burst, 900)
    return burst * 0.8


def cajon(rng, slap=False):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    if slap:
        return (rng.uniform(-1, 1, n) * np.exp(-t * 30) * 0.5 + np.sin(2 * np.pi * 320 * t) * np.exp(-t * 20) * 0.4)
    return np.sin(2 * np.pi * (70 + 40 * np.exp(-t * 30)) * t) * np.exp(-t * 14)


def place(track, sound, at, gain=1.0):
    s = int(at * SR)
    if s >= len(track):
        return
    e = min(len(track), s + len(sound))
    track[s:e] += sound[: e - s] * gain


def reverb(x, mix=0.18):
    out = x.copy()
    for delay, g in [(0.029, 0.5), (0.037, 0.45), (0.041, 0.42), (0.053, 0.38)]:
        d = int(delay * SR)
        y = np.zeros_like(x)
        y[d:] = x[:-d]
        for _ in range(3):
            y[d:] += y[:-d] * g * 0.5
        out += y * mix * 0.25
    return out


def finish(x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    x = np.tanh(x * 1.2) / np.tanh(1.2)
    fade = int(0.02 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


# --- Station styles ---------------------------------------------------------------

def rumba(bpm, progression, bars, seed, melody_scale):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = 4 * beat
    total = bars * bar
    track = np.zeros(int(total * SR) + SR)
    strum_cache = {}
    for b in range(bars):
        root, octv, q = progression[b % len(progression)]
        notes = chord(root, octv, q)
        t0 = b * bar
        # Rumba strum: down on 1, chuck on 2 and 4, ups in between.
        pattern = [(0.0, 1.0), (0.5, 0.45), (1.0, 0.8), (1.5, 0.4), (2.0, 0.9), (2.5, 0.45), (3.0, 0.8), (3.5, 0.5)]
        for off, vel in pattern:
            key = (root, q, vel > 0.7)
            if key not in strum_cache:
                strum = np.zeros(int(0.9 * SR))
                for k, f in enumerate(notes + [notes[0] * 2]):
                    place(strum, pluck(f, 0.85, rng, 0.5, 0.994), k * 0.012)
                strum_cache[key] = strum
            place(track, strum_cache[key], t0 + off * beat, 0.22 * vel)
        place(track, cajon(rng), t0, 0.6)
        place(track, cajon(rng), t0 + 2.5 * beat, 0.45)
        place(track, cajon(rng, True), t0 + 1 * beat, 0.4)
        place(track, cajon(rng, True), t0 + 3 * beat, 0.4)
        for p in [1.0, 3.0]:
            place(track, clap(rng), t0 + p * beat, 0.2)
        bass = osc("tri", notes[0] / 2, int(beat * 1.9 * SR)) * env(int(beat * 1.9 * SR), 0.01, 0.2)
        place(track, bass, t0, 0.35)
        place(track, bass, t0 + 2 * beat, 0.3)
        # Lead guitar phrases every other bar on the scale.
        if b % 2 == 1 and b > 2:
            steps = rng.choice(len(melody_scale), 6)
            for k, s in enumerate(steps):
                place(track, pluck(melody_scale[s], 0.5, rng, 0.35, 0.993), t0 + (k * 0.5) * beat, 0.3)
    return finish(lowpass_fast(reverb(track[: int(total * SR)], 0.25), 7000))


def chill(bpm, progression, bars, seed, arp_octave=5):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = 4 * beat
    total = bars * bar
    track = np.zeros(int(total * SR) + SR)
    for b in range(bars):
        root, octv, q = progression[b % len(progression)]
        notes = chord(root, octv, q)
        t0 = b * bar
        n = int(bar * SR)
        pad = sum(osc("saw", f, n, d) for f in notes for d in (-0.004, 0.004))
        pad = lowpass_fast(pad, 900) * env(n, 0.4, 0.4) * 0.07
        place(track, pad, t0)
        bass = osc("sine", notes[0] / 2, int(beat * 0.9 * SR)) * env(int(beat * 0.9 * SR), 0.005, 0.15)
        for p in [0, 1.5, 2.5]:
            place(track, bass, t0 + p * beat, 0.45)
        if b >= 2:
            for k in range(8):
                f = notes[k % len(notes)] * (2 if k % 4 > 1 else 1) * 2 ** (arp_octave - 5)
                note = lowpass_fast(osc("square", f, int(0.22 * SR)), 2500) * env(int(0.22 * SR), 0.003, 0.15)
                place(track, note, t0 + k * 0.5 * beat, 0.08)
                place(track, note, t0 + k * 0.5 * beat + 0.75 * beat, 0.035)  # dotted delay
        for p in range(4):
            place(track, kick(rng), t0 + p * beat, 0.55 if p % 2 == 0 else 0.0)
            place(track, hat(rng), t0 + (p + 0.5) * beat, 0.25)
        place(track, snare(rng), t0 + 3 * beat, 0.25)
    return finish(reverb(track[: int(total * SR)], 0.3))


def rock(bpm, riff, bars, seed):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = 4 * beat
    total = bars * bar
    track = np.zeros(int(total * SR) + SR)
    for b in range(bars):
        root, octv = riff[b % len(riff)]
        notes = chord(root, octv, "5")
        t0 = b * bar
        for k in range(8):
            n = int(beat * 0.48 * SR)
            gtr = sum(osc("saw", f, n, d) for f in notes for d in (-0.003, 0.003))
            gtr = np.tanh(gtr * 3.5) * env(n, 0.002, 0.05)
            gtr = lowpass_fast(gtr, 3200)
            place(track, gtr, t0 + k * 0.5 * beat, 0.16 if k % 2 == 0 else 0.11)
        bass = lowpass_fast(osc("saw", notes[0] / 2, int(beat * 0.45 * SR)), 700) * env(int(beat * 0.45 * SR), 0.003, 0.05)
        for k in range(8):
            place(track, bass, t0 + k * 0.5 * beat, 0.35)
        for p in [0, 2, 2.5]:
            place(track, kick(rng), t0 + p * beat, 0.6)
        for p in [1, 3]:
            place(track, snare(rng), t0 + p * beat, 0.5)
        for k in range(8):
            place(track, hat(rng, k == 7), t0 + k * 0.5 * beat, 0.22)
        if b % 8 == 7:
            for k in range(4):
                place(track, snare(rng), t0 + (3 + k * 0.25) * beat, 0.35)
    return finish(reverb(track[: int(total * SR)], 0.12))


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    wav_path = os.path.join(OUT, name + ".wav")
    ogg_path = os.path.join(OUT, name + ".ogg")
    data = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "3", ogg_path], check=True)
    os.remove(wav_path)
    return {"file": name + ".ogg", "seconds": round(len(samples) / SR, 1)}


def main():
    a_scale = [hz(n, o) for n, o in [("A", 4), ("Bb", 4), ("C#", 5), ("D", 5), ("E", 5), ("F", 5), ("G", 5), ("A", 5)]]
    e_scale = [hz(n, o) for n, o in [("E", 4), ("F", 4), ("G#", 4), ("A", 4), ("B", 4), ("C", 5), ("D", 5), ("E", 5)]]
    tracks = {
        "costa_rumba_paseo": rumba(104, [("A", 3, "m"), ("G", 3, "M"), ("F", 3, "M"), ("E", 3, "M")], 32, 11, a_scale),
        "costa_levante": rumba(112, [("E", 3, "M"), ("F", 3, "M"), ("G", 3, "M"), ("F", 3, "M")], 32, 12, e_scale),
        "poniente_cotobro": chill(92, [("D", 3, "m7"), ("A#", 2, "M7"), ("F", 3, "M7"), ("C", 3, "M")], 28, 21),
        "poniente_marina": chill(96, [("F#", 3, "m7"), ("D", 3, "M7"), ("A", 3, "M"), ("E", 3, "M")], 28, 22, 5),
        "sexi_penon": rock(132, [("E", 2), ("E", 2), ("G", 2), ("A", 2), ("E", 2), ("E", 2), ("C", 3), ("D", 3)], 40, 31),
        "sexi_castillo": rock(124, [("A", 2), ("A", 2), ("F", 2), ("G", 2), ("D", 2), ("D", 2), ("F", 2), ("E", 2)], 40, 32),
    }
    report = {"generator": "tools/audio/radio.py", "sample_rate": SR, "license": "original project-generated", "files": []}
    for name, samples in tracks.items():
        report["files"].append(write(name, samples))
        print("wrote", name)
    with open(os.path.join(OUT, "radio_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
