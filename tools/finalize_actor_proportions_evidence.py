"""Audit version 8 against actual engine/browser runs and preserved inputs."""
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile
from urllib.parse import unquote, urlsplit

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-proportions-20261115"
OLD = ROOT / "artifacts/verification/actor-party-20261115"
ART = ROOT / "assets/art/actor-proportions"


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
    failures = []

    def check(name, condition):
        if not condition:
            failures.append(name)

    baseline = read(EV / "before.json")
    protected = {r["path"]: r["sha256"] for r in baseline["protected"]}
    protection_changes = changed(protected)
    check("all 421 protected files retain their original bytes", len(protected) == 421 and not protection_changes)
    with zipfile.ZipFile(EV / "before.zip") as archive:
        snapshot_issues = [r["path"] for r in baseline["snapshotted"] if hashlib.sha256(archive.read(r["path"])).hexdigest() != r["sha256"]]
    check("before.zip retains all eight original snapshots", len(baseline["snapshotted"]) == 8 and not snapshot_issues)

    assets = sorted(p for p in ART.rglob("*") if p.suffix in (".json", ".png"))
    before = {rel(p): sha(p) for p in assets}
    archive_path = EV / "resources-final.zip"
    if not archive_path.exists():
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in assets:
                archive.write(path, rel(path))
    command = [sys.executable, str(ROOT / "tools/build_actor_proportions.py")]
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild-final.stdout.txt").write_bytes(result.stdout)
    (EV / "rebuild-final.stderr.txt").write_bytes(result.stderr)
    after = {rel(p): sha(p) for p in assets}
    check("all final PNG/JSON files rebuild byte identically", result.returncode == 0 and before == after)
    write(EV / "rebuild-final.json", {"command": command, "exit_code": result.returncode, "byte_identical": before == after, "before": before, "after": after})

    references = {}
    for role in ("P02", "P03", "P04"):
        rig = read(ART / role / "rig.json")
        source = read(ART / role / "source.json")
        check(role + " has actual version 8 proportion registration", rig["version"] == 8 and rig["proportions"]["vertical_leg_scale"] == .78)
        check(role + " has 27 bones, 14 parts and six weighted meshes", len(rig["bones"]) == 27 and len(rig["parts"]) == 14 and sum(bool(p.get("mesh")) for p in rig["parts"]) == 6)
        for texture in source["textures"]:
            references[texture["file"]] = texture["sha256"]
        check(role + " runtime texture source hashes agree", not changed({t["file"]: t["sha256"] for t in source["textures"]}))
        for prefix in ("rear", "front"):
            part = next(p for p in rig["parts"] if p["id"] == prefix + "_shoe")
            new = Image.open(ROOT / part["file"].removeprefix("res://")).convert("RGBA")
            old = Image.open(ROOT / "assets/art/actor-party" / role / Path(part["file"]).name).convert("RGBA")
            check(role + " " + prefix + " shoe preserves exact dimensions and pixels", new.size == old.size and new.tobytes() == old.tobytes())
    for role in ("P01", "N01"):
        check(role + " selected historical rig copied verbatim", (ART / role / "rig.json").read_bytes() == (ROOT / "assets/art/actor-anatomy" / role / "rig.json").read_bytes())
    extraction = read(EV / "extraction.json")
    check("all 57 emitted textures have exact source/output provenance", len([r for r in extraction["outputs"] if "file" in r]) == 57 and all(sha(ROOT / r["file"]) == r["sha256"] and sha(ROOT / r["source"]) == r["source_sha256"] for r in extraction["outputs"] if "file" in r))

    request = read(ROOT / "output/imagegen/actor-proportions-20261115/neck-request.json")
    api_sources = {request["prompt_file"]: request["prompt_file_sha256"], request["output"]: request["output_sha256"]}
    api_sources.update({r["file"]: r["sha256"] for r in request["input_images"]})
    prompt_text = (ROOT / request["prompt_file"]).read_text(encoding="utf-8-sig")
    check("original prompt text hash agrees after explicit newline normalization", hashlib.sha256(prompt_text.encode("utf-8")).hexdigest() == request["prompt_sha256"])
    check("uploaded images, prompt and generated original retain exact hashes", not changed(api_sources))
    api_run = read(ROOT / "output/imagegen/actor-proportions-20261115/p03-neck-v1-run.json")
    check("one authorized edit completed with the configured model", api_run["exit_code"] == 0 and api_run["mode"] == "edit" and api_run["model"] == "gpt-image-2.5-sunburst")
    check("API count stays within user authorization", request["previous_api_successful"] == 27 and request["new_api_successful"] == 1 and request["cumulative_api_successful"] == 28 <= request["api_limit"] == 200)
    audits = {}
    for name, total in (("asset-audit-final", 57), ("raw-audit", 1)):
        audit = read(EV / (name + ".json"))
        check(name + " passes real file checks", audit["status"] == "passed" and audit["total"] == total and audit["failed"] == 0 and audit["duplicates"] == 0)
        check(name + " inspected the current exact files", all(sha(Path(r["path"])) == r["sha256"] for r in audit["images"]))
        audits[name] = {k: audit[k] for k in ("status", "total", "failed", "duplicates", "require_alpha")}

    runs, characters = {}, {}
    for name in ("p02-final", "p03-final", "p04-final", "selected-v5-compat", "all-poses-final"):
        run = read(EV / (name + ".run.json"))
        role = {"p02-final": "P02", "p03-final": "P03", "p04-final": "P04", "selected-v5-compat": "P01"}.get(name)
        drift = changed(run["inputs"])
        # P03 was refined after the P02/P04 captures. Neither other role loads
        # that resource. Build/probe tools are not executed by the live pilot.
        unused = [key for key in drift if role and (
            key in ("tools/build_actor_proportions.py", "tools/render_actor_proportions_probe.gd")
            or (key.startswith("assets/art/actor-proportions/") and key.split("/")[3] not in (role, "N01")))]
        effective = [key for key in drift if key not in unused]
        check(name + " succeeded without engine errors", run["exit_code"] == 0 and run["engine_errors"] == 0)
        check(name + " actual runtime inputs remain unchanged", not effective)
        runs[name] = {k: v for k, v in run.items() if k != "inputs"}
        runs[name].update(record=rel(EV / (name + ".run.json")), effective_input_changes=effective, unused_other_character_or_build_input_changes=unused)
        if role:
            report = read(EV / name / "report.json")
            check(name + " all explicit checks pass", not report["failures"] and all(c["ok"] for c in report["checks"]))
            check(name + " published commands equal the nonanimated control", all(c["equal"] for c in report["commands"]))
            if role != "P01":
                characters[role] = {k: len(report[k]) for k in ("checks", "commands", "screens", "frames", "fullbody_frames")}
                characters[role]["geometry"] = {k: v for k, v in report["anatomy_geometry"].items() if k not in ("samples", "scope")}
    probe = read(EV / "all-poses-final/probe.json")
    check("all three characters have actual neutral and six-action inspection renders", len(probe["captures"]) == 21 and all(c["save_error"] == 0 for c in probe["captures"]))
    reused = {}
    for name in ("rules-01", "ui-01"):
        run = read(OLD / (name + ".run.json"))
        runtime_inputs = {k: v for k, v in run["inputs"].items() if k.startswith(("src/", "tests/", "data/")) or k == "project.godot"}
        check(name + " prior full regression still matches shared runtime", run["exit_code"] == 0 and run["engine_errors"] == 0 and not changed(runtime_inputs))
        reused[name] = {"record": rel(OLD / (name + ".run.json")), "rerun_this_revision": False,
                        "shared_runtime_input_hashes_checked": len(runtime_inputs), "shared_runtime_changes": changed(runtime_inputs),
                        "reason": "Shared src/data/tests and production entry unchanged; this revision reruns the three actor pilots and real commands."}

    browser = read(EV / "review-browser/report.json")
    check("63 actual offline browser checks pass", browser["passed"] and len(browser["checks"]) == 63 and all(browser["checks"].values()) and not browser["errors"] and not browser["failed_requests"])
    check("browser tested current exact page and tools", not changed(browser["inputs"]))
    media = read(EV / "review/manifest.json")
    check("both review versions reference exact real reports and media", not changed(media["inputs"]))
    visual = read(EV / "visual-review.json")
    check("AI actual image review and user acceptance remain distinct", visual["ai_review_complete"] and visual["user_final_art_acceptance"] == "pending")
    observations = {r["file"]: r["sha256"] for r in visual["reviewed_files"]}
    check("actual reviewed images retain their recorded bytes", len(observations) >= 16 and not changed(observations))
    check("visual observations include 96 full-body frames and 21 final poses", visual["fullbody_keyframes_reviewed"] == 96 and visual["final_pose_captures_represented"] == 21)

    docs = [ROOT / name for name in ("docs/plans/2026-11-15-actor-proportions-design.md", "README.md", "ui-plan/README.md", "agent.md", "AGENTS.md", "docs/界面层契约.md", "动作或者图片描述/需求台账.md", "实施计划与验收基线.md")]
    page = EV / "review/index.html"
    parser = Links()
    parser.feed(page.read_text(encoding="utf-8"))
    links = [(page, target) for target in parser.targets]
    for doc in docs:
        text = doc.read_text(encoding="utf-8-sig")
        if doc.name != "2026-11-15-actor-proportions-design.md":
            text = "\n".join(text.splitlines()[:5])
        links.extend((doc, target) for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text))
    broken = []
    for origin, target in links:
        parts = urlsplit(target)
        if parts.scheme or not parts.path:
            continue
        path = (origin.parent / unquote(parts.path)).resolve()
        if path != EV / "verification-summary.json" and not path.is_file():
            broken.append({"origin": rel(origin), "target": target})
    check("new entry/document/media links resolve", not broken)
    scan_paths = [p for folder in (EV, ART, ROOT / "output/imagegen/actor-proportions-20261115") for p in folder.rglob("*") if p.suffix in (".json", ".txt", ".log", ".html")]
    scan_paths += list((ROOT / "tools").glob("*actor_proportions*"))
    patterns = (re.compile(r"\bsk-[A-Za-z0-9_-]{24,}"), re.compile(r"\bBearer\s+[A-Za-z0-9_./+\-=]{24,}", re.I))
    credential_matches = [rel(p) for p in scan_paths if p.is_file() and p.suffix in (".json", ".txt", ".log", ".html", ".py", ".gd") and any(pattern.search(p.read_text(encoding="utf-8-sig", errors="replace")) for pattern in patterns)]
    check("new assets, logs and tools contain no credential strings", not credential_matches)

    summary = {"date": "2026-11-15", "recorded_utc": datetime.now(timezone.utc).isoformat(), "passed": not failures, "failures": failures,
               "scope": "Version 8: three protagonists' leg proportions and P03 continuous neck correction; opt-in pilot only",
               "characters": characters, "runs": runs, "reused_full_regressions": reused,
               "totals": {k: sum(c[k] for c in characters.values()) for k in ("checks", "commands", "screens", "frames", "fullbody_frames")},
               "api": {"previous_successful": 27, "successful_this_revision": 1, "cumulative_successful": 28, "limit": 200, "remaining": 172, "model": api_run["model"], "mode": "edit", "billing": "Provider billing not queried; amount unknown"},
               "protection": {"files": len(protected), "changes": protection_changes, "before_zip_sha256": sha(EV / "before.zip"), "snapshot_issues": snapshot_issues},
               "rebuild": {"exit_code": result.returncode, "files": len(assets), "byte_identical": before == after},
               "machine_audits": audits, "source_hashes": api_sources, "runtime_texture_hashes": references,
               "browser": {"passed": browser["passed"], "checks": len(browser["checks"]), "version": browser["browser"]},
               "visual_review": rel(EV / "visual-review.json"), "review_media_and_reports": len(media["inputs"]),
               "links_checked": len(links), "broken_links": broken, "credential_scan": {"files": len(scan_paths), "matched_paths": credential_matches},
               "document_hashes": {rel(p): sha(p) for p in docs},
               "limitations": ["Final user art acceptance pending.", "Existing sleeve/forearm drawing crossfades can show brief transition ghosts in slow motion; no scope expansion into a new animation system.", "Captured playback is not a real-time performance benchmark or a full 3D turnaround.", "Shared full rules/UI suites were reused by input hashes; three actor pilots, commands, 21 poses and browser checks were run this revision.", "No complete G0/G6/G8 production, licensing, balance or packaging acceptance is claimed."]}
    write(EV / "verification-summary.json", summary)
    print(json.dumps({"passed": summary["passed"], "failures": failures, "protected_files": len(protected), "rebuild_identical": before == after, "totals": summary["totals"], "browser_checks": len(browser["checks"])}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
