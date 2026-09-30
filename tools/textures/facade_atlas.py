"""Generate the original façade detail atlas (windows, shutters, rejas, doors, shops).

Deterministic procedural art (no external inputs). Output: 4x4 grid of 256 px cells,
RGB = albedo; A = 0 wall (show the building plaster), ~200 opaque detail, 255 glass
(used for gloss/reflection and night glow).
Usage: python tools/textures/facade_atlas.py [--out game/assets/generated/facade_atlas.png]
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/generated/facade_atlas.png"
CELL = 256
CELLS = [
    "window_shutters_green", "window_shutters_blue", "window_shutters_brown", "window_reja",
    "balcony_door", "shop_front", "door_wood", "window_modern",
    "garage_door", "shop_front_awning", "window_small_reja", "door_arched",
    "window_modern_blind", "balcony_door_shutters", "railing", "vent",
]
RNG = np.random.default_rng(7404)


def glass(draw: ImageDraw.ImageDraw, mask: ImageDraw.ImageDraw, box: tuple[int, int, int, int], tone: tuple[int, int, int] = (58, 82, 92)) -> None:
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        c = tuple(int(v * (1.25 - 0.55 * t)) for v in tone)
        draw.line([(x0, y), (x1, y)], fill=c)
    # diagonal sky reflection streak
    draw.polygon([(x0 + (x1 - x0) * 0.15, y1), (x0 + (x1 - x0) * 0.35, y1), (x0 + (x1 - x0) * 0.75, y0), (x0 + (x1 - x0) * 0.55, y0)], fill=tuple(min(255, v + 45) for v in tone))
    mask.rectangle(box, fill=255)


def frame(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: tuple[int, int, int], width: int = 8) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, outline=color, width=width)
    draw.line([((x0 + x1) // 2, y0), ((x0 + x1) // 2, y1)], fill=color, width=width // 2)
    draw.line([(x0, (y0 + y1) // 2), (x1, (y0 + y1) // 2)], fill=color, width=width // 3)


def shutter(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: tuple[int, int, int]) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=color)
    dark = tuple(int(v * 0.7) for v in color)
    for y in range(y0 + 6, y1 - 4, 9):
        draw.line([(x0 + 4, y), (x1 - 4, y)], fill=dark, width=3)
    draw.rectangle(box, outline=tuple(int(v * 0.55) for v in color), width=3)


def reja(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], bulge: bool = True) -> None:
    x0, y0, x1, y1 = box
    iron = (30, 30, 32)
    for x in range(x0 + 10, x1 - 5, 18):
        draw.line([(x, y0), (x, y1)], fill=iron, width=4)
    for y in (y0 + 12, (y0 + y1) // 2, y1 - 12):
        draw.line([(x0, y), (x1, y)], fill=iron, width=4)
    draw.rectangle(box, outline=iron, width=5)
    if bulge:
        draw.arc([x0 + 20, y0 - 18, x1 - 20, y0 + 40], 180, 360, fill=iron, width=4)


def cell_image(name: str) -> tuple[Image.Image, Image.Image]:
    img = Image.new("RGB", (CELL, CELL), (236, 231, 221))
    mask = Image.new("L", (CELL, CELL), 0)
    d, m = ImageDraw.Draw(img), ImageDraw.Draw(mask)
    white = (250, 249, 246)
    if name.startswith("window_shutters"):
        color = {"green": (74, 112, 88), "blue": (52, 92, 140), "brown": (112, 74, 48)}[name.split("_")[-1]]
        glass(d, m, (78, 40, 178, 216))
        frame(d, (78, 40, 178, 216), white)
        shutter(d, (18, 36, 76, 220), color)
        shutter(d, (180, 36, 238, 220), color)
        d.rectangle((66, 216, 190, 232), fill=(214, 206, 192))  # sill
    elif name in ("window_reja", "window_small_reja"):
        box = (60, 40, 196, 216) if name == "window_reja" else (80, 70, 176, 190)
        glass(d, m, box)
        frame(d, box, white)
        reja(d, (box[0] - 10, box[1] - 6, box[2] + 10, box[3] + 6))
        d.rectangle((box[0] - 14, box[3] + 6, box[2] + 14, box[3] + 20), fill=(214, 206, 192))
    elif name in ("balcony_door", "balcony_door_shutters"):
        glass(d, m, (72, 20, 184, 250))
        frame(d, (72, 20, 184, 250), white, 10)
        if name == "balcony_door_shutters":
            shutter(d, (14, 16, 70, 252), (74, 112, 88))
            shutter(d, (186, 16, 242, 252), (74, 112, 88))
    elif name in ("shop_front", "shop_front_awning"):
        d.rectangle((0, 0, 255, 255), fill=(60, 58, 55))
        glass(d, m, (14, 60, 242, 250), (70, 90, 96))
        d.rectangle((14, 60, 242, 250), outline=(40, 40, 40), width=6)
        d.line([(128, 60), (128, 250)], fill=(40, 40, 40), width=6)
        d.rectangle((0, 0, 255, 56), fill=(210, 200, 180))  # fascia for a fictional shop sign
        for x in range(20, 236, 26):
            d.rectangle((x, 18, x + 14, 38), fill=(120, 110, 95))
        if name == "shop_front_awning":
            for i, x in enumerate(range(0, 256, 32)):
                d.polygon([(x, 0), (x + 32, 0), (x + 32, 50), (x, 58)], fill=[(189, 117, 94), (240, 236, 228)][i % 2])
    elif name in ("door_wood", "door_arched"):
        wood = (98, 64, 40)
        if name == "door_arched":
            d.pieslice((52, 10, 204, 120), 180, 360, fill=wood)
            d.rectangle((52, 64, 204, 255), fill=wood)
        else:
            d.rectangle((52, 20, 204, 255), fill=wood)
        for x in range(64, 200, 22):
            d.line([(x, 70), (x, 250)], fill=(78, 50, 30), width=4)
        d.ellipse((170, 150, 182, 162), fill=(190, 160, 90))
        d.rectangle((40, 10, 216, 255), outline=(214, 206, 192), width=10)
    elif name in ("window_modern", "window_modern_blind"):
        glass(d, m, (40, 30, 216, 226), (60, 76, 84))
        d.rectangle((40, 30, 216, 226), outline=(170, 172, 170), width=8)
        d.line([(128, 30), (128, 226)], fill=(170, 172, 170), width=6)
        if name == "window_modern_blind":
            d.rectangle((40, 30, 216, 110), fill=(196, 176, 140))
            m.rectangle((40, 30, 216, 110), fill=0)
            for y in range(34, 110, 8):
                d.line([(42, y), (214, y)], fill=(170, 150, 118), width=2)
    elif name == "garage_door":
        d.rectangle((20, 40, 236, 255), fill=(150, 152, 150))
        for y in range(48, 255, 14):
            d.line([(20, y), (236, y)], fill=(118, 120, 118), width=3)
    elif name == "railing":  # wrought-iron balcony railing, transparent between bars
        iron = (34, 35, 37)
        d.rectangle((0, 18, 255, 30), fill=iron)
        d.rectangle((0, 238, 255, 250), fill=iron)
        for x in range(8, 256, 21):
            d.rectangle((x, 30, x + 5, 238), fill=iron)
        for x in range(18, 256, 42):
            d.ellipse((x, 120, x + 26, 150), outline=iron, width=4)
    elif name == "vent":
        d.rectangle((100, 100, 156, 140), fill=(180, 176, 168))
        for y in range(104, 138, 6):
            d.line([(104, y), (152, y)], fill=(120, 116, 110), width=2)
    base = np.asarray(img, dtype=float)
    background = (np.abs(base - np.array([236, 231, 221])).max(axis=2) < 4)
    # subtle grime at the bottom and noise so cells never look flat
    noise = RNG.normal(0, 5, (CELL, CELL, 1))
    arr = np.clip(np.asarray(img, dtype=float) + noise, 0, 255)
    grad = np.linspace(1.0, 0.9, CELL)[:, None, None]
    arr = np.clip(arr * grad, 0, 255).astype(np.uint8)
    alpha = np.where(np.asarray(mask) > 0, 255, 200).astype(np.uint8)
    alpha[background] = 0
    return Image.fromarray(arr).filter(ImageFilter.SMOOTH), Image.fromarray(alpha)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    atlas = Image.new("RGBA", (CELL * 4, CELL * 4))
    for i, name in enumerate(CELLS):
        rgb, mask = cell_image(name)
        rgba = rgb.convert("RGBA")
        rgba.putalpha(mask)
        atlas.paste(rgba, ((i % 4) * CELL, (i // 4) * CELL))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.out, optimize=False)
    report = {"generator": "tools/textures/facade_atlas.py", "seed": 7404, "grid": [4, 4], "cell_px": CELL, "cells": CELLS,
              "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "output_sha256": hashlib.sha256(args.out.read_bytes()).hexdigest(), "license": "Original project art"}
    args.out.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"ATLAS PASS: {len(CELLS)} cells -> {args.out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
