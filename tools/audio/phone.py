#!/usr/bin/env python3
"""Original phone ringtone for Brisa Móvil (project-generated, numpy only).

A bright two-bar marimba-like arpeggio (E5 G#5 B5 E6 · D6 B5) with a soft
second partial and a short tail, followed by silence so the game can loop it
as "ring … pause … ring". Writes game/assets/audio/phone_ring.wav.
"""
import os, sys, wave
import numpy as np

SR = 22050
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "game", "assets", "audio")


def note(freq, length, start, buf):
    n = int(length * SR)
    t = np.arange(n) / SR
    env = (1 - np.exp(-t * 400)) * np.exp(-t * 7.5)
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-t * 20) \
        + 0.18 * np.sin(2 * np.pi * freq * 2.0 * t)
    i = int(start * SR)
    buf[i:i + n] += (tone * env)[: len(buf) - i]


def main():
    total = 2.4
    buf = np.zeros(int(total * SR))
    e5, gs5, b5, e6, d6 = 659.25, 830.61, 987.77, 1318.51, 1174.66
    step = 0.11
    phrase = [e5, gs5, b5, e6, d6, b5]
    for bar in range(2):
        for k, f in enumerate(phrase):
            note(f, 0.35, bar * 0.78 + k * step, buf)
    buf = np.tanh(buf * 0.9)
    buf = buf / (np.max(np.abs(buf)) + 1e-9) * 0.9
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, "phone_ring.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((buf * 32767).astype(np.int16).tobytes())
    print("phone_ring.wav ok")


if __name__ == "__main__":
    main()
