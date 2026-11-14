"""Build the original fixed parchment bitmap. Never accesses game state or RNG."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/map"
OUT.mkdir(parents=True, exist_ok=True)
WIDTH, HEIGHT = 1024, 2048
rng = np.random.default_rng(261114)


def cloud(width, height, strength):
    values = np.clip(rng.normal(128, strength, (height, width)), 0, 255).astype("uint8")
    return np.asarray(Image.fromarray(values).resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC), dtype=float) - 128


y, x = np.mgrid[0:HEIGHT, 0:WIDTH]
edge = np.minimum(x, WIDTH - 1 - x) / WIDTH
field = cloud(9, 15, 9) + cloud(55, 95, 3) + cloud(240, 410, 1.5)
field += rng.normal(0, 1.1, (HEIGHT, WIDTH))
field -= 20 * np.exp(-edge * 29)
field -= 7 * np.exp(-np.minimum(y, HEIGHT - 1 - y) / 38)
for crease in [.32, .69]:
    axis = WIDTH * crease + np.sin(y / 330) * 1.4
    field -= 8 * np.exp(-((x - axis) / 3.2) ** 2)
    field += 6 * np.exp(-((x - axis - 4) / 3.0) ** 2)
field -= 4 * np.exp(-((y - HEIGHT * .52 - x * .032) / 6) ** 2)
base = np.array([214, 194, 151], dtype=float)
pixels = np.clip(base + field[:, :, None] * np.array([1., .94, .78]), 0, 255).astype("uint8")
paper = Image.fromarray(pixels, "RGB").convert("RGBA")
fibers = Image.new("RGBA", paper.size)
draw = ImageDraw.Draw(fibers)
for _ in range(24500):
    px, py = rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT)
    length = rng.uniform(1, 7)
    angle = rng.uniform(0, np.pi)
    color = (65, 43, 23, int(rng.integers(6, 21))) if rng.random() < .68 else (255, 244, 218, 30)
    draw.line((px, py, px + np.cos(angle) * length, py + np.sin(angle) * length * .36), fill=color, width=1)
paper = Image.alpha_composite(paper, fibers.filter(ImageFilter.GaussianBlur(.25))).convert("RGB")
target = OUT / "parchment-fiber-v1.png"
paper.save(target, optimize=True)
(OUT / "source.json").write_text(json.dumps({
    "asset": target.name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    "dimensions": [WIDTH, HEIGHT], "origin": "original procedural drawing", "generator": "tools/build_map_paper.py",
    "seed": 261114, "date": "2026-11-14", "external_images": [], "game_rng_used": False,
    "purpose": "UIR-019 map and preview paper; not character art"
}, indent=2) + "\n", encoding="utf-8")
print(target.relative_to(ROOT), target.stat().st_size, "bytes")
