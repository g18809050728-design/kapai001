"""Audit the selected Lin V12 assets and retained Godot verification evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

from PIL import Image
import verify_lin_polish

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-lin-polish-20261115"
ART = ROOT / "output/imagegen/actor-lin-polish-20261115"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    checks = []

    def check(ok, message):
        checks.append({"ok": bool(ok), "message": message})

    baseline = load(EV / "baseline.json")
    with zipfile.ZipFile(EV / "before.zip") as archive:
        original = {name: archive.read(name) for name in archive.namelist()}
    for name, expected in baseline["before_files"].items():
        check(hashlib.sha256(original[name]).hexdigest() == expected, "before snapshot: " + name)
    exception = baseline["authorized_runtime_exception"]
    with zipfile.ZipFile(EV / "texture-support-before.zip") as archive:
        check(hashlib.sha256(archive.read(exception["file"])).hexdigest() == exception["sha256"],
              "shared renderer snapshot")
    protected = {k: v for k, v in baseline["protected"].items() if k != exception["file"]}
    differences = [name for name, expected in protected.items()
                   if not (ROOT / name).is_file() or digest(ROOT / name) != expected]
    check(not differences, "protected files unchanged")

    # Only the optional high-resolution sprite dimension support is authorized here.
    with zipfile.ZipFile(EV / "texture-support-before.zip") as archive:
        old_runtime = archive.read(exception["file"])
    new_runtime = (ROOT / exception["file"]).read_bytes()
    addition = (b'\t\t\tif item.has("display_size"):\n'
                b'\t\t\t\tsprite.scale = _vector(item.display_size) / sprite.texture.get_size()\n')
    check(new_runtime.replace(b"\r\n", b"\n").replace(addition, b"") ==
          old_runtime.replace(b"\r\n", b"\n"), "shared renderer has only optional display_size addition")

    # Updates are inserted above historical records, retaining their original bytes.
    for name in ("agent.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md"):
        old_body = original[name].split(b"\n", 2)[2]
        check(old_body in (ROOT / name).read_bytes(), "historical document bytes: " + name)
    old_plan = original["实施计划与验收基线.md"]
    new_plan = (ROOT / "实施计划与验收基线.md").read_bytes()
    start = old_plan.index("2026-11-05：".encode("utf-8"))
    split = old_plan.index(b"\n## 1.")
    check(old_plan[start:split] in new_plan and old_plan[split:] in new_plan,
          "historical plan sections retained")

    manifest = load(ART / "asset-manifest.json")
    check(len(manifest["entries"]) == manifest["successful_images"] == 13, "13 successful API images")
    check(manifest["cumulative_before"] == 38 and manifest["cumulative_after"] == 51
          and manifest["cumulative_after"] <= manifest["authorized_limit"] == 200, "API cumulative count")
    for entry in manifest["entries"]:
        ok = digest(ROOT / entry["prompt_file"]) == entry["prompt_sha256"]
        ok = ok and digest(ROOT / entry["output"]) == entry["sha256"] and entry["exit_code"] == 0
        with Image.open(ROOT / entry["output"]) as im:
            im.load()
            ok = ok and list(im.size) == entry["actual_size"]
        for item in entry["inputs"]:
            ok = ok and digest(ROOT / item["file"]) == item["sha256"]
        check(ok, "API provenance: " + entry["asset_id"])
    for name, expected in (("raw-audit.json", 13), ("runtime-audit.json", 18)):
        audit = load(EV / name)
        check(audit["status"] == "passed" and audit["total"] == expected
              and audit["failed"] == 0 and audit["duplicates"] == 0, name)
        check(all(digest(Path(x["path"])) == x["sha256"] for x in audit["images"]), name + " still current")
    extraction = load(EV / "extraction.json")
    check(len(extraction["outputs"]) == 18, "18 extracted runtime textures")
    check(all(digest(ROOT / x["file"]) == x["sha256"] and
              digest(ROOT / x["source"]) == x["source_sha256"] for x in extraction["outputs"]),
          "extraction and source hashes")

    rig = load(ROOT / "assets/art/actor-lin-polish/P01/rig.json")
    check(rig["version"] == 12 and len(rig["bones"]) == 27 and len(rig["parts"]) == 14
          and len(rig["animations"]) == 6, "selected V12 rig structure")
    versions = {"P01": 12, "P02": 8, "P03": 10, "P04": 11}
    source = load(ROOT / "assets/art/characters/source.json")
    old_source = json.loads(original["assets/art/characters/source.json"])
    check({x["character"]: x["version"] for x in source["characters"]} == versions, "static selected versions")
    check(source["characters"][1:] == old_source["characters"][1:], "other static source records preserved")
    static_images = []
    for name in ("neutral.png", "portrait.png"):
        p = ROOT / "assets/art/characters/P01" / name
        with Image.open(p) as im:
            im.load()
            alpha = im.getchannel("A").getextrema() if "A" in im.getbands() else None
            check(alpha == (0, 255), "transparent P01 static image: " + name)
            static_images.append({"file": p.relative_to(ROOT).as_posix(), "size": list(im.size),
                                  "sha256": digest(p), "alpha_range": alpha})

    game = load(EV / "game-final-01/report.json")
    geometry = load(EV / "game-final-01/lin-geometry.json")
    check(not game["failures"] and len(game["checks"]) == 558
          and all(x["ok"] for x in game["checks"]), "558 real game checks")
    check(game["versions"] == versions and not game["pilot_enabled"], "normal production character routing")
    check(len(game["commands"]) == 22 and all(x["accepted"] and x["equal"]
          and x["actual_hash"] == x["expected_hash"] for x in game["commands"]), "22 published command A/B results")
    captures = [EV / "game-final-01" / (x["name"] + ".png") for x in game["screens"]]
    captures += [EV / "game-final-01" / x["file"] for x in game["frames"]]
    for p in captures:
        with Image.open(p) as im:
            im.load()
    check(len(game["screens"]) == 61 and len(game["frames"]) == 294, "61 window captures and 294 continuous frames decode")
    check(len(geometry["samples"]) == 606 and geometry["maximum_contact_error"] == 0
          and geometry["maximum_foot_error"] < 0.01, "606 motion constraints")
    legacy_pairs = [(variant, pose) for variant in ("v5", "shen") for pose in ("neutral", "action")]
    check(all(digest(EV / "probe-03" / f"{v}-{p}.png") ==
              digest(EV / "probe-final" / f"{v}-{p}.png") for v, p in legacy_pairs),
          "historical Lin and Shen fixed-pose captures are byte identical")

    current = verify_lin_polish.inputs()
    runs = []
    derivatives = {"assets/art/characters/P01/neutral.png", "assets/art/characters/P01/portrait.png",
                   "assets/art/characters/source.json"}
    for name in ("probe-final", "static-art-final", "static-import-final", "game-final-01",
                 "full-rules-final", "full-ui-final", "main-smoke-final"):
        record = load(EV / (name + ".run.json"))
        check(record["exit_code"] == record["engine_errors"] == 0
              and not record["unexpected_changes"], "Godot recorded run: " + name)
        excluded = derivatives if name == "probe-final" else set()
        stale = [k for k in set(record["inputs_after"]) | set(current)
                 if k not in excluded and record["inputs_after"].get(k) != current.get(k)]
        check(not stale, "recorded final inputs still current: " + name + (str(stale) if stale else ""))
        runs.append({k: v for k, v in record.items() if not k.startswith("inputs")})
    saves = load(EV / "real-save-preservation.json")
    check(saves["exit_code"] == 0 and saves["unchanged"] and saves["before"] == saves["after"]
          and len(saves["before"]) == 10, "10 real save files preserved during bootstrap")
    failures = [x["message"] for x in checks if not x["ok"]]
    summary = {
        "created_utc": datetime.now(timezone.utc).isoformat(), "status": "failed" if failures else "passed",
        "versions": versions, "snapshots": 9, "protected_files": len(protected), "protected_differences": differences,
        "api_successful_this_batch": 13, "api_cumulative": 51, "api_limit": 200,
        "game_checks": len(game["checks"]), "commands": len(game["commands"]),
        "screens": len(game["screens"]), "continuous_frames": len(game["frames"]),
        "motion_samples": len(geometry["samples"]), "maximum_contact_error": geometry["maximum_contact_error"],
        "maximum_foot_error": geometry["maximum_foot_error"], "static_images": static_images,
        "runs": runs, "checks": checks, "failures": failures,
        "visual_review": {"performed_by": "AI; separate from automated checks and user final acceptance",
            "viewed": ["review/face-before-after.jpg", "review/style-comparison.jpg", "review/fullbody.jpg",
                       "review/garment-before-after.jpg", "review/poses.jpg", "review/real-command-strip.jpg",
                       "game-final-01/P01-setup-1280-100.png", "game-final-01/P01-battle-1280-100.png",
                       "game-final-01/P01-battle-960-150.png", "game-final-01/P03-battle-1280-100.png",
                       "raw-contact.jpg", "runtime-contact.jpg"],
            "finding": "Clearer face, glasses, hair, collar and hands; removed old dark neck band; same illustrated style as Shen V10. Full-body proportions and ordinary action contacts remain stable.",
            "limits": "2D local drawing changes can remain visible in slow motion; user art acceptance and full G0/G6/G8 exits remain pending."},
    }
    (EV / "verification-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k not in ("checks", "runs", "visual_review", "static_images")}, ensure_ascii=False))
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
