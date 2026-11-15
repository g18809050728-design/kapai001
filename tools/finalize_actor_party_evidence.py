"""Audit the final prototype against real runs and the preserved workspace baseline."""
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-party-20261115"
ART = ROOT / "assets/art/actor-party"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def relative(path):
    return path.relative_to(ROOT).as_posix()


def hashes(paths):
    return {relative(path): sha(path) for path in paths}


def changed(records):
    return [name for name, digest in records.items() if not (ROOT / name).is_file() or sha(ROOT / name) != digest]


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        self.targets.extend(value for key, value in attrs if key in ["src", "href"] and value)


def main():
    failures = []

    def check(name, condition):
        if not condition:
            failures.append(name)

    baseline = read(EV / "before.json")
    protection = {item["path"]: item["sha256"] for item in baseline["protected"]}
    protection_changes = changed(protection)
    check("1155 protected files preserve original bytes", not protection_changes and len(protection) == 1155)
    with zipfile.ZipFile(EV / "before.zip") as archive:
        bad_snapshot = [item["path"] for item in baseline["snapshotted"] if hashlib.sha256(archive.read(item["path"])).hexdigest() != item["sha256"]]
    check("before.zip matches original snapshots", not bad_snapshot)
    unchanged_shared = {item["path"]: item["sha256"] for item in baseline["snapshotted"] if item["path"].startswith(("src/", "tools/")) or item["path"] == "project.godot"}
    check("shared runtime, old tools and production entry unchanged", not changed(unchanged_shared))

    asset_paths = sorted(p for p in ART.rglob("*") if p.suffix in [".png", ".json"])
    asset_before = hashes(asset_paths)
    archive_path = EV / "resource-final.zip"
    if not archive_path.exists():
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in asset_paths:
                archive.write(path, relative(path))
    command = [sys.executable, str(ROOT / "tools/build_actor_party.py")]
    started = time.perf_counter()
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild-final.stdout.txt").write_bytes(result.stdout)
    (EV / "rebuild-final.stderr.txt").write_bytes(result.stderr)
    asset_after = hashes(sorted(p for p in ART.rglob("*") if p.suffix in [".png", ".json"]))
    rebuilt_equal = result.returncode == 0 and asset_before == asset_after
    check("rebuilding reproduces exact PNG and JSON bytes", rebuilt_equal)
    rebuild = {"command": command, "seconds": time.perf_counter() - started, "exit_code": result.returncode, "files": len(asset_before), "byte_identical": rebuilt_equal, "before": asset_before, "after": asset_after}
    write(EV / "rebuild-final.json", rebuild)

    manifest_path = ROOT / "output/imagegen/actor-party-20261115/asset-manifest.json"
    manifest = read(manifest_path)
    api_sources, source_issues = {}, []
    for item in manifest["assets"]:
        expected = [(item["output"], item["sha256"]), (item["prompt_file"], item["prompt_sha256"])]
        expected.extend((source["file"], source["sha256"]) for source in item["input_images"])
        for name, digest in expected:
            if not (ROOT / name).is_file() or sha(ROOT / name) != digest:
                source_issues.append(name)
            else:
                api_sources[name] = digest
        for key in ["run_record", "api_log"]:
            check(item["asset_id"] + " " + key + " exists", (ROOT / item[key]).is_file())
    check("all prompts, uploaded references and output images match hashes", not source_issues)
    check("API count reconciles with authorized budget", len(manifest["assets"]) == manifest["successful_this_batch"] == 12 and manifest["previous_successful"] == 15 and manifest["cumulative_successful"] == 27 <= manifest["limit"] == 200)

    resource_references, texture_issues = {}, []
    for role in ["P02", "P03", "P04"]:
        source = read(ART / role / "source.json")
        for texture in source["textures"]:
            name = texture["file"]
            if sha(ROOT / name) != texture["sha256"]:
                texture_issues.append(name)
        rig = read(ART / role / "rig.json")

        def collect(value):
            if isinstance(value, dict):
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
            elif isinstance(value, str) and value.startswith("res://"):
                path = ROOT / value.removeprefix("res://")
                check("resource reference exists: " + value, path.is_file())
                if path.is_file():
                    resource_references[relative(path)] = sha(path)

        collect(rig)
    check("registered texture provenance matches actual runtime images", not texture_issues)
    for role in ["P01", "N01"]:
        check(role + " selected old rig copied verbatim", (ART / role / "rig.json").read_bytes() == (ROOT / "assets/art/actor-anatomy" / role / "rig.json").read_bytes())

    audits = {}
    for name, folder, total in [("master-audit-final", EV, 3), ("sheet-audit-final", EV, 3), ("trunk-audit-final", manifest_path.parent, 3), ("upper-audit-final", manifest_path.parent, 3), ("derived-audit-final", EV, 72)]:
        audit = read(folder / (name + ".json"))
        check(name + " passes actual machine inspection", audit["status"] == "passed" and audit["total"] == total and audit["failed"] == 0 and audit["duplicates"] == 0)
        check(name + " still matches inspected files", all(sha(Path(item["path"])) == item["sha256"] for item in audit["images"]))
        audits[name] = {key: audit[key] for key in ["status", "total", "failed", "duplicates", "require_alpha"]}

    runs, characters = {}, {}
    ignore_unused_party = lambda key: key.startswith("assets/art/actor-party/") or key in ["tools/build_actor_party.py", "tools/run_actor_party_pilot.gd", "tools/render_actor_party_probe.gd", "tools/start_actor_party.ps1", "tools/verify_actor_party.py"]
    for name in ["p02-final", "p03-final", "p04-final", "selected-v5-compat", "rules-01", "ui-01", "import-final", "pose-probe-final"]:
        run = read(EV / (name + ".run.json"))
        drift = changed(run["inputs"])
        unused = [key for key in drift if name in ["rules-01", "ui-01"] and ignore_unused_party(key)]
        used_drift = [key for key in drift if key not in unused]
        check(name + " succeeded without engine errors", run["exit_code"] == 0 and run["engine_errors"] == 0)
        check(name + " actual tested inputs unchanged", not used_drift)
        runs[name] = {key: value for key, value in run.items() if key != "inputs"}
        runs[name].update(record=relative(EV / (name + ".run.json")), actual_input_changes=used_drift, changed_unused_experimental_inputs=unused)
        if name in ["p02-final", "p03-final", "p04-final", "selected-v5-compat"]:
            report = read(EV / name / "report.json")
            check(name + " all explicit checks pass", not report["failures"] and all(c["ok"] for c in report["checks"]))
            check(name + " real commands match nonanimated control", all(c["equal"] for c in report["commands"]))
            if name != "selected-v5-compat":
                geometry = {key: value for key, value in report["anatomy_geometry"].items() if key not in ["samples", "scope"]}
                frame_state = [f["state"] for f in report["fullbody_frames"]]
                characters[report["character"]] = {"checks": len(report["checks"]), "commands": len(report["commands"]), "static_png": len(report["screens"]), "battle_frames": len(report["frames"]), "fullbody_frames": len(report["fullbody_frames"]), "geometry": geometry, "max_captured_prop_contact_error": max(s["held_contact_error"] for s in frame_state)}

    browser = read(EV / "review-browser/report.json")
    check("actual offline browser checks pass without console/media errors", browser["passed"] and all(browser["checks"].values()) and not browser["errors"] and not browser["failed_requests"])
    check("browser tested page, template and scripts unchanged", not changed(browser["inputs"]))
    review = read(EV / "review/manifest.json")
    check("review media and reports match final rendered runs", not changed(review["inputs"]))
    visual = read(EV / "visual-review.json")
    check("AI visual review is separately recorded", visual["ai_review_complete"] and visual["user_final_art_acceptance"] == "pending")

    html = EV / "review/index.html"
    parser = Links()
    parser.feed(html.read_text(encoding="utf-8"))
    links = [(html, target) for target in parser.targets]
    docs = [ROOT / "docs/plans/2026-11-15-actor-party-design.md", ROOT / "README.md", ROOT / "ui-plan/README.md", ROOT / "agent.md", ROOT / "AGENTS.md", ROOT / "docs/界面层契约.md", ROOT / "动作或者图片描述/需求台账.md", ROOT / "实施计划与验收基线.md"]
    for doc in docs:
        text = doc.read_text(encoding="utf-8-sig")
        if doc.name != "2026-11-15-actor-party-design.md":
            text = "\n".join(text.splitlines()[:5])
        links.extend((doc, target) for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text))
    broken = []
    for origin, target in links:
        parts = urlsplit(target)
        if parts.scheme or not parts.path:
            continue
        path = (origin.parent / unquote(parts.path)).resolve()
        if path != EV / "verification-summary.json" and not path.is_file():
            broken.append({"origin": relative(origin), "target": target})
    check("new document and review links resolve", not broken)

    scan_paths = [p for base in [manifest_path.parent, ART, EV] for p in base.rglob("*") if p.suffix in [".json", ".txt", ".log", ".html", ".py", ".cjs"]]
    scan_paths += [ROOT / name for name in ["tools/build_actor_party.py", "tools/run_actor_party_pilot.gd", "tools/render_actor_party_probe.gd", "tools/verify_actor_party.py", "tools/start_actor_party.ps1", "tools/build_actor_party_review.py", "tools/verify_actor_party_review.py", "tools/actor_party_review.html", "tools/finalize_actor_party_evidence.py"]]
    patterns = [re.compile(r"\bsk-[A-Za-z0-9_-]{24,}"), re.compile(r"\bBearer\s+[A-Za-z0-9_./+\-=]{24,}", re.I)]
    secret_paths = [relative(path) for path in scan_paths if any(pattern.search(path.read_text(encoding="utf-8-sig", errors="replace")) for pattern in patterns)]
    check("new assets, prompts, logs and tools contain no credential strings", not secret_paths)

    summary = {"date": "2026-11-15", "recorded_utc": datetime.now(timezone.utc).isoformat(), "passed": not failures, "failures": failures,
               "scope": "P02/P03/P04 opt-in native 2D prototype; final user visual acceptance pending",
               "characters": characters, "runs": runs, "api": {key: manifest[key] for key in ["previous_successful", "successful_this_batch", "cumulative_successful", "remaining", "limit", "billing"]},
               "protection": {"files": len(protection), "changes": protection_changes, "shared_runtime_changes": changed(unchanged_shared), "before_zip_sha256": sha(EV / "before.zip"), "bad_snapshot_entries": bad_snapshot},
               "rebuild": {key: value for key, value in rebuild.items() if key not in ["before", "after"]},
               "source_hashes": api_sources, "runtime_texture_hashes": resource_references, "machine_audits": audits,
               "browser": {"passed": browser["passed"], "checks": len(browser["checks"]), "engine": browser["browser"], "errors": browser["errors"], "media_errors": browser["failed_requests"]},
               "optional_skill_smoke": read(EV / "review-browser/skill-environment.json"),
               "visual_review": relative(EV / "visual-review.json"), "review_media_and_reports": len(review["inputs"]), "local_links_checked": len(links), "broken_links": broken,
               "credential_scan": {"files": len(scan_paths), "matched_paths": secret_paths},
               "document_hashes": hashes(docs), "finalizer_sha256": sha(Path(__file__)),
               "limitations": ["Each character's common play/end-turn battle was compared with an animation-free control; dedicated complete playthroughs of every character-specific mechanic were not performed.", "Time-stamped image capture is not a realtime performance benchmark.", "Large-view sleeve perspective and minor texture joins can receive further art adjustment; no full 3D rotation is supplied.", "Construction-time pending_rendered_review fields in preserved rig/source files are superseded for this delivery by visual-review.json; user final art acceptance remains pending.", "No complete G0/G6/G8 production, licensing, performance or packaging acceptance is claimed."]}
    write(EV / "verification-summary.json", summary)
    print(json.dumps({"passed": summary["passed"], "failures": failures, "protected": len(protection), "rebuild_identical": rebuilt_equal, "characters": {role: {k: v for k, v in data.items() if k != "geometry"} for role, data in characters.items()}, "browser_checks": len(browser["checks"])}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
