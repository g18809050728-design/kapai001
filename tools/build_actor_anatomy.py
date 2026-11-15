"""Build opt-in v5 P01 anatomy from registered, continuous lower-body art.

All lower-body crops share a single source transform. Joint positions are
measured in that source, rather than fitting tilted strips to a straight rig.
Old actors and the game entry point are never rewritten.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import label

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/actor-anatomy-20261115"
ART = ROOT / "assets/art/actor-anatomy"
EV = ROOT / "artifacts/verification/actor-anatomy-20261115"
UPPER_SCALE = .88
HEAD_SCALE = .78
LOWER_SCALE = [.58, .45]
PELVIS_Y = -590.0
RECORDS = []


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource(name):
    return "res://assets/art/actor-anatomy/P01/" + name + ".png"


def emit(name, bitmap, record):
    path = ART / "P01" / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    bitmap.save(path)
    RECORDS.append({"file": path.relative_to(ROOT).as_posix(), "size": list(bitmap.size),
                    "sha256": digest(path), **record})
    return resource(name)


def keyed(path):
    rgba = np.array(Image.open(path).convert("RGBA"))
    rgb = rgba[:, :, :3].astype(float)
    foreground = ~((rgb[:, :, 0] > rgb[:, :, 1] * 1.3 + 20) &
                   (rgb[:, :, 2] > rgb[:, :, 1] * 1.3 + 20))
    components, _ = label(foreground)
    counts = np.bincount(components.ravel())
    counts[0] = 0
    alpha = components == int(counts.argmax())
    rgba[~alpha] = 0
    # Remove background-colored antialias fringe from retained opaque edges.
    spill = np.maximum(0, np.minimum(rgba[:, :, 0].astype(int), rgba[:, :, 2].astype(int)) - rgba[:, :, 1].astype(int) - 28)
    rgba[:, :, 0] = np.maximum(0, rgba[:, :, 0].astype(int) - spill).astype(np.uint8)
    rgba[:, :, 2] = np.maximum(0, rgba[:, :, 2].astype(int) - spill).astype(np.uint8)
    return Image.fromarray(rgba)


def scaled_sprite(file, factor, name):
    source = ROOT / file.removeprefix("res://")
    image = Image.open(source).convert("RGBA")
    return emit(name, image.resize(tuple(round(v * factor) for v in image.size), Image.Resampling.LANCZOS),
                {"source": source.relative_to(ROOT).as_posix(), "source_sha256": digest(source),
                 "processing": "uniform resample of existing registered sprite and its variant canvas", "factor": factor})


def torso_without_baked_arm(file, name):
    source = ROOT / file.removeprefix("res://")
    image = Image.open(source).convert("RGBA")
    rgba = np.array(image)
    yy, xx = np.mgrid[:image.height, :image.width]
    # The old torso drawing included a complete hanging upper sleeve. Leaving
    # it behind a raised independent arm created a second shoulder/arm stump.
    # Keep the collar and trunk, with the moving sleeve overlapping this socket.
    boundary = np.interp(yy, [0, 55, 80, 120, 190, 250, 290, 330, 460], [0, 0, 35, 100, 112, 78, 58, 0, 0])
    mask = np.clip((xx - boundary + .5), 0, 1)
    rgba[:, :, 3] = np.minimum(rgba[:, :, 3], np.round(mask * 255).astype(np.uint8))
    return emit(name, Image.fromarray(rgba), {"source": source.relative_to(ROOT).as_posix(), "source_sha256": digest(source),
                "processing": "remove baked viewer-left sleeve beneath the separately rotating upper arm; original canvas retained",
                "socket_boundary": [[0, 0], [55, 0], [80, 35], [120, 100], [190, 112], [250, 78], [290, 58], [330, 0], [460, 0]]})


def lower_art():
    source = RAW / "lowerbody-balanced-v2.png"
    image = keyed(source)
    alpha = np.array(image.getchannel("A"))
    height, width = alpha.shape
    yy, xx = np.mgrid[:height, :width]
    rear = (xx < 515) & (yy >= 175)
    front = (xx >= 515) & (yy >= 175)
    rear_bottom = int(np.where((alpha > 0) & rear)[0].max()) + 1
    front_bottom = int(np.where((alpha > 0) & front)[0].max()) + 1
    front_shift = rear_bottom - front_bottom

    def mapped(point, shift=0):
        return [round((point[0] - 510) * LOWER_SCALE[0], 6),
                round((point[1] + shift - rear_bottom) * LOWER_SCALE[1], 6)]

    def extract(name, mask, shift=0):
        piece = image.copy()
        piece.putalpha(Image.fromarray(np.minimum(alpha, np.asarray(mask, dtype=np.uint8))))
        box = piece.getbbox()
        assert box is not None
        bitmap = piece.crop(box)
        bounds = mapped(box[:2], shift)
        size = [round(bitmap.width * LOWER_SCALE[0], 6), round(bitmap.height * LOWER_SCALE[1], 6)]
        # Keep high-resolution original pixels for meshes. The rectangle uses
        # the shared source transform, not independent leg width/length fits.
        file = emit(name, bitmap, {"source": source.relative_to(ROOT).as_posix(), "source_sha256": digest(source),
                    "source_crop": list(box), "source_shift_y": shift, "source_scale": LOWER_SCALE,
                    "skeleton_bounds": [*bounds, *size], "processing": "shared source coordinates; alpha crop, no per-leg squashing"})
        return {"file": file, "position": bounds, "size": size, "source_box": list(box), "bitmap": bitmap}

    # The continuous waist/crotch covers the overlapping thigh roots. It is
    # opaque above the crotch and fades only inside existing trouser fabric.
    pelvis_alpha = np.where(yy <= 360, 255, np.clip((455 - yy) / 95, 0, 1) * 255).astype(np.uint8)
    pelvis = extract("pelvis", pelvis_alpha)
    legs = []
    for name, region, shift, knee, ankle, hip_x, cuff in [
        ("rear", rear, 0, [400, 730], [360, 1290], 405, 1296),
        ("front", front, front_shift, [650, 720], [637, 1274], 615, 1286),
    ]:
        # Skinning ends at the cuff. Shoes use a rigid ankle sprite, so their
        # soles and toe shape cannot collapse into the calf deformation.
        leg = extract(name + "_leg", ((region & (yy < cuff)) * 255).astype(np.uint8), shift)
        shoe = extract(name + "_shoe", ((region & (yy >= cuff - 44)) * 255).astype(np.uint8), shift)
        hip = [round((hip_x - 510) * LOWER_SCALE[0], 6), PELVIS_Y]
        knee_point = mapped(knee, shift)
        ankle_point = mapped(ankle, shift)
        lengths = [math.dist(hip, knee_point), math.dist(knee_point, ankle_point)]
        cross = ((knee_point[0] - hip[0]) * (ankle_point[1] - knee_point[1]) -
                 (knee_point[1] - hip[1]) * (ankle_point[0] - knee_point[0]))
        legs.append({"name": name, "mesh": leg, "shoe": shoe, "hip": hip, "knee": knee_point, "ankle": ankle_point,
                     "lengths": lengths, "bend": -1 if cross > 0 else 1,
                     "source_knee": knee, "source_ankle": ankle, "source_shift_y": shift})
    return image, pelvis, legs, mapped


def hero():
    old = read(ROOT / "assets/art/actor-rig-drawings/P01/rig.json")
    spec = deepcopy(old)
    spec.update(version=5, upright_bones=["pelvis"], anatomy={"upper_scale": UPPER_SCALE, "head_scale": HEAD_SCALE,
                "source_transform": LOWER_SCALE, "status": "pending_rendered_visual_review"})
    old_bones = {b["id"]: b for b in old["bones"]}
    spec["bones"] = [b for b in spec["bones"] if not b["id"].startswith(("rear_", "front_"))]
    for bone in spec["bones"]:
        bone["position"] = [v * UPPER_SCALE for v in bone["position"]]
        if bone["id"] == "torso":
            bone["position"] = [0, PELVIS_Y]
    torso_index = next(i for i, b in enumerate(spec["bones"]) if b["id"] == "torso")
    spec["bones"].insert(torso_index + 1, {"id": "pelvis", "parent": "torso", "position": [0, 0], "length": 110})
    spec["parts"] = [p for p in spec["parts"] if p["id"] not in ("rear_leg", "front_leg")]
    for part in spec["parts"]:
        factor = HEAD_SCALE if part["id"] in ("head", "neck_overlap") else UPPER_SCALE
        if part.get("mesh"):
            part["position"] = [part["position"][0] * UPPER_SCALE, PELVIS_Y + (part["position"][1] + 508) * UPPER_SCALE]
            part["size"] = [v * UPPER_SCALE for v in part["size"]]
            if "weight_axis" in part:
                part["weight_axis"] = [[x * UPPER_SCALE, PELVIS_Y + (y + 508) * UPPER_SCALE] for x, y in part["weight_axis"]]
            if part["id"] in ("near_upper", "far_upper"):
                # The painted sleeve is an upper arm, not a cloth bridge
                # between a fixed shoulder and a rotating elbow. Both ends
                # share its rigid humerus rotation; the shoulder cap overlaps
                # the jacket. This avoids the old stretched crescent at strike.
                part["bone"] = part["id"]
            if part["id"] == "torso":
                part["file"] = torso_without_baked_arm(part["file"], "torso_neutral")
        else:
            part["offset"] = [v * factor for v in part["offset"]]
            part["file"] = scaled_sprite(part["file"], factor, part["id"] + "_neutral")
    for layer in spec["drawings"]:
        if layer["part"] == "torso":
            for variant in layer["variants"]:
                variant["file"] = torso_without_baked_arm(variant["file"], variant["id"])
            continue  # Existing mesh UVs retain the original registered canvas.
        factor = HEAD_SCALE if layer["part"] == "head" else UPPER_SCALE
        for variant in layer["variants"]:
            variant["file"] = scaled_sprite(variant["file"], factor, variant["id"])
    spec["expression"]["blink"] = scaled_sprite(spec["expression"]["blink"], HEAD_SCALE, "head_blink")
    spec["held_contact"]["point"] = [v * UPPER_SCALE for v in spec["held_contact"]["point"]]

    for animation in spec["animations"].values():
        for curve in animation["tracks"]:
            if curve["property"] == "position":
                if curve["bone"] == "torso":
                    # A subtle forward weight transfer, with no forced full
                    # extension or upward hip overshoot in the new relaxed stance.
                    curve["keys"] = [[t, [value[0] * .8, PELVIS_Y + max(0, value[1] + 508) * .7]] for t, value in curve["keys"]]
                else:
                    curve["keys"] = [[t, [v * UPPER_SCALE for v in value]] for t, value in curve["keys"]]
    # Leave a small positive settling height before the final rest key. Cubic
    # interpolation across an early zero used to overshoot above the stance,
    # making both nearly straight legs unreachable during recovery.
    for pose, time in [("hit", .56), ("enter", .30)]:
        for curve in spec["animations"][pose]["tracks"]:
            if curve["bone"] == "torso" and curve["property"] == "position":
                curve["keys"] = [[t, [value[0], PELVIS_Y + 2.0] if abs(t - time) < .00001 else list(value)] for t, value in curve["keys"]]
    for curve in spec["idle_tracks"]:
        if curve["property"] == "position":
            # The newly drawn near-straight stance does not need the old hip
            # bob. Breathing remains in the independent chest, head and hands.
            factors = [.2 / 7, 0] if curve["bone"] == "loop_hips" else [UPPER_SCALE, UPPER_SCALE]
            curve["keys"] = [[t, [v * factors[i] for i, v in enumerate(value)]] for t, value in curve["keys"]]

    raw, pelvis, legs, mapped = lower_art()
    # A Sprite2D is rigid here. Produce its actual transformed pixel size and
    # use a source-space crop for the diagnostic preview and overlap checks.
    def sprite(item, name, parent, anchor, z):
        bitmap = item["bitmap"].resize(tuple(round(v) for v in item["size"]), Image.Resampling.LANCZOS)
        file = emit(name + "_registered", bitmap, {"source": item["file"].removeprefix("res://"),
                    "processing": "shared lower-body transform resample for rigid sprite", "source_scale": LOWER_SCALE})
        return {"id": name, "bone": parent, "offset": [item["position"][i] - anchor[i] for i in range(2)], "z": z, "file": file}

    # Keep the registered source preview in the extraction record. The live
    # pelvis uses three weights: waistband follows the pelvis; lower left and
    # right overlap follow their own thigh, avoiding a rigid extra pant flap.
    sprite(pelvis, "pelvis", "pelvis", [0, PELVIS_Y], -1)
    spec["parts"].append({"id": "pelvis", "mesh": True, "bone": "pelvis", "base_bone": "rear_thigh", "split_bone": "front_thigh",
                          "position": pelvis["position"], "size": pelvis["size"], "z": -1, "cells": 16,
                          "weight_range": [.24, .82], "split_range": [.40, .62], "file": pelvis["file"]})
    spec["feet"] = []
    calibration = []
    for leg in legs:
        name = leg["name"]
        hip, knee, ankle = leg["hip"], leg["knee"], leg["ankle"]
        for id_, parent, point, parent_point, length_ in [
            (name + "_thigh", "pelvis", hip, [0, PELVIS_Y], leg["lengths"][0]),
            (name + "_shin", name + "_thigh", knee, hip, leg["lengths"][1]),
            (name + "_ankle", name + "_shin", ankle, knee, 65),
        ]:
            spec["bones"].append({"id": id_, "parent": parent, "position": [round(point[i] - parent_point[i], 6) for i in range(2)], "length": length_})
        bounds = leg["mesh"]
        knee_fraction = (knee[1] - bounds["position"][1]) / bounds["size"][1]
        spec["parts"].append({"id": name + "_leg", "mesh": True, "bone": name + "_thigh", "base_bone": name + "_shin",
                              "position": bounds["position"], "size": bounds["size"], "z": -3 if name == "rear" else -2,
                              "cells": 16, "weight_range": [knee_fraction - .075, knee_fraction + .075], "file": bounds["file"]})
        spec["parts"].append(sprite(leg["shoe"], name + "_shoe", name + "_ankle", ankle, -4))
        spec["feet"].append({"upper": name + "_thigh", "lower": name + "_shin", "ankle": name + "_ankle",
                             "target": ankle, "lengths": leg["lengths"], "bend": leg["bend"], "bind_axes": True})
        calibration.append({key: leg[key] for key in ["name", "hip", "knee", "ankle", "lengths", "source_knee", "source_ankle", "source_shift_y"]})
    spec["contact_shadows"] = [[leg["ankle"][0] + (20 if leg["name"] == "front" else 0), 0, 58, 11] for leg in legs]
    spec["cast_shadows"] = [[-20, 9, 180, 16]]
    spec["anatomy"]["calibration"] = calibration
    preview(spec, raw, mapped)
    return spec


def preview(spec, raw, mapped):
    """Resource composition, clearly distinct from subsequent Godot evidence."""
    positions = {}
    for bone in spec["bones"]:
        parent = positions.get(bone["parent"], [0, 0])
        positions[bone["id"]] = [parent[i] + bone["position"][i] for i in range(2)]
    canvas = Image.new("RGBA", (950, 1300), "#e6dfd1")
    origin = [360, 1230]
    for part in sorted(spec["parts"], key=lambda p: p["z"]):
        texture = Image.open(ROOT / part["file"].removeprefix("res://")).convert("RGBA")
        if part.get("mesh"):
            point = part["position"]
            texture = texture.resize(tuple(round(v) for v in part["size"]), Image.Resampling.LANCZOS)
        else:
            point = [positions[part["bone"]][i] + part["offset"][i] for i in range(2)]
        canvas.alpha_composite(texture, tuple(round(origin[i] + point[i]) for i in range(2)))
    painter = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    painter.text((20, 15), "v5 资源静止构图预览（后续另存Godot实渲）", font=font, fill="#26353e")
    painter.line([(50, 1230), (880, 1230)], fill="#837f73", width=2)
    canvas.convert("RGB").save(EV / "resource-neutral-preview.jpg", quality=96)
    joints = canvas.copy()
    draw = ImageDraw.Draw(joints)
    for item in spec["anatomy"]["calibration"]:
        points = [tuple(origin[i] + item[key][i] for i in range(2)) for key in ["hip", "knee", "ankle"]]
        draw.line(points, fill="#d27028", width=4)
        for point in points:
            draw.ellipse((point[0] - 6, point[1] - 6, point[0] + 6, point[1] + 6), fill="#edab49")
    joints.convert("RGB").save(EV / "resource-joint-registration.jpg", quality=96)


def main():
    EV.mkdir(parents=True, exist_ok=True)
    RECORDS.clear()
    spec = hero()
    save(ART / "P01/rig.json", spec)
    # The enemy is unchanged, with its explicit v4 texture paths intact.
    enemy = read(ROOT / "assets/art/actor-rig-drawings/N01/rig.json")
    save(ART / "N01/rig.json", enemy)
    for entity, value in [("P01", spec), ("N01", enemy)]:
        files = {p["file"].removeprefix("res://") for p in value["parts"]}
        files.update(v["file"].removeprefix("res://") for d in value.get("drawings", []) for v in d["variants"])
        if "expression" in value:
            files.add(value["expression"]["blink"].removeprefix("res://"))
        save(ART / entity / "source.json", {"version": value["version"], "status": "pending_rendered_visual_review",
                    "source_rig": f"assets/art/actor-rig-drawings/{entity}/rig.json", "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
                    "api_manifest": "output/imagegen/actor-anatomy-20261115/asset-manifest.json",
                    "textures": [{"file": file, "sha256": digest(ROOT / file)} for file in sorted(files)]})
    save(EV / "extraction.json", {"outputs": RECORDS, "count": len(RECORDS), "calibration": spec["anatomy"]["calibration"]})
    print(json.dumps({"bones": len(spec["bones"]), "parts": len(spec["parts"]), "outputs": len(RECORDS)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
