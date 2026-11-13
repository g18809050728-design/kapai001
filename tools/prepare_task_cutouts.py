"""Derive paper task silhouettes from existing art; never modify source images."""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/presentation-v3"


def derive(source: Path) -> Image.Image:
    picture = Image.open(source).convert("RGBA")
    picture.thumbnail((640, 640), Image.Resampling.LANCZOS)
    rgb = np.array(picture)[:, :, :3]
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    ink = np.uint8((gray < 205) | ((hsv[:, :, 1] > 65) & (gray < 235))) * 255
    # Ignore isolated texture flecks and the thin neighbouring-tile remnants
    # present at the top of a few original atlas crops.
    count, components, stats, _ = cv2.connectedComponentsWithStats(ink)
    clean = np.zeros_like(ink)
    for index in range(1, count):
        x, y, width, height, area = stats[index]
        if area < 30 or (y == 0 and height < picture.height * .065):
            continue
        clean[components == index] = 255
    points = cv2.findNonZero(clean)
    if points is None:
        raise ValueError(f"No task silhouette: {source}")
    # An opaque convex paper envelope preserves pale sheets and notebook
    # interiors, rather than punching holes through white foreground paper.
    mask = np.zeros_like(ink)
    cv2.fillConvexPoly(mask, cv2.convexHull(points), 255)
    mask = cv2.dilate(mask, np.ones((5, 5), dtype=np.uint8))
    alpha = Image.fromarray(mask).filter(ImageFilter.GaussianBlur(.65))
    picture.putalpha(alpha)
    bounds = alpha.getbbox()
    return picture.crop(bounds)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ids", nargs="*")
    args = parser.parse_args()
    labels = json.loads((ROOT / "src/ui/ui_labels.json").read_text(encoding="utf-8"))
    destination = OUT / "tasks"
    destination.mkdir(parents=True, exist_ok=True)
    entries = []
    for key, path in labels["textures"].items():
        if "/tasks/" not in path or (args.ids and key not in args.ids):
            continue
        source = ROOT / path.removeprefix("res://")
        output = destination / f"{key}.png"
        picture = derive(source)
        picture.save(output)
        entries.append({"id": key, "requirement": "UIR-012/027", "source": path,
                        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "file": output.relative_to(ROOT).as_posix(), "size": list(picture.size),
                        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                        "method": "640px maximum; ink/chroma mask; remove tiny/top-strip atlas noise; convex opaque paper envelope; 2px dilation; 0.65px alpha feather; trim transparent bounds",
                        "limitations": "Prototype envelope retains paper between objects; no reconstructed off-frame art or final animation layers"})
    manifest = {"version": 1, "date": "2026-11-13", "paid_generation_requests": 0,
                "sample_only": bool(args.ids), "assets": entries,
                "visual_review": "pending; audit and view the contact sheets before runtime use"}
    (OUT / ("samples.json" if args.ids else "manifest.json")).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Derived {len(entries)} task silhouettes; sources unchanged.")


if __name__ == "__main__":
    main()
