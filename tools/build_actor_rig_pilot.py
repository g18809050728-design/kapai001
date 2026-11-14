"""Reproducible chroma extraction and explicit joint layout for the opt-in pilot.

Atlas parts are newly repainted with hidden overlap, not crops of the assembled
masters. Coordinate regions deliberately follow the actual edited sheets: the
provider did not obey an exact 3x3 grid. Originals are never overwritten.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/actor-rig-pilot-20261114"
OUT = ROOT / "assets/art/actor-rig-pilot"
EVIDENCE = ROOT / "artifacts/verification/actor-rig-pilot-20261114"


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def extract(source, region, destination, size):
    im = Image.open(source).convert("RGBA").crop(region)
    rgba = np.array(im)
    rgb = rgba[:, :, :3].astype(float)
    # Chroma is absent from the costumes/paper. Remove even mixed pink fringes;
    # resampling the resulting alpha supplies antialiasing at game scale.
    key = (rgb[:, :, 0] > rgb[:, :, 1] * 1.35 + 25) & (rgb[:, :, 2] > rgb[:, :, 1] * 1.35 + 25)
    rgba[key] = [0, 0, 0, 0]
    im = Image.fromarray(rgba)
    box = im.getbbox()
    if not box:
        raise ValueError(f"Empty part: {destination}")
    im = im.crop(box).resize(size, Image.Resampling.LANCZOS)
    destination.parent.mkdir(parents=True, exist_ok=True)
    im.save(destination)
    return {"source": source.relative_to(ROOT).as_posix(), "region": region, "trim_box": box,
            "size": list(size), "file": destination.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


def build(id_, atlas, layout, bones, parts, idle, poses, canvas, ground, action_bone):
    records = []
    for name, region, size in layout:
        source = RAW / ("hero-torso-v2.png" if id_ == "P01" and name == "torso" else atlas)
        records.append(extract(source, region, OUT / id_ / f"{name}.png", size))
    for part in parts:
        part["file"] = f"res://assets/art/actor-rig-pilot/{id_}/{part['id']}.png"
    spec = {"version": 1, "definition_id": id_, "canvas": canvas, "ground": ground,
            "action_bone": action_bone, "bones": bones, "parts": parts,
            "idle": idle, "poses": poses}
    write_json(OUT / id_ / "rig.json", spec)
    write_json(OUT / id_ / "source.json", {"status": "pilot_only_pending_user_art_acceptance",
        "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
        "provider": "configured jiji.cc image API", "model": "gpt-image-2.5-sunburst",
        "method": "reference-image edit: separated complete parts, local magenta chroma removal and recorded joint fitting",
        "alpha_method": "R > 1.35G+25 and B > 1.35G+25 -> transparent, crop alpha bounds, Lanczos RGBA resize",
        "master": "hero-master-v1.png" if id_ == "P01" else "enemy-master-v1.png",
        "used_parts": [p["id"] for p in parts], "parts": records})
    # An assembled rest view is a resource review, not an engine screenshot.
    preview = Image.new("RGBA", (1500, 1500), "#26383f")
    points = {}
    for bone in bones:
        parent = points.get(bone["parent"], (750, 1390))
        points[bone["id"]] = (parent[0] + bone["position"][0], parent[1] + bone["position"][1])
    for part in sorted(parts, key=lambda p: p["z"]):
        pic = Image.open(ROOT / part["file"].removeprefix("res://")).convert("RGBA")
        origin = part["position"] if part.get("mesh") else [points[part["bone"]][i] - [750,1390][i] + part["offset"][i] for i in range(2)]
        preview.alpha_composite(pic, (round(750 + origin[0]), round(1390 + origin[1])))
    preview.convert("RGB").save(EVIDENCE / f"{id_}-rest-resource-review.png")
    return records


def bone(id_, parent, x, y):
    return {"id": id_, "parent": parent, "position": [x,y], "length": 70}


def sprite(id_, bone_, x, y, z):
    return {"id": id_, "bone": bone_, "offset": [x,y], "z": z}


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    hero_layout = [
        ("head", (70, 0, 465, 356), (230, 265)),
        ("torso", (0, 0, 1024, 1024), (350, 460)),
        ("near_upper", (1086, 0, 1434, 355), (160, 265)),
        ("near_forearm", (80, 397, 468, 646), (300, 170)),
        ("far_upper", (656, 398, 906, 665), (125, 245)),
        ("laptop_forearm", (1055, 388, 1505, 663), (350, 240)),
        ("rear_leg", (110, 659, 414, 1024), (190, 650)),
        ("front_leg", (690, 666, 911, 1024), (165, 650)),
        ("hem", (1110, 714, 1443, 976), (340, 235)),
    ]
    hero_bones = [bone("root","",0,0),bone("torso","root",0,-640),
        bone("loop_chest","torso",0,-225),bone("head","loop_chest",20,-205),
        bone("loop_head","head",0,0),bone("near_upper","loop_chest",-135,-140),
        bone("near_forearm","near_upper",-78,216),bone("action_tip","near_forearm",220,-65),
        bone("far_upper","loop_chest",120,-125),bone("far_forearm","far_upper",30,210),
        bone("rear_leg","root",-40,-630),bone("front_leg","root",65,-630),
        bone("loop_cloth","torso",0,-60)]
    hero_parts = [sprite("rear_leg","rear_leg",-150,-20,-3),sprite("front_leg","front_leg",-46,-20,-2),
        sprite("far_upper","far_upper",-38,-18,-1),
        {"id":"torso","mesh":True,"bone":"loop_chest","base_bone":"loop_cloth","position":[-175,-1070],"size":[350,460],"z":0},
        sprite("head","loop_head",-115,-243,2),sprite("near_upper","near_upper",-118,-21,3),
        sprite("near_forearm","near_forearm",-39,-122,4),sprite("laptop_forearm","far_forearm",-35,-197,5)]
    hero_poses = {
        "action":{"torso":.06,"head":-.12,"near_upper":-.32,"near_forearm":.7,"far_forearm":-.035},
        "hit":{"torso":-.12,"head":.18,"near_upper":.25,"near_forearm":-.16,"far_upper":.08},
        "guard":{"torso":-.025,"near_upper":-.1,"near_forearm":-.42,"head":-.09},
        "enter":{"torso":-.045,"head":-.08,"far_upper":.07,"near_forearm":.12},
        "depart":{"torso":-.2,"head":.12,"near_upper":.2},
        "phase":{"torso":.055,"head":-.1,"near_forearm":.25}}
    records = build("P01", "hero-parts-v1.png",hero_layout,hero_bones,hero_parts,
        {"loop_chest":.008,"loop_head":-.016,"loop_cloth":.028},hero_poses,[1000,1370],[500,1340],"action_tip")
    enemy_layout = [
        ("body", (58, 12, 510, 418), (490,650)),
        ("fan", (570, 15, 1035, 408), (500,440)),
        ("clip", (1134, 12, 1492, 391), (240,250)),
        ("pencil", (15, 454, 553, 695), (480,175)),
        ("back_arm", (681, 410, 943, 711), (185,250)),
        ("near_foot", (1068, 443, 1463, 680), (270,180)),
        ("far_foot", (72, 744, 462, 991), (210,175)),
        ("tab", (670, 781, 877, 963), (95,100)),
        ("loose_sheet", (1070, 719, 1472, 1008), (340,300)),
    ]
    enemy_bones = [bone("root","",0,0),bone("near_foot","root",-65,-92),bone("far_foot","root",190,-95),
        bone("torso","root",20,-130),bone("loop_body","torso",0,-300),
        bone("loop_fan","loop_body",140,-40),bone("clip","loop_body",10,-330),
        bone("loop_clip","clip",0,0),bone("pencil","loop_body",-155,-50),
        bone("action_tip","pencil",-430,-45),bone("back_arm","loop_body",230,-35),
        bone("loop_paper","torso",150,-120)]
    enemy_parts = [sprite("far_foot","far_foot",-110,-82,-4),sprite("near_foot","near_foot",-150,-92,-3),
        sprite("fan","loop_fan",-190,-360,-2),sprite("back_arm","back_arm",-15,-30,-1),
        {"id":"loose_sheet","mesh":True,"bone":"torso","base_bone":"loop_paper","position":[140,-700],"size":[340,300],"z":-1},
        sprite("body","loop_body",-220,-350,0),sprite("clip","loop_clip",-90,-205,2),
        sprite("pencil","pencil",-450,-85,3),sprite("tab","loop_body",110,-290,3)]
    enemy_poses = {
        "action":{"torso":-.055,"pencil":.32,"back_arm":-.18,"clip":-.12},
        "hit":{"torso":.11,"pencil":-.24,"back_arm":.19,"clip":.2},
        "guard":{"torso":.035,"pencil":-.2,"back_arm":-.3},
        "enter":{"torso":-.035,"pencil":.12,"clip":-.08},
        "depart":{"torso":.32,"pencil":-.3,"back_arm":.35,"clip":.25},
        "phase":{"torso":-.08,"pencil":.25,"clip":-.3}}
    records += build("N01", "enemy-parts-v1.png",enemy_layout,enemy_bones,enemy_parts,
        {"loop_body":.012,"loop_fan":-.03,"loop_clip":.024,"loop_paper":.045},enemy_poses,[1300,1020],[650,1000],"action_tip")
    write_json(EVIDENCE / "extraction.json",{"parts":records,"count":len(records),"art_acceptance":"not_claimed"})
    print(f"Extracted {len(records)} real-alpha parts. Rest previews require visual review.")


if __name__ == "__main__":
    main()
