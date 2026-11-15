"""Check retained evidence for P04 motion correction without rerunning shared suites."""
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

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-motion-20261115"
ART = ROOT / "assets/art/actor-motion"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def changed(inputs):
    return [p for p, digest in inputs.items() if not (ROOT / p).is_file() or sha(ROOT / p) != digest]


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

    before = read(EV / "before.json")
    protection_changes = changed({r["path"]: r["sha256"] for r in before["protected"]})
    check("protected historical shared and selected files retain their exact bytes", not protection_changes and len(before["protected"]) == 572)
    with zipfile.ZipFile(EV / "before.zip") as archive:
        issues = [r["path"] for r in before["snapshotted"] if hashlib.sha256(archive.read(r["path"])).hexdigest() != r["sha256"]]
        old_plan = archive.read("实施计划与验收基线.md")
        marker = "### 0.20.23 ".encode()
        check("previous plan history retains its exact bytes", (ROOT / "实施计划与验收基线.md").read_bytes().endswith(old_plan[old_plan.index(marker):]))
    check("all eight before snapshots are intact", len(before["snapshotted"]) == 8 and not issues)

    resources = sorted(p for p in ART.rglob("*") if p.suffix in (".json", ".png"))
    resource_before = {rel(p): sha(p) for p in resources}
    if not (EV / "resources-final.zip").exists():
        with zipfile.ZipFile(EV / "resources-final.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in resources:
                archive.write(path, rel(path))
    command = [sys.executable, str(ROOT / "tools/build_actor_motion.py")]
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (EV / "rebuild-final.stdout.txt").write_bytes(result.stdout)
    (EV / "rebuild-final.stderr.txt").write_bytes(result.stderr)
    resource_after = {rel(p): sha(p) for p in resources}
    check("final resources rebuild byte identically", result.returncode == 0 and resource_before == resource_after)
    write(EV / "rebuild-final.json", {"command": command, "exit_code": result.returncode, "before": resource_before, "after": resource_after, "byte_identical": resource_before == resource_after})
    rig = read(ART / "P04/rig.json")
    old = read(ROOT / "assets/art/actor-proportions/P04/rig.json")
    check("V11 retains the painted neutral joints feet proportions and texture references", rig["version"] == 11 and rig["bones"] == old["bones"] and rig["feet"] == old["feet"] and rig["proportions"] == old["proportions"] and [p["file"] for p in rig["parts"]] == [p["file"] for p in old["parts"]])
    for role, family in (("P01", "actor-anatomy"), ("N01", "actor-anatomy"), ("P02", "actor-proportions"), ("P03", "actor-rebuild")):
        check(role + " preserves selected rig bytes", (ART / role / "rig.json").read_bytes() == (ROOT / "assets/art" / family / role / "rig.json").read_bytes())
    source = read(ART / "P04/source.json")
    check("all reused texture and base rig hashes match provenance", not changed({r["path"]: r["sha256"] for r in source["textures"] + [source["base_rig"]]}))
    check("no new API generation and cumulative count remains 38 of 200", source["new_api_images"] == 0 and source["api_successful_cumulative"] == 38)

    runs = {}
    for name in ("p04-final-02", "poses-final"):
        run = read(EV / (name + ".run.json"))
        check(name + " exits without engine errors and retains exact runtime inputs", run["exit_code"] == 0 and run["engine_errors"] == 0 and not changed(run["inputs"]) and not run["motion_inputs_changed_during_run"])
        runs[name] = {k: run[k] for k in ("command", "started_utc", "seconds", "exit_code", "engine_errors")}
    report = read(EV / "p04-final-02/report.json")
    check("all real engine checks pass", not report["failures"] and all(c["ok"] for c in report["checks"]))
    check("five actual commands match unanimated state events revision and RNG", len(report["commands"]) == 5 and all(c["equal"] for c in report["commands"]))
    check("all six motions have continuous joint and support samples", len(report["motion_chain"]["samples"]) == 606)
    probe = read(EV / "poses-final/probe.json")
    check("140 paired actual renderer poses saved successfully", len(probe["captures"]) == 140 and all(c["save_error"] == 0 and (EV / "poses-final" / c["file"]).is_file() for c in probe["captures"]))
    neutral_old = Image.open(EV / "poses-final/v8-neutral.png").convert("RGB")
    neutral_new = Image.open(EV / "poses-final/v11-neutral.png").convert("RGB")
    diff = ImageChops.difference(neutral_old, neutral_new)
    extrema = diff.getextrema()
    check("neutral renders differ only by mesh rounding", max(v[1] for v in extrema) <= 2)

    reused = {}
    for name in ("rules-01", "ui-01"):
        path = ROOT / "artifacts/verification/actor-party-20261115" / (name + ".run.json")
        run = read(path)
        shared = {k: v for k, v in run["inputs"].items() if k.startswith(("src/", "tests/", "data/")) or k == "project.godot"}
        check(name + " shared inputs match the previous passing regression", run["exit_code"] == 0 and run["engine_errors"] == 0 and not changed(shared))
        reused[name] = {"record": rel(path), "rerun_this_revision": False, "shared_hashes_verified": len(shared)}
    browser = read(EV / "review-browser-final/report.json")
    check("actual browser checks pass with exact review inputs", browser["passed"] and not changed(browser["inputs"]))
    manifest = read(EV / "review/manifest.json")
    check("all review media and original reports retain their recorded bytes", not changed(manifest["inputs"]) and manifest["default_character"] == "P04" and manifest["versions"] == ["v11", "v8"])
    parser = Links()
    parser.feed((EV / "review/index.html").read_text(encoding="utf-8"))
    broken = [target for target in parser.targets if not urlsplit(target).scheme and urlsplit(target).path and not (EV / "review" / unquote(urlsplit(target).path)).resolve().exists()]
    check("all static review links resolve", not broken)
    plan = ROOT / "docs/plans/2026-11-15-actor-motion-design.md"
    plan_links = re.findall(r"\]\(([^)]+)\)", plan.read_text(encoding="utf-8"))
    check("current design links resolve", all((plan.parent / p.split("#")[0]).resolve().exists() for p in plan_links if not urlsplit(p).scheme))
    visual = read(EV / "visual-review.json")
    check("AI rendered inspection and user judgment are recorded separately", visual["actual_images_inspected"] and visual["user_final_acceptance"] == "pending")
    attempts = read(EV / "attempts.json")
    check("intermediate parse and wrist checks are retained honestly", len(attempts["runs"]) >= 4 and attempts["final_run"] == "p04-final-02")

    summary = {"passed": all(checks.values()), "recorded_utc": datetime.now(timezone.utc).isoformat(), "checks": checks,
               "protected_files": len(before["protected"]), "protected_changes": protection_changes,
               "snapshotted_files": len(before["snapshotted"]), "new_resource_files": len(resources),
               "engine_checks": len(report["checks"]), "actual_commands": len(report["commands"]),
               "screens": len(report["screens"]), "battle_frames": len(report["frames"]), "fullbody_frames": len(report["fullbody_frames"]),
               "probe_renders": len(probe["captures"]), "browser_checks": len(browser["checks"]),
               "neutral_max_channel_delta": max(v[1] for v in extrema),
               "motion_chain": {k: v for k, v in report["motion_chain"].items() if k != "samples"},
               "runs": runs, "shared_regressions_reused": reused, "broken_links": broken,
               "api_successful_this_revision": 0, "api_successful_cumulative": 38,
               "limits": ["2D joint and support proxy checks are not physical simulation", "hand facing still changes through local drawing variants in slow motion", "user final motion judgment pending", "original G0 G6 G8 exits remain open"]}
    write(EV / "verification-summary.json", summary)
    print(json.dumps({"passed": summary["passed"], "checks": len(checks), "failures": [k for k, v in checks.items() if not v], "protected": len(before["protected"])}, ensure_ascii=False))
    if not summary["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
