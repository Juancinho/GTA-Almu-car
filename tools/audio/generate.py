"""Generate small, original placeholder sounds with only Python's standard library."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

SAMPLE_RATE = 22_050


def write_wav(path: Path, samples: list[float]) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = [max(-1.0, min(1.0, sample)) for sample in samples]
    with wave.open(str(path), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(SAMPLE_RATE)
        sound.writeframes(struct.pack("<" + "h" * len(clipped), *(int(value * 32767) for value in clipped)))
    return {"file": str(path), "seconds": round(len(samples) / SAMPLE_RATE, 3),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def click() -> list[float]:
    count = int(0.13 * SAMPLE_RATE)
    return [0.35 * math.sin(2 * math.pi * (620 + 180 * i / count) * i / SAMPLE_RATE)
            * (1 - i / count) ** 2 for i in range(count)]


def footstep(rng: random.Random) -> list[float]:
    count = int(0.18 * SAMPLE_RATE)
    result = []
    low = 0.0
    for i in range(count):
        low = low * 0.82 + rng.uniform(-1, 1) * 0.18
        envelope = math.exp(-23 * i / count)
        result.append(0.65 * low * envelope)
    return result


def engine() -> list[float]:
    # Exactly 80 cycles per second keeps the 1-second loop phase aligned.
    return [0.17 * (math.sin(2 * math.pi * 80 * i / SAMPLE_RATE)
                    + 0.32 * math.sin(2 * math.pi * 160 * i / SAMPLE_RATE)
                    + 0.16 * math.sin(2 * math.pi * 240 * i / SAMPLE_RATE))
            for i in range(SAMPLE_RATE)]


def sea_wind(rng: random.Random) -> list[float]:
    count = 4 * SAMPLE_RATE
    low = 0.0
    result = []
    for i in range(count):
        low = low * 0.985 + rng.uniform(-1, 1) * 0.015
        wave_rhythm = 0.45 + 0.3 * math.sin(2 * math.pi * i / count)
        fade = min(1.0, i / 2500, (count - i) / 2500)
        result.append(0.52 * low * wave_rhythm * fade)
    return result


def gunshot(rng: random.Random, seconds: float, body_hz: float, crack: float) -> list[float]:
    """Sharp noise crack over a decaying low thump; stylised, not a recording."""
    count = int(seconds * SAMPLE_RATE)
    result = []
    low = 0.0
    for i in range(count):
        t = i / SAMPLE_RATE
        noise = rng.uniform(-1, 1)
        low = low * 0.9 + noise * 0.1
        thump = math.sin(2 * math.pi * body_hz * t * (1 - 0.6 * i / count)) * math.exp(-t * 28)
        result.append(crack * noise * math.exp(-t * 60) + 0.55 * low * math.exp(-t * 9) + 0.6 * thump)
    return result


def bat_hit(rng: random.Random) -> list[float]:
    count = int(0.16 * SAMPLE_RATE)
    return [0.7 * (math.sin(2 * math.pi * 190 * i / SAMPLE_RATE) * 0.6 + rng.uniform(-1, 1) * 0.4)
            * math.exp(-30 * i / count * 0.25) * (1 - i / count) for i in range(count)]


def dry_click() -> list[float]:
    count = int(0.05 * SAMPLE_RATE)
    return [0.5 * math.sin(2 * math.pi * 2400 * i / SAMPLE_RATE) * (1 - i / count) ** 4 for i in range(count)]


def reload_sound(rng: random.Random) -> list[float]:
    result = []
    for tone in (900, 1400):
        count = int(0.07 * SAMPLE_RATE)
        result += [0.4 * (math.sin(2 * math.pi * tone * i / SAMPLE_RATE) + rng.uniform(-0.4, 0.4)) * (1 - i / count) ** 3
                   for i in range(count)]
        result += [0.0] * int(0.12 * SAMPLE_RATE)
    return result


def coastal_session() -> list[float]:
    """Original 16-second instrumental phrase, no sampled or borrowed recording."""
    result: list[float] = []
    progression = ((57, 60, 64), (53, 57, 60), (55, 59, 62), (52, 55, 59))
    for index in range(16 * SAMPLE_RATE):
        t = index / SAMPLE_RATE
        chord = progression[int(t / 4) % 4]
        step = int(t * 4)
        note = chord[step % 3] + 12
        phase = t % 0.25
        hz = 440 * 2 ** ((note - 69) / 12)
        lead = math.sin(math.tau * hz * t) * math.exp(-phase * 17) * 0.16
        bass_hz = 440 * 2 ** ((chord[0] - 12 - 69) / 12)
        bass = math.sin(math.tau * bass_hz * t) * 0.12
        beat = t % 0.5
        kick = math.sin(math.tau * (52 * beat + 5 * (1 - math.exp(-beat * 20)))) * math.exp(-beat * 35) * 0.22
        fade = min(1.0, t / 0.1, (16 - t) / 0.25)
        result.append((lead + bass + kick) * fade)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("game/assets/audio"))
    args = parser.parse_args()
    rng = random.Random(7401)
    reports = [write_wav(args.out / "ui_click.wav", click()),
               write_wav(args.out / "footstep.wav", footstep(rng)),
               write_wav(args.out / "engine_loop.wav", engine()),
               write_wav(args.out / "sea_wind_loop.wav", sea_wind(rng)),
               write_wav(args.out / "pistol_shot.wav", gunshot(rng, 0.45, 120.0, 0.9)),
               write_wav(args.out / "smg_shot.wav", gunshot(rng, 0.16, 150.0, 0.75)),
               write_wav(args.out / "bat_hit.wav", bat_hit(rng)),
               write_wav(args.out / "dry_click.wav", dry_click()),
               write_wav(args.out / "reload.wav", reload_sound(rng)),
               write_wav(args.out / "coastal_session.wav", coastal_session())]
    report = {"generator": "tools/audio/generate.py", "sample_rate": SAMPLE_RATE,
              "seed": 7401, "license": "original project-generated", "placeholder": True,
              "files": reports}
    (args.out / "generation_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("AUDIO PASS: " + ", ".join(item["file"] for item in reports))


if __name__ == "__main__":
    main()
