"""Build three independently registered protagonists using the selected V5 rig family.

Master figures supply continuous pelvis/legs, upper sleeves and the held assembly.
Reviewed edits supply clean garments; parts sheets supply articulated forearms and faces.
Every crop retains one source-space transform; legacy assets are read-only.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt, label

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/actor-party-20261115"
ART = ROOT / "assets/art/actor-party"
EV = ROOT / "artifacts/verification/actor-party-20261115"
SCALE = .78
ORIGIN = np.array([500., 1520.])
RECORDS: list[dict] = []


CONFIG = {
    "P02": {
        "name": "许知微", "prop": "研究论文夹", "pelvis": [525, 700],
        "chest": [515, 425], "neck": [501, 275], "cloth": [525, 600],
        "near_shoulder": [377, 312], "near_elbow": [355, 526], "near_wrist": [479, 461],
        "far_shoulder": [597, 312], "far_elbow": [636, 552], "wrist": [655, 525],
        "tip": [573, 450], "waist": 646, "crotch": 770,
        "split": [[630, 540], [790, 538], [1030, 505], [1520, 470]],
        "legs": [
            {"name": "rear", "hip": [455, 700], "knee": [413, 1030], "ankle": [350, 1430], "cuff": 1411},
            {"name": "front", "hip": [589, 700], "knee": [596, 1037], "ankle": [570, 1416], "cuff": 1408},
        ],
        "upper_near": [[357, 285], [379, 279], [400, 291], [416, 322], [428, 380], [416, 453], [402, 513], [371, 539], [335, 540], [315, 515], [321, 466], [331, 360], [341, 309]],
        "upper_far": [[575, 280], [615, 310], [638, 390], [655, 470], [673, 530], [661, 572], [625, 574], [611, 541], [597, 423]],
        "far_forearm": [[617, 521], [646, 500], [672, 502], [683, 531], [665, 564], [635, 575], [615, 561]],
        "hand": [[625, 476], [641, 471], [653, 481], [668, 478], [680, 490], [689, 509], [679, 537], [655, 553], [633, 538], [639, 518], [628, 501]],
        "prop_poly": [[528, 524], [645, 374], [762, 390], [813, 342], [805, 369], [785, 392], [681, 533]],
        "trunk_target": [377, 251, 653, 647],
        "trunk_outline": [[251, 452, 548], [280, 380, 605], [320, 378, 618], [430, 400, 631], [540, 403, 643], [647, 401, 649]],
        "neck_patch": [[449, 208], [484, 225], [524, 231], [537, 266], [535, 294], [511, 299], [472, 273]],
        "near_hole": [[347, 488], [455, 435], [477, 381], [501, 378], [582, 444], [558, 485], [488, 506], [410, 551], [350, 554]],
        "trunk_socket": [[0, 0], [100, 106], [170, 180], [270, 196], [380, 190], [512, 175]],
        "head_anchors": [[276, 984], [789, 984], [1301, 984]], "head_scale": .544,
        "arm_anchors": [[[615, 394], [834, 309]], [[1123, 395], [1360, 280]]],
        "action_upper": -.70, "action_forearm": .92, "action_length": 1.78,
        "idle_phase": .2,
    },
    "P03": {
        "name": "沈见章", "prop": "论证卡片", "pelvis": [502, 730],
        "chest": [486, 430], "neck": [488, 270], "cloth": [493, 650],
        "near_shoulder": [319, 300], "near_elbow": [317, 527], "near_wrist": [454, 454],
        "far_shoulder": [585, 307], "far_elbow": [641, 550], "wrist": [692, 487],
        "tip": [560, 428], "waist": 727, "crotch": 795,
        "split": [[660, 510], [820, 507], [1050, 490], [1520, 470]],
        "legs": [
            {"name": "rear", "hip": [423, 732], "knee": [401, 1040], "ankle": [348, 1430], "cuff": 1410},
            {"name": "front", "hip": [568, 732], "knee": [577, 1042], "ankle": [554, 1426], "cuff": 1407},
        ],
        "upper_near": [[295, 282], [323, 278], [349, 306], [376, 383], [365, 460], [353, 510], [321, 553], [284, 548], [261, 510], [275, 439], [286, 346]],
        "upper_far": [[558, 280], [604, 306], [627, 384], [643, 467], [673, 527], [656, 574], [618, 578], [603, 530], [589, 434]],
        "far_forearm": [[620, 518], [651, 508], [680, 477], [700, 474], [716, 494], [687, 533], [654, 564], [627, 566]],
        "hand": [[684, 413], [702, 405], [723, 413], [743, 430], [751, 453], [740, 480], [718, 499], [694, 489], [681, 470], [688, 447]],
        "prop_poly": [[659, 415], [690, 324], [751, 330], [748, 345], [800, 354], [759, 443], [709, 430]],
        "trunk_target": [318, 201, 657, 728],
        "trunk_outline": [[201, 435, 513], [260, 352, 582], [315, 343, 611], [430, 371, 634], [555, 359, 645], [675, 342, 656], [728, 336, 654]],
        "neck_patch": [[434, 192], [475, 215], [514, 224], [530, 262], [525, 292], [488, 302], [449, 273]],
        "near_hole": [[290, 500], [414, 447], [462, 382], [503, 380], [570, 425], [545, 471], [465, 499], [345, 558]],
        "trunk_socket": [[0, 0], [100, 85], [200, 124], [330, 142], [410, 130], [512, 112]],
        "head_anchors": [[221, 996], [733, 996], [1246, 996]], "head_scale": .535,
        "arm_anchors": [[[618, 370], [805, 297]], [[1120, 348], [1340, 278]]],
        "action_upper": -.76, "action_forearm": .88, "action_length": 1.66,
        "idle_phase": 1.1,
    },
    "P04": {
        "name": "唐以宁", "prop": "分工清单板", "pelvis": [525, 732],
        "chest": [520, 450], "neck": [515, 285], "cloth": [529, 651],
        "near_shoulder": [400, 339], "near_elbow": [378, 552], "near_wrist": [370, 459],
        "far_shoulder": [611, 336], "far_elbow": [660, 569], "wrist": [724, 559],
        "tip": [280, 393], "waist": 728, "crotch": 795,
        "split": [[660, 540], [810, 539], [1050, 505], [1520, 465]],
        "legs": [
            {"name": "rear", "hip": [460, 734], "knee": [422, 1047], "ankle": [352, 1432], "cuff": 1406},
            {"name": "front", "hip": [592, 734], "knee": [589, 1044], "ankle": [555, 1414], "cuff": 1402},
        ],
        "upper_near": [[380, 302], [411, 299], [433, 323], [449, 390], [428, 464], [416, 522], [394, 569], [365, 583], [339, 551], [340, 507], [364, 425], [367, 363]],
        "upper_far": [[583, 290], [627, 323], [645, 404], [669, 493], [696, 551], [692, 584], [660, 606], [640, 563], [622, 470]],
        "far_forearm": [[641, 551], [670, 535], [707, 533], [734, 544], [740, 572], [707, 593], [674, 605], [648, 588]],
        "hand": [[730, 515], [746, 510], [767, 514], [779, 530], [774, 548], [758, 566], [736, 578], [720, 564], [721, 541]],
        "prop_poly": [[608, 587], [707, 380], [749, 373], [755, 360], [780, 356], [787, 368], [838, 365], [740, 576]],
        "trunk_target": [384, 277, 681, 729],
        "trunk_outline": [[277, 465, 558], [320, 385, 632], [390, 401, 652], [450, 412, 660], [600, 393, 673], [729, 384, 680]],
        "neck_patch": [[467, 224], [490, 242], [540, 246], [554, 273], [562, 315], [522, 323], [486, 302], [466, 274]],
        "near_hole": [[280, 380], [390, 381], [417, 490], [406, 550], [350, 558], [320, 475]],
        "trunk_socket": [[0, 0], [80, 105], [180, 163], [300, 173], [400, 164], [512, 128]],
        "head_anchors": [[285, 977], [798, 977], [1310, 977]], "head_scale": .584,
        "arm_anchors": [[[700, 414], [782, 283]], [[1128, 347], [1276, 260]]],
        "action_upper": -.78, "action_forearm": 1.58, "action_length": 1.84,
        "idle_phase": 2.0,
    },
}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keyed(path: Path) -> Image.Image:
    rgba = np.array(Image.open(path).convert("RGBA"))
    rgb = rgba[:, :, :3].astype(float)
    foreground = ~((rgb[:, :, 0] > rgb[:, :, 1] * 1.3 + 20) & (rgb[:, :, 2] > rgb[:, :, 1] * 1.3 + 20))
    components, _ = label(foreground)
    counts = np.bincount(components.ravel())
    keep = counts > 50
    keep[0] = False
    rgba[~keep[components]] = 0
    spill = np.maximum(0, np.minimum(rgba[:, :, 0].astype(int), rgba[:, :, 2].astype(int)) - rgba[:, :, 1].astype(int) - 28)
    rgba[:, :, 0] = np.maximum(0, rgba[:, :, 0].astype(int) - spill).astype(np.uint8)
    rgba[:, :, 2] = np.maximum(0, rgba[:, :, 2].astype(int) - spill).astype(np.uint8)
    return Image.fromarray(rgba)


def polygon(size, points):
    result = Image.new("L", size)
    ImageDraw.Draw(result).polygon([tuple(p) for p in points], fill=255)
    return np.asarray(result)


def masked(image: Image.Image, mask) -> Image.Image:
    result = image.copy()
    alpha = np.minimum(np.asarray(result.getchannel("A")), np.asarray(mask, dtype=np.uint8))
    result.putalpha(Image.fromarray(alpha))
    return result


def point(value, shift=0):
    v = (np.asarray(value, dtype=float) + [0, shift] - ORIGIN) * SCALE
    return [round(float(x), 6) for x in v]


def affine_canvas(image, source_anchors, target_anchors):
    """Uniform scale and rotation from two actual joint/attachment landmarks."""
    source = np.asarray(source_anchors, dtype=float)
    target = np.asarray(target_anchors, dtype=float)
    a, b = source[1] - source[0], target[1] - target[0]
    scale = np.linalg.norm(b) / np.linalg.norm(a)
    angle = math.atan2(b[1], b[0]) - math.atan2(a[1], a[0])
    rotation = np.array([[math.cos(angle), -math.sin(angle)], [math.sin(angle), math.cos(angle)]]) * scale
    translation = target[0] - rotation @ source[0]
    inverse = np.linalg.inv(rotation)
    offset = -inverse @ translation
    matrix = (inverse[0, 0], inverse[0, 1], offset[0], inverse[1, 0], inverse[1, 1], offset[1])
    result = image.transform((1024, 1536), Image.Transform.AFFINE, matrix, Image.Resampling.BICUBIC)
    return result, {"source_landmarks": source.tolist(), "target_landmarks": target.tolist(), "uniform_scale": float(scale), "rotation_radians": float(angle)}


def emit(entity, name, image, source, processing, extra=None):
    path = ART / entity / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    RECORDS.append({"file": path.relative_to(ROOT).as_posix(), "sha256": sha(path), "size": list(image.size), "source": source.relative_to(ROOT).as_posix(), "source_sha256": sha(source), "processing": processing, **(extra or {})})
    return "res://" + path.relative_to(ROOT).as_posix()


def main_piece(entity, name, image, source, mask=None, shift=0, processing=None):
    if mask is not None:
        image = masked(image, mask)
    box = image.getbbox()
    if box is None:
        raise ValueError(f"Empty registered part: {entity}/{name}")
    crop = image.crop(box)
    file = emit(entity, name, crop, source, processing or "chroma removal and source-space alpha crop; shared scale and optional sole translation", {"source_box": list(box), "source_shift_y": shift, "source_scale": SCALE})
    return {"file": file, "position": point(box[:2], shift), "size": [round(crop.width * SCALE, 6), round(crop.height * SCALE, 6)], "bitmap": crop, "source_box": box, "shift": shift}


def sprite(entity, name, item, bone, anchor, z):
    bitmap = item["bitmap"].resize(tuple(round(x) for x in item["size"]), Image.Resampling.LANCZOS)
    source = ROOT / item["file"].removeprefix("res://")
    file = emit(entity, name + "_registered", bitmap, source, "uniform source-to-rig resample for rigid sprite", {"source_scale": SCALE})
    return {"id": name, "file": file, "bone": bone, "offset": [round(item["position"][i] - anchor[i], 6) for i in range(2)], "z": z}


def registered_variants(entity, name, canvases, source, bone, anchor, z, split=None):
    boxes = [canvas.getbbox() for canvas in canvases.values()]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    position = point(box[:2])
    size = [round((box[2] - box[0]) * SCALE), round((box[3] - box[1]) * SCALE)]
    files = {}
    for variant, canvas in canvases.items():
        crop = canvas.crop(box)
        if split is not None:
            yy = np.arange(crop.height)[:, None] + box[1]
            # Opaque shared overlap prevents a translucent horizontal neck seam.
            fade = (yy <= split + 4) if name == "head" else (yy >= split - 4)
            crop = masked(crop, np.broadcast_to(np.round(fade * 255), (crop.height, crop.width)))
        bitmap = crop.resize(tuple(size), Image.Resampling.LANCZOS)
        files[variant] = emit(entity, name + "_" + variant, bitmap, source, "uniform landmark registration onto shared variant canvas", {"registered_source_box": box, "source_scale": SCALE, "split_y": split})
    part = {"id": name, "file": files["neutral"], "bone": bone, "offset": [round(position[i] - anchor[i], 6) for i in range(2)], "z": z}
    return part, files


def build(entity, cfg):
    master_path = RAW / (entity.lower() + "-master-v1.png")
    sheet_path = RAW / (entity.lower() + "-parts-v1.png")
    master = keyed(master_path)
    sheet = keyed(sheet_path)
    yy, xx = np.mgrid[:1536, :1024]
    base = read(ROOT / "assets/art/actor-anatomy/P01/rig.json")
    spec = deepcopy(base)
    spec.update(version=7, definition_id=entity, canvas=[800, 1220], ground=[400, 1200],
                anatomy={"base_version": 5, "source_scale": SCALE, "origin": ORIGIN.tolist(), "status": "pending_rendered_review"},
                held_contact={"hand": "loop_wrist", "prop": "loop_laptop", "point": [0, 0]})

    # Register every upper-body pivot to this character, retaining the proven bone family.
    sources = {
        "root": ORIGIN, "loop_hips": ORIGIN,
        "torso": cfg["pelvis"], "pelvis": cfg["pelvis"], "loop_chest": cfg["chest"],
        "head": cfg["neck"], "loop_head": cfg["neck"],
        "loop_near": cfg["near_shoulder"], "near_upper": cfg["near_shoulder"],
        "near_forearm": cfg["near_elbow"], "near_elbow": cfg["near_elbow"], "action_tip": cfg["tip"],
        "loop_far": cfg["far_shoulder"], "far_upper": cfg["far_shoulder"],
        "far_forearm": cfg["far_elbow"], "far_elbow": cfg["far_elbow"],
        "loop_cloth": cfg["cloth"], "held_wrist": cfg["wrist"], "loop_wrist": cfg["wrist"],
        "held_laptop": cfg["wrist"], "loop_laptop": cfg["wrist"],
    }
    positions = {name: point(value) for name, value in sources.items()}
    spec["bones"] = [bone for bone in spec["bones"] if not bone["id"].startswith(("rear_", "front_"))]
    for bone in spec["bones"]:
        origin = positions[bone["parent"]] if bone["parent"] else [0, 0]
        bone["position"] = [round(positions[bone["id"]][i] - origin[i], 6) for i in range(2)]
    spec["parts"] = []
    spec["drawings"] = []

    # A masked API edit reconstructs the original garment behind the arms.
    # It shares the full figure's source canvas, with no nonuniform garment warp.
    trunk_path = RAW / (entity.lower() + "-trunk-v1.png")
    outline = cfg["trunk_outline"]
    body_poly = [[row[1], row[0]] for row in outline] + [[row[2], row[0]] for row in reversed(outline)]
    body_mask = polygon(master.size, body_poly)
    trunk_canvas = keyed(trunk_path)
    if entity in ["P03", "P04"]:
        # An armless source includes a dark socket; the moving sleeve must
        # reveal the cardigan's side fabric, not a painted empty armhole.
        pixels = np.asarray(trunk_canvas).copy()
        bounds, fabric = (([326, 265, 389, 440], [400, 430]) if entity == "P03" else ([389, 310, 454, 475], [464, 482]))
        x0, y0, x1, y1 = bounds
        socket = polygon(master.size, [[x0, y0], [x1, y0], [x1, y1], [x0, y1]])
        blend = cv2.GaussianBlur(socket, (13, 13), 0).astype(float) / 255
        replacement = pixels[:, :, :3].copy()
        replacement[:, x0:x1] = cv2.resize(pixels[:, fabric[0]:fabric[1], :3], (x1 - x0, 1536), interpolation=cv2.INTER_CUBIC)
        pixels[:, :, :3] = np.round(pixels[:, :, :3] * (1 - blend[:, :, None]) + replacement * blend[:, :, None]).astype(np.uint8)
        trunk_canvas = Image.fromarray(pixels)
        if entity == "P03":
            # The original upper arm concealed the shoulder side. Give the
            # rotating sleeve a real fabric overlap back to the collar, rather
            # than exposing background between two independently cut pieces.
            bridge = polygon(master.size, [[350, 260], [319, 276], [298, 300], [309, 348], [326, 407], [357, 458], [386, 425], [380, 300]])
            patch = np.zeros_like(pixels)
            patch[:, 290:390, :3] = cv2.resize(pixels[:, 400:430, :3], (100, 1536), interpolation=cv2.INTER_CUBIC)
            patch[:, :, 3] = bridge
            underlay = Image.fromarray(patch)
            underlay.alpha_composite(trunk_canvas)
            trunk_canvas = underlay
            body_mask = np.maximum(body_mask, bridge)
    trunk_canvas = masked(trunk_canvas, body_mask)
    torso = main_piece(entity, "trunk", trunk_canvas, trunk_path,
                       processing="chroma removal and source-space alpha crop; P03/P04 shoulder sockets overpainted with adjacent garment fabric; P03 hidden shoulder extended for sleeve overlap")
    spec["parts"].append({"id": "torso", "mesh": True, "bone": "loop_chest", "base_bone": "loop_cloth", "position": torso["position"], "size": torso["size"], "z": 0, "cells": 12, "file": torso["file"]})

    # The near sleeve is repaired independently to remove the painted forearm
    # that otherwise remains visible when the separate forearm turns away.
    for name, key, z in [("near_upper", "upper_near", 3), ("far_upper", "upper_far", -1)]:
        source = master_path
        canvas = masked(master, polygon(master.size, cfg[key]))
        if name == "near_upper":
            box = canvas.getbbox()
            registration = next(row for row in read(RAW / "upper-edit-inputs.json") if row["character"] == entity)
            x, y = registration["canvas_offset"]
            w, h = registration["scaled_size"]
            source = RAW / (entity.lower() + "-upper-clean-v1.png")
            sleeve = keyed(source).crop((x, y, x + w, y + h)).resize((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", master.size)
            canvas.alpha_composite(sleeve, box[:2])
            RECORDS.append({"kind": "clean_upper_registration", "entity": entity, "source_box": list(box), **registration})
        item = main_piece(entity, name, canvas, source)
        spec["parts"].append({"id": name, "mesh": True, "bone": name, "base_bone": name.replace("upper", "elbow"), "position": item["position"], "size": item["size"], "z": z, "cells": 10, "file": item["file"], "weight_axis": [positions[name], positions[name.replace("upper", "elbow")]], "weight_range": [.06, .94]})

    # Forearm alternatives use the same measured elbow and wrist, not separate fits.
    arms = {}
    for index, name in enumerate(["neutral", "strike"]):
        arm_cell = Image.new("RGBA", sheet.size)
        arm_cell.alpha_composite(sheet.crop((512 * (index + 1), 0, 512 * (index + 2), 512)), (512 * (index + 1), 0))
        arm, calibration = affine_canvas(arm_cell, cfg["arm_anchors"][index], [cfg["near_elbow"], cfg["near_wrist"]])
        arms[name] = arm
        RECORDS.append({"kind": "forearm_registration", "entity": entity, "variant": name, **calibration})
    part, arm_files = registered_variants(entity, "near_forearm", arms, sheet_path, "near_forearm", positions["near_forearm"], 8)
    spec["parts"].append(part)
    action_draw = [[0, [1, 0, 0, 0]], [.27, [1, 0, 0, 0]], [.36, [0, 1, 0, 0]], [.66, [0, 1, 0, 0]], [.83, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]]
    spec["drawings"].append({"part": "near_forearm", "variants": [{"id": "arm_strike", "file": arm_files["strike"]}], "poses": {"action": action_draw}})

    # Forearm, hand and prop share original pixels and coordinates. Hidden hand pixels
    # are inpainted inside the paper only, so wrist articulation cannot reveal a ghost hand.
    hand_mask = polygon(master.size, cfg["hand"])
    forearm = main_piece(entity, "held_forearm", master, master_path, polygon(master.size, cfg["far_forearm"]))
    hand = main_piece(entity, "held_hand", master, master_path, hand_mask)
    prop_mask = polygon(master.size, cfg["prop_poly"])
    prop = masked(master, prop_mask)
    pixels = np.array(prop)
    repair = cv2.dilate((hand_mask > 0).astype(np.uint8) * 255, np.ones((17, 17), np.uint8))
    if repair.any():
        trusted = (pixels[:, :, 3] > 0) & (repair == 0)
        nearest = distance_transform_edt(~trusted, return_distances=False, return_indices=True)
        rgb = pixels[:, :, :3].copy()
        # Extend actual paper color beyond the cutout before filling the hand;
        # transparent black and skin outside the board cannot bleed into it.
        rgb[~trusted] = rgb[nearest[0][~trusted], nearest[1][~trusted]]
        pixels[:, :, :3] = cv2.inpaint(rgb, repair, 5, cv2.INPAINT_TELEA)
    prop = Image.fromarray(pixels)
    held = main_piece(entity, "held_prop", prop, master_path,
                      processing="source-space alpha crop; hand mask dilation, nearest trusted paper color extension and local inpaint remove occluded hand pixels")
    spec["parts"].extend([
        sprite(entity, "held_forearm", forearm, "far_forearm", positions["far_forearm"], 5),
        sprite(entity, "held_laptop", held, "loop_laptop", positions["loop_laptop"], 6),
        sprite(entity, "held_hand", hand, "loop_wrist", positions["loop_wrist"], 7),
    ])

    # Complete head alternatives are uniformly registered by neck attachment.
    heads = {}
    for index, name in enumerate(["neutral", "focus", "hit"]):
        patch = Image.new("RGBA", sheet.size)
        patch.alpha_composite(sheet.crop((512 * index, 512, 512 * (index + 1), 1024)), (512 * index, 512))
        anchor = np.array(cfg["head_anchors"][index], dtype=float)
        target_anchor = np.array(cfg["neck"], dtype=float)
        head, calibration = affine_canvas(patch, [anchor, anchor + [0, -200]], [target_anchor, target_anchor + [0, -200 * cfg["head_scale"]]])
        neck_underlay = masked(master, polygon(master.size, cfg["neck_patch"]))
        neck_underlay.alpha_composite(head)
        heads[name] = neck_underlay
        RECORDS.append({"kind": "head_registration", "entity": entity, "variant": name, **calibration})
    face_split = cfg["neck"][1] - 26
    head_poses = {"action": [[0, [1, 0, 0, 0]], [.09, [1, 0, 0, 0]], [.18, [0, 1, 0, 0]], [.77, [0, 1, 0, 0]], [.89, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]],
                  "hit": [[0, [1, 0, 0, 0]], [.06, [0, 0, 1, 0]], [.57, [0, 0, 1, 0]], [.78, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]],
                  "guard": [[0, [1, 0, 0, 0]], [.2, [0, 1, 0, 0]], [.72, [0, 1, 0, 0]], [.9, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]]}
    for name, z in [("head", 2), ("neck_overlap", -1)]:
        part, files = registered_variants(entity, name, heads, sheet_path, "loop_head", positions["loop_head"], z, split=face_split)
        spec["parts"].append(part)
        spec["drawings"].append({"part": name, "variants": [{"id": "head_focus", "file": files["focus"]}, {"id": "head_hit", "file": files["hit"]}], "poses": deepcopy(head_poses)})
        if name == "head":
            spec["expression"] = {"part": "head", "blink": files["hit"], "intervals": [[1.12, 1.23], [2.91, 3.03], [5.72, 5.84]]}

    # Continuous waist and two legs retain the original figure's shared pixel transform.
    split = np.interp(yy, [p[0] for p in cfg["split"]], [p[1] for p in cfg["split"]])
    fade = np.clip((cfg["crotch"] + 80 - yy) / 90, 0, 1)
    # Pants continue under the independently leaning garment. The hidden top
    # band reflects adjacent trouser pixels, so opposite waist corners never
    # open into the background or expose a second floating garment hem.
    pants = np.array(master)
    join = cfg["waist"] + 16
    for row in range(cfg["waist"] - 65, join):
        pants[row] = np.asarray(master)[2 * join - row]
        if row < cfg["waist"]:
            occupied = np.flatnonzero(pants[row, :, 3] > 0)
            if len(occupied):
                inset = round((cfg["waist"] + 32 - row) * .65)
                pants[row, :occupied[0] + inset] = 0
                pants[row, occupied[-1] - inset + 1:] = 0
    pelvis_mask = np.where(yy >= cfg["waist"] - 65, fade * 255, 0).astype(np.uint8)
    pelvis = main_piece(entity, "pelvis", Image.fromarray(pants), master_path, pelvis_mask,
                        processing="source-space alpha crop; mirrored adjacent trouser pixels extend 65px behind leaning garment; shared source scale")
    spec["parts"].append({"id": "pelvis", "mesh": True, "bone": "loop_cloth", "base_bone": "rear_thigh", "split_bone": "front_thigh", "position": pelvis["position"], "size": pelvis["size"], "z": -1, "cells": 16, "weight_range": [.25, .86], "split_range": [.4, .63], "file": pelvis["file"]})
    spec["feet"] = []
    calibration = []
    alpha = np.asarray(master.getchannel("A"))
    for leg in cfg["legs"]:
        name = leg["name"]
        region = (xx < split if name == "rear" else xx >= split) & (yy >= cfg["crotch"] - 50)
        bottom = int(np.where((alpha > 0) & region)[0].max()) + 1
        shift = 1520 - bottom
        limb = main_piece(entity, name + "_leg", master, master_path, np.where(region & (yy < leg["cuff"] + 8), 255, 0), shift=shift)
        shoe = main_piece(entity, name + "_shoe", master, master_path, np.where(region & (yy >= leg["cuff"] - 15), 255, 0), shift=shift)
        hip = point(leg["hip"])
        knee = point(leg["knee"], shift)
        ankle = point(leg["ankle"], shift)
        lengths = [math.dist(hip, knee), math.dist(knee, ankle)]
        cross = (knee[0] - hip[0]) * (ankle[1] - knee[1]) - (knee[1] - hip[1]) * (ankle[0] - knee[0])
        bend = -1 if cross > 0 else 1
        for id_, parent, p, parent_point, length in [
            (name + "_thigh", "pelvis", hip, positions["pelvis"], lengths[0]),
            (name + "_shin", name + "_thigh", knee, hip, lengths[1]),
            (name + "_ankle", name + "_shin", ankle, knee, 65),
        ]:
            spec["bones"].append({"id": id_, "parent": parent, "position": [round(p[i] - parent_point[i], 6) for i in range(2)], "length": length})
            positions[id_] = p
        fraction = (knee[1] - limb["position"][1]) / limb["size"][1]
        spec["parts"].append({"id": name + "_leg", "mesh": True, "bone": name + "_thigh", "base_bone": name + "_shin", "position": limb["position"], "size": limb["size"], "z": -3 if name == "rear" else -2, "cells": 16, "weight_range": [fraction - .08, fraction + .08], "file": limb["file"]})
        spec["parts"].append(sprite(entity, name + "_shoe", shoe, name + "_ankle", ankle, -4))
        spec["feet"].append({"upper": name + "_thigh", "lower": name + "_shin", "ankle": name + "_ankle", "target": ankle, "lengths": lengths, "bend": bend, "bind_axes": True})
        calibration.append({"name": name, "hip": hip, "knee": knee, "ankle": ankle, "lengths": lengths, "source_hip": leg["hip"], "source_knee": leg["knee"], "source_ankle": leg["ankle"], "source_shift_y": shift})
    spec["anatomy"]["calibration"] = calibration
    spec["contact_shadows"] = [[x["ankle"][0] + 12, 0, 52, 10] for x in calibration]
    spec["cast_shadows"] = [[-20, 9, 170, 15]]

    # Retarget V5 timings and secondary loops to the measured body, with a distinct
    # arm phrase per role. Position curves use new rest landmarks and safe settling.
    old_positions = {}
    for bone in base["bones"]:
        parent = old_positions.get(bone["parent"], [0, 0])
        old_positions[bone["id"]] = [parent[i] + bone["position"][i] for i in range(2)]
    new_bones = {b["id"]: b for b in spec["bones"]}
    old_bones = {b["id"]: b for b in base["bones"]}
    for pose, animation in spec["animations"].items():
        for track in animation["tracks"]:
            if track["property"] != "position":
                if track["bone"] == "torso":
                    track["keys"] = [[t, value * .72] for t, value in track["keys"]]
                continue
            name = track["bone"]
            old_rest = old_bones[name]["position"]
            new_rest = new_bones[name]["position"]
            track["keys"] = [[t, [round(new_rest[i] + (value[i] - old_rest[i]) * (.72 if i == 0 else 1), 6) for i in range(2)]] for t, value in track["keys"]]
            if name == "torso":
                track["keys"] = [[t, [value[0], max(new_rest[1], value[1])]] for t, value in track["keys"]]
            if name == "action_tip":
                track["keys"] = [[0, list(new_rest)], [1, list(new_rest)]]
    action = spec["animations"]["action"]
    # These painted legs are nearly straight at rest. Recover the recoil with
    # a small remaining knee allowance instead of overshooting the resting hip.
    rest = new_bones["torso"]["position"]
    for track in spec["animations"]["hit"]["tracks"]:
        if track["bone"] == "torso" and track["property"] == "position":
            track["keys"] = [[t, [rest[0] + dx, rest[1] + dy]] for t, dx, dy in [
                (0, 0, 0), (.09, -17.856, 11.9), (.30, -11.52, 7.7),
                (.56, -2, 4), (.76, -.5, 2), (.90, 0, .65), (1, 0, 0)]]
    action["length"] = cfg["action_length"]
    for track in action["tracks"]:
        if track["bone"] == "near_upper":
            peak = cfg["action_upper"]
            track["keys"] = [[0, 0], [.18, .10], [.28, .09], [.4, peak], [.55, peak * .94], [.71, peak * .55], [.87, -.08], [1, 0]]
        elif track["bone"] == "near_forearm":
            peak = cfg["action_forearm"]
            track["keys"] = [[0, 0], [.19, -.16], [.29, -.10], [.41, peak], [.55, peak * .95], [.73, peak * .48], [.87, .05], [1, 0]]
        elif track["bone"] == "torso" and track["property"] == "position":
            rest = new_bones["torso"]["position"]
            track["keys"] = [[t, [rest[0] + dx, rest[1] + dy]] for t, dx, dy in [(0, 0, 0), (.22, -8, 11), (.40, 23, 16), (.55, 18, 16), (.78, -2, 4), (1, 0, 0)]]
    # Gentle breathing differs in phase and pace while keeping planted hips still.
    spec["idle_length"] = {"P02": 6.7, "P03": 6.1, "P04": 6.5}[entity]
    for track in spec["idle_tracks"]:
        if track["bone"] == "loop_hips":
            track["keys"] = [[t, [0, 0]] for t, _ in track["keys"]]
        elif track["property"] == "rotation":
            amplitude = max(abs(value) for _, value in track["keys"])
            amplitude *= .65 if track["bone"] in ["loop_near", "loop_far", "loop_wrist", "loop_laptop"] else .85
            track["keys"] = [[i / 64, round(amplitude * math.sin(i / 64 * math.tau * (2 if "wrist" in track["bone"] else 1) + cfg["idle_phase"]), 7)] for i in range(65)]
    spec["drawing_blend_seconds"] = .1
    spec["party"] = {"name": cfg["name"], "prop": cfg["prop"], "base_art": "selected_P01_v5", "master": master_path.relative_to(ROOT).as_posix(), "sheet": sheet_path.relative_to(ROOT).as_posix(), "garment_edit": trunk_path.relative_to(ROOT).as_posix()}
    return spec


def preview(entity, spec):
    positions = {}
    for bone in spec["bones"]:
        parent = positions.get(bone["parent"], [0, 0])
        positions[bone["id"]] = [parent[i] + bone["position"][i] for i in range(2)]
    canvas = Image.new("RGBA", (950, 1320), "#e6dfd1")
    origin = [370, 1260]
    for part in sorted(spec["parts"], key=lambda p: p["z"]):
        texture = Image.open(ROOT / part["file"].removeprefix("res://")).convert("RGBA")
        if part.get("mesh"):
            p = part["position"]
            texture = texture.resize(tuple(round(v) for v in part["size"]), Image.Resampling.LANCZOS)
        else:
            p = [positions[part["bone"]][i] + part["offset"][i] for i in range(2)]
        canvas.alpha_composite(texture, tuple(round(origin[i] + p[i]) for i in range(2)))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 24)
    draw.text((24, 15), f"{entity} {spec['party']['name']} · 资源组装预览（另存Godot实渲）", font=font, fill="#26353e")
    draw.line((50, origin[1], 880, origin[1]), fill="#868173", width=2)
    canvas.convert("RGB").save(EV / (entity.lower() + "-resource-preview.jpg"), quality=96)
    joints = canvas.copy()
    draw = ImageDraw.Draw(joints)
    for leg in spec["anatomy"]["calibration"]:
        points = [tuple(origin[i] + leg[key][i] for i in range(2)) for key in ["hip", "knee", "ankle"]]
        draw.line(points, fill="#c47824", width=3)
        for p in points:
            draw.ellipse((p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5), fill="#de9230")
    joints.convert("RGB").save(EV / (entity.lower() + "-joint-registration.jpg"), quality=96)


def main():
    EV.mkdir(parents=True, exist_ok=True)
    RECORDS.clear()
    # Preserve the selected V5 and v4 enemy data verbatim in the new opt-in family.
    for entity in ["P01", "N01"]:
        source = ROOT / "assets/art/actor-anatomy" / entity / "rig.json"
        destination = ART / entity / "rig.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
    summaries = []
    for entity, config in CONFIG.items():
        spec = build(entity, config)
        save(ART / entity / "rig.json", spec)
        textures = {p["file"].removeprefix("res://") for p in spec["parts"]}
        textures.update(v["file"].removeprefix("res://") for layer in spec["drawings"] for v in layer["variants"])
        textures.add(spec["expression"]["blink"].removeprefix("res://"))
        save(ART / entity / "source.json", {"version": 7, "base_version": 5, "definition_id": entity, "status": "pending_rendered_review", "api_manifest": "output/imagegen/actor-party-20261115/asset-manifest.json", "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"], "textures": [{"file": file, "sha256": sha(ROOT / file)} for file in sorted(textures)]})
        preview(entity, spec)
        summaries.append({"definition_id": entity, "bones": len(spec["bones"]), "parts": len(spec["parts"]), "meshes": sum(bool(p.get("mesh")) for p in spec["parts"]), "textures": len(textures), "calibration": spec["anatomy"]["calibration"]})
    save(EV / "extraction.json", {"outputs": RECORDS, "characters": summaries, "source_scale": SCALE})
    print(json.dumps({"characters": [{k: v for k, v in s.items() if k != "calibration"} for s in summaries], "derived_outputs": sum("file" in r for r in RECORDS)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
