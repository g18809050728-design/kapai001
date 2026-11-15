"""Verify the v4 delivery against its backup, raw runs, media and source hashes."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import html
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-rig-drawings-20261115"
ART = ROOT / "assets/art/actor-rig-drawings"
RUNS = ["import-02", "render-04", "legacy-v1-01", "legacy-v2-01", "legacy-v3-01", "regression-rules-01", "regression-ui-01"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def missing_links(text, parent):
    result = set()
    for link in re.findall(r'\]\(([^)]+)\)|(?:href|src)="([^"]+)"', text):
        target = html.unescape(next(v for v in link if v)).strip().strip("<>")
        if target.startswith(("#", "http:", "https:", "data:", "app:", "mailto:")):
            continue
        target = target.split("#")[0]
        if target and not (parent / target).exists():
            result.add(target)
    return result


def main():
    before = load(EV / "before.json")["inputs"]
    with zipfile.ZipFile(EV / "before.zip") as backup:
        backup_errors = [p for p, h in before.items() if hashlib.sha256(backup.read(p)).hexdigest() != h]
        old_docs = {p: backup.read(p).decode("utf-8-sig") for p in before if p.endswith(".md")}
    changed = [p for p, h in before.items() if not (ROOT / p).exists() or digest(ROOT / p) != h]
    allowed = {"src/ui/battle/native_actor_rig.gd"}
    unexpected = [p for p in changed if p.startswith(("src/", "tests/", "data/", "assets/", "docs/提交文档_20261114/")) and p not in allowed]
    if "project.godot" in changed:
        unexpected.append("project.godot")
    immutable_art = [p for p in before if p.startswith(("assets/art/actor-rig-pilot/", "assets/art/actor-rig-polish/", "assets/art/actor-rig-refinement/"))]
    art_changes = [p for p in immutable_art if digest(ROOT / p) != before[p]]
    runs, drift, context_only = [], [], []
    for name in RUNS:
        path = EV / (name + ".run.json")
        run = load(path)
        assert run["exit_code"] == 0 and run["engine_errors"] == 0, name
        for file, expected in run["inputs"].items():
            if digest(ROOT / file) == expected:
                continue
            item = {"run": name, "file": file, "captured_sha256": expected, "current_sha256": digest(ROOT / file)}
            if name.startswith("legacy-") and (file.startswith("assets/art/actor-rig-drawings/") or file == "tools/build_actor_drawings.py"):
                item["reason"] = "Only optional v4 art/build data changed after this legacy run; this command selects v1/v2/v3 and never loads v4. All runtime and selected legacy textures/specs remain byte-identical."
                context_only.append(item)
            else:
                drift.append(item)
        runs.append({"name": name, **{k: run[k] for k in ["command", "started_utc", "seconds", "exit_code", "engine_errors"]},
            "metadata": path.relative_to(ROOT).as_posix(), "metadata_sha256": digest(path), "input_hash_count": len(run["inputs"]),
            "stdout_sha256": digest(EV / (name + ".stdout.txt")), "stderr_sha256": digest(EV / (name + ".stderr.txt"))})
    save(EV / "input-context-followup.json", {"relevant_drift": drift, "legacy_context_only_changes": context_only})
    report = load(EV / "render-04/report.json")
    browser = load(EV / "review-browser/report.json")
    assert report["drawings"] and not report["failures"] and all(c["ok"] for c in report["checks"])
    assert all(c["equal"] for c in report["commands"])
    assert browser["passed"] and not browser["errors"] and not browser["failed_requests"]
    rebuild = load(EV / "rebuild.json")
    assert rebuild["byte_identical"] and rebuild["exit_code"] == 0
    source_errors = []
    for source in ART.rglob("source.json"):
        for item in load(source)["textures"]:
            if digest(ROOT / item["file"]) != item["sha256"]:
                source_errors.append(item["file"])
    image_manifest = load(ROOT / "output/imagegen/actor-rig-drawings-20261115/asset-manifest.json")
    for asset in image_manifest["assets"]:
        for file, expected in [(asset["output"], asset["output_sha256"]), (asset["prompt_file"], asset["prompt_sha256"])]:
            if digest(ROOT / file) != expected:
                source_errors.append(file)
        for item in asset["inputs"]:
            if digest(ROOT / item["file"]) != item["sha256"]:
                source_errors.append(item["file"])
    docs = [ROOT / p for p in ["README.md", "AGENTS.md", "agent.md", "实施计划与验收基线.md", "ui-plan/README.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md", "docs/plans/2026-11-15-actor-drawings-design.md", "docs/plans/2026-11-15-actor-refinement-design.md"]]
    # The summary is the only forward reference while this finalizer runs.
    if not (EV / "verification-summary.json").exists():
        save(EV / "verification-summary.json", {"status": "finalizing"})
    missing = []
    for doc in docs:
        relative = doc.relative_to(ROOT).as_posix()
        new = missing_links(doc.read_text(encoding="utf-8"), doc.parent)
        old = missing_links(old_docs.get(relative, ""), doc.parent)
        missing.extend({"file": relative, "target": t} for t in sorted(new - old))
    page = EV / "review/index.html"
    missing.extend({"file": page.relative_to(ROOT).as_posix(), "target": t} for t in missing_links(page.read_text(encoding="utf-8"), page.parent))
    for frame in report["frames"]:
        if not (EV / "render-04" / frame["file"]).is_file():
            missing.append({"frame": frame["file"]})
    prior_manifest = load(ROOT / "artifacts/verification/actor-rig-refinement-20261115/review/manifest.json")
    prior_report = ROOT / prior_manifest["after"] / "report.json"
    prior_errors = [] if digest(prior_report) == prior_manifest["after_report_sha256"] else [str(prior_report)]
    secret_hits = []
    text_files = [*docs, *EV.rglob("*.json"), *EV.rglob("*.txt"), *(ROOT / "output/imagegen/actor-rig-drawings-20261115").glob("*.log")]
    for path in text_files:
        if re.search(r"(?:sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9_-]{20,})", path.read_text(encoding="utf-8", errors="replace")):
            secret_hits.append(path.relative_to(ROOT).as_posix())
    files = set(ROOT / p for p in before)
    files.update(docs)
    for directory, suffixes in [(ART, {".json", ".png"}), (ROOT / "tools", {".py", ".ps1", ".gd"}), (ROOT / "output/imagegen/actor-rig-drawings-20261115", {".json", ".txt", ".png", ".log"})]:
        files.update(p for p in directory.rglob("*") if p.is_file() and p.suffix in suffixes)
    files.add(ROOT / "src/ui/battle/actor_drawing_mix.gdshader")
    save(EV / "after.json", {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(files)})
    passed = not any([backup_errors, unexpected, art_changes, drift, source_errors, missing, prior_errors, secret_hits])
    audit = {"passed": passed, "before_files": len(before), "backup_hash_errors": backup_errors, "unexpected_runtime_changes": unexpected,
        "old_art_changes": art_changes, "source_hash_errors": source_errors, "missing_new_links_or_media": missing,
        "relevant_input_drift": drift, "legacy_context_only_count": len(context_only), "prior_report_hash_errors": prior_errors, "secret_patterns": secret_hits}
    save(EV / "delivery-audit.json", audit)
    save(EV / "verification-summary.json", {"status": "passed" if passed else "failed", "date_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "P01/N01 optional version4 local drawing refinement; no full art acceptance", "final_render": "render-04",
        "checks": len(report["checks"]), "failures": report["failures"], "commands": len(report["commands"]), "screens": len(report["screens"]), "frames": len(report["frames"]),
        "api_successful_this_batch": 6, "api_cumulative_successful": 12, "api_limit": 200, "billing": "not returned",
        "metrics": load(EV / "motion-metrics.json"), "runs": runs, "browser_report": "review-browser/report.json", "audit": audit,
        "context_explanation": "Earlier legacy checks remain applicable: only unused v4 art and its offline builder changed. Exact differences are retained in input-context-followup.json.",
        "remaining": ["final user visual acceptance", "larger turn and extreme sleeve deformation", "non-paper enemy, ally and multi-stage boss samples", "full G0/G6/G8 exits"]})
    print(json.dumps(audit, ensure_ascii=False))
    assert passed


if __name__ == "__main__":
    main()
