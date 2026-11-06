from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import subprocess
import sys

EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[2]
ENGINE = Path("D:/chrome/godot/Godot_v4.7.2-stable_win64_console.exe")
name = sys.argv[1]
arguments = {
    "import": ["--editor", "--import"],
    "rules": ["--script", "res://tests/run_tests.gd"],
    "ui": ["--script", "res://tests/run_ui_tests.gd"],
}[name]
environment = os.environ.copy()
isolated = EVIDENCE / "isolated_appdata" / name
for key in ("APPDATA", "LOCALAPPDATA"):
    location = isolated / key.lower()
    location.mkdir(parents=True, exist_ok=True)
    environment[key] = str(location)

inputs = sorted({ROOT / "project.godot"} | {p for directory, pattern in [("src", "*.gd"), ("tests", "*.gd"), ("data", "*.json")] for p in (ROOT / directory).rglob(pattern)})
hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
command = [str(ENGINE), "--headless", "--path", str(ROOT), *arguments, "--log-file", str(EVIDENCE / f"{name}.godot.log")]
started = datetime.now().astimezone()
with (EVIDENCE / f"{name}.stdout.log").open("wb") as stdout, (EVIDENCE / f"{name}.stderr.log").open("wb") as stderr:
    result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stdout, stderr=stderr)
finished = datetime.now().astimezone()
(EVIDENCE / f"{name}.exit").write_text(str(result.returncode) + "\n", encoding="utf-8")
record = {
    "command": command,
    "cwd": str(ROOT),
    "environment": {key: environment[key] for key in ("APPDATA", "LOCALAPPDATA")},
    "engine_version": subprocess.check_output([str(ENGINE), "--version"], env=environment, text=True, encoding="utf-8").strip(),
    "started_at": started.isoformat(),
    "finished_at": finished.isoformat(),
    "elapsed_seconds": (finished - started).total_seconds(),
    "exit_code": result.returncode,
    "input_sha256": hashes,
}
(EVIDENCE / f"{name}.result.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"{name}: exit {result.returncode}; {record['elapsed_seconds']:.2f}s; {len(hashes)} hashed inputs", flush=True)
for stream in ("stdout", "stderr"):
    output = (EVIDENCE / f"{name}.{stream}.log").read_text(encoding="utf-8", errors="replace")
    print(f"{stream}:\n" + "\n".join(output.splitlines()[-15:]), flush=True)
sys.exit(result.returncode)
