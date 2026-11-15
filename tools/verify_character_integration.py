"""Retain exact inputs, command, environment and unmodified engine logs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "artifacts/verification/actor-integration-20261115"
ENGINE = Path(os.environ.get("GODOT_BIN", "F:/GoDot/Godot_v4.7.2-stable_win64_console.exe"))


def inputs():
    paths = [ROOT / "project.godot"]
    for directory in ("src", "data", "tests", "assets/art/characters"):
        paths.extend(p for p in (ROOT / directory).rglob("*") if p.suffix in (".gd", ".gdshader", ".tscn", ".json", ".png"))
    paths.extend(p for p in (ROOT / "assets/art").glob("actor-*/*/*") if p.suffix in (".json", ".png"))
    paths.extend(ROOT / "tools" / name for name in ("render_character_art.gd", "verify_character_integration.py", "run_character_integration.gd", "run_actor_rig_pilot.gd", "verify_character_contact.gd"))
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths)) if p.is_file()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    prefix = EVIDENCE / args.name
    record_path = prefix.with_suffix(".run.json")
    if record_path.exists():
        raise SystemExit("Evidence exists: use a fresh run name")
    before = inputs()
    command = [str(ENGINE), "--path", str(ROOT), *arguments]
    start = time.perf_counter()
    utc = datetime.now(timezone.utc).isoformat()
    with prefix.with_suffix(".stdout.txt").open("wb") as out, prefix.with_suffix(".stderr.txt").open("wb") as err:
        result = subprocess.run(command, cwd=ROOT, stdout=out, stderr=err, timeout=900)
    after = inputs()
    logs = "\n".join(prefix.with_suffix(s).read_text(encoding="utf-8", errors="replace") for s in (".stdout.txt", ".stderr.txt"))
    errors = len(re.findall(r"(?m)^(?:SCRIPT ERROR:|ERROR:)", logs))
    changes = [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)]
    # The art renderer creates its eight declared derivative files and source manifest.
    unexpected = [p for p in changes if not ("res://tools/render_character_art.gd" in arguments and p.startswith("assets/art/characters/"))]
    report = {"command": command, "started_utc": utc, "seconds": time.perf_counter() - start,
              "exit_code": result.returncode, "engine_errors": errors, "os": platform.platform(),
              "python": platform.python_version(), "inputs_before": before, "inputs_after": after,
              "changed_during_run": changes, "unexpected_changes": unexpected}
    record_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    prefix.with_suffix(".exit_code.txt").write_text(str(result.returncode), encoding="utf-8")
    print("\n".join(logs.splitlines()[-14:]))
    print(json.dumps({k: v for k, v in report.items() if not k.startswith("inputs")}, ensure_ascii=False))
    return result.returncode or bool(errors or unexpected)


if __name__ == "__main__":
    raise SystemExit(main())
