"""Run the G7 functional checks once and retain the actual engine output."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from datetime import datetime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get(
        "GODOT_BIN", r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    run_id = "g7-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    evidence = root / "artifacts" / "verification" / run_id
    evidence.mkdir(parents=True)

    def write(name, value):
        (evidence / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

    commands = [
        ("engine_version", [args.godot, "--version"], "4.7.2.stable"),
        ("editor_import", [args.godot, "--headless", "--editor", "--path", str(root), "--quit"], None),
        ("ui_tests", [args.godot, "--headless", "--path", str(root), "--script", "res://tests/run_ui_tests.gd"], "G7 UI tests passed"),
        ("session_regression", [args.godot, "--headless", "--path", str(root), "--script", "res://tests/run_tests.gd"], "G5 headless tests passed"),
        ("main_smoke", [args.godot, "--headless", "--path", str(root), "--quit-after", "3"], "Project bootstrap ready"),
        ("format_check", [shutil.which("gdformat") or "gdformat", "--check", "src/battle/battle_engine.gd", "tests/suites/test_relic_battle_entry.gd", "tests/suites/test_production_boss.gd", "tests/run_tests.gd", "src/ui", "src/app", "src/storage/save_store.gd", "src/common/action_result.gd", "src/common/setup_options.gd", "src/common/session_storage_view.gd", "src/run/run_service.gd", "tests/run_ui_tests.gd", "tests/suites/test_ui_shell_pages.gd", "tests/suites/test_ui_save_seed.gd", "tests/suites/test_ui_flow_feedback.gd", "tests/suites/test_run_content_views.gd", "tests/suites/test_ui_battle_polish.gd", "tests/suites/test_ui_battle_choice.gd", "tests/suites/test_ui_battle_pointer.gd", "tools/capture_g7.gd", "tools/capture_g7_polish.gd"], None),
    ]
    write("command.json", [{"name": name, "argv": argv} for name, argv, _ in commands])
    write("environment.json", {"os": platform.platform(), "python": sys.version,
          "engine_executable": args.godot, "cwd": str(root), "started": datetime.now().isoformat()})
    paths = [root / "project.godot", root / "assets/g6/selection.json", root / "tools/capture_g7_polish.gd", Path(__file__)]
    for folder in ("src", "tests", "data"):
        paths.extend(p for p in (root / folder).rglob("*") if p.is_file() and p.suffix in (".gd", ".tscn", ".json"))
    write("inputs.json", {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))})
    results = []
    for name, argv, marker in commands:
        print(f"Running {name}", flush=True)
        try:
            completed = subprocess.run(argv, cwd=root, capture_output=True, timeout=180)
            stdout = completed.stdout.decode("utf-8", errors="replace")
            stderr = completed.stderr.decode("utf-8", errors="replace")
            code = completed.returncode
        except (OSError, subprocess.TimeoutExpired) as exc:
            stdout, stderr, code = "", str(exc), 1
        (evidence / f"{name}.stdout.txt").write_text(stdout, encoding="utf-8")
        (evidence / f"{name}.stderr.txt").write_text(stderr, encoding="utf-8")
        (evidence / f"{name}.exit_code.txt").write_text(str(code), encoding="utf-8")
        log = stdout + stderr
        errors = any(token in log for token in ("SCRIPT ERROR", "Parse Error", "GDScript backtrace", "ERROR:"))
        passed = code == 0 and not errors and (marker is None or marker in log)
        results.append({"name": name, "exit_code": code, "passed": passed})
        print(f"{name}: {'passed' if passed else 'failed'}", flush=True)
        if not passed:
            print(log[-8000:], flush=True)
            break
    passed = len(results) == len(commands) and all(r["passed"] for r in results)
    write("report.json", {"stage": "G7", "functional_checks": "passed" if passed else "failed",
          "visual_review": "separate capture required", "checks": results,
          "evidence": evidence.relative_to(root).as_posix()})
    (evidence / "exit_code.txt").write_text("0" if passed else "1", encoding="utf-8")
    print(f"Evidence: {evidence}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
