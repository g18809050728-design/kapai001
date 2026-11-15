"""Author the isolated second rig revision from reviewed, unchanged RGBA parts.

Motion curves have independent accents; textures are not redrawn by this tool.
Source records explicitly distinguish the old API art from local rig changes.
"""
from pathlib import Path
import copy
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/art/actor-rig-pilot"
OUT = ROOT / "assets/art/actor-rig-polish"


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def bone(name, parent, position):
    return {"id": name, "parent": parent, "position": position, "length": 70}


def track(name, prop, keys):
    return {"bone": name, "property": prop, "keys": keys}


def rotation(name, keys):
    return track(name, "rotation", keys)


def position(name, rest, keys):
    return track(name, "position", [[t, [rest[0] + v[0], rest[1] + v[1]]] for t, v in keys])


def scale(name, keys):
    return track(name, "scale", keys)


def wave(name, prop, base, amplitude, cycles=2, phase=0.0):
    keys = []
    for i in range(65):
        t = i / 64
        value = math.sin(t * math.tau * cycles + phase)
        v = [base[j] + amplitude[j] * value for j in range(2)] if isinstance(base, list) else base + amplitude * value
        keys.append([round(t, 6), v])
    return track(name, prop, keys)


def complete(spec, animations):
    # Every action owns the same non-loop channels. Native animation blending
    # can therefore return an interrupted limb to rest instead of leaving it stuck.
    channels = {}
    for animation in animations.values():
        for t in animation["tracks"]:
            channels[t["bone"], t["property"]] = t
    rests = {b["id"]: b for b in spec["bones"]}
    for animation in animations.values():
        existing = {(t["bone"], t["property"]) for t in animation["tracks"]}
        for name, prop in sorted(channels):
            if (name, prop) not in existing:
                value = rests[name]["position"] if prop == "position" else ([1, 1] if prop == "scale" else 0)
                animation["tracks"].append(track(name, prop, [[0, value], [1, value]]))
    spec["animations"] = animations
    return spec


def hero():
    spec = json.loads((SOURCE / "P01/rig.json").read_text(encoding="utf-8"))
    spec.update(version=2, canvas=[800, 1220], ground=[400, 1200], ground_offset=14,
                idle_length=6.4, blend_seconds=0.22, contact_fraction=0.39)
    spec["bones"] = [
        bone("root", "", [0, 0]), bone("loop_hips", "root", [0, 0]),
        bone("torso", "loop_hips", [0, -500]), bone("loop_chest", "torso", [0, -225]),
        bone("head", "loop_chest", [20, -205]), bone("loop_head", "head", [0, 0]),
        bone("loop_near", "loop_chest", [-135, -130]), bone("near_upper", "loop_near", [0, 0]),
        bone("near_forearm", "near_upper", [-68, 205]), bone("action_tip", "near_forearm", [220, -65]),
        bone("loop_far", "loop_chest", [120, -125]), bone("far_upper", "loop_far", [0, 0]),
        bone("far_forearm", "far_upper", [30, 210]), bone("loop_cloth", "torso", [0, -60]),
        bone("rear_thigh", "torso", [-75, 5]), bone("rear_shin", "rear_thigh", [0, 260]),
        bone("rear_ankle", "rear_shin", [0, 260]),
        bone("front_thigh", "torso", [65, 5]), bone("front_shin", "front_thigh", [0, 260]),
        bone("front_ankle", "front_shin", [0, 260]),
    ]
    spec["feet"] = [
        {"upper": "rear_thigh", "lower": "rear_shin", "ankle": "rear_ankle", "target": [-118, 0], "lengths": [260, 260], "bend": -1},
        {"upper": "front_thigh", "lower": "front_shin", "ankle": "front_ankle", "target": [95, 0], "lengths": [260, 260], "bend": -1},
    ]
    spec["parts"] = [p for p in spec["parts"] if p["id"] not in ["rear_leg", "front_leg"]]
    torso = next(p for p in spec["parts"] if p["id"] == "torso")
    torso.update(position=[-195, -930], size=[390, 460], cells=8)
    for name, hip, width, z in [("rear", -75, 190, -3), ("front", 65, 178, -2)]:
        spec["parts"].append({"id": name + "_leg", "mesh": True, "bone": name + "_thigh",
            "base_bone": name + "_shin", "foot_bone": name + "_ankle", "position": [hip - width * 0.45, -510],
            "size": [width, 535], "z": z, "cells": 9,
            "file": f"res://assets/art/actor-rig-pilot/P01/{name}_leg.png"})
    spec["idle_tracks"] = [
        wave("loop_hips", "position", [0, 0], [7, -7]),
        wave("loop_chest", "rotation", 0, 0.018, phase=0.2),
        wave("loop_chest", "scale", [1, 1], [0.008, 0.012]),
        wave("loop_head", "rotation", 0, -0.032, cycles=1, phase=-0.4),
        wave("loop_near", "rotation", 0, 0.034, phase=-0.7),
        wave("loop_far", "rotation", 0, -0.018, phase=-1.1),
        wave("loop_cloth", "rotation", 0, 0.050, cycles=3, phase=-0.8),
    ]
    spec["contact_shadows"] = [[-115, 0, 70, 13], [96, 0, 60, 12]]
    action = [
        rotation("torso", [[0, 0], [.18, -.075], [.29, -.085], [.39, .145], [.52, .11], [.76, -.025], [1, 0]]),
        position("torso", [0, -500], [[0, [0, 0]], [.22, [-18, 12]], [.39, [38, 6]], [.52, [30, 9]], [.76, [-5, 3]], [1, [0, 0]]]),
        rotation("near_upper", [[0, 0], [.19, .22], [.29, .14], [.38, -.92], [.48, -.80], [.70, -.22], [.88, .04], [1, 0]]),
        rotation("near_forearm", [[0, 0], [.22, -.32], [.32, -.18], [.43, 1.02], [.55, .84], [.73, .24], [.9, -.04], [1, 0]]),
        rotation("head", [[0, 0], [.24, .055], [.42, -.15], [.63, -.09], [.83, .024], [1, 0]]),
        rotation("far_upper", [[0, 0], [.26, -.07], [.47, .08], [.72, -.025], [1, 0]]),
        rotation("far_forearm", [[0, 0], [.23, -.05], [.48, -.12], [.72, .035], [1, 0]]),
    ]
    hit = [
        rotation("torso", [[0, 0], [.08, -.19], [.24, -.13], [.48, .045], [.72, -.016], [1, 0]]),
        position("torso", [0, -500], [[0, [0, 0]], [.09, [-31, 17]], [.3, [-20, 11]], [.56, [5, -3]], [1, [0, 0]]]),
        rotation("head", [[0, 0], [.15, .27], [.32, .17], [.58, -.055], [.82, .018], [1, 0]]),
        rotation("near_upper", [[0, 0], [.12, .30], [.30, .18], [.62, -.06], [1, 0]]),
        rotation("near_forearm", [[0, 0], [.2, -.36], [.38, -.22], [.68, .055], [1, 0]]),
        rotation("far_forearm", [[0, 0], [.18, .14], [.4, .08], [.72, -.025], [1, 0]]),
    ]
    guard = [rotation("torso", [[0, 0], [.25, -.06], [.55, -.04], [1, 0]]),
        rotation("near_upper", [[0, 0], [.22, -.35], [.6, -.3], [1, 0]]),
        rotation("near_forearm", [[0, 0], [.32, -.50], [.66, -.40], [1, 0]]),
        rotation("head", [[0, 0], [.33, -.12], [.68, -.09], [1, 0]])]
    enter = [position("torso", [0, -500], [[0, [-16, 15]], [.3, [0, -5]], [.6, [2, 2]], [1, [0, 0]]]),
        rotation("head", [[0, -.12], [.38, .035], [1, 0]]),
        rotation("near_forearm", [[0, -.24], [.42, .075], [1, 0]])]
    depart = [rotation("torso", [[0, 0], [.2, -.08], [.55, -.29], [.8, -.25], [1, -.25]]),
        position("torso", [0, -500], [[0, [0, 0]], [.4, [-5, 30]], [.8, [-12, 38]], [1, [-12, 38]]]),
        rotation("head", [[0, 0], [.4, .22], [1, .18]])]
    phase = [rotation("torso", [[0, 0], [.22, -.05], [.5, .09], [.73, -.015], [1, 0]]),
        rotation("near_forearm", [[0, 0], [.26, -.25], [.5, .62], [.77, .14], [1, 0]])]
    return complete(spec, {"action": {"length": 1.72, "tracks": action}, "hit": {"length": 1.36, "tracks": hit},
        "guard": {"length": 1.48, "tracks": guard}, "enter": {"length": 1.40, "tracks": enter},
        "depart": {"length": 1.80, "tracks": depart}, "phase": {"length": 1.60, "tracks": phase}})


def enemy():
    spec = json.loads((SOURCE / "N01/rig.json").read_text(encoding="utf-8"))
    spec.update(version=2, canvas=[1160, 940], ground=[580, 920], ground_offset=5,
                idle_length=6.4, blend_seconds=0.20, contact_fraction=0.40)
    body = next(p for p in spec["parts"] if p["id"] == "body")
    body.update(mesh=True, bone="loop_body", base_bone="root", position=[-200, -780], size=[490, 650], cells=8)
    body.pop("offset", None)
    paper = next(p for p in spec["parts"] if p["id"] == "loose_sheet")
    paper["cells"] = 7
    spec["bones"].append(bone("tab", "loop_body", [110, -290]))
    spec["bones"].append(bone("loop_tab", "tab", [0, 0]))
    tab = next(p for p in spec["parts"] if p["id"] == "tab")
    tab.update(bone="loop_tab", offset=[0, 0])
    spec["idle_tracks"] = [
        wave("loop_body", "rotation", 0, .025, phase=.2),
        wave("loop_body", "position", [0, -300], [6, -9]),
        wave("loop_body", "scale", [1, 1], [.012, -.016]),
        wave("loop_fan", "rotation", 0, -.065, cycles=3, phase=-.8),
        wave("loop_clip", "rotation", 0, .065, cycles=1, phase=-.6),
        wave("loop_paper", "rotation", 0, .10, cycles=3, phase=-1.2),
        wave("loop_tab", "rotation", 0, .12, cycles=4, phase=-.4),
    ]
    spec["contact_shadows"] = [[-70, -2, 90, 20], [205, -2, 70, 18]]
    action = [
        rotation("torso", [[0, 0], [.20, .13], [.3, .16], [.4, -.24], [.53, -.18], [.76, .05], [1, 0]]),
        position("torso", [20, -130], [[0, [0, 0]], [.23, [28, 20]], [.4, [-74, -13]], [.56, [-48, 2]], [.8, [8, 4]], [1, [0, 0]]]),
        scale("torso", [[0, [1, 1]], [.24, [1.06, .88]], [.4, [.94, 1.08]], [.61, [1.025, .97]], [1, [1, 1]]]),
        rotation("pencil", [[0, 0], [.22, .47], [.31, .5], [.42, -.38], [.55, -.22], [.78, .09], [1, 0]]),
        rotation("back_arm", [[0, 0], [.26, -.23], [.48, .24], [.67, -.10], [1, 0]]),
        rotation("clip", [[0, 0], [.28, .10], [.47, -.32], [.64, .15], [.82, -.05], [1, 0]]),
        rotation("tab", [[0, 0], [.32, -.25], [.5, .4], [.69, -.18], [.86, .06], [1, 0]]),
    ]
    hit = [
        rotation("torso", [[0, 0], [.09, .25], [.28, .17], [.5, -.07], [.74, .022], [1, 0]]),
        position("torso", [20, -130], [[0, [0, 0]], [.08, [36, 18]], [.24, [25, 9]], [.53, [-8, -2]], [1, [0, 0]]]),
        scale("torso", [[0, [1, 1]], [.09, [1.10, .86]], [.26, [.98, 1.035]], [.52, [1.02, .99]], [1, [1, 1]]]),
        rotation("pencil", [[0, 0], [.17, -.4], [.35, -.15], [.58, .12], [.80, -.04], [1, 0]]),
        rotation("clip", [[0, 0], [.18, .40], [.4, -.16], [.66, .07], [1, 0]]),
        rotation("back_arm", [[0, 0], [.16, .35], [.38, -.12], [.65, .04], [1, 0]]),
        rotation("tab", [[0, 0], [.23, -.50], [.46, .23], [.7, -.10], [1, 0]]),
    ]
    guard = [rotation("torso", [[0, 0], [.25, .065], [.6, .045], [1, 0]]),
        scale("torso", [[0, [1, 1]], [.28, [1.04, .95]], [.6, [1.03, .97]], [1, [1, 1]]]),
        rotation("pencil", [[0, 0], [.3, -.42], [.64, -.3], [1, 0]]),
        rotation("back_arm", [[0, 0], [.35, -.38], [.7, -.3], [1, 0]])]
    enter = [scale("torso", [[0, [.97, .91]], [.30, [1.025, 1.03]], [.6, [.99, .985]], [1, [1, 1]]]),
        rotation("clip", [[0, -.2], [.4, .12], [.7, -.04], [1, 0]]),
        rotation("pencil", [[0, .24], [.45, -.08], [1, 0]])]
    depart = [position("torso", [20, -130], [[0, [0, 0]], [.18, [15, 10]], [.5, [38, 95]], [.78, [52, 120]], [1, [52, 120]]]),
        rotation("torso", [[0, 0], [.22, -.08], [.58, .55], [.8, .60], [1, .60]]),
        scale("torso", [[0, [1, 1]], [.3, [1.04, .95]], [.65, [1.1, .78]], [1, [1.1, .78]]]),
        rotation("pencil", [[0, 0], [.35, -.4], [.7, .45], [1, .48]]),
        rotation("clip", [[0, 0], [.43, .38], [.7, -.2], [1, -.15]]),
        rotation("back_arm", [[0, 0], [.45, .4], [1, .5]]),
        rotation("tab", [[0, 0], [.4, -.7], [.7, .4], [1, .25]])]
    phase = [rotation("torso", [[0, 0], [.25, .1], [.52, -.17], [.75, .05], [1, 0]]),
        scale("torso", [[0, [1, 1]], [.25, [1.1, .85]], [.52, [.95, 1.12]], [.76, [1.025, .98]], [1, [1, 1]]]),
        rotation("clip", [[0, 0], [.28, .2], [.56, -.44], [.8, .14], [1, 0]]),
        rotation("pencil", [[0, 0], [.32, -.2], [.56, .36], [.8, -.08], [1, 0]])]
    return complete(spec, {"action": {"length": 1.80, "tracks": action}, "hit": {"length": 1.40, "tracks": hit},
        "guard": {"length": 1.48, "tracks": guard}, "enter": {"length": 1.40, "tracks": enter},
        "depart": {"length": 2.00, "tracks": depart}, "phase": {"length": 1.60, "tracks": phase}})


def main():
    for entity, spec in [("P01", hero()), ("N01", enemy())]:
        write(OUT / entity / "rig.json", spec)
        files = sorted(set(p["file"].removeprefix("res://") for p in spec["parts"]))
        write(OUT / entity / "source.json", {"status": "motion_polish_pending_user_visual_review", "version": 2,
            "source_rig": f"assets/art/actor-rig-pilot/{entity}/rig.json", "api_new_images": 0,
            "method": "unchanged reviewed textures; local proportions, weighted limb meshes, foot IK, per-channel motion curves",
            "textures": [{"file": f, "sha256": hashlib.sha256((ROOT/f).read_bytes()).hexdigest()} for f in files],
            "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"]})
        print(f"{entity}: {len(spec['bones'])} bones, {len(spec['parts'])} parts, {len(spec['animations'])} authored actions")


if __name__ == "__main__":
    main()
