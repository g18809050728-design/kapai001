"""Retain density followup evidence without rewriting first-batch reports."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), "-c", "core.quotepath=false", *args], encoding="utf-8", stderr=subprocess.PIPE)


def links(source):
    result = set()
    for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", source):
        target = match[1].strip("<>")
        if not re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) and not target.startswith("#"):
            result.add(unquote(target.split("#", 1)[0]))
    return result


def main():
    state_path = ROOT / "docs/baselines/current-state.json"
    backup = OUT / "observed-state-before.json"
    if not backup.exists():
        backup.write_bytes(state_path.read_bytes())
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state["annual_maps"].update(map_version=2, supported_map_versions=[1, 2],
        initial_exits=3, middle_layer_width=[3, 5], minimum_dense_middle_layer_fraction=0.5,
        legacy_algorithm="annual_map_generator_v1.gd; original seed domain and frozen maps preserved")
    changed = set(git("diff", "--name-only", "HEAD").splitlines())
    changed.update(git("ls-files", "--others", "--exclude-standard").splitlines())
    for relative in sorted(changed | set(state["source_sha256"])):
        path = ROOT / relative
        if path.is_file() and relative != "docs/baselines/current-state.json" and (
            relative.endswith((".gd", ".py", ".md")) and not relative.startswith("artifacts/")
        ):
            state["source_sha256"][relative] = sha(path)
    issues = []
    proofs = {}
    for label in ["density-import", "density-rules", "density-ui-final", "density-visual"]:
        path = OUT.parent / label / "summary.json"
        if not path.exists():
            issues.append("Missing verification: " + label)
            continue
        proof = json.loads(path.read_text(encoding="utf-8"))
        proofs[label] = proof
        if any(row["exit_code"] or row["engine_errors"] for row in proof):
            issues.append("Verification failed: " + label)
        state["evidence"][label] = path.relative_to(ROOT).as_posix()
    before = (OUT / "annual-map-generator-before.txt").read_text(encoding="utf-8")
    legacy = (ROOT / "src/run/annual_map_generator_v1.gd").read_text(encoding="utf-8")
    same = before == legacy.replace("class_name AnnualMapGeneratorV1", "class_name AnnualMapGenerator", 1)
    if not same:
        issues.append("Legacy generator changed beyond its class name")
    new_links = []
    for relative in sorted(changed):
        path = ROOT / relative
        if not relative.endswith(".md") or not path.is_file():
            continue
        old = subprocess.run(["git", "-C", str(ROOT), "show", "HEAD:" + relative], capture_output=True, encoding="utf-8")
        prior = links(old.stdout) if old.returncode == 0 else set()
        for target in sorted(links(path.read_text(encoding="utf-8-sig")) - prior):
            new_links.append({"document": relative, "target": target})
            if target and not (path.parent / target).exists() and (path.parent / target).resolve() != (OUT / "doc-audit.json").resolve():
                issues.append("Missing new link: " + relative + " -> " + target)
    capture_root = OUT.parent / "density-visual-png"
    capture = json.loads((capture_root / "capture.json").read_text(encoding="utf-8"))
    if capture["failures"] or len(capture["screenshots"]) != 168:
        issues.append("Final real-renderer capture count or checks differ from expected168")
    for relative, expected in capture["inputs"].items():
        if sha(ROOT / relative) != expected:
            issues.append("Rendered source changed since final capture: " + relative)
    for shot in capture["screenshots"]:
        if not (capture_root / shot["file"]).is_file():
            issues.append("Missing captured PNG: " + shot["file"])
    reviewed = ["seed42-y1-first-fork-1280x800-text100-selected.png",
        "seed7-y1-first-fork-960x600-text150-selected.png",
        "seed7-y3-middle-1280x800-text125-selected.png",
        "seed42-y4-annual-960x600-text150-overview.png"]
    (OUT / "visual-review.json").write_text(json.dumps(dict(
        reviewer="Codex model visual inspection; not human art acceptance",
        screenshots={name: sha(capture_root / name) for name in reviewed},
        observations=["three initial exits and downstream sustained branches visible",
            "small window150percent retains two full node rows and scrollable forecast",
            "labels remain clear of curved routes; current/available/completed/unreachable distinguishable",
            "year4overview fits small window at150percent"],
        captured_sources_match_current=all(sha(ROOT / path) == expected for path, expected in capture["inputs"].items())), ensure_ascii=False, indent=2), encoding="utf-8")
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = dict(utc=datetime.now(timezone.utc).isoformat(), issues=issues, exit_code=int(bool(issues)),
        scope="FY-MAP-007 incremental acceptance; historical missing links remain outside this audit",
        legacy_source_equal_except_class_name=same, legacy_before_sha256=sha(OUT / "annual-map-generator-before.txt"),
        legacy_source_sha256=sha(ROOT / "src/run/annual_map_generator_v1.gd"),
        proofs=proofs, new_links=new_links, observed_snapshot_sha256=sha(state_path))
    (OUT / "doc-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "git-status.txt").write_text(git("status", "--short"), encoding="utf-8")
    print(json.dumps({key: report[key] for key in ["exit_code", "issues", "legacy_source_equal_except_class_name"]}, ensure_ascii=False))
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
