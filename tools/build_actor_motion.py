"""Author P04 V11 motion data while preserving all selected artwork and rigs."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art/actor-motion"
EV = ROOT / "artifacts/verification/actor-motion-20261115"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    ART.mkdir(parents=True, exist_ok=True)
    for role, family in (("P01", "actor-anatomy"), ("N01", "actor-anatomy"),
                         ("P02", "actor-proportions"), ("P03", "actor-rebuild")):
        target = ART / role / "rig.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / "assets/art" / family / role / "rig.json").read_bytes())
    source = ROOT / "assets/art/actor-proportions/P04/rig.json"
    rig = copy.deepcopy(json.loads(source.read_text(encoding="utf-8")))
    rig["version"] = 11
    rest = {b["id"]: b["position"] for b in rig["bones"]}

    def track(pose, bone, keys, prop="rotation"):
        tracks = rig["animations"][pose]["tracks"]
        tracks[:] = [t for t in tracks if (t["bone"], t["property"]) != (bone, prop)]
        tracks.append({"bone": bone, "property": prop, "keys": keys})

    def body(pose, keys):
        track(pose, "torso", [[f, [round(rest["torso"][0] + x, 6),
                                  round(rest["torso"][1] + y, 6)]] for f, x, y in keys], "position")

    # Keep the sleeve cap attached to the shoulder/chest. The old two sleeve
    # bones had the same rigid transform, so the entire cap rotated out of the shirt.
    for part in rig["parts"]:
        if part["id"] == "near_upper":
            part["bone"] = "loop_chest"
            part["base_bone"] = "near_upper"
            part["weight_range"] = [0.02, 0.48]
            part["cells"] = 18
        elif part["id"] == "far_upper":
            part["bone"] = "loop_chest"
            part["base_bone"] = "far_upper"
            part["weight_range"] = [0.02, 0.48]
            part["cells"] = 18

    body("action", [(0, 0, 0), (.13, -1.6, .8), (.23, -2, 1.2),
                    (.34, 9, 2.5), (.40, 16.4, 4), (.49, 16.4, 4),
                    (.63, 11, 2.8), (.82, 2.5, .9), (1, 0, 0)])
    for bone, keys in {
        "torso": [[0, 0], [.15, -.007], [.25, -.009], [.38, .024], [.49, .025], [.68, .012], [.86, .002], [1, 0]],
        "near_upper": [[0, 0], [.14, .025], [.24, .02], [.34, -.17], [.40, -.26], [.52, -.25], [.68, -.16], [.84, -.03], [1, 0]],
        "near_forearm": [[0, 0], [.12, .015], [.23, .10], [.34, .69], [.42, 1.00], [.53, .98], [.69, .60], [.85, .12], [1, 0]],
        "head": [[0, 0], [.18, .012], [.36, -.025], [.53, -.03], [.75, -.008], [1, 0]],
        "far_upper": [[0, 0], [.23, -.005], [.40, .015], [.52, .015], [.75, .004], [1, 0]],
        "far_forearm": [[0, 0], [.23, .014], [.40, -.04], [.52, -.04], [.75, -.008], [1, 0]],
        "held_wrist": [[0, 0], [1, 0]],
        "held_laptop": [[0, 0], [1, 0]],
    }.items():
        track("action", bone, keys)

    # A brief arm articulation replaces the old whole-body crouch/recoil.
    body("hit", [(0, 0, 0), (.10, -4.5, 1.6), (.24, -3.0, 1.0), (.50, -.5, .4), (.76, 0, 0), (1, 0, 0)])
    for bone, keys in {
        "torso": [[0, 0], [.09, -.032], [.25, -.025], [.48, .006], [.72, 0], [1, 0]],
        "head": [[0, 0], [.16, .052], [.34, .034], [.61, -.01], [.82, 0], [1, 0]],
        "near_upper": [[0, 0], [.12, .045], [.31, .032], [.61, -.008], [1, 0]],
        "near_forearm": [[0, 0], [.18, .15], [.35, .10], [.66, .015], [1, 0]],
        "far_upper": [[0, 0], [.12, -.008], [.33, -.005], [1, 0]],
        "far_forearm": [[0, 0], [.15, .035], [.36, .022], [.68, -.004], [1, 0]],
        "held_wrist": [[0, 0], [1, 0]],
        "held_laptop": [[0, 0], [1, 0]],
    }.items():
        track("hit", bone, keys)

    body("guard", [(0, 0, 0), (.22, -2.0, 1.2), (.58, -2.0, 1.2), (.82, -.5, .3), (1, 0, 0)])
    for bone, peak in {"torso": -.012, "near_upper": -.08, "near_forearm": .24,
                       "head": -.016, "far_upper": -.012, "far_forearm": .04,
                       "held_wrist": 0, "held_laptop": 0}.items():
        track("guard", bone, [[0, 0], [.27, peak], [.60, peak], [.83, peak * .25], [1, 0]])

    body("phase", [(0, 0, 0), (.23, -1, .5), (.45, 4, 1.2), (.67, 3, .9), (1, 0, 0)])
    for bone, peak in {"torso": .012, "near_upper": -.07, "near_forearm": .24,
                       "head": -.015, "far_upper": .004, "far_forearm": -.016,
                       "held_wrist": 0, "held_laptop": 0}.items():
        track("phase", bone, [[0, 0], [.22, peak * .15], [.46, peak], [.67, peak * .7], [.86, peak * .1], [1, 0]])

    body("enter", [(0, -3.2, 2.2), (.28, -1.0, .8), (.58, 0, 0), (1, 0, 0)])
    for bone in ["torso", "head", "near_upper", "near_forearm", "far_upper", "far_forearm", "held_wrist", "held_laptop"]:
        peak = {"head": -.02, "near_forearm": .08, "near_upper": -.02}.get(bone, 0)
        track("enter", bone, [[0, peak], [.40, peak * .2], [.72, 0], [1, 0]])

    body("depart", [(0, 0, 0), (.25, -1.5, 1.5), (.60, -3, 3.0), (1, -3, 3.0)])
    for bone, peak in {"torso": -.038, "head": .045, "near_upper": .025, "near_forearm": .10,
                       "far_upper": -.006, "far_forearm": .038, "held_wrist": 0, "held_laptop": 0}.items():
        track("depart", bone, [[0, 0], [.24, peak * .25], [.62, peak], [1, peak]])

    # Supporting wrist yields a little to the board's inertia, then recovers.
    # A completely frozen wrist made the supporting side read as a rigid prop.
    track("action", "held_wrist", [[0, 0], [.20, .012], [.43, -.032], [.60, -.022], [.85, .006], [1, 0]])
    track("hit", "held_wrist", [[0, 0], [.15, .030], [.35, .018], [.65, -.006], [1, 0]])
    track("guard", "held_wrist", [[0, 0], [.27, .018], [.60, .018], [.85, .004], [1, 0]])
    track("phase", "held_wrist", [[0, 0], [.46, -.008], [.67, -.006], [1, 0]])
    track("depart", "held_wrist", [[0, 0], [.28, .008], [.65, .025], [1, .025]])

    # Arm drawing changes happen while the elbow begins its forward arc;
    # the old long opacity crossfade created two simultaneous pens/hands.
    for drawing in rig["drawings"]:
        if drawing["part"] == "near_forearm":
            drawing["poses"]["action"] = [[0, [1, 0, 0, 0]], [.245, [1, 0, 0, 0]],
                [.270, [0, 1, 0, 0]], [.755, [0, 1, 0, 0]],
                [.780, [1, 0, 0, 0]], [1, [1, 0, 0, 0]]]
    for track_data in rig.get("idle_tracks", []):
        factor = {"loop_near": .35, "loop_far": .4, "loop_cloth": .35,
                  "loop_wrist": .3, "loop_laptop": .25, "loop_head": .6}.get(track_data["bone"], 1)
        if track_data["property"] == "rotation":
            track_data["keys"] = [[f, v * factor] for f, v in track_data["keys"]]
    rig["motion_revision"] = {
        "base_version": 8, "scope": "P04 shoulder elbow support and prop coordination",
        "artwork_unchanged": True, "rest_bones_unchanged": True,
        "shoulder_cap_chest_weighted": True, "near_shoulder_peak_radians": -.26,
        "near_elbow_peak_radians": 1.0, "pelvis_peak_offset": [16.4, 4.0],
        "validation": "2D authored joint/support constraints, not physical simulation",
    }
    target = ART / "P04/rig.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(rig, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    provenance = {"base_rig": {"path": source.relative_to(ROOT).as_posix(), "sha256": sha(source)},
                  "version": 11, "requirements": ["UIR-011", "UIR-013", "UIR-051", "UIR-052", "UIR-054", "UIR-057", "UIR-059"],
                  "new_api_images": 0, "api_successful_cumulative": 38,
                  "textures": [{"path": f.removeprefix("res://"), "sha256": sha(ROOT / f.removeprefix("res://"))}
                               for f in sorted({p["file"] for p in rig["parts"]} |
                                               {v["file"] for d in rig["drawings"] for v in d["variants"]})]}
    (target.parent / "source.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"version": 11, "selected_rigs_preserved": 4, "new_api_images": 0, "resource_root": str(ART)}, ensure_ascii=False))


if __name__ == "__main__":
    build()
