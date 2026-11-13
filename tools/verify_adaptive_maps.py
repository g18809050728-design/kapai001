"""Run Godot with isolated data and retain adaptive-map verification evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(os.environ.get("GODOT_BIN", r"D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe"))
OUT = ROOT / "artifacts/verification/adaptive-maps-20261113"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / ".gdignore").touch()
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--script-arg", action="append", default=[])
    parser.add_argument("scripts", nargs="*")
    args = parser.parse_args()
    output = OUT / args.name
    output.mkdir(parents=True, exist_ok=True)
    def record(name, value):
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    record("environment.json", {"utc": datetime.now(timezone.utc).isoformat(), "os": platform.platform(), "python": sys.version, "engine": str(ENGINE), "scope": "Incremental implementation verification, not full G0/G6/G8 acceptance"})
    files = [p for folder in ("src", "tests", "data") for p in (ROOT / folder).rglob("*") if p.is_file()]
    files += [ROOT / "project.godot", Path(__file__)]
    record("inputs.json", {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)})
    commands = [("version", [str(ENGINE), "--version"])]
    if args.scripts:
        mode = ["--rendering-method", "gl_compatibility", "--position", "-16000,-16000"] if args.visual else ["--headless"]
        user_args = ["--", *args.script_arg] if args.script_arg else []
        commands.extend((Path(script).stem, [str(ENGINE), *mode, "--path", str(ROOT), "--script", script, *user_args]) for script in args.scripts)
    else:
        commands.append(("import", [str(ENGINE), "--headless", "--editor", "--path", str(ROOT), "--quit"]))
    results = []
    for label, command in commands:
        isolated = output / "user_data" / label
        isolated.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, APPDATA=str(isolated), LOCALAPPDATA=str(isolated), PYTHONUTF8="1")
        started = time.monotonic()
        with (output / (label + ".stdout.log")).open("wb") as stdout, (output / (label + ".stderr.log")).open("wb") as stderr:
            try:
                code = subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=300, creationflags=subprocess.CREATE_NO_WINDOW).returncode
            except subprocess.TimeoutExpired:
                code = 124
        errors = (output / (label + ".stderr.log")).read_text(encoding="utf-8", errors="replace")
        engine_errors = sum(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in errors.splitlines())
        result = {"name": label, "command": command, "isolated_appdata": str(isolated), "exit_code": code, "engine_errors": engine_errors, "seconds": round(time.monotonic() - started, 3)}
        results.append(result)
        print(json.dumps(result), flush=True)
    record("summary.json", results)
    return max(max(row["exit_code"], int(row["engine_errors"] > 0)) for row in results)


if __name__ == "__main__":
    raise SystemExit(main())
