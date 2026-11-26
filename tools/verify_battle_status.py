"""Run the buff UI checks with isolated user data and retain engine evidence."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--check", choices=["focused", "native", "rules", "ui", "smoke"], default="focused")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    out = root / "artifacts/verification/battle-buff-20261126"
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(out / ("userdata-" + args.check))
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    command = [args.godot, "--path", str(root)]
    if args.check != "native":
        command.append("--headless")
    scripts = {"focused": "tools/run_battle_status_checks.gd", "native": "tools/run_battle_status_checks.gd", "rules": "tests/run_tests.gd", "ui": "tests/run_ui_tests.gd"}
    if args.check in scripts:
        command += ["--script", "res://" + scripts[args.check]]
    else:
        command += ["--quit-after", "3"]
    if args.check == "native":
        command += ["--", "--capture-only"]
    try:
        completed = subprocess.run(command, cwd=root, env=env, capture_output=True, timeout=600)
        stdout, stderr, code = completed.stdout, completed.stderr, completed.returncode
    except subprocess.TimeoutExpired as exc:
        stdout, stderr, code = exc.stdout or b"", (exc.stderr or b"") + b"\nTimed out after 600 seconds", 124
    stdout = stdout.decode("utf-8", errors="replace")
    stderr = stderr.decode("utf-8", errors="replace")
    (out / (args.check + ".stdout.txt")).write_text(stdout, encoding="utf-8")
    (out / (args.check + ".stderr.txt")).write_text(stderr, encoding="utf-8")
    paths = [root / "project.godot"]
    for folder in ("src", "tests", "data"):
        paths += [p for p in (root / folder).rglob("*") if p.suffix in (".gd", ".json", ".tscn")]
    report = {"command": command, "exit_code": code, "engine": subprocess.check_output([args.godot, "--version"], text=True).strip(), "inputs": {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
    (out / (args.check + ".json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(stdout)
    print(stderr)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
