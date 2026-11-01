#!/usr/bin/env python3
"""Write the static-verification evidence bundle for the elite content build.

    python artifacts/elite-build-20261101/write_evidence.py

Creates artifacts/verification/elite-content-<UTC timestamp>/ with the commands,
environment, exit codes, raw output and input hashes. The Godot test suite is NOT
run here because no Godot 4.7.2 binary exists on this machine; the bundle records
that gap explicitly instead of implying a pass.
"""

import datetime
import hashlib
import json
import pathlib
import platform
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILD = ROOT / "artifacts" / "elite-build-20261101"
SCRIPT = pathlib.Path(__file__).resolve()

INPUTS = [
    "data/definitions/tasks.json",
    "data/definitions/encounters.json",
    "data/definitions/statuses.json",
    "data/definitions/rulesets.json",
    "data/definitions/cards.json",
    "data/manifests/campus_mvp.json",
    "src/ui/ui_labels.json",
    "src/content/content_db.gd",
    "src/battle/battle_engine.gd",
    "src/ui/battle_layout.gd",
    "tests/run_tests.gd",
    "tests/suites/test_elite_encounters.gd",
]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command):
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    return completed.returncode, completed.stdout, completed.stderr


def find_godot():
    for candidate in (
        r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe",
        r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe",
        r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe",
    ):
        path = pathlib.Path(candidate)
        if path.is_file():
            return str(path)
    return "missing (no candidate install path found)"


def main():
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    out = ROOT / "artifacts" / "verification" / ("elite-content-" + stamp)
    out.mkdir(parents=True, exist_ok=False)

    python = sys.executable
    commands = [
        [python, str(BUILD / "validate_content.py")],
        [python, str(BUILD / "check_gdscript.py")],
    ]
    results = []
    for command in commands:
        code, stdout, stderr = run(command)
        results.append(
            {
                "command": " ".join(command),
                "exit_code": code,
                "stdout": stdout,
                "stderr": stderr,
            }
        )

    hashes = {}
    for relative in INPUTS:
        path = ROOT / relative
        hashes[relative] = sha256(path) if path.exists() else "missing"

    accepted = all(result["exit_code"] == 0 for result in results)
    (out / "command.json").write_text(
        json.dumps(
            {
                "run_id": out.name,
                "commands": [result["command"] for result in results],
                "godot_test_command": (
                    "$env:GODOT_BIN = '<Godot 4.7.2 console>'; "
                    "& $env:GODOT_BIN --headless --path . --script res://tests/run_tests.gd"
                ),
                "godot_tests_executed": False,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (out / "environment.json").write_text(
        json.dumps(
            {
                "os": platform.platform(),
                "python": platform.python_version(),
                "python_executable": python,
                "godot_binary": find_godot(),
                "godot_version_required": "4.7.2.stable",
                "godot_suites": (
                    "run artifacts/elite-build-20261101/run_godot_evidence.py "
                    "for the executed headless/UI results"
                ),
                "timestamp_utc": stamp,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (out / "input_hashes.json").write_text(
        json.dumps(hashes, indent=2) + "\n", encoding="utf-8"
    )
    lines = []
    for result in results:
        lines.append("$ " + result["command"])
        lines.append(result["stdout"].rstrip())
        if result["stderr"].strip():
            lines.append("[stderr]")
            lines.append(result["stderr"].rstrip())
        lines.append("[exit code: %d]" % result["exit_code"])
        lines.append("")
    (out / "stdout.txt").write_text("\n".join(lines), encoding="utf-8")
    (out / "exit_code.txt").write_text(
        ("0" if accepted else "1") + "\n", encoding="utf-8"
    )
    (out / "summary.md").write_text(
        "\n".join(
            [
                "# 精英内容静态核查（%s）" % stamp,
                "",
                "- 已执行：内容镜像校验与 GDScript 缩进/括号检查，退出码 %s。"
                % ("0" if accepted else "1"),
                "- 未执行：Godot 4.7.2 测试（本机无可执行文件），"
                "`tests/suites/test_elite_encounters.gd` 状态为未验证。",
                "- 本证据只证明 JSON/字段/引用闭包与文件结构层面的一致性，"
                "不证明战斗行为、平衡或 G8 验收。",
                "",
                "详见 [精英敌人实现记录](../../../docs/精英敌人实现记录_20261101.md)§6。",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(out.relative_to(ROOT))
    print("exit_code=%d" % (0 if accepted else 1))
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
