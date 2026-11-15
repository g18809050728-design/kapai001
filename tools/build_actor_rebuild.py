"""Build P03 version 10 from a newly generated whole figure and its own edits.

No V7/V8/V9 P03 pixels or geometry are reused. The selected P01 V5 bone names,
timings and runtime contract are retained; every P03 joint is registered anew.
"""
from copy import deepcopy
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt

import build_actor_party as b

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/actor-rebuild-20261115"
ART = ROOT / "assets/art/actor-rebuild"
EV = ROOT / "artifacts/verification/actor-rebuild-20261115"
MASTER = RAW / "p03-master-v3.png"
SCALE = .70
ORIGIN = np.array([510., 1520.])

LANDMARKS = {
    "pelvis": [520, 755], "chest": [518, 420], "neck": [516, 244], "cloth": [520, 650],
    "near_shoulder": [353, 302], "near_elbow": [315, 535], "near_wrist": [415, 490],
    "far_shoulder": [646, 310], "far_elbow": [680, 550], "wrist": [728, 550],
    "tip": [513, 500], "waist": 696, "crotch": 806,
    "legs": [
        {"name": "rear", "hip": [449, 755], "knee": [408, 1070], "ankle": [371, 1430], "cuff": 1424},
        {"name": "front", "hip": [587, 755], "knee": [604, 1064], "ankle": [584, 1430], "cuff": 1426},
    ],
}


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def unregistered(path, key, keyed=True):
    """Undo the documented crop's uniform enlargement, without anatomical warp."""
    reg = b.read(RAW / "edit-registration.json")[key]
    image = b.keyed(path) if keyed else Image.open(path).convert("RGBA")
    x, y = reg["offset"]
    box = reg["source_crop"]
    w, h = round((box[2] - box[0]) * reg["scale"]), round((box[3] - box[1]) * reg["scale"])
    crop = image.crop((x, y, x + w, y + h)).resize((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (1024, 1536))
    result.alpha_composite(crop, box[:2])
    return result


def main():
    EV.mkdir(parents=True, exist_ok=True)
    b.ART, b.RAW, b.EV, b.SCALE, b.ORIGIN = ART, RAW, EV, SCALE, ORIGIN
    b.RECORDS.clear()
    for entity, family in (("P01", "actor-anatomy"), ("N01", "actor-anatomy"), ("P02", "actor-proportions"), ("P04", "actor-proportions")):
        source = ROOT / "assets/art" / family / entity / "rig.json"
        dest = ART / entity / "rig.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(source.read_bytes())

    base = b.read(ROOT / "assets/art/actor-anatomy/P01/rig.json")
    spec = deepcopy(base)
    spec.update(version=10, definition_id="P03", canvas=[800, 1220], ground=[400, 1200],
                anatomy={"base_version": 5, "source_scale": SCALE, "origin": ORIGIN.tolist(), "status": "pending_rendered_review"},
                held_contact={"hand": "loop_wrist", "prop": "loop_laptop", "point": [0, 0]})
    cfg = LANDMARKS
    points = {
        "root": ORIGIN, "loop_hips": ORIGIN, "torso": cfg["pelvis"], "pelvis": cfg["pelvis"],
        "loop_chest": cfg["chest"], "head": cfg["neck"], "loop_head": cfg["neck"],
        "loop_near": cfg["near_shoulder"], "near_upper": cfg["near_shoulder"],
        "near_forearm": cfg["near_elbow"], "near_elbow": cfg["near_elbow"], "action_tip": cfg["tip"],
        "loop_far": cfg["far_shoulder"], "far_upper": cfg["far_shoulder"],
        "far_forearm": cfg["far_elbow"], "far_elbow": cfg["far_elbow"],
        "loop_cloth": cfg["cloth"], "held_wrist": cfg["wrist"], "loop_wrist": cfg["wrist"],
        "held_laptop": cfg["wrist"], "loop_laptop": cfg["wrist"],
    }
    positions = {key: b.point(value) for key, value in points.items()}
    spec["bones"] = [bone for bone in spec["bones"] if not bone["id"].startswith(("rear_", "front_"))]
    for bone in spec["bones"]:
        origin = positions[bone["parent"]] if bone["parent"] else [0, 0]
        bone["position"] = [round(positions[bone["id"]][i] - origin[i], 6) for i in range(2)]
    spec["parts"], spec["drawings"] = [], []
    master = b.keyed(MASTER)
    yy, xx = np.mgrid[:1536, :1024]
    head_polygon = [[405, 0], [620, 0], [620, 170], [583, 185], [561, 205], [543, 219], [544, 245], [555, 269], [538, 277], [512, 274], [491, 267], [474, 248], [462, 227], [458, 205], [461, 179], [441, 163], [426, 145], [416, 100]]
    head_mask = b.polygon(master.size, head_polygon)

    # Reconstruct only the API-edited clothing area. The new master's exact
    # neck/collar outside it remains authoritative, never a skin-color patch.
    trunk_path = RAW / "p03-trunk-v1.png"
    garment = master.copy()
    garment.paste(b.keyed(trunk_path).crop((235, 285, 851, 641)), (235, 285))
    body_poly = [[446, 204], [463, 204], [480, 225], [542, 219], [580, 242], [674, 282], [688, 445], [677, 560], [689, 714], [630, 744], [620, 697], [508, 697], [491, 747], [352, 719], [364, 630], [382, 561], [377, 501], [350, 430], [331, 370], [331, 276]]
    body_mask = b.polygon(master.size, body_poly)
    body_mask = np.where(head_mask > 0, 0, body_mask).astype(np.uint8)
    trunk = b.main_piece("P03", "trunk", garment, trunk_path, body_mask,
                         processing="same-master masked API garment reconstruction; original collar retained; original new head/neck silhouette excluded")
    spec["parts"].append({"id": "torso", "mesh": True, "bone": "loop_chest", "base_bone": "loop_cloth", "position": trunk["position"], "size": trunk["size"], "z": 0, "cells": 12, "file": trunk["file"]})

    near_path = RAW / "p03-sleeve-v1.png"
    upper_near = unregistered(near_path, "sleeve")
    upper_far_mask = b.polygon(master.size, [[617, 277], [651, 285], [672, 314], [682, 391], [691, 455], [708, 502], [710, 527], [699, 553], [681, 583], [655, 596], [639, 566], [641, 512], [636, 466], [634, 390]])
    for name, image, source, mask, z in [("near_upper", upper_near, near_path, None, 3), ("far_upper", master, MASTER, upper_far_mask, -1)]:
        item = b.main_piece("P03", name, image, source, mask)
        spec["parts"].append({"id": name, "mesh": True, "bone": name, "base_bone": name.replace("upper", "elbow"), "position": item["position"], "size": item["size"], "z": z, "cells": 10, "file": item["file"], "weight_axis": [positions[name], positions[name.replace("upper", "elbow")]], "weight_range": [.06, .94]})

    arms = {name: unregistered(RAW / filename, "forearm") for name, filename in [("neutral", "p03-forearm-v1.png"), ("strike", "p03-strike-v1.png")]}
    part, files = b.registered_variants("P03", "near_forearm", arms, RAW / "p03-strike-v1.png", "near_forearm", positions["near_forearm"], 8)
    spec["parts"].append(part)
    spec["drawings"].append({"part": "near_forearm", "variants": [{"id": "arm_strike", "file": files["strike"]}], "poses": {"action": [[0, [1, 0, 0, 0]], [.29, [1, 0, 0, 0]], [.34, [0, 1, 0, 0]], [.69, [0, 1, 0, 0]], [.75, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]]}})

    fore_mask = b.polygon(master.size, [[669, 530], [688, 523], [713, 532], [730, 520], [747, 525], [752, 549], [739, 564], [716, 574], [690, 580], [674, 572], [664, 553]])
    hand_mask = b.polygon(master.size, [[735, 504], [748, 494], [758, 496], [762, 509], [769, 495], [779, 498], [785, 510], [789, 526], [791, 539], [784, 551], [772, 560], [755, 565], [738, 564], [722, 559], [718, 545], [724, 530]])
    prop_mask = b.polygon(master.size, [[706, 528], [727, 441], [750, 441], [755, 427], [769, 430], [778, 418], [832, 443], [790, 515], [763, 541]])
    fore = b.main_piece("P03", "held_forearm", master, MASTER, fore_mask)
    hand = b.main_piece("P03", "held_hand", master, MASTER, hand_mask)
    pixels = np.asarray(b.masked(master, prop_mask)).copy()
    repair = cv2.dilate((hand_mask > 0).astype(np.uint8) * 255, np.ones((11, 11), np.uint8))
    trusted = (pixels[:, :, 3] > 0) & (repair == 0)
    nearest = distance_transform_edt(~trusted, return_distances=False, return_indices=True)
    rgb = pixels[:, :, :3].copy()
    rgb[~trusted] = rgb[nearest[0][~trusted], nearest[1][~trusted]]
    pixels[:, :, :3] = cv2.inpaint(rgb, repair, 5, cv2.INPAINT_TELEA)
    prop = b.main_piece("P03", "held_prop", Image.fromarray(pixels), MASTER, processing="new master card crop; hidden hand pixels locally inpainted within paper only")
    spec["parts"].extend([b.sprite("P03", "held_forearm", fore, "far_forearm", positions["far_forearm"], 5), b.sprite("P03", "held_laptop", prop, "loop_laptop", positions["loop_laptop"], 6), b.sprite("P03", "held_hand", hand, "loop_wrist", positions["loop_wrist"], 7)])

    heads = {"neutral": b.masked(master, head_mask)}
    reg = b.read(RAW / "edit-registration.json")["face"]
    mask_in = Image.open(RAW / "p03-face-mask.png").getchannel("A")
    x, y = reg["offset"]; box = reg["source_crop"]
    local_mask = Image.eval(mask_in, lambda v: 255 - v).crop((x, y, x + 728, y + 840)).resize((260, 300), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(2.2))
    feature_mask = Image.new("L", master.size); feature_mask.paste(local_mask, box[:2])
    for name in ("focus", "hit"):
        face = unregistered(RAW / ("p03-" + name + "-v1.png"), "face")
        # An API edit may move a cheek by a pixel. Only replace features where
        # both drawings are opaque; retain the master's exact silhouette/alpha.
        safe_mask = np.asarray(feature_mask).copy()
        safe_mask[(np.asarray(face.getchannel("A")) < 230) | (np.asarray(master.getchannel("A")) < 230)] = 0
        merged = Image.composite(face, master, Image.fromarray(safe_mask))
        merged.putalpha(master.getchannel("A"))
        heads[name] = b.masked(merged, head_mask)
    face_poses = {
        "action": [[0, [1, 0, 0, 0]], [.11, [1, 0, 0, 0]], [.17, [0, 1, 0, 0]], [.79, [0, 1, 0, 0]], [.85, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]],
        "hit": [[0, [1, 0, 0, 0]], [.06, [0, 0, 1, 0]], [.56, [0, 0, 1, 0]], [.68, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]],
        "guard": [[0, [1, 0, 0, 0]], [.16, [0, 1, 0, 0]], [.74, [0, 1, 0, 0]], [.85, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]],
    }
    for name, bone, z in [("head", "loop_head", 2), ("neck_overlap", "loop_chest", -1)]:
        part, files = b.registered_variants("P03", name, heads, MASTER, bone, positions[bone], z, split=244)
        spec["parts"].append(part)
        spec["drawings"].append({"part": name, "variants": [{"id": "head_focus", "file": files["focus"]}, {"id": "head_hit", "file": files["hit"]}], "poses": deepcopy(face_poses)})
        if name == "head":
            spec["expression"] = {"part": "head", "blink": files["hit"], "intervals": [[1.12, 1.23], [2.91, 3.03], [5.72, 5.84]]}

    split = np.interp(yy, [690, 806, 1060, 1520], [535, 532, 505, 480])
    pants = np.asarray(master).copy()
    for row in range(655, 713):
        pants[row] = np.asarray(master)[1426 - row]
        pants[row, :397 + round((696 - row) * .3)] = 0
        pants[row, 649 - round((696 - row) * .3):] = 0
    # Only trouser fabric may continue behind the moving shirt; mirroring a
    # garment hem would otherwise leave small green triangles on the pelvis.
    for row in range(655, 763):
        rgb = pants[row, :, :3].astype(int)
        green = (rgb[:, 1] > rgb[:, 0] * .99) & (rgb[:, 1] > rgb[:, 2] + 6) & (pants[row, :, 3] > 0)
        for col in np.flatnonzero(green):
            pants[row, col] = np.asarray(master)[790 + (row - 655) // 5, min(630, max(406, col))]
    fade = np.clip((cfg["crotch"] + 80 - yy) / 90, 0, 1)
    pelvis = b.main_piece("P03", "pelvis", Image.fromarray(pants), MASTER, np.where(yy >= 655, fade * 255, 0).astype(np.uint8), processing="new master trouser pixels; mirrored hidden waist underlap; one uniform source scale")
    spec["parts"].append({"id": "pelvis", "mesh": True, "bone": "loop_cloth", "base_bone": "rear_thigh", "split_bone": "front_thigh", "position": pelvis["position"], "size": pelvis["size"], "z": -1, "cells": 16, "weight_range": [.25, .86], "split_range": [.4, .63], "file": pelvis["file"]})
    calibration, spec["feet"] = [], []
    for leg in cfg["legs"]:
        name = leg["name"]
        region = (xx < split if name == "rear" else xx >= split) & (yy >= cfg["crotch"] - 50)
        bottom = int(np.where((np.asarray(master.getchannel("A")) > 0) & region)[0].max()) + 1
        shift = 1520 - bottom
        limb = b.main_piece("P03", name + "_leg", master, MASTER, np.where(region & (yy < leg["cuff"] + 8), 255, 0), shift=shift)
        shoe = b.main_piece("P03", name + "_shoe", master, MASTER, np.where(region & (yy >= leg["cuff"] - 15), 255, 0), shift=shift)
        hip, knee, ankle = b.point(leg["hip"]), b.point(leg["knee"], shift), b.point(leg["ankle"], shift)
        lengths = [math.dist(hip, knee), math.dist(knee, ankle)]
        cross = (knee[0] - hip[0]) * (ankle[1] - knee[1]) - (knee[1] - hip[1]) * (ankle[0] - knee[0])
        for id_, parent, p, parent_p, length in [(name + "_thigh", "pelvis", hip, positions["pelvis"], lengths[0]), (name + "_shin", name + "_thigh", knee, hip, lengths[1]), (name + "_ankle", name + "_shin", ankle, knee, 65)]:
            spec["bones"].append({"id": id_, "parent": parent, "position": [round(p[i] - parent_p[i], 6) for i in range(2)], "length": length}); positions[id_] = p
        fraction = (knee[1] - limb["position"][1]) / limb["size"][1]
        spec["parts"].append({"id": name + "_leg", "mesh": True, "bone": name + "_thigh", "base_bone": name + "_shin", "position": limb["position"], "size": limb["size"], "z": -3 if name == "rear" else -2, "cells": 16, "weight_range": [fraction - .08, fraction + .08], "file": limb["file"]})
        spec["parts"].append(b.sprite("P03", name + "_shoe", shoe, name + "_ankle", ankle, -4))
        spec["feet"].append({"upper": name + "_thigh", "lower": name + "_shin", "ankle": name + "_ankle", "target": ankle, "lengths": lengths, "bend": -1 if cross > 0 else 1, "bind_axes": True})
        calibration.append({"name": name, "hip": hip, "knee": knee, "ankle": ankle, "lengths": lengths, "source_hip": leg["hip"], "source_knee": leg["knee"], "source_ankle": leg["ankle"], "source_shift_y": shift})
    spec["anatomy"]["calibration"] = calibration
    spec["contact_shadows"] = [[row["ankle"][0] + 12, 0, 52, 10] for row in calibration]
    spec["cast_shadows"] = [[-20, 9, 170, 15]]

    old_bones, new_bones = {x["id"]: x for x in base["bones"]}, {x["id"]: x for x in spec["bones"]}
    for pose, anim in spec["animations"].items():
        for track in anim["tracks"]:
            name = track["bone"]
            if track["property"] == "position":
                old_rest, new_rest = old_bones[name]["position"], new_bones[name]["position"]
                track["keys"] = [[t, [round(new_rest[i] + (v[i] - old_rest[i]) * .60, 6) for i in range(2)]] for t, v in track["keys"]]
                if name == "torso":
                    track["keys"] = [[t, [v[0], max(new_rest[1], v[1])]] for t, v in track["keys"]]
                if name == "action_tip": track["keys"] = [[0, new_rest], [1, new_rest]]
            elif name in ("torso", "head"):
                track["keys"] = [[t, v * (.30 if name == "torso" else .38)] for t, v in track["keys"]]
    action = spec["animations"]["action"]; action["length"] = 1.66
    for track in action["tracks"]:
        if track["bone"] == "near_upper":
            track["keys"] = [[0, 0], [.18, .10], [.28, .08], [.4, -.65], [.55, -.62], [.71, -.34], [.87, -.05], [1, 0]]
        elif track["bone"] == "near_forearm":
            track["keys"] = [[0, 0], [.19, -.12], [.29, -.08], [.41, .78], [.55, .75], [.73, .38], [.87, .04], [1, 0]]
        elif track["bone"] == "torso" and track["property"] == "position":
            rest = new_bones["torso"]["position"]
            track["keys"] = [[t, [rest[0] + dx, rest[1] + dy]] for t, dx, dy in [(0, 0, 0), (.22, -4, 4), (.4, 20, 6), (.55, 17, 6), (.78, -1, 2), (1, 0, 0)]]
    for track in spec["animations"]["hit"]["tracks"]:
        if track["bone"] == "torso" and track["property"] == "position":
            rest = new_bones["torso"]["position"]
            track["keys"] = [[t, [rest[0] + dx, rest[1] + dy]] for t, dx, dy in [(0, 0, 0), (.09, -9, 8), (.30, -6, 6), (.56, -1, 3), (.76, -.3, 1.6), (.9, 0, .6), (1, 0, 0)]]
    spec["idle_length"] = 6.1
    for track in spec["idle_tracks"]:
        name = track["bone"]
        if name == "loop_hips": track["keys"] = [[t, [0, 0]] for t, _ in track["keys"]]
        elif track["property"] == "rotation":
            amplitude = max(abs(v) for _, v in track["keys"]) * (.20 if name == "loop_head" else .5)
            track["keys"] = [[i / 64, round(amplitude * math.sin(i / 64 * math.tau * (2 if "wrist" in name else 1) + 1.1), 7)] for i in range(65)]
        elif name == "loop_chest" and track["property"] == "scale":
            track["keys"] = [[t, [1 + (v[0] - 1) * .6, 1 + (v[1] - 1) * .6]] for t, v in track["keys"]]
    spec["drawing_blend_seconds"] = .07
    spec["party"] = {"name": "沈见章", "prop": "论证卡片", "base_art": "selected_P01_v5_style_only", "master": MASTER.relative_to(ROOT).as_posix(), "garment_edit": trunk_path.relative_to(ROOT).as_posix()}
    spec["rebuild"] = {"complete_new_master": True, "uniform_source_scale": True, "legacy_body_pixels": False, "source_scale": SCALE, "master_sha256": b.sha(MASTER), "landmarks": cfg, "face_features_only": True, "neck_base_follows_chest": True, "approval": "pending_user_visual_review"}
    save(ART / "P03/rig.json", spec)
    textures = {p["file"].removeprefix("res://") for p in spec["parts"]}
    textures.update(v["file"].removeprefix("res://") for layer in spec["drawings"] for v in layer["variants"])
    save(ART / "P03/source.json", {"version": 10, "definition_id": "P03", "status": "pending_rendered_review", "api_manifest": "output/imagegen/actor-rebuild-20261115/asset-manifest.json", "textures": [{"file": f, "sha256": b.sha(ROOT / f)} for f in sorted(textures)], "master": {"file": MASTER.relative_to(ROOT).as_posix(), "sha256": b.sha(MASTER)}})
    b.preview("P03", spec)
    save(EV / "extraction.json", {"outputs": b.RECORDS, "uniform_source_scale": SCALE, "master": str(MASTER.relative_to(ROOT)), "calibration": calibration, "inputs": {str(p.relative_to(ROOT)): b.sha(p) for p in RAW.glob("*.png")}})
    print(json.dumps({"version": 10, "bones": len(spec["bones"]), "parts": len(spec["parts"]), "meshes": sum(bool(p.get("mesh")) for p in spec["parts"]), "textures": len(textures), "new_derived_outputs": len(b.RECORDS)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
