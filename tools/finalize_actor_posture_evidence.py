"""Verify the scoped P03 posture delivery against actual runs and protected bytes."""
from copy import deepcopy
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

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-posture-20261115"
OLD = ROOT / "artifacts/verification/actor-proportions-20261115"
ART = ROOT / "assets/art/actor-posture"
RAW = ROOT / "output/imagegen/actor-posture-20261115"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def changed(records):
    return [name for name, digest in records.items() if not (ROOT / name).is_file() or sha(ROOT / name) != digest]


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        self.targets.extend(value for key, value in attrs if key in ("src", "href") and value)


def main():
    checks = {}

    def check(name, condition):
        checks[name] = bool(condition)

    baseline = read(EV / "before.json")
    protected = {r["path"]: r["sha256"] for r in baseline["protected"]}
    protection_changes = changed(protected)
    check("499 protected files retain original bytes", len(protected) == 499 and not protection_changes)
    with zipfile.ZipFile(EV / "before.zip") as archive:
        snapshot_issues = [r["path"] for r in baseline["snapshotted"] if hashlib.sha256(archive.read(r["path"])).hexdigest() != r["sha256"]]
    check("all eight before snapshots are intact", len(baseline["snapshotted"]) == 8 and not snapshot_issues)

    assets = sorted(p for p in ART.rglob("*") if p.suffix in (".json", ".png"))
    before = {rel(p): sha(p) for p in assets}
    archive_path = EV / "resources-final.zip"
    if not archive_path.exists():
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in assets:
                archive.write(path, rel(path))
    command = [sys.executable, str(ROOT / "tools/build_actor_posture.py")]
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild-final.stdout.txt").write_bytes(result.stdout)
    (EV / "rebuild-final.stderr.txt").write_bytes(result.stderr)
    after = {rel(p): sha(p) for p in assets}
    check("twelve final PNG/JSON files rebuild byte identically", len(assets) == 12 and result.returncode == 0 and before == after)
    write(EV / "rebuild-final.json", {"command": command, "exit_code": result.returncode, "byte_identical": before == after, "before": before, "after": after})

    rig = read(ART / "P03/rig.json")
    old = read(ROOT / "assets/art/actor-proportions/P03/rig.json")
    source = read(ART / "P03/source.json")
    check("actual V9 keeps 27 bones fourteen parts and six meshes", rig["version"] == 9 and len(rig["bones"]) == 27 and len(rig["parts"]) == 14 and sum(bool(p.get("mesh")) for p in rig["parts"]) == 6)
    references = {r["file"]: r["sha256"] for r in source["textures"]}
    check("runtime texture provenance matches actual files", not changed(references))
    for role in ("P01", "P02", "P04", "N01"):
        check(role + " retains exact selected V8-family rig", (ART / role / "rig.json").read_bytes() == (ROOT / "assets/art/actor-proportions" / role / "rig.json").read_bytes())
    old_parts = {p["id"]: p for p in old["parts"]}
    check("all non-head parts retain V8 pixels and registration", all(p == old_parts[p["id"]] for p in rig["parts"] if p["id"] not in ("head", "neck_overlap")))
    old_bones = {b["id"]: b for b in old["bones"]}
    check("only the head joint is repositioned", all(b == old_bones[b["id"]] for b in rig["bones"] if b["id"] != "head"))
    new_head = next(b for b in rig["bones"] if b["id"] == "head")
    check("head joint actually retracts ten pixels and rises six", all(abs(new_head["position"][i] - old_bones["head"]["position"][i] - delta) < .000001 for i, delta in enumerate((-10, -6))))
    expected = deepcopy(old)
    for animation in expected["animations"].values():
        for track in animation["tracks"]:
            if track["bone"] == "head" and track["property"] == "rotation":
                track["keys"] = [[t, round(v * (.6 if v > 0 else .8), 7)] for t, v in track["keys"]]
    for track in expected["idle_tracks"]:
        if track["bone"] == "loop_head" and track["property"] == "rotation":
            track["keys"] = [[t, round(v * .6, 7)] for t, v in track["keys"]]
    check("motion changes affect only selected head rotation tracks", rig["animations"] == expected["animations"] and rig["idle_tracks"] == expected["idle_tracks"])
    check("V8 leg registration stays exact", all(rig[k] == old[k] for k in ("proportions", "ground", "canvas", "feet", "anatomy")))
    extraction = read(EV / "extraction.json")
    check("six new textures retain exact source and output hashes", len(extraction["outputs"]) == 6 and all(sha(ROOT / r["file"]) == r["sha256"] and sha(ROOT / r["source"]) == r["source_sha256"] for r in extraction["outputs"]))

    request = read(RAW / "request.json")
    api_sources = {request["prompt_file"]: request["prompt_sha256"], request["output"]: request["output_sha256"]}
    api_sources.update({r["file"]: r["sha256"] for r in request["input_images"]})
    api_run = read(RAW / "p03-upright-neck-v1-run.json")
    check("uploaded edit target prompt and generated output retain exact hashes", not changed(api_sources))
    check("one authorized API edit completed", api_run["exit_code"] == 0 and api_run["mode"] == "edit" and api_run["model"] == "gpt-image-2.5-sunburst")
    check("API total is 29 of authorized 200", request["previous_api_successful"] == 28 and request["new_api_successful"] == 1 and request["cumulative_api_successful"] == 29 <= request["api_limit"] == 200)
    audits = {}
    for name, total in (("asset-audit-final", 6), ("raw-audit", 1)):
        audit = read(EV / (name + ".json"))
        check(name + " passes exact-file checks", audit["status"] == "passed" and audit["total"] == total and audit["failed"] == 0 and audit["duplicates"] == 0 and all(sha(Path(r["path"])) == r["sha256"] for r in audit["images"]))
        audits[name] = {k: audit[k] for k in ("status", "total", "failed", "duplicates", "require_alpha")}

    runs = {}
    for name in ("import-03", "poses-final", "p03-final"):
        run = read(EV / (name + ".run.json"))
        check(name + " exited without engine errors", run["exit_code"] == 0 and run["engine_errors"] == 0)
        check(name + " exact runtime inputs remain unchanged", not changed(run["inputs"]) and not run["posture_inputs_changed_during_run"])
        runs[name] = {k: v for k, v in run.items() if k not in ("inputs", "posture_inputs_before")}
        runs[name]["record"] = rel(EV / (name + ".run.json"))
    report = read(EV / "p03-final/report.json")
    check("all P03 real engine checks passed", not report["failures"] and all(c["ok"] for c in report["checks"]))
    check("five actual commands equal the nonanimated session", len(report["commands"]) == 5 and all(c["equal"] for c in report["commands"]))
    check("six action return samples were actually checked", len(report["posture"]["pose_samples"]) == 6)
    probe = read(EV / "poses-final/probe.json")
    check("fourteen actual V8 and V9 pose renders exist", len(probe["captures"]) == 14 and all(c["save_error"] == 0 for c in probe["captures"]))
    pixels = []
    for pose in ("neutral", "action", "hit", "guard", "depart", "phase", "enter"):
        a = np.asarray(Image.open(EV / "poses-final" / ("v8-" + pose + ".png")).convert("RGBA"))
        b = np.asarray(Image.open(EV / "poses-final" / ("v9-" + pose + ".png")).convert("RGBA"))
        pixels.append({"pose": pose, "roi": [0, 760, 1200, 1400], "different_pixels": int(np.any(a[760:] != b[760:], axis=2).sum())})
    check("all seven lower-body rendered comparisons are pixel identical", all(p["different_pixels"] == 0 for p in pixels))
    reused = {}
    for name in ("rules-01", "ui-01"):
        path = ROOT / "artifacts/verification/actor-party-20261115" / (name + ".run.json")
        run = read(path)
        shared = {k: v for k, v in run["inputs"].items() if k.startswith(("src/", "tests/", "data/")) or k == "project.godot"}
        check(name + " previous full regression matches shared inputs", run["exit_code"] == 0 and run["engine_errors"] == 0 and not changed(shared))
        reused[name] = {"record": rel(path), "rerun_this_revision": False, "shared_hashes_verified": len(shared), "changes": changed(shared)}

    browser = read(EV / "review-browser-final/report.json")
    check("66 actual browser checks pass", browser["passed"] and len(browser["checks"]) == 66 and all(browser["checks"].values()) and not browser["errors"] and not browser["failed_requests"])
    check("browser used the current exact page and tools", not changed(browser["inputs"]))
    media = read(EV / "review/manifest.json")
    check("review references exact current and reused real captures", not changed(media["inputs"]))
    visual = read(EV / "visual-review.json")
    check("AI viewing and pending final user art judgment stay distinct", visual["ai_review_complete"] and visual["user_final_art_acceptance"] == "pending")
    check("reviewed images retain their actual bytes", len(visual["reviewed_files"]) >= 16 and not changed({r["file"]: r["sha256"] for r in visual["reviewed_files"]}))
    check("32 full-body keyframes and fourteen poses were represented", visual["fullbody_keyframes_reviewed"] == 32 and visual["final_pose_captures_represented"] == 14)

    docs = [ROOT / name for name in ("README.md", "ui-plan/README.md", "agent.md", "AGENTS.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md", "实施计划与验收基线.md", "docs/plans/2026-11-15-actor-posture-design.md")]
    parser = Links()
    page = EV / "review/index.html"
    parser.feed(page.read_text(encoding="utf-8"))
    links = [(page, t) for t in parser.targets]
    for doc in docs:
        text = doc.read_text(encoding="utf-8-sig")
        if doc.name != "2026-11-15-actor-posture-design.md":
            text = "\n".join(text.splitlines()[:5])
        links.extend((doc, t) for t in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text))
    broken = []
    for origin, target in links:
        parts = urlsplit(target)
        if parts.scheme or not parts.path:
            continue
        path = (origin.parent / unquote(parts.path)).resolve()
        if path != EV / "verification-summary.json" and not path.is_file():
            broken.append({"origin": rel(origin), "target": target})
    check("new review and document links resolve", not broken)
    scan_paths = [p for folder in (EV, ART, RAW) for p in folder.rglob("*") if p.suffix in (".json", ".txt", ".log", ".html")]
    scan_paths += list((ROOT / "tools").glob("*actor_posture*"))
    patterns = (re.compile(r"\bsk-[A-Za-z0-9_-]{24,}"), re.compile(r"\bBearer\s+[A-Za-z0-9_./+\-=]{24,}", re.I))
    credential_matches = [rel(p) for p in scan_paths if p.is_file() and p.suffix in (".json", ".txt", ".log", ".html", ".py", ".gd") and any(pattern.search(p.read_text(encoding="utf-8-sig", errors="replace")) for pattern in patterns)]
    check("new logs and tools contain no credential strings", not credential_matches)
    diff = subprocess.run(["git", "diff", "--check"], cwd=ROOT, capture_output=True)
    (EV / "git-diff-check.txt").write_bytes(diff.stdout + diff.stderr)
    check("git diff check passes", diff.returncode == 0)
    status = subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True)
    (EV / "git-status-final.txt").write_bytes(status.stdout)
    failures = [name for name, ok in checks.items() if not ok]
    totals = {k: len(report[k]) for k in ("checks", "commands", "screens", "frames", "fullbody_frames")}
    summary = {"date": "2026-11-15", "recorded_utc": datetime.now(timezone.utc).isoformat(), "passed": not failures, "checks": checks, "failures": failures,
               "scope": "P03 V9 head and neck posture, selected other characters preserved; opt-in battle pilot", "totals": totals,
               "runs": runs, "reused_full_regressions": reused,
               "protection": {"files": len(protected), "changes": protection_changes, "snapshot_issues": snapshot_issues, "before_zip_sha256": sha(EV / "before.zip")},
               "rebuild": {"files": len(assets), "exit_code": result.returncode, "byte_identical": before == after},
               "api": {"previous_successful": 28, "successful_this_revision": 1, "cumulative_successful": 29, "limit": 200, "remaining": 171, "billing": "Provider amount unknown"},
               "machine_audits": audits, "lower_body_pixels": pixels, "runtime_texture_hashes": references,
               "browser": {"passed": browser["passed"], "checks": len(browser["checks"]), "version": browser["browser"], "record": rel(EV / "review-browser-final/report.json")},
               "review_media_and_reports": len(media["inputs"]), "visual_review": rel(EV / "visual-review.json"), "user_final_art_acceptance": "pending",
               "broken_links": broken, "links_checked": len(links), "credential_scan": {"files": len(scan_paths), "matched_paths": credential_matches},
               "document_hashes": {rel(p): sha(p) for p in docs},
               "limitations": ["Final user art judgment pending.", "Existing local drawing crossfades can briefly ghost in slow motion, including the hit-to-neutral transition.", "The 12-degree value describes the local prototype before API refinement, not a measured final pixel angle.", "Only the P03 pilot, paired pose renders and browser were rerun; unchanged P02/P04 and full rules/UI captures are explicitly reused.", "Capture playback is not a real-time performance benchmark, complete 3D turnaround, or original G0/G6/G8 production acceptance."]}
    write(EV / "verification-summary.json", summary)
    print(json.dumps({"passed": not failures, "failures": failures, "protected_files": len(protected), "rebuild_identical": before == after, "totals": totals, "browser_checks": len(browser["checks"])}, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
