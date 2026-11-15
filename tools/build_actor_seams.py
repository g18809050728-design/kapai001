"""Derive v6 local sleeve and contact repairs; retain v5 anatomy verbatim."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art/actor-seams"
EV = ROOT / "artifacts/verification/actor-seams-20261115"
RECORDS = []


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def emit(name, image, source, processing, **details):
    path = ART / "P01" / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    RECORDS.append({"file": path.relative_to(ROOT).as_posix(), "size": list(image.size),
                    "sha256": digest(path), "source": source,
                    "source_sha256": digest(ROOT / source), "processing": processing, **details})
    return "res://" + path.relative_to(ROOT).as_posix()


def premultiplied_warp(image, source_y, source_x):
    rgba = np.asarray(image).astype(float) / 255
    alpha = rgba[:, :, 3]
    values = [map_coordinates(rgba[:, :, i] * alpha, [source_y, source_x], order=1, mode="constant", cval=0)
              for i in range(3)]
    out_alpha = map_coordinates(alpha, [source_y, source_x], order=1, mode="constant", cval=0)
    rgb = np.stack(values, axis=-1) / np.maximum(out_alpha[:, :, None], 1 / 255)
    return Image.fromarray(np.round(np.clip(np.dstack([rgb, out_alpha]), 0, 1) * 255).astype(np.uint8))


def sleeve():
    source = "assets/art/actor-rig-pilot/P01/near_upper.png"
    image = Image.open(ROOT / source).convert("RGBA")
    yy, xx = np.mgrid[:image.height, :image.width].astype(float)
    original = np.asarray(image)
    inside = np.array([np.flatnonzero(row > 8)[-1] if np.any(row > 8) else 0
                       for row in original[:, :, 3]], dtype=float)[:, None]
    bridge = np.interp(yy, [0, 48, 100, 165, 215, 264], [0, 0, 11, 13, 0, 0])
    width = np.interp(yy, [0, 48, 100, 190, 264], [.97, .94, .80, .80, .84])
    result = premultiplied_warp(image, yy, inside + (xx - inside - bridge) / width)
    pixels = np.array(result)
    # The forearm drawing already owns the rolled cuff. Retire the duplicate
    # cuff inside the upper arm, fading entirely within that opaque overlap.
    pixels[:, :, 3] = np.round(pixels[:, :, 3] * np.clip((244 - yy) / 23, 0, 1)).astype(np.uint8)
    return emit("near_upper", Image.fromarray(pixels), source,
                "row-wise premultiplied-alpha taper pinned to inner sleeve edge; small fabric overlap bridges armpit; fade duplicated cuff inside elbow overlap",
                width_factors=[[0, .97], [48, .94], [100, .80], [190, .80], [264, .84]], cuff_fade=[221, 244])


def forearm_cuff(source):
    image = Image.open(ROOT / source).convert("RGBA")
    yy, xx = np.mgrid[:image.height, :image.width].astype(float)
    # Preserve palm, fingers and pen pixels. Compress only the raised rolled
    # sleeve around its original elbow registration, rather than shifting it.
    factor = np.interp(xx, [0, 85, 135, 165, image.width], [.88, .88, .94, 1, 1])
    result = premultiplied_warp(image, 118.8 + (yy - 118.8) / factor, xx)
    return emit(Path(source).stem, result, source,
                "slim only rolled sleeve around registered elbow; unchanged hand and pen beyond x165",
                elbow_y=118.8, sleeve_y_scale=.88, unchanged_from_x=165)


def neck():
    source = "assets/art/actor-anatomy/P01/neck_overlap_neutral.png"
    image = Image.open(ROOT / source).convert("RGBA")
    result = Image.new("RGBA", (image.width + 8, image.height + 18))
    result.alpha_composite(image, (4, 0))
    pixels = np.array(result)
    old = np.array(image)
    for x in range(5, image.width - 5):
        indices = np.flatnonzero(old[:, x, 3] > 220)
        if not len(indices):
            continue
        end = int(indices[-1])
        color = np.median(old[max(0, end - 5):end + 1, x, :3], axis=0)
        for y in range(end + 1, min(result.height, end + 17)):
            alpha = int(255 * min(1, (end + 17 - y) / 7))
            pixels[y, x + 4] = [*color.astype(np.uint8), alpha]
    mask = Image.fromarray(pixels[:, :, 3]).filter(ImageFilter.GaussianBlur(.65))
    pixels[:, :, 3] = np.minimum(pixels[:, :, 3], np.array(mask))
    yy, xx = np.mgrid[:result.height, :result.width]
    left_edge = np.interp(yy, [0, 12, 28, result.height], [18, 13, 5, 10])
    taper = np.clip((xx - left_edge) / 3, 0, 1) * np.clip(yy / 16, 0, 1)
    pixels[:, :, 3] = np.round(pixels[:, :, 3] * taper).astype(np.uint8)
    return emit("neck_overlap", Image.fromarray(pixels), source,
                "extend sampled original neck below collar; taper and feather upper rear edge inside all registered neck silhouettes; original top registration",
                paste_origin=[4, 0], added_height=18)


def held_art():
    source = "assets/art/actor-rig-pilot/P01/laptop_forearm.png"
    image = Image.open(ROOT / source).convert("RGBA")
    pixels = np.array(image)
    yy, xx = np.mgrid[:image.height, :image.width]
    prop_mask = Image.new("L", image.size)
    ImageDraw.Draw(prop_mask).polygon([(34, 157), (149, 160), (203, 0), (350, 16),
                                     (282, 176), (207, 180), (147, 176), (35, 174)], fill=255)
    prop = pixels.copy()
    skin = (pixels[:, :, 0].astype(float) > pixels[:, :, 1] * 1.12) & (pixels[:, :, 2] < pixels[:, :, 0] * .82)
    hidden = skin & (xx > 152) & (yy > 138) & (yy < 229) & (np.array(prop_mask) > 0)
    for y, x in zip(*np.nonzero(hidden)):
        prop[y, x, :3] = np.median(pixels[122:136, x, :3], axis=0) if y < 174 else [53, 49, 43]
        prop[y, x, 3] = 255
    prop[:, :, 3] = np.minimum(prop[:, :, 3], np.array(prop_mask))

    arm_mask = Image.new("L", image.size)
    ImageDraw.Draw(arm_mask).polygon([(0, 101), (103, 101), (103, 156), (151, 177),
                                    (205, 181), (207, 222), (176, 234), (0, 240)], fill=255)
    arm_alpha = np.minimum(pixels[:, :, 3], np.array(arm_mask)).astype(float)
    arm_alpha *= np.clip((207 - xx) / 23, 0, 1)
    arm_alpha[np.array(prop_mask.filter(ImageFilter.MaxFilter(3))) > 0] = 0
    # Exclude the source keyboard rim above the traced lid/base mask as well.
    arm_alpha[(xx >= 95) & (yy < 177 + .05 * (xx - 95))] = 0
    arm_alpha[(xx >= 34) & (xx < 95) & (yy >= 153) & (yy < 177)] = 0

    hand_mask = Image.new("L", image.size)
    ImageDraw.Draw(hand_mask).polygon([(143, 183), (168, 178), (187, 175), (190, 157), (201, 147),
        (210, 150), (208, 176), (215, 168), (218, 151), (229, 144), (237, 148),
        (240, 170), (246, 150), (256, 151), (260, 169), (268, 181), (254, 192),
        (244, 202), (226, 213), (194, 220), (175, 227), (145, 229)], fill=255)
    hand_alpha = np.minimum(pixels[:, :, 3], np.array(hand_mask)).astype(float)
    hand_alpha *= np.clip((xx - 145) / 22, 0, 1)
    # The overlap remains opaque on the arm while the hand fades in. Both use
    # the same source transform; no two vertical hard cuts meet at the wrist.
    for name, alpha in [("held_forearm", arm_alpha), ("held_hand", hand_alpha)]:
        rgba = pixels.copy()
        rgba[:, :, 3] = np.round(alpha).astype(np.uint8)
        bitmap = Image.fromarray(rgba).resize(tuple(round(v * .88) for v in image.size), Image.Resampling.LANCZOS)
        emit(name, bitmap, source, "registered continuous original arm/palm with feathered 40px internal wrist overlap; prop excluded from forearm",
             shared_scale=.88, hand_fade_x=[145, 167], arm_fade_x=[184, 207])
    emit("held_laptop", Image.fromarray(prop).resize(tuple(round(v * .88) for v in image.size), Image.Resampling.LANCZOS),
         source, "traced original prop; finger-covered screen pixels reconstructed from adjacent original screen band",
         shared_scale=.88, reconstruction_rows=[122, 136])


def main():
    RECORDS.clear()
    EV.mkdir(parents=True, exist_ok=True)
    previous = read(ROOT / "assets/art/actor-anatomy/P01/rig.json")
    spec = deepcopy(previous)
    spec["version"] = 6
    spec["seams"] = {"source_version": 5, "api_calls_this_batch": 0, "status": "pending_actual_render_review"}
    paths = {"near_upper": sleeve(), "neck_overlap": neck()}
    held_art()
    for name in ["held_forearm", "held_hand", "held_laptop"]:
        paths[name] = f"res://assets/art/actor-seams/P01/{name}.png"
    for part in spec["parts"]:
        if part["id"] in paths:
            part["file"] = paths[part["id"]]
        if part["id"] == "neck_overlap":
            part["offset"][0] -= 4
    for layer in spec["drawings"]:
        if layer["part"] == "near_forearm":
            for variant in layer["variants"]:
                variant["file"] = forearm_cuff(variant["file"].removeprefix("res://"))
    # The paired deltas preserve the original forearm direction at contact.
    corrections = {"near_upper": [[0, 0], [.18, .24], [.28, .19], [.39, -1.42], [.53, -1.36], [.68, -.79], [.84, -.18], [1, 0]],
                   "near_forearm": [[0, 0], [.19, -.36], [.28, -.28], [.39, 1.26], [.53, 1.24], [.68, .62], [.84, .14], [1, 0]]}
    for track in spec["animations"]["action"]["tracks"]:
        if track["bone"] in corrections and track["property"] == "rotation":
            track["keys"] = corrections[track["bone"]]
    protected = ["bones", "feet", "anatomy", "upright_bones", "idle_tracks", "contact_shadows", "cast_shadows"]
    assert all(spec[key] == previous[key] for key in protected)
    assert all(p == next(q for q in previous["parts"] if q["id"] == p["id"])
               for p in spec["parts"] if p["id"] in ["pelvis", "rear_leg", "front_leg", "rear_shoe", "front_shoe"])
    for entity, value in [("P01", spec), ("N01", read(ROOT / "assets/art/actor-anatomy/N01/rig.json"))]:
        save(ART / entity / "rig.json", value)
        textures = {p["file"].removeprefix("res://") for p in value["parts"]}
        textures.update(v["file"].removeprefix("res://") for d in value.get("drawings", []) for v in d["variants"])
        if "expression" in value:
            textures.add(value["expression"]["blink"].removeprefix("res://"))
        save(ART / entity / "source.json", {"version": value["version"], "source_rig": f"assets/art/actor-anatomy/{entity}/rig.json",
            "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
            "textures": [{"file": f, "sha256": digest(ROOT / f)} for f in sorted(textures)],
            "api_calls_this_batch": 0, "api_successful_total": 15,
            "processing": [p for p in RECORDS if f"/{entity}/" in p["file"]]})
    save(EV / "extraction.json", {"outputs": RECORDS, "count": len(RECORDS), "protected_v5_fields": protected,
         "lower_body_parts_exact": True, "enemy_exact": True, "api_calls_this_batch": 0})
    print(json.dumps({"bones": len(spec["bones"]), "parts": len(spec["parts"]), "new_images": len(RECORDS), "api_calls": 0}))


if __name__ == "__main__":
    main()
