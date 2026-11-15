"""Audit v5 evidence and retain full-body inspections without rewriting v1-v4."""
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
import argparse
import hashlib
import html
import json
import math
import re
import subprocess
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-anatomy-20261115"
ART = ROOT / "assets/art/actor-anatomy"
FINAL_RUN = "render-05"
RUNS = ["import-03", FINAL_RUN, "legacy-v1-02", "legacy-v2-02", "legacy-v3-02", "legacy-v4-02", "regression-rules-02", "regression-ui-02"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def links(text, parent):
    missing = set()
    for pair in re.findall(r'\]\(([^)]+)\)|(?:href|src)="([^"]+)"', text):
        target = html.unescape(next(item for item in pair if item)).strip().strip("<>")
        if target.startswith(("#", "http:", "https:", "data:", "mailto:", "app:")):
            continue
        target = target.split("#")[0]
        if target and not (parent / target).exists():
            missing.add(target)
    return missing


def prepare():
    report = load(EV / FINAL_RUN / "report.json")
    frames = [(frame, rig) for frame in report["frames"] for rig in frame["rigs"] if rig["bone_count"] == 27]
    calibration = load(ART / "P01/rig.json")["anatomy"]["calibration"]
    states = [rig for _, rig in frames]
    feet = [foot for rig in states for foot in rig["feet"]]
    metrics = {"actual_p01_frame_samples": len(states), "actual_frame_count": len(report["frames"]),
        "max_ankle_error": max(foot["error"] for foot in feet),
        "min_reach_margin": min(foot["reach_margin"] for foot in feet),
        "max_knee_degrees": max(abs(math.degrees(foot["knee_flexion"])) for foot in feet),
        "max_shoe_radians": max(abs(foot["shoe_rotation"]) for foot in feet),
        "max_hand_prop_error": max(rig["held_contact_error"] for rig in states),
        "neutral_and_six_pose_geometry": {k: v for k, v in report["anatomy_geometry"].items() if k != "samples"},
        "sequence_counts": dict(Counter(frame["sequence"] for frame in report["frames"])),
        "geometry_is_not_art_acceptance": True}
    metrics["max_segment_error"] = max(abs(foot["lengths"][j] - calibration[i]["lengths"][j]) for rig in states for i, foot in enumerate(rig["feet"]) for j in range(2))
    save(EV / "motion-metrics.json", metrics)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    for sequence in ["command-00", "command-02", "motion-action-authored1-slow", "motion-hit-authored1-slow"]:
        candidates = [(frame, rig) for frame, rig in frames if frame["sequence"] == sequence]
        active = [(frame, rig) for frame, rig in candidates if rig["pose"] in ("hit", "action")]
        if not active:
            active = candidates
        duration = max(rig["action_time"] for _, rig in active)
        chosen = [min(active, key=lambda row: abs(row[1]["action_time"] - duration * fraction)) for fraction in [0, .10, .22, .37, .48, .64, .82, .98]]
        sheet = Image.new("RGB", (1160, 920), "#172b34")
        draw = ImageDraw.Draw(sheet)
        for index, (frame, state) in enumerate(chosen):
            with Image.open(EV / FINAL_RUN / frame["file"]) as source:
                pic = source.convert("RGB").crop((60, 0, 340, 355)).resize((280, 355), Image.Resampling.LANCZOS)
            x, y = 10 + index % 4 * 290, 60 + index // 4 * 430
            sheet.paste(pic, (x, y))
            draw.text((x, y - 28), f'{frame["elapsed_ms"]} ms / {state["pose"]}', font=font, fill="#eed5ad")
            draw.text((x, y + 360), f'动作时间 {state["action_time"]:.3f} s', font=font, fill="white")
        sheet.save(EV / f"inspection-{sequence}.jpg", quality=96)
    return metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    metrics = prepare()
    if args.prepare_only:
        print(json.dumps(metrics, ensure_ascii=False))
        return
    before = load(EV / "before.json")["inputs"]
    with zipfile.ZipFile(EV / "before.zip") as archive:
        backup_errors = [file for file, expected in before.items() if hashlib.sha256(archive.read(file)).hexdigest() != expected]
        old_docs = {file: archive.read(file).decode("utf-8-sig") for file in before if file.endswith(".md")}
    changed = [file for file, expected in before.items() if not (ROOT / file).is_file() or digest(ROOT / file) != expected]
    runtime_changes = [file for file in changed if file.startswith(("src/", "tests/", "data/")) and file != "src/ui/battle/native_actor_rig.gd"]
    immutable = [file for file in before if file.startswith(("assets/art/actor-rig-pilot/", "assets/art/actor-rig-polish/", "assets/art/actor-rig-refinement/", "assets/art/actor-rig-drawings/", "docs/提交文档_20261114/", "output/文档提交_20261114/")) or file == "project.godot" or file.endswith("交大四年_DDL战争_文档提交包_20261114.zip")]
    immutable_changes = [file for file in immutable if not (ROOT / file).is_file() or digest(ROOT / file) != before[file]]
    runs, drift, run_failures = [], [], []
    for name in RUNS:
        result = load(EV / (name + ".run.json"))
        if result["exit_code"] != 0 or result["engine_errors"] != 0:
            run_failures.append(name)
        drift.extend({"run": name, "file": file} for file, expected in result["inputs"].items() if not (ROOT / file).is_file() or digest(ROOT / file) != expected)
        runs.append({"name": name, **{key: result[key] for key in ["command", "seconds", "exit_code", "engine_errors"]}, "metadata_sha256": digest(EV / (name + ".run.json"))})
    report, browser = load(EV / FINAL_RUN / "report.json"), load(EV / "review-browser/report.json")
    assert not report["failures"] and all(command["equal"] for command in report["commands"])
    assert browser["passed"] and not browser["errors"] and not browser["failed_requests"]
    assert metrics["max_ankle_error"] < .05 and metrics["min_reach_margin"] > .01
    for path in [EV / "raw-audit.json", EV / "parts-audit-final.json"]:
        assert load(path)["status"] == "passed"
    # Rebuild once, comparing actual asset bytes rather than adding mirrored
    # implementation tests. The subprocess has no network or player save work.
    outputs = sorted(p for p in ART.rglob("*") if p.is_file() and p.suffix in (".png", ".json"))
    hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in outputs}
    rebuilt = subprocess.run(["python", str(ROOT / "tools/build_actor_anatomy.py")], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    (EV / "rebuild.stdout.txt").write_text(rebuilt.stdout, encoding="utf-8")
    (EV / "rebuild.stderr.txt").write_text(rebuilt.stderr, encoding="utf-8")
    rebuild_drift = [file for file, expected in hashes.items() if digest(ROOT / file) != expected]
    save(EV / "rebuild.json", {"exit_code": rebuilt.returncode, "outputs": len(outputs), "byte_identical": not rebuild_drift, "mismatches": rebuild_drift, "inputs": hashes})
    source_errors = []
    for path in ART.rglob("source.json"):
        source_errors.extend(item["file"] for item in load(path)["textures"] if digest(ROOT / item["file"]) != item["sha256"])
    api = load(ROOT / "output/imagegen/actor-anatomy-20261115/asset-manifest.json")
    for item in api["assets"]:
        for file, expected in [(item["output"], item["output_sha256"]), (item["prompt_file"], item["prompt_sha256"]), *[(value["file"], value["sha256"]) for value in item["inputs"]]]:
            if digest(ROOT / file) != expected:
                source_errors.append(file)
    assert len(api["assets"]) == 3 and api["cumulative_successful"] == 15
    docs = [ROOT / file for file in ["README.md", "AGENTS.md", "agent.md", "实施计划与验收基线.md", "ui-plan/README.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md", "docs/plans/2026-11-15-actor-anatomy-design.md"]]
    summary_path = EV / "verification-summary.json"
    if not summary_path.exists():
        save(summary_path, {"status": "finalizing"})
    missing = []
    for doc in docs:
        new = links(doc.read_text(encoding="utf-8"), doc.parent)
        old = links(old_docs.get(doc.relative_to(ROOT).as_posix(), ""), doc.parent)
        missing.extend({"file": doc.relative_to(ROOT).as_posix(), "target": target} for target in sorted(new - old))
    page = EV / "review/index.html"
    missing.extend({"file": "review/index.html", "target": target} for target in links(page.read_text(encoding="utf-8"), page.parent))
    for frame in report["frames"]:
        if not (EV / FINAL_RUN / frame["file"]).exists():
            missing.append({"frame": frame["file"]})
    for screen in report["screens"]:
        file = screen.get("file", screen.get("name", ""))
        if not file.endswith(".png"):
            file += ".png"
        if not (EV / FINAL_RUN / file).exists():
            missing.append({"screen": file})
    visual = load(EV / "visual-review.json")
    assert visual["fullbody_and_legs_reviewed"] and not visual["human_accepted"]
    text_paths = [*docs, *EV.rglob("*.json"), *(ROOT / "output/imagegen/actor-anatomy-20261115").glob("*.log")]
    secret_hits = [p.relative_to(ROOT).as_posix() for p in text_paths if re.search(r"(?:sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9_-]{20,})", p.read_text(encoding="utf-8", errors="replace"))]
    passed = not any([backup_errors, runtime_changes, immutable_changes, drift, run_failures, rebuild_drift, source_errors, missing, secret_hits]) and rebuilt.returncode == 0
    audit = {"passed": passed, "backup_files": len(before), "backup_hash_errors": backup_errors, "unexpected_runtime_changes": runtime_changes,
             "old_art_default_entry_frozen_changes": immutable_changes, "input_drift": drift, "run_failures": run_failures,
             "rebuild_mismatches": rebuild_drift, "source_hash_errors": source_errors, "missing_new_links_or_media": missing, "secret_patterns": secret_hits}
    save(EV / "delivery-audit.json", audit)
    save(EV / "verification-summary.json", {"status": "passed" if passed else "failed", "utc": datetime.now(timezone.utc).isoformat(),
         "scope": "Optional P01 v5 full-body, pelvis and legs; N01 unchanged v4; pending user art review", "final_render": FINAL_RUN,
         "checks": len(report["checks"]), "commands": len(report["commands"]), "screens": len(report["screens"]), "frames": len(report["frames"]),
         "API_new_successful": 3, "API_cumulative_successful": 15, "API_limit": 200, "billing": "not returned",
         "metrics": metrics, "runs": runs, "browser": "review-browser/report.json", "audit": audit,
         "remaining": ["user visual acceptance", "extreme sleeve, larger turn and hand/prop perspective", "other body families", "full G0/G6/G8 exits"]})
    after_files = set(ROOT / file for file in before)
    after_files.update(p for folder in [ART, ROOT / "output/imagegen/actor-anatomy-20261115"] for p in folder.rglob("*") if p.is_file() and p.suffix in (".json", ".png", ".txt", ".log"))
    after_files.update(docs)
    after_files.update(p for p in (ROOT / "tools").glob("*anatomy*") if p.is_file())
    save(EV / "after.json", {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(after_files)})
    print(json.dumps(audit, ensure_ascii=False))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
