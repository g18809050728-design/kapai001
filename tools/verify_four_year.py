"""Run real Godot checks with isolated user data and retained raw evidence."""
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
ENGINE = Path(os.environ.get("GODOT_BIN", r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("scripts", nargs="*")
    args = parser.parse_args()
    out = ROOT / "artifacts/verification/four-year-20261104" / args.name
    out.mkdir(parents=True, exist_ok=True)
    def write(name, data):
        (out / name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    write("environment.json", dict(started_utc=datetime.now(timezone.utc).isoformat(), os=platform.platform(), python=sys.version, engine=str(ENGINE), scope="Implementation checks; not G0/G8 acceptance"))
    inputs = [p for folder in ["src", "tests", "data"] for p in (ROOT / folder).rglob("*") if p.is_file()]
    inputs += [ROOT / "project.godot", ROOT / "tools/build_four_year_content.py"]
    write("input_hashes.json", {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)})
    checks = [("version", [str(ENGINE), "--version"])]
    if not args.scripts:
        checks += [("import", [str(ENGINE), "--headless", "--editor", "--path", str(ROOT), "--quit"])]
    else:
        display = ["--rendering-method", "gl_compatibility", "--position", "-16000,-16000"] if args.visual else ["--headless"]
        if args.verbose:
            display.append("--verbose")
        checks += [(Path(s).stem, [str(ENGINE)] + display + ["--path", str(ROOT), "--script", s]) for s in args.scripts]
    results = []
    for name, command in checks:
        isolated = out / "user_data" / name
        isolated.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, APPDATA=str(isolated), LOCALAPPDATA=str(isolated), PYTHONUTF8="1")
        start = time.monotonic()
        with (out / (name + ".stdout.txt")).open("wb") as stdout, (out / (name + ".stderr.txt")).open("wb") as stderr:
            try:
                code = subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=240, creationflags=subprocess.CREATE_NO_WINDOW).returncode
            except subprocess.TimeoutExpired:
                code = 124
        errors = (out / (name + ".stderr.txt")).read_text(encoding="utf-8", errors="replace")
        engine_errors = sum(1 for line in errors.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:")))
        result = dict(name=name, command=command, isolated_appdata=str(isolated), exit_code=code, engine_errors=engine_errors, seconds=round(time.monotonic()-start, 3))
        results.append(result)
        print(json.dumps(result), flush=True)
    write("summary.json", results)
    return max(max(r["exit_code"], int(r["engine_errors"] > 0)) for r in results)


if __name__ == "__main__":
    raise SystemExit(main())
