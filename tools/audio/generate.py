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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("game/assets/audio"))
    args = parser.parse_args()
    rng = random.Random(7401)
    reports = [write_wav(args.out / "ui_click.wav", click()),
               write_wav(args.out / "footstep.wav", footstep(rng)),
               write_wav(args.out / "engine_loop.wav", engine()),
               write_wav(args.out / "sea_wind_loop.wav", sea_wind(rng))]
    report = {"generator": "tools/audio/generate.py", "sample_rate": SAMPLE_RATE,
              "seed": 7401, "license": "original project-generated", "placeholder": True,
              "files": reports}
    (args.out / "generation_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("AUDIO PASS: " + ", ".join(item["file"] for item in reports))


if __name__ == "__main__":
    main()
