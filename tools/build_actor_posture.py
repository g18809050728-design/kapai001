"""Retain V8 proportions and correct P03's actual resting head/neck pose."""
import argparse
from copy import deepcopy
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from build_actor_proportions import absolute, compose, disk, read, save, sha

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / "assets/art/actor-proportions"
ART = ROOT / "assets/art/actor-posture"
EV = ROOT / "artifacts/verification/actor-posture-20261115"
CHOICES = {
    "v8": {"angle": 0, "shift": [0, 0]},
    "upright-a": {"angle": 8, "shift": [-8, -4]},
    "upright-b": {"angle": 12, "shift": [-14, -6]},
}
SELECTED = "upright-b"
RAW = ROOT / "output/imagegen/actor-posture-20261115"


def raster_on_stage(spec, part, file):
    image = Image.new("RGBA", tuple(spec["canvas"]))
    rest = absolute(spec)
    xy = rest[part["bone"]] + part["offset"] + spec["ground"]
    image.alpha_composite(Image.open(disk(file)).convert("RGBA"), tuple(round(v) for v in xy))
    return image


def warp(image, setting):
    if setting["angle"] == 0:
        return image.copy()
    # The entire face stays rigid. Neck skin is reconstructed separately so
    # lifting the chin cannot expose the old horizontal split below it.
    pivot = [390., 350.]
    matrix = cv2.getRotationMatrix2D(tuple(pivot), setting["angle"], 1.)
    matrix[:, 2] += setting["shift"]
    inverse = cv2.invertAffineTransform(matrix)
    yy, xx = np.mgrid[:image.height, :image.width].astype(np.float32)
    sx = inverse[0, 0] * xx + inverse[0, 1] * yy + inverse[0, 2]
    sy = inverse[1, 0] * xx + inverse[1, 1] * yy + inverse[1, 2]
    sx = sx.astype(np.float32)
    sy = sy.astype(np.float32)
    return Image.fromarray(cv2.remap(np.asarray(image), sx, sy, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT))


def layers(spec, setting):
    from build_actor_party import polygon
    from scipy.ndimage import distance_transform_edt
    result = {}
    for part in spec["parts"]:
        if part["id"] not in ("head", "neck_overlap"):
            continue
        drawing = next(d for d in spec["drawings"] if d["part"] == part["id"])
        sources = {"neutral": part["file"], **{v["id"].removeprefix("head_"): v["file"] for v in drawing["variants"]}}
        result[part["id"]] = {key: raster_on_stage(spec, part, file) for key, file in sources.items()}
    if setting["angle"] == 0:
        return result
    matrix = cv2.getRotationMatrix2D((390., 350.), setting["angle"], 1.)
    matrix[:, 2] += setting["shift"]
    def point(x, y):
        return (matrix @ np.array([x, y, 1.])).tolist()
    # Same fixed collar opening as V8, but the top now meets the retracted jaw.
    envelope = [point(347, 288), point(362, 295), point(382, 312),
                point(414, 331), [427, 350], [401, 359], [369, 347],
                [349, 326], point(344, 310)]
    mask = polygon(tuple(spec["canvas"]), envelope)
    yy, xx = np.mgrid[:spec["canvas"][1], :spec["canvas"][0]]
    jaw_line = np.interp(xx, [0, 347, 355, 363, 414, 423, 445, 800],
                       [310, 310, 297, 301, 334, 330, 300, 300])
    for variant, image in result["head"].items():
        head = np.asarray(image).copy()
        head[:, :, 3] = np.where(yy <= jaw_line, head[:, :, 3], 0)
        result["head"][variant] = warp(Image.fromarray(head), setting)
        source = np.asarray(result["neck_overlap"][variant])
        valid = (source[:, :, 3] > 240) & (yy > 320) & (yy < 346) & (xx > 362) & (xx < 405)
        nearest = distance_transform_edt(~valid, return_distances=False, return_indices=True)
        skin = np.zeros_like(source)
        skin[:, :, :3] = cv2.GaussianBlur(source[nearest[0], nearest[1], :3], (13, 13), 0)
        skin[:, :, 3] = mask
        result["neck_overlap"][variant] = Image.fromarray(skin)
    return result


def preview(spec, setting):
    changed = layers(spec, setting)
    canvas = Image.new("RGBA", tuple(spec["canvas"]))
    for part in sorted(spec["parts"], key=lambda p: p.get("z", 0)):
        if part["id"] in changed:
            canvas.alpha_composite(changed[part["id"]]["neutral"])
        else:
            alone = deepcopy(spec)
            alone["parts"] = [part]
            canvas.alpha_composite(compose(alone))
    return canvas


def api_layers(spec):
    """Register the exact edited busts, keeping the original torso untouched."""
    from build_actor_party import keyed, polygon
    from scipy.ndimage import distance_transform_edt
    sheet = np.asarray(keyed(RAW / "p03-upright-neck-v1.png"))
    yy, xx = np.mgrid[:1220, :800].astype(np.float32)
    result = {"head": {}, "neck_overlap": {}}
    envelope = polygon((800, 1220), [[343, 309], [354, 307], [380, 315],
                                    [405, 314], [413, 322], [420, 335],
                                    [426, 351], [400, 358],
                                    [369, 346], [349, 327]])
    head_envelope = polygon((800, 1220), [[280, 100], [500, 100], [500, 290],
                                         [425, 290], [416, 303], [409, 319],
                                         [418, 335], [389, 335], [352, 325],
                                         [343, 312], [330, 305], [309, 280], [280, 280]])
    for col, variant in enumerate(("neutral", "focus", "hit")):
        sx = ((xx - 260) * 1.3 + 54 + col * 512).astype(np.float32)
        sy = ((yy - 120) * 1.3 + 110).astype(np.float32)
        pixels = cv2.remap(sheet, sx, sy, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT)
        rgb = pixels[:, :, :3].astype(float)
        skin_valid = (pixels[:, :, 3] > 240) & (yy >= 330) & (yy <= 344) & (xx > 369) & (xx < 397)
        skin_valid &= (rgb[:, :, 0] > rgb[:, :, 1] + 15) & (rgb[:, :, 2] < rgb[:, :, 1] * .83)
        nearest = distance_transform_edt(~skin_valid, return_distances=False, return_indices=True)
        underlay = np.zeros_like(pixels)
        underlay[:, :, :3] = cv2.GaussianBlur(pixels[nearest[0], nearest[1], :3], (7, 7), 0)
        underlay[:, :, 3] = envelope
        head = pixels.copy()
        head[:, :, 3] = np.minimum(head[:, :, 3], head_envelope)
        # The edited bust used a magenta key. Let clean chest skin replace its
        # front-neck fringe, while retaining the actual jaw and facial contour.
        fringe = ((rgb[:, :, 0] > rgb[:, :, 1] * 1.05)
                  & (rgb[:, :, 2] > rgb[:, :, 1] * .88)
                  & (yy > 309) & (xx > 390) & (xx < 432))
        head[:, :, 3] = np.where(fringe | ((yy > 323) & (xx > 395)), 0, head[:, :, 3])
        result["head"][variant] = Image.fromarray(head)
        result["neck_overlap"][variant] = Image.fromarray(underlay)
    return result


def candidates():
    EV.mkdir(parents=True, exist_ok=True)
    spec = read(OLD / "P03/rig.json")
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 26)
    board = Image.new("RGB", (1800, 1760), "#e6dfd1")
    draw = ImageDraw.Draw(board)
    for column, (name, setting) in enumerate(CHOICES.items()):
        image = preview(spec, setting)
        image.thumbnail((600, 1040), Image.Resampling.LANCZOS)
        x = column * 600 + (600 - image.width) // 2
        board.paste(image, (x, 60), image)
        draw.text((column * 600 + 30, 12), name, font=font, fill="#27383b")
        full = preview(spec, setting)
        crop = full.crop((210, 120, 610, 545)).resize((560, 595), Image.Resampling.LANCZOS)
        board.paste(crop, (column * 600 + 20, 1120), crop)
        background = Image.new("RGBA", full.size, "#e6dfd1")
        background.alpha_composite(full)
        background.convert("RGB").save(EV / (name + "-resource-preview.jpg"), quality=96)
    board.save(EV / "posture-candidates.jpg", quality=96)
    save(EV / "posture-candidates.json", {"choices": CHOICES, "scope": "resource registration candidates; not engine poses"})


def build():
    EV.mkdir(parents=True, exist_ok=True)
    spec = read(OLD / "P03/rig.json")
    original = deepcopy(spec)
    setting = CHOICES[SELECTED]
    images = api_layers(spec)
    boxes = [image.getbbox() for variants in images.values() for image in variants.values()]
    box = [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]
    head_bone = next(b for b in spec["bones"] if b["id"] == "head")
    head_bone["position"] = [head_bone["position"][0] - 10., head_bone["position"][1] - 6.]
    rest = absolute(spec)
    records = []
    for part in spec["parts"]:
        if part["id"] not in images:
            continue
        files = {}
        for variant, canvas in images[part["id"]].items():
            path = ART / "P03" / (part["id"] + "_" + variant + ".png")
            path.parent.mkdir(parents=True, exist_ok=True)
            canvas.crop(box).save(path)
            files[variant] = "res://" + path.relative_to(ROOT).as_posix()
            source = RAW / "p03-upright-neck-v1.png"
            records.append({"file": path.relative_to(ROOT).as_posix(), "sha256": sha(path),
                            "source": source.relative_to(ROOT).as_posix(), "source_sha256": sha(source),
                            "processing": "registered API upright head/neck; plain skin underlay without jaw contours; original torso retained", "setting": setting,
                            "source_column": ("neutral", "focus", "hit").index(variant), "stage_crop": [260, 120, 570, 600], "panel_scale": 1.3})
        part["file"] = files["neutral"]
        part["offset"] = np.round(np.array(box[:2]) - np.array(spec["ground"]) - rest[part["bone"]], 6).tolist()
        drawing = next(d for d in spec["drawings"] if d["part"] == part["id"])
        for variant in drawing["variants"]:
            variant["file"] = files[variant["id"].removeprefix("head_")]
        if part["id"] == "head":
            spec["expression"]["blink"] = files["hit"]
    for animation in spec["animations"].values():
        for track in animation["tracks"]:
            if track["bone"] == "head" and track["property"] == "rotation":
                track["keys"] = [[t, round(value * (.60 if value > 0 else .80), 7)] for t, value in track["keys"]]
    for track in spec["idle_tracks"]:
        if track["bone"] == "loop_head" and track["property"] == "rotation":
            track["keys"] = [[t, round(value * .6, 7)] for t, value in track["keys"]]
    spec["version"] = 9
    spec["posture"] = {"base_version": 8, "selected": SELECTED, "face_rigid_rotation_degrees": setting["angle"],
                       "face_translation_px": setting["shift"], "neck_root_pinned_y": 358,
                       "head_joint_retraction_px": [-10, -6], "positive_head_motion_scale": .60,
                       "negative_head_motion_scale": .80, "lower_body_unchanged": True,
                       "source": "upright-b local face/pose target followed by one registered API neck refinement"}
    save(ART / "P03/rig.json", spec)
    for role in ("P01", "P02", "P04", "N01"):
        dst = ART / role / "rig.json"
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((OLD / role / "rig.json").read_bytes())
    textures = {p["file"] for p in spec["parts"]}
    textures.update(v["file"] for d in spec["drawings"] for v in d["variants"])
    save(ART / "P03/source.json", {"version": 9, "definition_id": "P03", "base_version": 8,
        "source_rig": (OLD / "P03/rig.json").relative_to(ROOT).as_posix(), "source_rig_sha256": sha(OLD / "P03/rig.json"),
        "posture": spec["posture"], "api_successful_this_revision": 1, "api_cumulative_successful": 29,
        "textures": [{"file": f.removeprefix("res://"), "sha256": sha(disk(f))} for f in sorted(textures)]})
    save(EV / "extraction.json", {"selected": SELECTED, "outputs": records, "specification": spec["posture"]})
    image = compose(spec)
    bg = Image.new("RGBA", image.size, "#e6dfd1")
    bg.alpha_composite(image)
    bg.convert("RGB").save(EV / "p03-resource-final.jpg", quality=96)
    print(json.dumps({"version": 9, "textures_emitted": len(records), "posture": spec["posture"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", action="store_true")
    args = parser.parse_args()
    candidates() if args.candidates else build()
