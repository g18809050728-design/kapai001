"""Audit the retained production-path evidence without rerunning gameplay."""
import hashlib
import json
from pathlib import Path
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-integration-20261115"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    checks = {}
    before = read(EV / "before.json")
    amendment = read(EV / "scope-amendment.json")
    amendment2 = read(EV / "scope-amendment-02.json")
    amended = {r["path"] for note in (amendment, amendment2) for r in note["additional_mutable_files"]}
    changes = [r["path"] for r in before["protected"] if r["path"] not in amended and digest(ROOT / r["path"]) != r["sha256"]]
    checks["unmodified historical assets tools domain and remaining tests"] = not changes
    with zipfile.ZipFile(EV / "before.zip") as archive:
        checks["thirteen original snapshots intact"] = all(hashlib.sha256(archive.read(r["path"])).hexdigest() == r["sha256"] for r in before["snapshotted"])
        plan = archive.read("实施计划与验收基线.md")
        marker = "### 0.20.24 ".encode()
        checks["previous plan history retains exact bytes"] = (ROOT / "实施计划与验收基线.md").read_bytes().endswith(plan[plan.index(marker):])
    with zipfile.ZipFile(EV / "supplement-before.zip") as archive:
        checks["additional timing-test snapshot intact"] = all(hashlib.sha256(archive.read(r["path"])).hexdigest() == r["sha256_before"] for r in amendment["additional_mutable_files"])
    with zipfile.ZipFile(EV / "timing-before.zip") as archive:
        checks["three additional timing-test snapshots intact"] = all(hashlib.sha256(archive.read(r["path"])).hexdigest() == r["sha256_before"] for r in amendment2["additional_mutable_files"])
    records = {}
    for name in ("art-render-01", "import-02", "game-final", "full-rules-01", "full-ui-final", "main-smoke-01", "semantic-contact-final"):
        record = read(EV / (name + ".run.json"))
        records[name] = {k: v for k, v in record.items() if not k.startswith("inputs")}
        checks[name + " actual command succeeds"] = record["exit_code"] == 0 and record["engine_errors"] == 0 and not record["unexpected_changes"]
        relevant = {p: sha for p, sha in record["inputs_after"].items() if p == "project.godot" or p.startswith(("src/", "data/", "assets/art/"))}
        checks[name + " production inputs still match"] = all((ROOT / p).is_file() and digest(ROOT / p) == sha for p, sha in relevant.items())
    game = read(EV / "game-final/report.json")
    checks["normal route used selected versions without pilot"] = game["versions"] == {"P01": 5, "P02": 8, "P03": 10, "P04": 11} and game["pilot_enabled"] is False and game["production_seed"] == "32"
    checks["engine checks and all real command comparisons pass"] = not game["failures"] and all(r["ok"] for r in game["checks"]) and all(c["equal"] and c["accepted"] for c in game["commands"])
    checks["all four characters have command evidence"] = {c["character"] for c in game["commands"]} == {"P01", "P02", "P03", "P04"}
    for screen in game["screens"]:
        with Image.open(EV / "game-final" / (screen["name"] + ".png")) as im:
            im.verify()
    for frame in game["frames"]:
        with Image.open(EV / "game-final" / frame["file"]) as im:
            im.verify()
    checks["all actual screenshots and command frames decode"] = True
    resources = read(EV / "resource-check.json")
    checks["selected resources have complete references and eight RGBA derivatives"] = not resources["missing_references"] and len(resources["images"]) == 8 and all(p["mode"] == "RGBA" and p["alpha"][0] == 0 and p["alpha"][1] == 255 for p in resources["images"])
    saves = read(EV / "real-save-preservation.json")
    checks["formal player save bytes unchanged during real main smoke"] = saves["unchanged"] and saves["exit_code"] == 0
    expected = [("P01", "assets/art/actor-anatomy/P01/rig.json", 5), ("P02", "assets/art/actor-proportions/P02/rig.json", 8), ("P03", "assets/art/actor-rebuild/P03/rig.json", 10), ("P04", "assets/art/actor-motion/P04/rig.json", 11)]
    selected = [{"character": c, "file": p, "version": v, "sha256": digest(ROOT / p)} for c, p, v in expected]
    for r in selected:
        checks[r["character"] + " exact selected resource remains"] = read(ROOT / r["file"])["version"] == r["version"]
    summary = {"passed": all(checks.values()), "checks": checks, "engine_checks": len(game["checks"]),
               "real_commands": len(game["commands"]), "actual_screenshots": len(game["screens"]),
               "actual_command_frames": len(game["frames"]), "protected_files": len(before["protected"]) - len(amended),
               "protected_changes": changes, "snapshots": len(before["snapshotted"]) + len(amended),
               "selected": selected, "runs": records, "api_new": 0, "api_cumulative": 38,
               "limitations": ["Local drawing variants can briefly change facing in slow motion.", "No export package or full-project G0/G6/G8 signoff is claimed.", "Historical pilot verifiers retain earlier default-mode expectations; explicit version launchers remain available."]}
    (EV / "verification-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("passed", "engine_checks", "real_commands", "actual_screenshots", "actual_command_frames", "protected_files", "snapshots")}, ensure_ascii=False))
    if not summary["passed"]:
        print(json.dumps({k: v for k, v in checks.items() if not v}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
