"""Extract same-source enemy components and author native presentation rigs."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

import build_actor_motion_polish as curves

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/enemy-roster-20261115"
OUT = ROOT / "assets/art/enemies"
EV = ROOT / "artifacts/verification/enemy-roster-20261115"


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def components(path):
    raw = Image.open(path).convert("RGB")
    rgb = np.asarray(raw).astype(np.float32)
    dominance = np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1]
    # Support-limited alpha avoids preserving faint near-magenta background noise.
    alpha = np.clip((170.0 - dominance) / 120.0, 0.0, 1.0)
    support = cv2.dilate(np.uint8(dominance < 65), np.ones((3, 3), np.uint8))
    alpha *= support
    count, labels, stats, centers = cv2.connectedComponentsWithStats(np.uint8(alpha > .14))
    meaningful = [i for i in range(1, count) if stats[i, cv2.CC_STAT_AREA] > 30]
    main = max(meaningful, key=lambda i: stats[i, cv2.CC_STAT_AREA])
    groups = {"body": [main], "attack": [], "accent": []}
    for i in meaningful:
        if i == main:
            continue
        x, y = centers[i]
        groups["body" if x >= raw.width * .31 else ("attack" if y < raw.height * .53 else "accent")].append(i)
    result = {}
    for name, group in groups.items():
        if not group:
            raise ValueError(f"Missing separate {name} component: {path.name}")
        mask = np.isin(labels, group)
        a = alpha * mask
        # Unmatte edge pixels against the actual flat-magenta key, retaining fine ink edges.
        clean = np.clip((rgb - (1 - a[:, :, None]) * np.array([255, 0, 255])) /
                        np.maximum(a[:, :, None], .01), 0, 255)
        rgba = np.dstack([clean, a * 255]).astype(np.uint8)
        image = Image.fromarray(rgba)
        box = image.getchannel("A").getbbox()
        if box is None:
            raise ValueError(f"Empty {name}: {path.name}")
        image = image.crop(box)
        result[name] = (image, list(box))
    return result, raw.size


def rig(entry, extracted, ordinal):
    body = extracted["body"][0]
    factor = min(820 / body.height, 735 / body.width)
    w, h = round(body.width * factor, 3), round(body.height * factor, 3)
    family = entry["family"]
    flex = {"paper": 1.0, "ink": .8, "machine": .32, "liquid": 1.15, "stone": .25}[family]
    speed = {"paper": 1.75, "ink": 1.9, "machine": 1.85, "liquid": 2.05, "stone": 2.2}[family]
    variation = (ordinal % 7 - 3) * .012
    b = curves.bone
    body_rest = [0, -h * .42]
    crown_rest = [0, -h * .35]
    attack_rest = [-w * .43 - 85, -h * .54]
    accent_rest = [w * .45 + 35, -h * .36]
    bones = [b("root", "", [0, 0]), b("ground_anchor", "root", [0, 0]),
             b("torso", "root", body_rest), b("loop_body", "torso", [0, 0]),
             b("crown", "loop_body", crown_rest), b("loop_crown", "crown", [0, 0]),
             b("attack", "loop_body", [attack_rest[0], attack_rest[1] - body_rest[1]]),
             b("loop_attack", "attack", [0, 0]), b("action_tip", "loop_attack", [-40, -30]),
             b("accent", "loop_body", [accent_rest[0], accent_rest[1] - body_rest[1]]),
             b("loop_accent", "accent", [0, 0])]
    parts = [{"id": "body", "mesh": True, "bone": "loop_crown", "base_bone": "loop_body",
              "foot_bone": "ground_anchor", "position": [-w / 2, -h], "size": [w, h], "cells": 12,
              "z": 0, "file": f"res://assets/art/enemies/{entry['id']}/body.png"}]
    for name, height, z in (("attack", min(235, h * .29), 2), ("accent", min(130, h * .17), 1)):
        im = extracted[name][0]
        f = min(height / im.height, (165 if name == "attack" else 120) / im.width)
        size = [round(im.width * f, 3), round(im.height * f, 3)]
        parts.append({"id": name, "bone": "loop_" + name, "offset": [-size[0] / 2, -size[1] / 2],
                      "display_size": size, "z": z, "file": f"res://assets/art/enemies/{entry['id']}/{name}.png"})
    R, P, S = curves.rotation, curves.position, curves.scale
    torso_peak = -.055 - .045 * flex + variation * .2
    rest = {x["id"]: x["position"] for x in bones}
    animations = {
        "action": {"length": speed, "tracks": [
            R("torso", [[0, 0], [.19, .045], [.28, .055], [.4, torso_peak], [.53, torso_peak * .8], [.79, .012], [1, 0]]),
            P("torso", body_rest, [[0, [0, 0]], [.22, [12, 5]], [.4, [-22, -6]], [.55, [-14, 0]], [.8, [3, 0]], [1, [0, 0]]]),
            R("crown", [[0, 0], [.26, .04 * flex], [.44, -.075 * flex], [.68, .025 * flex], [1, 0]]),
            R("attack", [[0, 0], [.21, .37], [.3, .42], [.4, -.62], [.54, -.42], [.8, .06], [1, 0]]),
            P("attack", rest["attack"], [[0, [0, 0]], [.24, [18, 12]], [.4, [-35, -12]], [.58, [-22, -3]], [1, [0, 0]]]),
            R("accent", [[0, 0], [.3, -.10], [.5, .22 * flex], [.75, -.055], [1, 0]]),
            S("torso", [[0, [1, 1]], [.25, [1 + .017 * flex, 1 - .022 * flex]], [.43, [1 - .013 * flex, 1 + .016 * flex]], [.72, [1, 1]], [1, [1, 1]]])]},
        "hit": {"length": 1.3 + .13 * flex, "tracks": [
            R("torso", [[0, 0], [.09, .1 + .055 * flex], [.26, .07], [.53, -.025], [.8, .008], [1, 0]]),
            P("torso", body_rest, [[0, [0, 0]], [.09, [23, 8]], [.28, [13, 6]], [.58, [-3, 0]], [1, [0, 0]]]),
            R("crown", [[0, 0], [.13, -.11 * flex], [.36, .06 * flex], [.65, -.02], [1, 0]]),
            R("attack", [[0, 0], [.14, .36], [.4, -.13], [.68, .04], [1, 0]]),
            R("accent", [[0, 0], [.2, -.3 * flex], [.46, .12], [.74, -.04], [1, 0]])]},
        "guard": {"length": 1.55, "tracks": [
            R("torso", [[0, 0], [.26, .035], [.6, .027], [1, 0]]),
            R("crown", [[0, 0], [.3, -.035 * flex], [.64, -.025 * flex], [1, 0]]),
            R("attack", [[0, 0], [.28, -.37], [.63, -.32], [1, 0]]),
            R("accent", [[0, 0], [.31, -.16], [.67, -.1], [1, 0]])]},
        "enter": {"length": 1.4, "tracks": [
            P("torso", body_rest, [[0, [10, 15]], [.32, [-2, -4]], [.65, [1, 2]], [1, [0, 0]]]),
            R("crown", [[0, -.06 * flex], [.35, .02], [1, 0]]),
            R("attack", [[0, .22], [.42, -.08], [.72, .025], [1, 0]])]},
        "depart": {"length": 1.8, "tracks": [
            R("root", [[0, 0], [.22, .04], [.55, .22], [.82, .25], [1, .25]]),
            P("root", [0, 0], [[0, [0, 0]], [.24, [8, 5]], [.6, [30, 42]], [1, [34, 49]]]),
            R("crown", [[0, 0], [.4, .1 * flex], [1, .12 * flex]]),
            R("attack", [[0, 0], [.35, .4], [.7, -.12], [1, .13]]),
            R("accent", [[0, 0], [.32, -.4 * flex], [.76, .15], [1, .1]])]},
        "phase": {"length": 1.7, "tracks": [
            R("torso", [[0, 0], [.23, .045], [.51, -.065], [.76, .015], [1, 0]]),
            R("crown", [[0, 0], [.28, -.055 * flex], [.56, .07 * flex], [1, 0]]),
            R("attack", [[0, 0], [.29, .27], [.53, -.38], [.8, .08], [1, 0]]),
            R("accent", [[0, 0], [.27, -.28], [.56, .32], [.8, -.075], [1, 0]])]},
    }
    specification = {"version": 13, "definition_id": entry["id"], "canvas": [1120, 1050], "ground": [560, 940],
                     "ground_offset": 6, "action_bone": "action_tip", "bones": bones, "parts": parts,
                     "idle_length": 6.4 + (ordinal % 4) * .4, "blend_seconds": .18, "contact_fraction": .4,
                     "contact_shadows": [[0, 0, min(250, w * .33), 18]],
                     "idle_tracks": [curves.wave("loop_body", "rotation", 0, .006 + .006 * flex, phase=.2),
                         curves.wave("loop_crown", "rotation", 0, .012 * flex, cycles=1, phase=-.4),
                         curves.wave("loop_crown", "scale", [1, 1], [.003 * flex, .008 * flex], phase=.2),
                         curves.wave("loop_attack", "rotation", 0, .035 + .025 * flex, cycles=2, phase=-.8),
                         curves.wave("loop_accent", "rotation", 0, .05 + .035 * flex, cycles=3, phase=-1.2),
                         curves.wave("loop_accent", "position", [0, 0], [2, -4 - 3 * flex], phase=-.5)],
                     "material_family": family, "art_version": 1,
                     "construction": "One original weighted body mesh (crown/body/ground), two separately painted same-source props, independent loop and action bones; no humanoid IK claim."}
    return curves.complete(specification, animations)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--available", action="store_true")
    parser.add_argument("--ids", nargs="*")
    args = parser.parse_args()
    roster = json.loads((RAW / "roster.json").read_text(encoding="utf-8"))
    overrides = RAW / "selected-sources.json"
    selected = json.loads(overrides.read_text(encoding="utf-8")) if overrides.exists() else {}
    index, processed, missing, failed = {}, [], [], []
    for ordinal, entry in enumerate(roster["entries"]):
        id = entry["id"]
        if id == "N01":
            old = json.loads((ROOT / entry["rig"].removeprefix("res://")).read_text(encoding="utf-8"))
            body = next(x for x in old["parts"] if x["id"] == "body")
            index[id] = {"rig": entry["rig"], "texture": body["file"], "version": 4, "name": entry["name"], "source": "existing reviewed N01 V4"}
            continue
        source = ROOT / selected.get(id, entry["output"])
        if not source.exists():
            missing.append(id)
            continue
        dest = OUT / id
        if not (dest / "rig.json").exists() or (args.ids and id in args.ids):
            try:
                extracted, original_size = components(source)
                dest.mkdir(parents=True, exist_ok=True)
                records = []
                for name, (image, box) in extracted.items():
                    target = dest / (name + ".png")
                    image.save(target)
                    records.append({"file": target.relative_to(ROOT).as_posix(), "size": list(image.size),
                                    "sha256": digest(target), "source_bbox": box})
                specification = rig(entry, extracted, ordinal)
                write(dest / "rig.json", specification)
                write(dest / "source.json", {"id": id, "version": 13, "name": entry["name"],
                      "requirements": entry["requirements"], "source": source.relative_to(ROOT).as_posix(),
                      "source_sha256": digest(source), "source_size": list(original_size),
                      "method": "Magenta dominance alpha with foreground support limit; edge unmatte; connected-component grouping into body/upper-left prop/lower-left accent; retain original pixels, independent material-specific native rig.",
                      "outputs": records, "visual_acceptance": "pending review; machine metrics do not establish visual quality"})
                processed.append(id)
            except (ValueError, OSError) as error:
                failed.append({"id": id, "error": str(error)})
                continue
        index[id] = {"rig": f"res://assets/art/enemies/{id}/rig.json", "texture": f"res://assets/art/enemies/{id}/body.png",
                     "version": 13, "name": entry["name"], "source": source.relative_to(ROOT).as_posix()}
    write(OUT / "roster.json", {"requirements": ["UIR-069"], "expected_count": 60, "enemies": index,
          "complete": not missing and not failed and len(index) == 60})
    write(EV / "build-summary.json", {"available": len(index), "processed": processed, "missing": missing, "failed": failed})
    print(json.dumps({"available": len(index), "processed": processed, "missing": missing, "failed": failed}))
    return bool(failed or (missing and not args.available))


if __name__ == "__main__":
    raise SystemExit(main())
