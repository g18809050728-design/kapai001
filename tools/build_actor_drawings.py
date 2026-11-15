"""Build v4 registered drawing canvases; previous art and rigs are read only."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label

import build_actor_motion_polish as curves

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/actor-rig-drawings-20261115"
OUT = ROOT / "assets/art/actor-rig-drawings"
EV = ROOT / "artifacts/verification/actor-rig-drawings-20261115"
RECORDS = []


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def resource(entity, name):
    return f"res://assets/art/actor-rig-drawings/{entity}/{name}.png"


def write_image(entity, name, image, record):
    path = OUT / entity / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    RECORDS.append({"file": path.relative_to(ROOT).as_posix(), "size": list(image.size),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **record})


def keyed(file, region):
    source = Image.open(RAW / file).convert("RGBA")
    rgba = np.array(source.crop(region))
    rgb = rgba[:, :, :3].astype(float)
    foreground = ~((rgb[:, :, 0] > rgb[:, :, 1] * 1.3 + 20) & (rgb[:, :, 2] > rgb[:, :, 1] * 1.3 + 20))
    components, _ = label(foreground)
    counts = np.bincount(components.ravel())
    counts[0] = 0
    # These inspected components are each contiguous; reject disconnected
    # magenta artifacts instead of silently including a neighboring drawing.
    mask = components == int(counts.argmax())
    rgba[~mask] = [0, 0, 0, 0]
    pic = Image.fromarray(rgba)
    box = pic.getbbox()
    return pic.crop(box), [region[0] + box[0], region[1] + box[1], region[0] + box[2], region[1] + box[3]]


def drawing(entity, name, file, region, canvas, *, size=None, scale=None, anchor=None, target=None):
    pic, box = keyed(file, region)
    source_size = pic.size
    if size is None:
        size = [round(pic.width * scale), round(pic.height * scale)]
    factors = [size[i] / source_size[i] for i in range(2)]
    origin = [0, 0] if anchor is None else [round(target[i] - (anchor[i] - box[i]) * factors[i]) for i in range(2)]
    assert origin[0] >= 0 and origin[1] >= 0, (name, origin)
    assert all(origin[i] + size[i] <= canvas[i] for i in range(2)), (name, origin, size, canvas)
    image = Image.new("RGBA", canvas)
    image.alpha_composite(pic.resize(size, Image.Resampling.LANCZOS), origin)
    write_image(entity, name, image, {"source": (RAW / file).relative_to(ROOT).as_posix(), "source_sha256": hashlib.sha256((RAW / file).read_bytes()).hexdigest(),
        "region": region, "component_box": box, "source_anchor": anchor, "target_anchor": target,
        "resized_size": size, "paste_origin": origin, "processing": "largest connected non-magenta component; RGB key R/G and B/G > 1.3 + 20; registered RGBA Lanczos canvas"})


def padded(entity, name, source, canvas, offset):
    image = Image.new("RGBA", canvas)
    image.alpha_composite(Image.open(ROOT / source).convert("RGBA"), offset)
    write_image(entity, name, image, {"source": source, "source_sha256": hashlib.sha256((ROOT / source).read_bytes()).hexdigest(),
        "processing": "unchanged RGBA pasted in registered canvas", "paste_origin": offset})


def art():
    neck_source = "assets/art/actor-rig-pilot/P01/head.png"
    neck = Image.open(ROOT / neck_source).convert("RGBA").crop((52, 207, 154, 265)).resize((92, 65), Image.Resampling.LANCZOS)
    mask = Image.new("L", neck.size)
    ImageDraw.Draw(mask).polygon([(8, 0), (87, 0), (80, 64), (12, 64)], fill=255)
    neck.putalpha(Image.fromarray(np.minimum(np.asarray(neck.getchannel("A")), np.asarray(mask))))
    write_image("P01", "neck_overlap", neck, {"source": neck_source, "source_sha256": hashlib.sha256((ROOT / neck_source).read_bytes()).hexdigest(),
        "processing": "original neck crop [52,207,154,265] resized to 92x65; tapered alpha overlap behind the jacket collar"})
    for name, source in [("head_neutral", "assets/art/actor-rig-pilot/P01/head.png"), ("head_blink", "assets/art/actor-rig-refinement/P01/head_blink.png")]:
        padded("P01", name, source, (300, 300), (35, 30))
    for name, region, anchor in [("head_turn", (0, 0, 512, 1024), (225, 802)),
                                  ("head_strike", (512, 0, 1026, 1024), (740, 802)),
                                  ("head_hit", (1026, 0, 1536, 1024), (1260, 802))]:
        drawing("P01", name, "P01-heads-v2.png", region, (300, 300), size=(230, 265), anchor=anchor, target=(155, 290))
    padded("P01", "arm_neutral", "assets/art/actor-rig-pilot/P01/near_forearm.png", (400, 270), (41, 13))
    drawing("P01", "arm_strike", "P01-strike-arm-v1.png", (0, 0, 830, 1024), (400, 270), scale=.38, anchor=(122, 492), target=(80, 135))
    drawing("P01", "arm_follow", "P01-strike-arm-v1.png", (830, 0, 1536, 1024), (400, 270), scale=.45, anchor=(940, 491), target=(80, 135))
    for name, region in [("torso_turn", (0, 0, 800, 1024)), ("torso_strike", (800, 0, 1536, 1024))]:
        drawing("P01", name, "P01-turn-torso-v1.png", region, (350, 460), size=(350, 460))
    for name, region in [("body_windup", (0, 0, 535, 1024)), ("body_strike", (535, 0, 1028, 1024)), ("body_hit", (1028, 0, 1536, 1024))]:
        drawing("N01", name, "N01-face-poses-v1.png", region, (490, 650), size=(490, 650))
    drawing("N01", "fan_fold", "N01-fan-poses-v1.png", (0, 0, 650, 1024), (500, 440), scale=.56, anchor=(422, 852), target=(175, 423))
    drawing("N01", "fan_spread", "N01-fan-poses-v1.png", (650, 0, 1536, 1024), (500, 440), scale=.56, anchor=(1018, 855), target=(175, 423))


def weights(*keys):
    result = []
    for t, index in keys:
        value = [0, 0, 0, 0]
        value[index] = 1
        result.append([t, value])
    # Long dissolves produce double eyes/hands in slow review. Hold the
    # registered source then cross to the next drawing during a short accent.
    tight = [result[0]]
    for right in result[1:]:
        left = tight[-1]
        if left[1] != right[1] and right[0] - left[0] > .035:
            tight.append([round(right[0] - .035, 6), list(left[1])])
        tight.append(right)
    return tight


def layer(entity, part, variants, poses):
    return {"part": part, "variants": [{"id": name, "file": resource(entity, name)} for name in variants], "poses": poses}


def replace(spec, pose, *tracks):
    channels = {(t["bone"], t["property"]) for t in tracks}
    definition = spec["animations"][pose]
    definition["tracks"] = [t for t in definition["tracks"] if (t["bone"], t["property"]) not in channels] + list(tracks)


def hero():
    spec = json.loads((ROOT / "assets/art/actor-rig-refinement/P01/rig.json").read_text(encoding="utf-8"))
    spec.update(version=4, drawing_blend_seconds=.11)
    spec["parts"].append({"id": "neck_overlap", "bone": "loop_head", "offset": [-44, -1], "z": -1, "file": resource("P01", "neck_overlap")})
    for part in spec["parts"]:
        if part["id"] == "head":
            part.update(file=resource("P01", "head_neutral"), offset=[-150, -273])
        if part["id"] == "near_forearm":
            part.update(file=resource("P01", "arm_neutral"), offset=[-80, -135], z=8)
    spec["expression"]["blink"] = resource("P01", "head_blink")
    spec["drawings"] = [
        layer("P01", "head", ["head_turn", "head_strike", "head_hit"], {
            "action": weights((0, 0), (.10, 1), (.27, 1), (.35, 2), (.65, 2), (.83, 0), (1, 0)),
            "hit": weights((0, 0), (.055, 3), (.42, 3), (.70, 0), (1, 0)),
            "guard": weights((0, 0), (.20, 2), (.62, 2), (.85, 0), (1, 0)),
            "phase": weights((0, 0), (.20, 1), (.45, 2), (.70, 0), (1, 0)),
        }),
        layer("P01", "torso", ["torso_turn", "torso_strike"], {
            "action": weights((0, 0), (.13, 1), (.27, 1), (.35, 2), (.60, 2), (.85, 0), (1, 0)),
        }),
        layer("P01", "near_forearm", ["arm_strike", "arm_follow"], {
            "action": weights((0, 0), (.29, 0), (.37, 1), (.58, 1), (.69, 2), (.78, 2), (.94, 0), (1, 0)),
        }),
    ]
    replace(spec, "action",
        curves.rotation("near_upper", [[0, 0], [.18, .24], [.28, .19], [.39, -1.80], [.53, -1.74], [.68, -.98], [.84, -.20], [1, 0]]),
        curves.rotation("near_forearm", [[0, 0], [.19, -.36], [.28, -.28], [.39, 1.64], [.53, 1.62], [.68, .81], [.84, .16], [1, 0]]),
        curves.rotation("head", [[0, 0], [.19, .06], [.29, .025], [.39, -.105], [.61, -.075], [.85, .015], [1, 0]]),
        curves.position("action_tip", [220, -65], [[0, [0, 0]], [.29, [0, 0]], [.37, [41, 52]], [.58, [41, 52]], [.69, [27, 157]], [.78, [27, 157]], [.94, [0, 0]], [1, [0, 0]]]),
    )
    # A focused peak reads at base x4 without changing any global speed.
    spec["contact_fraction"] = .40
    return curves.complete(spec, spec["animations"])


def enemy():
    spec = json.loads((ROOT / "assets/art/actor-rig-refinement/N01/rig.json").read_text(encoding="utf-8"))
    spec.update(version=4, drawing_blend_seconds=.10, contact_fraction=.40)
    spec["drawings"] = [
        layer("N01", "body", ["body_windup", "body_strike", "body_hit"], {
            "action": weights((0, 0), (.13, 1), (.28, 1), (.36, 2), (.58, 2), (.83, 0), (1, 0)),
            "hit": weights((0, 0), (.05, 3), (.40, 3), (.70, 0), (1, 0)),
            "guard": weights((0, 0), (.23, 1), (.60, 1), (.84, 0), (1, 0)),
        }),
        layer("N01", "fan", ["fan_fold", "fan_spread"], {
            "action": weights((0, 0), (.16, 1), (.29, 1), (.41, 2), (.62, 2), (.90, 0), (1, 0)),
            "hit": weights((0, 0), (.12, 2), (.38, 2), (.73, 0), (1, 0)),
        }),
    ]
    replace(spec, "action",
        curves.rotation("torso", [[0, 0], [.20, .12], [.29, .15], [.40, -.16], [.55, -.13], [.76, .035], [1, 0]]),
        curves.rotation("pencil", [[0, 0], [.22, .47], [.29, .50], [.40, .11], [.55, .08], [.78, -.02], [1, 0]]),
        curves.position("pencil", [-155, -50], [[0, [0, 0]], [.24, [17, 4]], [.4, [-34, -2]], [.57, [-27, 0]], [.78, [6, 0]], [1, [0, 0]]]),
    )
    return curves.complete(spec, spec["animations"])


def main():
    RECORDS.clear()
    art()
    for entity, spec in [("P01", hero()), ("N01", enemy())]:
        save(OUT / entity / "rig.json", spec)
        files = {p["file"].removeprefix("res://") for p in spec["parts"]}
        files.update(v["file"].removeprefix("res://") for d in spec["drawings"] for v in d["variants"])
        if "expression" in spec:
            files.add(spec["expression"]["blink"].removeprefix("res://"))
        save(OUT / entity / "source.json", {"version": 4, "status": "implemented_pending_user_visual_review", "source_rig": f"assets/art/actor-rig-refinement/{entity}/rig.json",
            "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
            "api_manifest": "output/imagegen/actor-rig-drawings-20261115/asset-manifest.json",
            "processing": [p for p in RECORDS if f"/{entity}/" in p["file"]],
            "textures": [{"file": p, "sha256": hashlib.sha256((ROOT / p).read_bytes()).hexdigest()} for p in sorted(files)]})
        print(f"{entity}: {len(spec['bones'])} bones, {len(spec['drawings'])} drawing layers")
    save(EV / "extraction.json", {"outputs": RECORDS, "count": len(RECORDS), "art_acceptance": "technical and visual inspection are separate; final user art acceptance pending"})


if __name__ == "__main__":
    main()
