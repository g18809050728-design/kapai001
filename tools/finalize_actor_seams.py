"""Audit v6 local art, unchanged anatomy and the actual isolated evidence."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-seams-20261115"
ART = ROOT / "assets/art/actor-seams"
RUNS = ["import-final", "render-final", "baseline-v5-final", "legacy-v1-final", "legacy-v2-final", "legacy-v3-final", "legacy-v4-final", "regression-rules-final", "regression-ui-final"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    report = load(EV / "render-final/report.json")
    states = [rig for frame in report["frames"] for rig in frame["rigs"] if rig["bone_count"] == 27]
    metrics = {"frame_count": len(report["frames"]), "p01_frame_samples": len(states),
               "max_hand_prop_error": max(s["held_contact_error"] for s in states),
               "max_foot_error": max(f["error"] for s in states for f in s["feet"]),
               "sequence_counts": dict(Counter(f["sequence"] for f in report["frames"])),
               "geometry_is_not_art_acceptance": True}
    save(EV / "motion-metrics.json", metrics)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 17)
    for name in ["command-00", "command-02", "motion-action-authored1-slow", "motion-hit-authored1-slow"]:
        frames = [(frame, rig) for frame in report["frames"] if frame["sequence"] == name
                  for rig in frame["rigs"] if rig["bone_count"] == 27]
        active = [pair for pair in frames if pair[1]["pose"] in ["action", "hit"]] or frames
        duration = max(rig["action_time"] for _, rig in active)
        chosen = [min(active, key=lambda pair: abs(pair[1]["action_time"] - duration * value))
                  for value in [0, .10, .22, .37, .48, .64, .82, .98]]
        sheet = Image.new("RGB", (1160, 920), "#172b34")
        draw = ImageDraw.Draw(sheet)
        for index, (frame, rig) in enumerate(chosen):
            with Image.open(EV / "render-final" / frame["file"]) as image:
                bitmap = image.convert("RGB").crop((60, 0, 340, 355))
            x, y = 10 + index % 4 * 290, 60 + index // 4 * 430
            sheet.paste(bitmap, (x, y))
            draw.text((x, y - 28), f'{frame["elapsed_ms"]} ms / {rig["pose"]}', font=font, fill="#eed5ad")
            draw.text((x, y + 360), f'动作时间 {rig["action_time"]:.3f} s', font=font, fill="white")
        sheet.save(EV / ("inspection-" + name + ".jpg"), quality=96)
    return metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    metrics = prepare()
    if args.prepare_only:
        print(json.dumps(metrics))
        return
    checks = []

    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})

    before = load(EV / "before.json")
    with zipfile.ZipFile(EV / "before.zip") as archive:
        corrupt = [f for f, h in before["files"].items() if hashlib.sha256(archive.read(f)).hexdigest() != h]
    check("before_zip_matches_all_hashes", not corrupt, corrupt)
    changed = [f for f, h in before["files"].items() if not (ROOT / f).is_file() or digest(ROOT / f) != h]
    unexpected = sorted(set(changed) - set(before["mutable_existing"]))
    check("only_authorized_existing_files_changed", not unexpected, {"changed": changed, "unexpected": unexpected})
    old_art = [f for f in before["files"] if f.startswith("assets/art/")]
    check("all_v1_to_v5_art_bytes_preserved", all(digest(ROOT / f) == before["files"][f] for f in old_art), len(old_art))
    check("runtime_rules_data_default_and_frozen_preserved", not any(f.startswith(("src/", "data/", "docs/提交文档_20261114/")) or f == "project.godot" for f in changed))

    old = load(ROOT / "assets/art/actor-anatomy/P01/rig.json")
    new = load(ART / "P01/rig.json")
    protected = ["bones", "feet", "anatomy", "upright_bones", "idle_tracks", "contact_shadows", "cast_shadows"]
    check("approved_v5_proportions_and_skeleton_exact", all(old[k] == new[k] for k in protected), protected)
    lower_ids = ["pelvis", "rear_leg", "front_leg", "rear_shoe", "front_shoe"]
    check("lower_body_parts_exact", all(next(p for p in old["parts"] if p["id"] == key) == next(p for p in new["parts"] if p["id"] == key) for key in lower_ids))
    other_tracks = []
    for pose in old["animations"]:
        keep = lambda t: pose != "action" or t["bone"] not in ["near_upper", "near_forearm"] or t["property"] != "rotation"
        other_tracks.append([t for t in old["animations"][pose]["tracks"] if keep(t)] == [t for t in new["animations"][pose]["tracks"] if keep(t)])
        other_tracks.append(old["animations"][pose]["length"] == new["animations"][pose]["length"])
    check("all_other_action_tracks_and_durations_exact", all(other_tracks))
    check("enemy_rig_exact_v4", load(ART / "N01/rig.json") == load(ROOT / "assets/art/actor-anatomy/N01/rig.json"))
    pixel_results = {}
    for pose in ["neutral", "action", "hit", "guard"]:
        file = "anatomy-full-" + pose + ".png"
        a = np.array(Image.open(EV / "baseline-v5-final" / file).convert("RGB"))[720:]
        b = np.array(Image.open(EV / "render-final" / file).convert("RGB"))[720:]
        pixel_results[pose] = {"different_pixels": int(np.any(a != b, axis=-1).sum()), "crop": [0, 720, 1200, 1400]}
    check("four_poses_lower_body_render_pixels_exact", all(v["different_pixels"] == 0 for v in pixel_results.values()), pixel_results)

    runs, drift = [], []
    for name in RUNS:
        result = load(EV / (name + ".run.json"))
        check(name + "_exit_and_errors", result["exit_code"] == 0 and result["engine_errors"] == 0)
        drift.extend({"run": name, "file": f} for f, h in result["inputs"].items() if not (ROOT / f).is_file() or digest(ROOT / f) != h)
        runs.append({"name": name, **{k: result[k] for k in ["command", "seconds", "exit_code", "engine_errors"]}, "metadata_sha256": digest(EV / (name + ".run.json"))})
    check("final_runs_inputs_still_current", not drift, drift)
    report = load(EV / "render-final/report.json")
    baseline = load(EV / "baseline-v5-final/report.json")
    check("actual_v6_checks_and_five_commands", not report["failures"] and len(report["commands"]) == 5 and all(c["equal"] for c in report["commands"]), len(report["checks"]))
    check("actual_v5_compatibility", not baseline["failures"] and len(baseline["commands"]) == 5 and all(c["equal"] for c in baseline["commands"]), len(baseline["checks"]))
    check("large_captures_use_real_pose_drawings", all(c["state"]["drawings"]["head"] == ("head_hit" if c["pose"] == "hit" else "head_strike") for c in report["anatomy_captures"] if c["pose"] != "neutral"))
    browser = load(EV / "review-browser/report.json")
    check("offline_browser_controls_and_media", browser["passed"], browser["checks"])
    audit = load(EV / "asset-audit-final.json")
    check("seven_local_assets_machine_audit", audit["status"] == "passed" and audit["total"] == 7)
    visual = load(EV / "visual-review.json")
    check("actual_visual_review_separate", visual["actual_ai_visual_review"] and len(visual["viewed_files"]) >= 10 and not visual["human_final_accepted"])

    generated = [p for p in ART.rglob("*") if p.is_file() and p.suffix in [".json", ".png"]]
    generated_hash = {p.relative_to(ROOT).as_posix(): digest(p) for p in generated}
    command = [sys.executable, "tools/build_actor_seams.py"]
    rebuilt = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild.stdout.txt").write_bytes(rebuilt.stdout)
    (EV / "rebuild.stderr.txt").write_bytes(rebuilt.stderr)
    check("local_rebuild_byte_identical", rebuilt.returncode == 0 and all(digest(ROOT / f) == h for f, h in generated_hash.items()))
    save(EV / "rebuild.json", {"command": command, "exit_code": rebuilt.returncode, "files": generated_hash})
    extraction = load(EV / "extraction.json")
    save(EV / "api-ledger.json", {"batch": "actor-seams-20261115", "api_calls_this_batch": 0, "generated_api_images_this_batch": 0,
        "successful_cumulative": 15, "authorized_limit": 200, "local_derived_pngs": extraction["count"],
        "processing_manifest": "extraction.json", "note": "No image API call or new API charge initiated by this batch."})
    own_files = ["tools/build_actor_seams.py", "tools/build_actor_seams_review.py", "tools/verify_actor_seams_review.py", "tools/finalize_actor_seams.py", "tools/start_actor_seams.ps1", "docs/plans/2026-11-15-actor-seams-design.md"]
    summary = {"project_date": "2026-11-15", "audited_utc": datetime.now(timezone.utc).isoformat(), "checks": checks,
        "failures": [c for c in checks if not c["passed"]], "runs": runs, "metrics": metrics,
        "screens": len(report["screens"]), "frames": len(report["frames"]), "behavior_checks": len(report["checks"]),
        "api_new": 0, "api_cumulative": 15, "source_sha256": {f: digest(ROOT / f) for f in own_files},
        "visual_acceptance": "AI reviewed; user's final review pending; approved v5 proportions preserved",
        "scope": "Only P01 sleeve/collar/wrist repairs; no whole G0/G6/G8 acceptance or production rollout."}
    save(EV / "verification-summary.json", summary)
    missing = []
    for file in [ROOT / "docs/plans/2026-11-15-actor-seams-design.md", EV / "review/index.html"]:
        for pair in re.findall(r'\]\(([^)]+)\)|(?:href|src)="([^"]+)"', file.read_text(encoding="utf-8")):
            address = html.unescape(next(s for s in pair if s)).strip().strip("<>")
            if address.startswith(("#", "http:", "https:", "data:", "mailto:")):
                continue
            address = address.split("#")[0]
            if address and not (file.parent / address).is_file():
                missing.append({"file": file.relative_to(ROOT).as_posix(), "target": address})
    check("new_design_and_review_links_exist", not missing, missing)
    summary["failures"] = [c for c in checks if not c["passed"]]
    save(EV / "verification-summary.json", summary)
    print(json.dumps({"checks": len(checks), "failures": summary["failures"], "screens": summary["screens"], "frames": summary["frames"]}, ensure_ascii=False))
    if summary["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
