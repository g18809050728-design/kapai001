"""Derive prototype silhouettes from reviewed portraits; preserve originals."""
from collections import deque
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/presentation-v2/actors"


def main():
    labels = json.loads((ROOT / "src/ui/ui_labels.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for key, name in labels["textures"].items():
        if key not in ("P01", "P02", "P03", "P04") and not key.startswith("R3-U"):
            continue
        source = ROOT / name.removeprefix("res://")
        picture = Image.open(source).convert("RGBA")
        picture.thumbnail((512, 640), Image.Resampling.LANCZOS)
        width, height = picture.size
        pixels = picture.load()
        visited = bytearray(width * height)
        pending = deque()
        def enqueue(x, y):
            i = y * width + x
            if visited[i]:
                return
            visited[i] = 1
            r, g, b, _ = pixels[x, y]
            if r >= 226 and g >= 215 and b >= 190 and max(r,g,b)-min(r,g,b) < 60:
                pending.append((x,y))
        for x in range(width):
            enqueue(x,0)
            enqueue(x,height-1)
        for y in range(height):
            enqueue(0,y)
            enqueue(width-1,y)
        alpha = Image.new("L",picture.size,255)
        mask = alpha.load()
        while pending:
            x, y = pending.popleft()
            mask[x,y] = 0
            for dx,dy in ((-1,0),(1,0),(0,-1),(0,1)):
                nx,ny = x+dx,y+dy
                if 0 <= nx < width and 0 <= ny < height:
                    enqueue(nx,ny)
        # White shirts and held papers touch the lower image edge. Keep the
        # interior between surviving ink outlines rather than cutting holes in it.
        draw = ImageDraw.Draw(alpha)
        for y in range(round(height * .38), height):
            occupied = [x for x in range(width) if mask[x,y] > 0]
            if occupied:
                draw.line((occupied[0],y,occupied[-1],y),fill=255)
        picture.putalpha(alpha.filter(ImageFilter.GaussianBlur(.35)))
        output = OUT / (key + ".png")
        picture.save(output)
        entries.append({"content_id": key, "requirement": "UIR-003/011/013", "source": name,
                        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "file": output.relative_to(ROOT).as_posix(), "size": list(picture.size),
                        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                        "method": "edge-connected pale background flood fill; lower silhouette row fill protects white garments/papers; 0.35px alpha feather; original retained",
                        "status": "prototype_cutout; not final layered character animation"})
    manifest = {"version": 1, "date": "2026-11-13", "paid_generation_requests": 0, "assets": entries}
    (OUT.parent / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"Prepared {len(entries)} transparent prototype portraits; original images unchanged.")


if __name__ == "__main__":
    main()
