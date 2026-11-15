"""Version 8: local leg proportions and one registered head/neck correction.

The selected V5, party version 7 and shared runtime remain inputs, never outputs.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / "assets/art/actor-party"
ART = ROOT / "assets/art/actor-proportions"
RAW = ROOT / "output/imagegen/actor-proportions-20261115"
EV = ROOT / "artifacts/verification/actor-proportions-20261115"
ENTITIES = ("P02", "P03", "P04")
RECORDS: list[dict] = []
LEG_SCALE = {"P02": .78, "P03": .78, "P04": .78}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def disk(resource: str):
    return ROOT / resource.removeprefix("res://")


def absolute(spec):
    result = {}
    for bone in spec["bones"]:
        parent = result.get(bone["parent"], [0, 0])
        result[bone["id"]] = np.asarray(parent) + bone["position"]
    return result


class LegTransform:
    """Continuous waist-to-ankle shortening; upper artwork only translates."""

    def __init__(self, spec, scale):
        rest = absolute(spec)
        self.scale = scale
        self.hip = float(np.mean([rest[x + "_thigh"][1] for x in ("rear", "front")]))
        self.ankle = float(np.mean([rest[x + "_ankle"][1] for x in ("rear", "front")]))
        self.delta = (scale - 1) * (self.hip - self.ankle)

    def y(self, y):
        return np.where(np.asarray(y) < self.hip, np.asarray(y) + self.delta,
                        self.ankle + self.scale * (np.asarray(y) - self.ankle))

    def inverse_y(self, y):
        boundary = self.hip + self.delta
        return np.where(np.asarray(y) < boundary, np.asarray(y) - self.delta,
                        self.ankle + (np.asarray(y) - self.ankle) / self.scale)

    def point(self, point):
        return [round(float(point[0]), 6), round(float(self.y(point[1])), 6)]


def compose(spec):
    canvas = Image.new("RGBA", tuple(spec["canvas"]))
    rest = absolute(spec)
    for part in sorted(spec["parts"], key=lambda x: x.get("z", 0)):
        bitmap = Image.open(disk(part["file"])).convert("RGBA")
        if part.get("mesh"):
            bitmap = bitmap.resize(tuple(round(x) for x in part["size"]), Image.Resampling.LANCZOS)
            position = part["position"]
        else:
            position = rest[part["bone"]] + part.get("offset", [0, 0])
        at = [round(spec["ground"][i] + position[i]) for i in (0, 1)]
        canvas.alpha_composite(bitmap, tuple(at))
    return canvas


def candidates():
    EV.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 23)
    sheet = Image.new("RGB", (1440, 2220), "#e6dfd1")
    draw = ImageDraw.Draw(sheet)
    records = []
    for row, entity in enumerate(ENTITIES):
        spec = read(OLD / entity / "rig.json")
        original = compose(spec)
        for column, scale in enumerate((1.0, .82, .78)):
            transform = LegTransform(spec, scale)
            yy, xx = np.mgrid[:original.height, :original.width].astype(np.float32)
            source_y = (transform.inverse_y(yy - spec["ground"][1]) + spec["ground"][1]).astype(np.float32)
            pixels = cv2.remap(np.asarray(original), xx, source_y, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT)
            frame = Image.fromarray(pixels).resize((448, 683), Image.Resampling.LANCZOS)
            x, y = column * 480 + 16, row * 740 + 42
            sheet.paste(frame, (x, y), frame)
            draw.text((x + 30, y - 31), f"{entity}  " + ("原版" if scale == 1 else f"下肢缩短 {round((1-scale)*100)}%"), fill="#313d3d", font=font)
            records.append({"entity": entity, "scale": scale, "hip_y": transform.hip,
                            "ankle_reference_y": transform.ankle, "upper_translation_y": transform.delta,
                            "same_pixel_scale": True, "scope": "art registration candidates, not engine verification"})
    sheet.save(EV / "proportion-candidates.jpg", quality=94)
    save(EV / "proportion-candidates.json", records)


def emit(entity, name, bitmap, source, processing, **extra):
    path = ART / entity / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    bitmap.save(path)
    RECORDS.append({"file": path.relative_to(ROOT).as_posix(), "sha256": sha(path),
                    "size": list(bitmap.size), "source": source.relative_to(ROOT).as_posix(),
                    "source_sha256": sha(source), "processing": processing, **extra})
    return "res://" + path.relative_to(ROOT).as_posix()


def clean_trunk_neck(bitmap):
    # This source includes the old neck and even a chin corner. Remove those
    # pixels before registering the corrected neck, while retaining both collars.
    from build_actor_party import polygon
    yy, xx = np.mgrid[:bitmap.height, :bitmap.width]
    sx, sy = xx + 298, yy + 201
    region = polygon(bitmap.size, [[132, -35], [246, -35], [241, 37],
                                   [234, 57], [231, 74], [204, 79],
                                   [172, 69], [148, 48], [130, 12]]) > 0
    rgb = np.asarray(bitmap)[:, :, :3].astype(float)
    warm = (rgb[:, :, 0] > rgb[:, :, 1] + 9) & (rgb[:, :, 1] > rgb[:, :, 2] + 9)
    # No source skin is allowed above the top of the generated neck attachment.
    mask = region & warm & (sy < 277) & (sx > 426)
    result = np.asarray(bitmap).copy()
    result[mask] = 0
    return Image.fromarray(result)


def replace_head(entity, spec, transform):
    """One continuous source for head and under-collar overlap; split after resampling."""
    from build_actor_party import keyed, polygon
    source = RAW / "p03-neck-v1.png"
    sheet = np.asarray(keyed(source))
    yy, xx = np.mgrid[:1220, :800].astype(np.float32)
    # Exact input bust: 1.6x, crop (280,10,560,405), paste (32,110).
    # The edited collars moved +6,+66; registration uses collar, not head top.
    full = {}
    for column, variant in enumerate(("neutral", "focus", "hit")):
        sample_x = 1.6 * xx - 410 + column * 512
        sample_y = 1.6 * yy + 160
        pixels = cv2.remap(sheet, sample_x, sample_y, cv2.INTER_CUBIC,
                           borderMode=cv2.BORDER_CONSTANT)
        # Retain the complete head and plain short neck. Everything below the
        # attachment is shirt artwork and belongs to the separately moving torso.
        mask = polygon((800, 1220), [[275, 20], [492, 20], [492, 188],
                                    [431, 211], [422, 223], [420, 228],
                                    [402, 230], [381, 223], [367, 210],
                                    [350, 195], [350, 178], [275, 178]])
        pixels[:, :, 3] = np.minimum(pixels[:, :, 3], mask)
        full[variant] = Image.fromarray(pixels)
    # Fill the original collar opening with a continuous neck underlay anchored
    # to the chest. Letting both neck pieces rotate with the head exposes a pale
    # wedge beside the collar during recoil, even when the neutral image aligns.
    from scipy.ndimage import distance_transform_edt
    neck_envelope = polygon((800, 1220), [[347, 175], [365, 182], [385, 203],
                                         [418, 221], [425, 232], [398, 236],
                                         [370, 224], [348, 197]])
    necks = {}
    for variant, image in full.items():
        pixels = np.asarray(image).copy()
        rgb = pixels[:, :, :3].astype(float)
        # No chin or mouth pixels may live on the static chest attachment.
        # Extend plain sampled neck skin under the moving head and collars.
        valid = (pixels[:, :, 3] > 240) & (yy >= 193) & (yy < 223) & (xx > 359) & (xx < 399)
        valid &= (rgb[:, :, 0] > rgb[:, :, 1] + 9) & (rgb[:, :, 1] > rgb[:, :, 2] + 9)
        valid &= (rgb[:, :, 0] > 175) & (rgb[:, :, 1] > 120)
        nearest = distance_transform_edt(~valid, return_distances=False, return_indices=True)
        fill = cv2.GaussianBlur(pixels[nearest[0], nearest[1], :3], (9, 9), 0)
        underlay = np.zeros_like(pixels)
        underlay[:, :, :3] = fill
        underlay[:, :, 3] = neck_envelope
        necks[variant] = Image.fromarray(underlay)
    # A shared crop and integer-pixel opaque overlap prevent the old resampled
    # horizontal line between two independently cut neck sources.
    boxes = [image.getbbox() for image in [*full.values(), *necks.values()]]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes),
           max(b[2] for b in boxes), max(b[3] for b in boxes))
    rest = absolute(spec)
    top_left = np.array([box[0] - 400, box[1] - 1200 + transform.delta])
    for layer in ("head", "neck_overlap"):
        part = next(p for p in spec["parts"] if p["id"] == layer)
        if layer == "neck_overlap":
            part["bone"] = "loop_chest"
        files = {}
        for variant, canvas in (full if layer == "head" else necks).items():
            crop = canvas.crop(box)
            pixels = np.asarray(crop).copy()
            sy = np.arange(box[1], box[3])[:, None]
            keep = sy <= 217 if layer == "head" else sy >= 175
            pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
            files[variant] = emit(entity, layer + "_" + variant,
                                  Image.fromarray(pixels), source,
                                  "chroma removal; collar registration; shared crop; opaque neck overlap split after final resampling",
                                  source_column=(0, 1, 2)[("neutral", "focus", "hit").index(variant)],
                                  source_to_rig_scale=.625, edited_collar_translation=[6, 66],
                                  registered_box=list(box), opaque_overlap_stage_y=[175, 217],
                                  neck_base_anchored_to_chest=layer == "neck_overlap",
                                  neck_underlay_contains_no_face_contours=layer == "neck_overlap")
        part["file"] = files["neutral"]
        part["offset"] = [round(float(x), 6) for x in top_left - rest[part["bone"]]]
        drawing = next(d for d in spec["drawings"] if d["part"] == layer)
        for variant in drawing["variants"]:
            variant["file"] = files[variant["id"].removeprefix("head_")]
        if layer == "head":
            spec["expression"]["blink"] = files["hit"]
    RECORDS.append({"kind": "P03_continuous_neck_registration", "source": source.relative_to(ROOT).as_posix(),
                    "new_head_neck_source": True, "old_trunk_skin_removed": True,
                    "neck_base_anchored_to_chest": True,
                    "head_width_and_height_scale": 1.0, "upper_translation_y": transform.delta})


def build(entity):
    original = read(OLD / entity / "rig.json")
    spec = deepcopy(original)
    transform = LegTransform(original, LEG_SCALE[entity])
    old_rest = absolute(original)
    rest = {name: np.asarray(transform.point(p)) if name not in ("root", "loop_hips") else p.copy()
            for name, p in old_rest.items()}
    original_bones = {b["id"]: b for b in original["bones"]}
    for bone in spec["bones"]:
        parent = rest.get(bone["parent"], [0, 0])
        bone["position"] = np.round(rest[bone["id"]] - parent, 6).tolist()
    new_bones = {b["id"]: b for b in spec["bones"]}
    # All rigid upper parts retain their bitmap scale; soles also retain exactly
    # the old pixel dimensions, silhouette and ankle offset.
    resources = {p["file"] for p in original["parts"]}
    resources.update(v["file"] for layer in original["drawings"] for v in layer["variants"])
    resources.add(original["expression"]["blink"])
    mapping = {}
    for resource in sorted(resources):
        path = disk(resource)
        if entity == "P03" and path.name.startswith(("head_", "neck_overlap_")):
            # replace_head emits these directly from the new API original.
            mapping[resource] = "res://" + (ART / entity / path.name).relative_to(ROOT).as_posix()
            continue
        image = Image.open(path).convert("RGBA")
        name = path.stem
        processing = "verbatim existing rigid artwork; offset retargeting only"
        part = next((p for p in spec["parts"] if p["file"] == resource), None)
        if part and part.get("mesh"):
            old_top = part["position"][1]
            old_height = part["size"][1]
            new_top = float(transform.y(old_top))
            new_height = float(transform.y(old_top + old_height)) - new_top
            if entity == "P03" and part["id"] == "torso":
                image = clean_trunk_neck(image)
                processing = "old painted neck/chin removed from torso; both garment collars retained"
            if old_top + old_height > transform.hip:
                new_pixel_height = max(1, round(image.height * new_height / old_height))
                yy, xx = np.mgrid[:new_pixel_height, :image.width].astype(np.float32)
                logical_y = new_top + (yy + .5) / new_pixel_height * new_height
                sample_y = ((transform.inverse_y(logical_y) - old_top) / old_height * image.height - .5).astype(np.float32)
                image = Image.fromarray(cv2.remap(np.asarray(image), xx, sample_y, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE))
                processing = "continuous hip/ankle piecewise vertical resample shared with registered joints; " + processing
            part["position"] = [part["position"][0], round(new_top, 6)]
            part["size"][1] = round(new_height, 6)
            if "weight_axis" in part:
                part["weight_axis"] = [transform.point(p) for p in part["weight_axis"]]
            if part["id"].endswith("_leg"):
                prefix = part["id"].split("_")[0]
                fraction = (rest[prefix + "_shin"][1] - new_top) / new_height
                part["weight_range"] = [float(fraction) - .08, float(fraction) + .08]
            if part["id"] == "pelvis":
                part["weight_range"] = [float((transform.y(old_top + t * old_height) - new_top) / new_height)
                                        for t in part["weight_range"]]
        mapping[resource] = emit(entity, name, image, path, processing)
    for part in spec["parts"]:
        part["file"] = mapping[part["file"]]
    for layer in spec["drawings"]:
        for variant in layer["variants"]:
            variant["file"] = mapping[variant["file"]]
    spec["expression"]["blink"] = mapping[spec["expression"]["blink"]]
    for foot, calibration in zip(spec["feet"], spec["anatomy"]["calibration"]):
        name = calibration["name"]
        hip, knee, ankle = [rest[name + suffix].tolist() for suffix in ("_thigh", "_shin", "_ankle")]
        lengths = [math.dist(hip, knee), math.dist(knee, ankle)]
        calibration.update(hip=hip, knee=knee, ankle=ankle, lengths=lengths,
                           source_registration="version7 source landmarks transformed by proportions metadata")
        foot.update(target=ankle, lengths=lengths)
        new_bones[name + "_thigh"]["length"] = lengths[0]
        new_bones[name + "_shin"]["length"] = lengths[1]
    # Position curves are local to the rest pose. Scale the hip displacement with
    # the shorter support while keeping the authored pen/hand gesture intact.
    for animation in [*spec["animations"].values(), {"tracks": spec["idle_tracks"]}]:
        for track in animation["tracks"]:
            if track["property"] != "position":
                continue
            old_local = np.asarray(original_bones[track["bone"]]["position"])
            new_local = np.asarray(new_bones[track["bone"]]["position"])
            amplitude = LEG_SCALE[entity] if track["bone"] == "torso" else 1.0
            track["keys"] = [[t, np.round(new_local + (np.asarray(value) - old_local) * amplitude, 6).tolist()]
                             for t, value in track["keys"]]
    spec["version"] = 8
    spec["anatomy"]["status"] = "registered_pending_engine_and_visual_review"
    spec["proportions"] = {"base_version": 7, "vertical_leg_scale": LEG_SCALE[entity],
                           "hip_y": transform.hip, "ankle_reference_y": transform.ankle,
                           "upper_translation_y": transform.delta, "shoes_rigid": True,
                           "head_neck_repaint": entity == "P03",
                           "selection": "artifacts/verification/actor-proportions-20261115/resource-selection.json"}
    if entity == "P03":
        replace_head(entity, spec, transform)
    return spec


def build_all():
    EV.mkdir(parents=True, exist_ok=True)
    RECORDS.clear()
    for entity in ("P01", "N01"):
        source = OLD / entity / "rig.json"
        destination = ART / entity / "rig.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
    summaries = []
    for entity in ENTITIES:
        spec = build(entity)
        save(ART / entity / "rig.json", spec)
        textures = {p["file"] for p in spec["parts"]}
        textures.update(v["file"] for layer in spec["drawings"] for v in layer["variants"])
        textures.add(spec["expression"]["blink"])
        save(ART / entity / "source.json", {"version": 8, "definition_id": entity, "base_version": 7,
             "status": "registered_pending_engine_and_visual_review", "requirements": read(OLD / entity / "source.json")["requirements"],
             "source_rig": (OLD / entity / "rig.json").relative_to(ROOT).as_posix(),
             "source_rig_sha256": sha(OLD / entity / "rig.json"), "proportions": spec["proportions"],
             "api_manifest": "output/imagegen/actor-proportions-20261115/neck-request.json",
             "textures": [{"file": file.removeprefix("res://"), "sha256": sha(disk(file))} for file in sorted(textures)]})
        image = compose(spec)
        preview = Image.new("RGBA", image.size, "#e6dfd1")
        preview.alpha_composite(image)
        preview.convert("RGB").save(EV / (entity.lower() + "-resource-preview.jpg"), quality=96)
        summaries.append({"entity": entity, "bones": len(spec["bones"]), "parts": len(spec["parts"]),
                          "meshes": sum(bool(p.get("mesh")) for p in spec["parts"]), "textures": len(textures),
                          "proportions": spec["proportions"]})
    save(EV / "extraction.json", {"outputs": RECORDS, "characters": summaries})
    print(json.dumps(summaries, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", action="store_true")
    args = parser.parse_args()
    if args.candidates:
        candidates()
        return
    build_all()


if __name__ == "__main__":
    main()
