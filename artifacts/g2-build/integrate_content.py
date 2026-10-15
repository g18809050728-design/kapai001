"""Merge frozen G2 staging, load the whole candidate, then publish its data files."""

from __future__ import annotations

import hashlib
import json
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.prepare_g2_data import kind_file, make_manifest, write_json


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    staging = ROOT / "artifacts/g2-build/staging"
    baseline = read(ROOT / "docs/baselines/g0.json")
    candidate = ROOT / ".godot/g2_full_candidate"
    evidence = ROOT / "artifacts/verification" / datetime.now().strftime("g2-integration-%Y%m%d-%H%M%S-%f")
    evidence.mkdir(parents=True)
    definitions = {
        kind: read(ROOT / f"data/definitions/{kind_file(kind)}.json")
        for kind in baseline["scope"]["enabled_by_kind"]
    }
    additions = [("card", row) for row in read(staging / "cards/cards.json")]
    for batch in ["entities", "flow"]:
        for path in sorted((staging / batch / "definitions").glob("*.json")):
            entry = read(path)
            additions.append((entry["kind"], entry["definition"]))
    for kind, row in additions:
        existing = next((item for item in definitions[kind] if item["id"] == row["id"]), None)
        if existing is not None:
            if existing != row:
                raise ValueError(f"Conflicting definition {kind}/{row['id']}")
        else:
            definitions[kind].append(row)
    for kind, ids in baseline["scope"]["enabled_by_kind"].items():
        rows = definitions[kind]
        if len(rows) != len(ids) or {row["id"] for row in rows} != set(ids):
            raise ValueError(f"Incomplete or unexpected G0 scope: {kind}")
        by_id = {row["id"]: row for row in rows}
        write_json(candidate / f"definitions/{kind_file(kind)}.json", [by_id[id_] for id_ in ids])
    manifest, deferred = make_manifest(baseline, candidate / "definitions")
    write_json(candidate / "manifests/campus_mvp.json", manifest)
    write_json(candidate / "manifests/content_deferred.json", deferred)
    godot = Path("F:/GoDot/Godot_v4.7.2-stable_win64_console.exe")
    command = [str(godot), "--headless", "--path", str(ROOT), "--script", "res://artifacts/g2-build/load_candidate.gd"]
    write_json(evidence / "command.json", command)
    write_json(evidence / "environment.json", {"python": sys.version, "os": platform.platform(), "engine": subprocess.check_output([str(godot), "--version"], text=True).strip(), "cwd": str(ROOT)})
    inputs = [ROOT / "docs/baselines/g0.json", Path(__file__), ROOT / "artifacts/g2-build/load_candidate.gd", ROOT / "tools/prepare_g2_data.py", ROOT / "src/content/content_db.gd", *sorted(candidate.rglob("*.json"))]
    write_json(evidence / "inputs.json", {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
    result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace")
    (evidence / "stdout.txt").write_text(result.stdout, encoding="utf-8")
    (evidence / "stderr.txt").write_text(result.stderr, encoding="utf-8")
    (evidence / "exit_code.txt").write_text(str(result.returncode) + "\n", encoding="utf-8")
    print(result.stdout)
    if result.returncode or "G2_FULL_PACKAGE_LOAD_OK" not in result.stdout or any(marker in result.stderr for marker in ["SCRIPT ERROR", "Parse Error"]):
        print(result.stderr)
        print(f"Candidate rejected; production unchanged. Evidence: {evidence}")
        return 1
    for path in sorted(candidate.rglob("*.json")):
        relative = path.relative_to(candidate)
        destination = ROOT / "data" / relative
        if destination.exists():
            backup = evidence / "before" / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(destination, backup)
        shutil.copy2(path, destination)
    write_json(evidence / "report.json", {"stage": "G2 candidate integration", "status": "passed", "added_ids": len(additions), "enabled_ids": sum(map(len, manifest["enabled"].values())), "holdback_ids": sum(map(len, deferred["manifest_holdback"].values())), "production_published": True, "behavior_acceptance": "G3/G4"})
    print(f"PRODUCTION_PUBLISHED enabled={sum(map(len, manifest['enabled'].values()))} holdback=0")
    print(f"Evidence: {evidence}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
