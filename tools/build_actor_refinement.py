"""Version 3: traced local cutouts, joint weights, held prop and expression.

Previous resource directories are read only. Only the missing environment is
API generated; all actor pieces below derive from the original reviewed PNGs.
"""
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import build_actor_motion_polish as prior

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/actor-rig-refinement"
SOURCE = ROOT / "assets/art/actor-rig-pilot"


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def resource(entity, name):
    return f"res://assets/art/actor-rig-refinement/{entity}/{name}.png"


def cutout(image, mask, destination):
    result = image.copy()
    alpha = np.minimum(np.asarray(image.getchannel("A")), np.asarray(mask))
    result.putalpha(Image.fromarray(alpha))
    result.save(destination)
    return result


def hero_art():
    dest = OUT / "P01"
    dest.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE / "P01/laptop_forearm.png").convert("RGBA")
    pixels = np.asarray(source)
    yy, xx = np.mgrid[:source.height, :source.width]
    skin = (pixels[:, :, 0].astype(float) > pixels[:, :, 1] * 1.12) & (pixels[:, :, 2] < pixels[:, :, 0] * .82)
    skin &= (xx > 152) & (yy > 138) & (yy < 229)
    # The prop's edge is traced from the source. Reconstruct only the small
    # regions originally hidden by the fingers; the palm remains an overlay.
    prop_mask = Image.new("L", source.size)
    ImageDraw.Draw(prop_mask).polygon([(34, 157), (149, 160), (203, 0), (350, 16), (282, 176), (207, 180), (147, 176), (35, 174)], fill=255)
    prop = source.copy()
    prop_pixels = np.array(prop)
    hidden = skin & (np.asarray(prop_mask) > 0)
    for y, x in zip(*np.nonzero(hidden)):
        prop_pixels[y, x, :3] = pixels[134, x, :3] if y < 173 else [53, 49, 43]
        prop_pixels[y, x, 3] = 255
    prop = Image.fromarray(prop_pixels)
    cutout(prop, prop_mask, dest / "laptop.png")
    forearm_mask = Image.new("L", source.size)
    ImageDraw.Draw(forearm_mask).polygon([(0, 101), (103, 101), (103, 156), (151, 177), (179, 184), (179, 224), (0, 240)], fill=255)
    forearm_mask = Image.fromarray(np.where(np.asarray(prop_mask) > 0, 0, np.asarray(forearm_mask)).astype("uint8"))
    cutout(source, forearm_mask, dest / "held_forearm.png")
    # Preserve anti-aliased skin edges with an explicit traced silhouette.
    boundary = Image.new("L", source.size)
    ImageDraw.Draw(boundary).polygon([(163, 182), (187, 175), (190, 157), (201, 147), (210, 150), (208, 176), (215, 168), (218, 151), (229, 144), (237, 148), (240, 170), (246, 150), (256, 151), (260, 169), (268, 181), (254, 192), (244, 202), (226, 213), (194, 220), (175, 227), (163, 223)], fill=255)
    # This keeps original edge pixels rather than growing a skin-colored fringe.
    cutout(source, boundary, dest / "held_hand.png")
    # A small local eye replacement keeps hair, face contour and glasses intact.
    head = Image.open(SOURCE / "P01/head.png").convert("RGBA")
    closed = head.copy()
    patch = Image.new("RGBA", head.size)
    pd = ImageDraw.Draw(patch)
    for y in range(118, 135):
        color = head.getpixel((149, 139))
        pd.line([(143, y), (169, y)], fill=color)
    eye_mask = Image.new("L", head.size)
    ImageDraw.Draw(eye_mask).polygon([(144, 119), (162, 119), (169, 123), (166, 132), (150, 133), (144, 129)], fill=255)
    eye_mask = eye_mask.filter(ImageFilter.GaussianBlur(.7))
    closed.paste(patch, (0, 0), eye_mask)
    draw = ImageDraw.Draw(closed)
    points = []
    for i in range(25):
        t = i / 24
        points.append((144 + 24*t, 123 + 4*math.sin(t*math.pi)))
    draw.line(points, fill=(49, 37, 28, 255), width=2)
    closed.save(dest / "head_blink.png")
    return {"laptop.png": "traced prop; reconstruct hidden pixels from adjacent original prop rows",
            "held_forearm.png": "original sleeve/forearm; 16 px overlap under the palm",
            "held_hand.png": "traced original palm/fingers overlay", "head_blink.png": "local iris replacement with skin sampled below eye and closed eyelid; hair/face/glasses unchanged"}


def environment():
    raw = ROOT / "output/imagegen/actor-rig-refinement-20261115/classroom-stage-v2.png"
    if not raw.exists():
        raise SystemExit("Missing reviewed environment source")
    image = Image.open(raw).convert("RGB")
    stage = Image.new("RGB", (1280, 800))
    # The API output places the skirting at y=590 despite the requested 42%.
    # Recompose two continuous painted bands at the skirting to put real floor
    # beneath the unchanged y=470 actor anchors. No new drawing or platform.
    split = 590
    stage.paste(image.crop((0, 0, image.width, split)).resize((1280, 342), Image.Resampling.LANCZOS))
    stage.paste(image.crop((0, split, image.width, image.height)).resize((1280, 458), Image.Resampling.LANCZOS), (0, 342))
    OUT.mkdir(parents=True, exist_ok=True)
    stage.save(OUT / "classroom-stage.png")
    save_json(OUT / "environment-source.json", {"source": raw.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
        "edit_input": "assets/art/g6-v1/backgrounds/BG_classroom_v1.png",
        "method": "wall [0,590) resized to [0,342); floor [590,1024) resized to [342,800), Lanczos; 1280x800",
        "floor_start": 342, "actor_ground_band": [465, 485], "api_successful_outputs_this_batch": 1,
        "status": "reviewed_for_isolated_stage_pending_user_visual_review"})


def add_tracks(spec, name, curves):
    spec["animations"][name]["tracks"].extend(curves)


def hero():
    spec = prior.hero()
    spec["version"] = 3
    spec["bones"][2]["position"] = [0, -508]
    # Maintain reachable knees while relaxing the former permanent crouch.
    for action in spec["animations"].values():
        for curve in action["tracks"]:
            if curve["bone"] == "torso" and curve["property"] == "position":
                # Prior rest tracks share their value list across keys/actions.
                # Replace values, rather than cumulatively mutating that list.
                curve["keys"] = [[t, [v[0], v[1] - 8]] for t, v in curve["keys"]]
    spec["bones"].extend([
        prior.bone("near_elbow", "near_upper", [-68, 205]),
        prior.bone("far_elbow", "far_upper", [30, 210]),
        prior.bone("held_wrist", "far_forearm", [135, 7]),
        prior.bone("loop_wrist", "held_wrist", [0, 0]),
        prior.bone("held_laptop", "loop_wrist", [54, -31]),
        prior.bone("loop_laptop", "held_laptop", [0, 0]),
    ])
    for item in spec["parts"]:
        if item["id"] == "torso":
            item["position"][1] -= 8
        elif item["id"] == "near_upper":
            item.update(mesh=True, bone="loop_near", base_bone="near_elbow", position=[-253, -884], size=[160, 265], cells=10,
                        weight_axis=[[-205, -862], [-205, -662]], weight_range=[.04, .96])
            item.pop("offset", None)
        elif item["id"] == "far_upper":
            item.update(mesh=True, bone="loop_far", base_bone="far_elbow", position=[82, -876], size=[125, 245], cells=9,
                        weight_axis=[[140, -864], [140, -656]], weight_range=[.06, .96])
            item.pop("offset", None)
        elif item["id"] in ["front_leg", "rear_leg"]:
            item["position"][1] -= 8
            item["size"][1] += 8
    spec["parts"] = [p for p in spec["parts"] if p["id"] != "laptop_forearm"]
    spec["parts"].extend([
        {"id": "held_forearm", "bone": "far_forearm", "offset": [-35, -197], "z": 5, "file": resource("P01", "held_forearm")},
        {"id": "held_laptop", "bone": "loop_laptop", "offset": [-224, -173], "z": 6, "file": resource("P01", "laptop")},
        {"id": "held_hand", "bone": "loop_wrist", "offset": [-170, -204], "z": 7, "file": resource("P01", "held_hand")},
    ])
    spec["expression"] = {"part": "head", "blink": resource("P01", "head_blink"),
                          "intervals": [[1.12, 1.23], [2.91, 3.03], [5.72, 5.84]]}
    spec["held_contact"] = {"hand": "loop_wrist", "prop": "loop_laptop", "point": [54, -31]}
    spec["idle_tracks"].extend([
        prior.wave("loop_wrist", "rotation", 0, -.022, cycles=2, phase=-1.3),
        prior.wave("loop_laptop", "rotation", 0, .011, cycles=2, phase=-2.1),
    ])
    add_tracks(spec, "action", [
        prior.rotation("held_wrist", [[0, 0], [.22, .025], [.42, -.07], [.58, -.04], [.79, .013], [1, 0]]),
        prior.rotation("held_laptop", [[0, 0], [.29, .009], [.47, -.022], [.65, .013], [.84, -.004], [1, 0]]),
    ])
    add_tracks(spec, "hit", [
        prior.rotation("held_wrist", [[0, 0], [.15, -.12], [.35, .055], [.62, -.018], [1, 0]]),
        prior.rotation("held_laptop", [[0, 0], [.21, .045], [.43, -.019], [.68, .007], [1, 0]]),
    ])
    add_tracks(spec, "guard", [prior.rotation("held_wrist", [[0, 0], [.31, -.045], [.68, -.025], [1, 0]])])
    add_tracks(spec, "depart", [prior.rotation("held_wrist", [[0, 0], [.39, .07], [1, .10]])])
    # Gentler shoulder travel is matched by the forearm's deliberate reach.
    for curve in spec["animations"]["action"]["tracks"]:
        if curve["bone"] == "near_upper" and curve["property"] == "rotation":
            for key in curve["keys"]:
                key[1] *= .83
        if curve["bone"] == "near_forearm" and curve["property"] == "rotation":
            for key in curve["keys"]:
                key[1] *= .84
    spec["contact_shadows"] = [[-118, 8, 69, 14], [95, 8, 64, 13]]
    spec["cast_shadows"] = [[-65, 20, 122, 23], [147, 20, 116, 21]]
    return prior.complete(spec, spec["animations"])


def enemy():
    spec = prior.enemy()
    spec["version"] = 3
    # Fan tips flex while its base remains attached to the paper body.
    spec["bones"].append(prior.bone("loop_fan_tip", "loop_fan", [80, -230]))
    fan = next(p for p in spec["parts"] if p["id"] == "fan")
    fan.update(mesh=True, bone="loop_fan_tip", base_bone="loop_fan", position=[-30, -830], size=[500, 440], cells=10,
               weight_axis=[[230, -810], [230, -410]], weight_range=[.08, .85])
    fan.pop("offset", None)
    spec["idle_tracks"].extend([prior.wave("loop_fan_tip", "rotation", 0, .035, cycles=3, phase=-1.5)])
    spec["contact_shadows"] = [[-70, -2, 100, 20], [205, -2, 82, 18]]
    spec["cast_shadows"] = [[0, 14, 155, 30], [266, 14, 128, 26]]
    return spec


def main():
    methods = hero_art()
    environment()
    for entity, spec in [("P01", hero()), ("N01", enemy())]:
        save_json(OUT / entity / "rig.json", spec)
        files = sorted(set(p["file"].removeprefix("res://") for p in spec["parts"]))
        if "expression" in spec:
            files.append(spec["expression"]["blink"].removeprefix("res://"))
        save_json(OUT / entity / "source.json", {
            "version": 3, "status": "refinement_pending_user_visual_review", "api_actor_images": 0,
            "source_rig": f"assets/art/actor-rig-polish/{entity}/rig.json", "local_processing": methods if entity == "P01" else {},
            "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
            "textures": [{"file": p, "sha256": hashlib.sha256((ROOT / p).read_bytes()).hexdigest()} for p in files],
        })
        print(f"{entity}: {len(spec['bones'])} bones / {len(spec['parts'])} parts / {sum(bool(p.get('mesh')) for p in spec['parts'])} meshes")


if __name__ == "__main__":
    main()
