"""Run a pilot check, retaining exact commands, inputs, environment and logs."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import platform
import re
import subprocess
import time
import os

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / os.environ.get("CAMPUS_ACTOR_EVIDENCE", "artifacts/verification/actor-rig-pilot-20261114")
ENGINE = Path("F:/GoDot/Godot_v4.7.2-stable_win64_console.exe")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    command = [str(ENGINE), "--path", str(ROOT), *arguments]
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    destination = EVIDENCE / args.name
    if destination.with_suffix(".run.json").exists():
        raise SystemExit("Evidence exists: choose a new name")
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    before = time.perf_counter()
    with destination.with_suffix(".stdout.txt").open("wb") as out, destination.with_suffix(".stderr.txt").open("wb") as err:
        result = subprocess.run(command, cwd=ROOT, stdout=out, stderr=err)
    inputs = list((ROOT / "src/ui/battle").glob("*.gd"))
    inputs += [ROOT / p for p in ("project.godot", "src/app/game_session.gd", "src/ui/game_shell.gd", "src/ui/battle_screen.gd", "src/ui/battle_layout.gd", "tools/run_actor_rig_pilot.gd", "tools/build_actor_motion_polish.py", "tools/verify_actor_rig_pilot.py", "tests/run_tests.gd", "tests/run_ui_tests.gd")]
    inputs += list((ROOT / "assets/art/actor-rig-pilot").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-rig-pilot").rglob("*.png"))
    inputs += list((ROOT / "assets/art/actor-rig-polish").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-rig-refinement").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-rig-refinement").rglob("*.png"))
    inputs += [ROOT / "tools/build_actor_refinement.py"]
    inputs += list((ROOT / "assets/art/actor-rig-drawings").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-rig-drawings").rglob("*.png"))
    inputs += [ROOT / "tools/build_actor_drawings.py", ROOT / "src/ui/battle/actor_drawing_mix.gdshader"]
    inputs += list((ROOT / "assets/art/actor-anatomy").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-anatomy").rglob("*.png"))
    inputs += [ROOT / "tools/build_actor_anatomy.py"]
    inputs += list((ROOT / "assets/art/actor-seams").rglob("*.json"))
    inputs += list((ROOT / "assets/art/actor-seams").rglob("*.png"))
    inputs += [ROOT / "tools/build_actor_seams.py", ROOT / "tools/start_actor_seams.ps1"]
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs if p.is_file()}
    raw_logs = "\n".join(destination.with_suffix(s).read_text(encoding="utf-8", errors="replace") for s in (".stdout.txt", ".stderr.txt"))
    engine_errors = len(re.findall(r"(?m)^(?:SCRIPT ERROR:|ERROR:)", raw_logs))
    report = {"command": command, "started_utc": started, "seconds": time.perf_counter() - before, "exit_code": result.returncode, "engine_errors": engine_errors, "os": platform.platform(), "python": platform.python_version(), "inputs": hashes}
    destination.with_suffix(".run.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    destination.with_suffix(".exit_code.txt").write_text(str(result.returncode), encoding="utf-8")
    for suffix in (".stdout.txt", ".stderr.txt"):
        lines = destination.with_suffix(suffix).read_text(encoding="utf-8", errors="replace").splitlines()
        print("\n".join(lines[-22:]))
    print(json.dumps({k: v for k, v in report.items() if k != "inputs"}, ensure_ascii=False))
    return result.returncode or (1 if engine_errors else 0)


if __name__ == "__main__":
    raise SystemExit(main())
