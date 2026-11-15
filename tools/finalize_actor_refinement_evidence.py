"""Finalize the second refinement; keep earlier reports and hashes intact."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-rig-refinement-20261115"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    before = load(EV / "before.json")["inputs"]
    with zipfile.ZipFile(EV / "before.zip") as backup:
        backup_errors = [p for p, expected in before.items() if hashlib.sha256(backup.read(p)).hexdigest() != expected]
        old_text = {p: backup.read(p).decode("utf-8-sig") for p in before if p.endswith(".md")}
    changed = [p for p, expected in before.items() if not (ROOT / p).is_file() or digest(ROOT / p) != expected]
    allowed_runtime = {"src/ui/battle/native_actor_rig.gd", "src/ui/battle/battle_actor_view.gd", "src/ui/battle/battle_stage_effects.gd", "src/ui/battle_layout.gd"}
    unexpected = [p for p in changed if (p.startswith(("src/", "tests/", "data/", "assets/")) or p == "project.godot") and p not in allowed_runtime]
    original_art = [p for p in before if p.startswith(("assets/art/actor-rig-pilot/", "assets/art/actor-rig-polish/"))]
    immutable_art_errors = [p for p in original_art if digest(ROOT / p) != before[p]]
    frozen = subprocess.check_output(["git", "status", "--short", "--", "docs/提交文档_20261114"], encoding="utf-8")
    run_names = ["import-01", "render-03", "legacy-v1-02", "legacy-v2-02", "regression-rules-02", "regression-ui-02"]
    runs, drift = [], []
    for name in run_names:
        path = EV / (name + ".run.json")
        run = load(path)
        assert run["exit_code"] == 0 and run["engine_errors"] == 0
        if name != "import-01":
            for file, expected in run["inputs"].items():
                if digest(ROOT / file) != expected:
                    drift.append({"run": name, "file": file, "captured_sha256": expected, "current_sha256": digest(ROOT / file)})
        runs.append({"name": name, "metadata": path.relative_to(ROOT).as_posix(), "metadata_sha256": digest(path),
            **{k: run[k] for k in ["command", "started_utc", "seconds", "exit_code", "engine_errors"]},
            "input_hash_count": len(run["inputs"]),
            "stdout_sha256": digest(EV / (name + ".stdout.txt")), "stderr_sha256": digest(EV / (name + ".stderr.txt"))})
    rebuild = load(EV / "rebuild.json")
    assert rebuild["byte_identical"] and rebuild["exit_code"] == 0
    assert not drift
    save(EV / "input-context-followup.json", {"runs": run_names, "drift": drift,
        "explanation": "All final tested runtime files, runner, builder and opt-in resources are current. Earlier pre-fix context is archived under pre-foot-fix."})
    report = load(EV / "render-03/report.json")
    assert report["refinement"] and not report["failures"] and all(c["ok"] for c in report["checks"])
    assert all(c["equal"] for c in report["commands"])
    browser = load(EV / "review-browser/report.json")
    assert browser["passed"] and not browser["errors"] and not browser["failed_requests"]
    source_errors = []
    rigs = []
    for entity in ["P01", "N01"]:
        folder = ROOT / "assets/art/actor-rig-refinement" / entity
        rig, source = load(folder / "rig.json"), load(folder / "source.json")
        rigs.append({"id": entity, "bones": len(rig["bones"]), "parts": len(rig["parts"]), "meshes": sum(bool(p.get("mesh")) for p in rig["parts"])})
        for texture in source["textures"]:
            if digest(ROOT / texture["file"]) != texture["sha256"]:
                source_errors.append(texture["file"])
    max_foot = max(f["error"] for frame in report["frames"] for rig in frame["rigs"] for f in rig["feet"])
    max_prop = max(r["held_contact_error"] for frame in report["frames"] for r in frame["rigs"])
    assert max_foot < 1.0 and max_prop < .05
    blinks = sum(any(r["face"] == "blink" for r in frame["rigs"]) for frame in report["frames"])
    summary = {"date": "2026-11-15", "created_utc": datetime.now(timezone.utc).isoformat(),
        "status": "P01_N01_version3_delivered_for_user_visual_review", "scope": "representatives only; full art acceptance and production not complete",
        "engine": report["engine"], "renderer": report["renderer"], "checks": {"passed": len(report["checks"]), "failed": len(report["failures"])},
        "real_commands": len(report["commands"]), "all_command_fingerprints_equal": all(c["equal"] for c in report["commands"]),
        "screenshots": len(report["screens"]), "continuous_frames": len(report["frames"]), "rigs": rigs,
        "timings": report["timings"], "max_sampled_ankle_endpoint_error_rig_units": max_foot,
        "max_sampled_prop_contact_error_rig_units": max_prop, "frames_with_actual_blink": blinks,
        "api_usage": load(EV / "api-ledger.json"), "runs": runs, "browser": "review-browser/report.json",
        "review": "review/index.html", "plan": "docs/plans/2026-11-15-actor-refinement-design.md",
        "old_resource_byte_identity": not immutable_art_errors, "default_project_entry_unchanged": digest(ROOT / "project.godot") == before["project.godot"],
        "visual_review": {"completed": ["full 1280x800", "960x600 at 150%", "action/hit key poses", "normal-speed browser playback", "slow authored sequences", "actual enemy turn and final command", "original pieces and official Silent sequence"],
            "remaining": ["extreme sleeve compression", "turn-around replacement drawings", "emotion set", "larger prop rotations and unseen surfaces", "other body types and rooms"], "final_user_acceptance": "pending"},
        "input_provenance": {"drift": drift, "explanation": "Final render, compatibility and rules/UI reruns use the same current runtime, runner, builder and resources. Ten generated outputs rebuild byte-identically.", "rebuild": "rebuild.json"},
        "iterations": {"render-01": "286 checks passed; retained before cast shadows", "render-02": "286 checks passed; final audit caught 18.153 rig-unit guard foot reach error from shared rest arrays; intermediate report retained under pre-foot-fix", "render-03": "287 checks, all six poses foot reach checked; final capture and visual review"},
        "limitations": ["not a performance benchmark", "controlled phase is not a real multistage Boss", "full G0/G6/G8 exits remain", "import retains pre-existing duplicate UID warnings"]}
    save(EV / "verification-summary.json", summary)
    page_path = EV / "review/index.html"
    page = page_path.read_text(encoding="utf-8")
    data = json.loads(re.search(r'<script id="motion-data" type="application/json">(.*?)</script>', page, re.S)[1])
    missing = [f["file"] for seq in data.values() for key in ["before", "after"] for f in seq[key] if not (page_path.parent / f["file"]).is_file()]
    for link in re.findall(r'(?:href|src)="([^"]+)"', page):
        if not link.startswith(("#", "http", "data:")) and not (page_path.parent / link.split("#")[0]).is_file():
            missing.append(link)
    docs = [ROOT / p for p in changed if p.endswith(".md")]
    docs.append(ROOT / "docs/plans/2026-11-15-actor-refinement-design.md")
    markdown = re.compile(r'\[[^\]]*\]\(([^)]+)\)')
    for path in docs:
        previous = set(markdown.findall(old_text.get(path.relative_to(ROOT).as_posix(), "")))
        for link in set(markdown.findall(path.read_text(encoding="utf-8"))) - previous:
            if link.startswith(("http", "#", "mailto:")):
                continue
            target = link.split("#")[0].strip("<>")
            if target and not (path.parent / target).is_file():
                missing.append(path.relative_to(ROOT).as_posix() + " -> " + link)
    tracked = [ROOT / p for p in before if (ROOT / p).is_file()]
    for folder, suffixes in [("assets/art/actor-rig-refinement", {".json", ".png", ".import"}), ("tools", {".py", ".gd", ".ps1"}), ("output/imagegen/actor-rig-refinement-20261115", {".json", ".txt", ".png", ".log"})]:
        tracked.extend(p for p in (ROOT / folder).rglob("*") if p.suffix in suffixes)
    tracked += docs
    after = {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(tracked))}
    save(EV / "after.json", after)
    secret_hits = []
    for p in [*docs, *EV.rglob("*.txt"), *EV.rglob("*.json"), *(ROOT / "output/imagegen/actor-rig-refinement-20261115").glob("*.log")]:
        if re.search(r"(?:sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9_-]{20,})", p.read_text(encoding="utf-8", errors="replace")):
            secret_hits.append(p.relative_to(ROOT).as_posix())
    passed = not any([backup_errors, unexpected, immutable_art_errors, source_errors, missing, secret_hits, frozen])
    audit = {"passed": passed, "before_files": len(before), "after_files": len(after), "backup_hash_errors": backup_errors,
        "unexpected_runtime_changes": unexpected, "original_art_changes": immutable_art_errors, "source_hash_errors": source_errors,
        "missing_links_or_frames": missing, "secret_pattern_hits": secret_hits, "frozen_submission_status": frozen,
        "changed_from_start": changed, "runtime_inputs_stable_after_checks": not drift,
        "resource_rebuild_byte_identical": rebuild["byte_identical"], "browser_checks_passed": all(browser["checks"].values())}
    save(EV / "delivery-audit.json", audit)
    print(json.dumps({"passed": passed, "checks": len(report["checks"]), "frames": len(report["frames"]), "max_foot": max_foot, "max_prop": max_prop, "blink_frames": blinks, "problems": {k: v for k,v in audit.items() if k in ["backup_hash_errors", "unexpected_runtime_changes", "original_art_changes", "source_hash_errors", "missing_links_or_frames", "secret_pattern_hits"]}}, ensure_ascii=False))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
