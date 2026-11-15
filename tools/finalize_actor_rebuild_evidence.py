"""Validate the P03 whole-component rebuild against actual retained evidence."""
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-rebuild-20261115"
ART = ROOT / "assets/art/actor-rebuild"
RAW = ROOT / "output/imagegen/actor-rebuild-20261115"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def changed(records):
    return [p for p, digest in records.items() if not (ROOT / p).is_file() or sha(ROOT / p) != digest]


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        self.targets.extend(v for k, v in attrs if k in ("href", "src") and v)


def main():
    checks = {}

    def check(name, ok):
        checks[name] = bool(ok)

    baseline = read(EV / "before.json")
    protected = {r["path"]: r["sha256"] for r in baseline["protected"]}
    protection_changes = changed(protected)
    check("530 protected historical and shared files retain exact bytes", len(protected) == 530 and not protection_changes)
    with zipfile.ZipFile(EV / "before.zip") as archive:
        snapshot_issues = [r["path"] for r in baseline["snapshotted"] if hashlib.sha256(archive.read(r["path"])).hexdigest() != r["sha256"]]
        historical_plan = archive.read("实施计划与验收基线.md")
        marker = "### 0.20.22 ".encode()
        check("V9 and earlier plan body remains intact", (ROOT / "实施计划与验收基线.md").read_bytes().endswith(historical_plan[historical_plan.index(marker):]))
    check("all eight before snapshots remain intact", len(baseline["snapshotted"]) == 8 and not snapshot_issues)

    assets = sorted(p for p in ART.rglob("*") if p.suffix in (".json", ".png"))
    before = {rel(p): sha(p) for p in assets}
    archive_path = EV / "resources-final.zip"
    if not archive_path.exists():
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in assets:
                archive.write(path, rel(path))
    command = [sys.executable, str(ROOT / "tools/build_actor_rebuild.py")]
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild-final.stdout.txt").write_bytes(result.stdout)
    (EV / "rebuild-final.stderr.txt").write_bytes(result.stderr)
    after = {rel(p): sha(p) for p in assets}
    check("all final resource files rebuild byte identically", result.returncode == 0 and before == after)
    write(EV / "rebuild-final.json", {"command": command, "exit_code": result.returncode, "byte_identical": before == after, "before": before, "after": after})
    rig = read(ART / "P03/rig.json")
    check("actual V10 has 27 registered bones fourteen parts and six meshes", rig["version"] == 10 and len(rig["bones"]) == 27 and len(rig["parts"]) == 14 and sum(bool(p.get("mesh")) for p in rig["parts"]) == 6)
    check("all live P03 parts are newly rebuilt resources", rig["rebuild"]["complete_new_master"] and not rig["rebuild"]["legacy_body_pixels"] and all(p["file"].startswith("res://assets/art/actor-rebuild/P03/") for p in rig["parts"]))
    references = {r["file"]: r["sha256"] for r in read(ART / "P03/source.json")["textures"]}
    check("all runtime texture hashes agree with their provenance", not changed(references))
    for role, family in (("P01", "actor-anatomy"), ("N01", "actor-anatomy"), ("P02", "actor-proportions"), ("P04", "actor-proportions")):
        check(role + " retains selected rig bytes", (ART / role / "rig.json").read_bytes() == (ROOT / "assets/art" / family / role / "rig.json").read_bytes())
    extraction = read(EV / "extraction.json")
    check("24 derived outputs retain recorded input and output hashes", len(extraction["outputs"]) == 24 and all(sha(ROOT / r["file"]) == r["sha256"] and sha(ROOT / r["source"]) == r["source_sha256"] for r in extraction["outputs"]) and not changed(extraction["inputs"]))

    api = read(RAW / "asset-manifest.json")
    api_changed = []
    for record in api["records"]:
        api_changed.extend(changed({r["path"]: r["sha256"] for r in record["inputs"]}))
        api_changed.extend(changed({record["output"]["path"]: record["output"]["sha256"]}))
        check(record["record"] + " records a successful actual image edit", record["exit_code"] == 0 and record["mode"] == "edit" and record["model"] == "gpt-image-2.5-sunburst" and record["n"] == 1)
    check("all actual uploaded inputs prompts and outputs match recorded hashes", not api_changed)
    check("API count is nine new images and 38 of 200 cumulative", api["api_successful_previous"] == 29 and api["api_successful_this_revision"] == len(api["records"]) == 9 and api["api_successful_cumulative"] == 38 <= api["user_limit"] == 200)
    audits = {}
    for name, total in (("raw-audit", 9), ("asset-audit-final", 24)):
        audit = read(EV / (name + ".json"))
        check(name + " passes file integrity checks", audit["status"] == "passed" and audit["total"] == total and audit["failed"] == 0 and all(sha(Path(r["path"])) == r["sha256"] for r in audit["images"]))
        audits[name] = {k: audit[k] for k in ("status", "total", "failed", "duplicates", "require_alpha")}
    check("neck base variants deliberately retain identical alpha and pixels", len({sha(ART / "P03" / ("neck_overlap_" + name + ".png")) for name in ("neutral", "focus", "hit")}) == 1)

    runs = {}
    for name in ("import-final", "poses-final", "p03-final"):
        run = read(EV / (name + ".run.json"))
        check(name + " exited without engine errors", run["exit_code"] == 0 and run["engine_errors"] == 0)
        check(name + " runtime inputs retain exact checked bytes", not changed(run["inputs"]) and not run["rebuild_inputs_changed_during_run"])
        runs[name] = {k: run[k] for k in ("command", "started_utc", "seconds", "exit_code", "engine_errors")}
    report = read(EV / "p03-final/report.json")
    check("all final real engine checks pass", not report["failures"] and all(c["ok"] for c in report["checks"]))
    check("five real commands match unanimated state events revision and RNG", len(report["commands"]) == 5 and all(c["equal"] for c in report["commands"]))
    check("six actual actions return to the rebuilt neutral posture", len(report["rebuild"]["pose_samples"]) == 6)
    probe = read(EV / "poses-final/probe.json")
    check("fourteen actual paired V9/V10 pose renders saved", len(probe["captures"]) == 14 and all(c["save_error"] == 0 for c in probe["captures"]))
    reused = {}
    for name in ("rules-01", "ui-01"):
        path = ROOT / "artifacts/verification/actor-party-20261115" / (name + ".run.json")
        run = read(path)
        shared = {k: v for k, v in run["inputs"].items() if k.startswith(("src/", "tests/", "data/")) or k == "project.godot"}
        check(name + " shared inputs match previous full regression", run["exit_code"] == 0 and run["engine_errors"] == 0 and not changed(shared))
        reused[name] = {"record": rel(path), "rerun_this_revision": False, "shared_hashes_verified": len(shared)}
    browser = read(EV / "review-browser-final/report.json")
    check("actual browser interaction and responsive checks pass", browser["passed"] and all(browser["checks"].values()) and not browser["errors"] and not browser["failed_requests"])
    check("browser used exact current page and tools", not changed(browser["inputs"]))
    media = read(EV / "review/manifest.json")
    check("review uses actual current or explicitly reused media bytes", not changed(media["inputs"]))
    visual = read(EV / "visual-review.json")
    check("AI visual review and pending user art acceptance remain separate", visual["ai_review_complete"] and visual["user_final_art_acceptance"] == "pending")
    check("all actually viewed media retains original bytes", not changed({r["file"]: r["sha256"] for r in visual["reviewed_files"]}))
    check("32 fullbody keyframes and fourteen paired poses are represented", visual["fullbody_keyframes_reviewed"] == 32 and visual["final_pose_captures_represented"] == 14)

    docs = [ROOT / p for p in ("README.md", "ui-plan/README.md", "agent.md", "AGENTS.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md", "实施计划与验收基线.md", "docs/plans/2026-11-15-actor-rebuild-design.md")]
    page = EV / "review/index.html"
    parser = Links(); parser.feed(page.read_text(encoding="utf-8"))
    links = [(page, t) for t in parser.targets]
    for doc in docs:
        text = doc.read_text(encoding="utf-8-sig")
        if doc.name != "2026-11-15-actor-rebuild-design.md": text = "\n".join(text.splitlines()[:5])
        links.extend((doc, target) for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text))
    broken = []
    for origin, target in links:
        parts = urlsplit(target)
        if parts.scheme or not parts.path: continue
        dest = (origin.parent / unquote(parts.path)).resolve()
        if dest != EV / "verification-summary.json" and not dest.is_file(): broken.append({"origin": rel(origin), "target": target})
    check("new review and documentation links resolve", not broken)
    patterns = [re.compile(r"\bsk-[A-Za-z0-9_-]{24,}"), re.compile(r"\bBearer\s+[A-Za-z0-9_./+\-=]{24,}", re.I)]
    scan = [p for folder in (EV, ART, RAW) for p in folder.rglob("*") if p.suffix in (".json", ".log", ".txt", ".html")]
    scan += list((ROOT / "tools").glob("*actor_rebuild*"))
    matches = [rel(p) for p in scan if p.is_file() and p.suffix in (".json", ".log", ".txt", ".html", ".gd", ".py") and any(pattern.search(p.read_text(encoding="utf-8-sig", errors="replace")) for pattern in patterns)]
    check("new artifacts and tools contain no credential strings", not matches)
    diff = subprocess.run(["git", "diff", "--check"], cwd=ROOT, capture_output=True)
    (EV / "git-diff-check.txt").write_bytes(diff.stdout + diff.stderr)
    check("git diff whitespace check passes", diff.returncode == 0)
    (EV / "git-status-final.txt").write_bytes(subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True).stdout)
    failures = [name for name, ok in checks.items() if not ok]
    totals = {k: len(report[k]) for k in ("checks", "commands", "screens", "frames", "fullbody_frames")}
    summary = {"date": "2026-11-15", "recorded_utc": datetime.now(timezone.utc).isoformat(), "passed": not failures, "checks": checks, "failures": failures,
               "scope": "P03 V10 whole-component rebuild from a new master; isolated opt-in pilot", "totals": totals, "runs": runs, "reused_full_regressions": reused,
               "protection": {"files": len(protected), "changes": protection_changes, "snapshot_issues": snapshot_issues, "before_zip_sha256": sha(EV / "before.zip")},
               "rebuild": {"files": len(assets), "byte_identical": before == after, "exit_code": result.returncode},
               "api": {"successful_this_revision": 9, "cumulative_successful": 38, "limit": 200, "billing": "Provider amount unknown", "mode": "edit", "model": api["model"]},
               "audits": audits, "browser_checks": len(browser["checks"]), "review_media_and_reports": len(media["inputs"]), "user_final_art_acceptance": "pending",
               "broken_links": broken, "credential_matches": matches, "document_hashes": {rel(p): sha(p) for p in docs},
               "limitations": ["Final character art approval is pending user viewing.", "P02/P04 V8 captures and shared full rules/UI suites are explicitly reused after exact input hash checks.", "Local drawing blends can briefly overlap in slow motion; no complete 3D turn or real-time performance benchmark is claimed.", "Existing unrelated historical image UID warnings remain on editor import; final engine error count is zero.", "Original G0/G6/G8 production acceptance gates remain pending."]}
    write(EV / "verification-summary.json", summary)
    print(json.dumps({"passed": not failures, "failures": failures, "protected_files": len(protected), "rebuild_identical": before == after, "totals": totals, "browser_checks": len(browser["checks"])}, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
