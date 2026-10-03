#!/usr/bin/env python3
"""Original explosion and glass-smash/whoosh effects (project-generated)."""
import os, sys, wave
import numpy as np
from scipy.signal import lfilter

SR = 22050
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "game", "assets", "audio")
rng = np.random.default_rng(909)


def lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - a], [1, -a], lfilter([1 - a], [1, -a], x))


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.95
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


t = np.arange(int(2.2 * SR)) / SR
boom = np.sin(2 * np.pi * (38 + 60 * np.exp(-t * 6)) * t) * np.exp(-t * 2.2)
rumble = lp(rng.uniform(-1, 1, len(t)), 400) * np.exp(-t * 1.6) * 3.0
crack = (rng.uniform(-1, 1, len(t)) - lp(rng.uniform(-1, 1, len(t)), 2000)) * np.exp(-t * 18) * 0.6
save("explosion.wav", np.tanh((boom + rumble + crack) * 1.6))
t = np.arange(int(0.6 * SR)) / SR
whoosh = lp(rng.uniform(-1, 1, len(t)), 900) * np.sin(np.pi * t / 0.6) ** 2 * 2.0
save("throw_whoosh.wav", whoosh)
t = np.arange(int(0.5 * SR)) / SR
glass = (rng.uniform(-1, 1, len(t)) - lp(rng.uniform(-1, 1, len(t)), 3000)) * np.exp(-t * 9)
fire = lp(rng.uniform(-1, 1, len(t)), 1500) * (1 - np.exp(-t * 20)) * 0.8
save("molotov_smash.wav", glass + fire)
print("effects ok")

# Rain loop (8 s, seamless): broadband hiss with a soft low body and scattered
# droplet ticks; the ends are cross-faded so the loop has no seam.
n = int(8.0 * SR)
hiss = rng.uniform(-1, 1, n + SR)
hiss = hiss - lp(hiss, 700)               # high-passed hiss
hiss = lp(hiss, 6000) * 0.5
body = lp(rng.uniform(-1, 1, n + SR), 300) * 1.5
drops = np.zeros(n + SR)
for i in rng.integers(0, n + SR - 400, 900):
    k = np.arange(300)
    drops[i:i + 300] += np.sin(2 * np.pi * rng.uniform(1800, 4200) * k / SR) * np.exp(-k / 40.0) * rng.uniform(0.05, 0.25)
rain = hiss + body + drops
fade = np.linspace(0, 1, SR)
loop = rain[:n].copy()
loop[:SR] = rain[:SR] * fade + rain[n:n + SR] * (1 - fade)
save("rain_loop.wav", loop * 0.8)
print("rain ok")

# Thunder (4.5 s): a sharp crack followed by a long low rolling rumble.
t = np.arange(int(4.5 * SR)) / SR
crack = (rng.uniform(-1, 1, len(t)) - lp(rng.uniform(-1, 1, len(t)), 1500)) * np.exp(-t * 14) * 0.7
roll = lp(rng.uniform(-1, 1, len(t)), 140) * 5.0
roll *= (0.55 + 0.45 * np.sin(2 * np.pi * 0.9 * t + 1.0) ** 2) * np.exp(-t * 0.75) * (1 - np.exp(-t * 6))
save("thunder.wav", np.tanh((crack + roll) * 1.4))
print("thunder ok")
