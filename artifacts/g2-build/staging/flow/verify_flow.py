"""Run and archive the flow batch's bounded staging and schema checks."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
STAGE = ROOT / "artifacts/g2-build/staging/flow"
GODOT = Path(r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe")

INPUTS = [
    "docs/baselines/g0.json",
    "data/manifests/content_deferred.json",
    "data/manifests/campus_mvp.json",
    "data/definitions/cards.json",
    "artifacts/g2-build/staging/cards/cards.json",
    "docs/交大四年_DDL战争_统一设计文档.md",
    "docs/交大四年_DDL战争_项目计划书.md",
    "docs/内容层契约.md",
    "docs/局流程契约.md",
    "src/content/content_db.gd",
    "src/battle/battle_engine.gd",
    "src/battle/battle_card_rules.gd",
    "src/app/game_session.gd",
    "src/run/run_state.gd",
    "tests/suites/test_battle_engine_begin.gd",
    "tests/suites/test_g2_state.gd",
    "tools/g2_content_builder.py",
    "artifacts/g2-build/staging/flow/build_flow.py",
    "artifacts/g2-build/staging/flow/schema_probe.gd",
    "artifacts/g2-build/staging/flow/runtime_probe/runtime_probe.gd",
    "artifacts/g2-build/staging/flow/runtime_probe/data/manifests/test_g2_flow.json",
    "artifacts/g2-build/staging/flow/batch_report.md",
    "artifacts/g2-build/staging/flow/verify_flow.py",
    "artifacts/g2-build/staging/flow/verify_flow.ps1",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name: str, command: list[str], cwd: Path, evidence: Path) -> int:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    (evidence / f"{name}.stdout.txt").write_text(result.stdout, encoding="utf-8")
    (evidence / f"{name}.stderr.txt").write_text(result.stderr, encoding="utf-8")
    (evidence / f"{name}.exit_code.txt").write_text(f"{result.returncode}\n", encoding="ascii")
    return result.returncode


def main() -> int:
    run_id = "g2-flow-20261015-" + datetime.now().strftime("%H%M%S")
    evidence = ROOT / "artifacts/verification" / run_id
    evidence.mkdir(parents=True, exist_ok=False)

    version = subprocess.run([str(GODOT), "--version"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    environment = {
        "cwd": str(ROOT),
        "platform": platform.platform(),
        "python": sys.version,
        "powershell": "5.1 (invoked by verify_flow.ps1)",
        "godot_path": str(GODOT),
        "godot_version_command": [str(GODOT), "--version"],
        "godot_version_exit_code": version.returncode,
        "godot_version_stdout": version.stdout,
        "godot_version_stderr": version.stderr,
        "gdformat_version": subprocess.run(["gdformat", "--version"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip(),
        "os_name": os.name,
    }
    (evidence / "environment.json").write_text(json.dumps(environment, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (evidence / "engine_version.stdout.txt").write_text(version.stdout, encoding="utf-8")
    (evidence / "engine_version.stderr.txt").write_text(version.stderr, encoding="utf-8")
    (evidence / "engine_version.exit_code.txt").write_text(f"{version.returncode}\n", encoding="ascii")

    commands = [
        {"name": "staging", "command": [sys.executable, "artifacts/g2-build/staging/flow/build_flow.py"]},
        {"name": "python_compile", "command": [sys.executable, "-m", "compileall", "-q", "artifacts/g2-build/staging/flow/build_flow.py", "artifacts/g2-build/staging/flow/verify_flow.py"]},
        {"name": "gdformat_apply", "command": ["gdformat", "artifacts/g2-build/staging/flow/runtime_probe/runtime_probe.gd"]},
        {"name": "gdformat_check", "command": ["gdformat", "--check", "artifacts/g2-build/staging/flow/schema_probe.gd", "artifacts/g2-build/staging/flow/runtime_probe/runtime_probe.gd"]},
        {"name": "godot_schema_probe", "command": [str(GODOT), "--headless", "--path", ".", "--script", "res://artifacts/g2-build/staging/flow/schema_probe.gd"]},
        {"name": "godot_reference_probe", "command": [str(GODOT), "--headless", "--path", ".", "--script", "res://artifacts/g2-build/staging/flow/runtime_probe/runtime_probe.gd"]},
    ]
    overall = 0
    command_records = []
    for item in commands:
        command_records.append({"name": item["name"], "command": item["command"], "cwd": str(ROOT)})
        if run(item["name"], item["command"], ROOT, evidence) != 0:
            overall = 1

    hashes = {path: digest(ROOT / path) for path in INPUTS}
    hashes.update({
        path.relative_to(ROOT).as_posix(): digest(path)
        for path in sorted((STAGE / "definitions").glob("*.json"))
    })
    hashes.update({
        path.relative_to(ROOT).as_posix(): digest(path)
        for path in sorted((STAGE / "runtime_probe").rglob("*.json"))
    })
    hashes["artifacts/g2-build/staging/flow/runtime_probe/runtime_probe.gd"] = digest(
        STAGE / "runtime_probe/runtime_probe.gd"
    )
    (evidence / "inputs.json").write_text(json.dumps(hashes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (evidence / "command.json").write_text(json.dumps(command_records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (evidence / "exit_code.txt").write_text(f"{overall}\n", encoding="ascii")
    batch_path = STAGE / "batch.json"
    batch = json.loads(batch_path.read_text(encoding="utf-8"))
    verification = batch.setdefault("verification", {})
    reference_exit = int((evidence / "godot_reference_probe.exit_code.txt").read_text(encoding="ascii").strip())
    verification["godot_reference_probe"] = {
        "status": "passed_reference_closure_and_event_schema_only" if reference_exit == 0 else "failed",
        "command": command_records[-1]["command"],
        "godot_version": version.stdout.strip(),
        "exit_code": reference_exit,
        "raw_output": str((evidence / "godot_reference_probe.stdout.txt").relative_to(ROOT)).replace("\\", "/"),
        "raw_stderr": str((evidence / "godot_reference_probe.stderr.txt").relative_to(ROOT)).replace("\\", "/"),
        "evidence": str(evidence.relative_to(ROOT)).replace("\\", "/"),
    }
    reference_stdout = (evidence / "godot_reference_probe.stdout.txt").read_text(encoding="utf-8")
    closure_ids = [
        *[f"task/{id_}" for id_ in ["N01", "N02", "N03", "N04", "Q01", "B01"]],
        *[f"encounter/{id_}" for id_ in ["N01", "N02", "N03", "N04", "Q01", "B01"]],
    ]
    if reference_exit == 0 and "FLOW_REFERENCE_CLOSURE_OK tasks=6 encounters=6 cards=5 override=N04:[1]" in reference_stdout:
        reference_closure = {
            "status": "partial",
            "scope": "test_g2_flow ContentDB enabled tasks and encounters only; events are intentionally disabled",
            "items": {
                full_id: {
                    "status": "passed",
                    "evidence": str(evidence.relative_to(ROOT)).replace("\\", "/"),
                }
                for full_id in closure_ids
            },
        }
    else:
        reference_closure = {"status": "failed", "items": {}}
    verification["reference_closure"] = reference_closure
    batch["reference_closure"] = reference_closure
    verification["evidence_bundle"] = str(evidence.relative_to(ROOT)).replace("\\", "/")
    batch["verification"] = verification
    batch_path.write_text(json.dumps(batch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"FLOW_EVIDENCE={evidence.relative_to(ROOT).as_posix()}")
    print(f"FLOW_EVIDENCE_EXIT={overall}")
    return overall


if __name__ == "__main__":
    sys.exit(main())
