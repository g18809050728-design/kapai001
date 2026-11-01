#!/usr/bin/env python3
"""Run the Godot suites for the elite content work and retain the real output.

    python artifacts/elite-build-20261101/run_godot_evidence.py

Creates artifacts/verification/elite-godot-<UTC timestamp>/ containing the
engine version, editor import, headless suite, UI suite, boot smoke, exit codes,
raw stdout/stderr, Godot logs and input hashes.
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

GODOT_CANDIDATES = [
    pathlib.Path(r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe"),
    pathlib.Path(r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe"),
    pathlib.Path(r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe"),
]

INPUTS = [
    "project.godot",
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
    "tests/run_ui_tests.gd",
    "tests/suites/test_elite_encounters.gd",
    "tests/suites/test_content_loader.gd",
]


def find_godot():
    for candidate in GODOT_CANDIDATES:
        if candidate.is_file():
            return candidate
    return None


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command, evidence, name):
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, errors="replace")
    (evidence / (name + ".stdout.txt")).write_text(completed.stdout, encoding="utf-8")
    (evidence / (name + ".stderr.txt")).write_text(completed.stderr, encoding="utf-8")
    (evidence / (name + ".exit_code.txt")).write_text(
        "%d\n" % completed.returncode, encoding="utf-8"
    )
    return completed


def main():
    godot = find_godot()
    if godot is None:
        print("Godot 4.7.2 not found; checked: " + ", ".join(str(path) for path in GODOT_CANDIDATES))
        return 1
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    evidence = ROOT / "artifacts" / "verification" / ("elite-godot-" + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    results = {}

    def step(name, arguments):
        completed = run([str(godot)] + arguments, evidence, name)
        results[name] = {
            "command": " ".join([str(godot)] + arguments),
            "exit_code": completed.returncode,
        }
        return completed

    version = step("engine_version", ["--version"])
    step("editor_import", ["--headless", "--editor", "--path", str(ROOT), "--quit"])
    headless = step(
        "headless_tests",
        [
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            "res://tests/run_tests.gd",
            "--log-file",
            str(evidence / "headless_tests.log"),
        ],
    )
    ui = step(
        "ui_tests",
        [
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            "res://tests/run_ui_tests.gd",
            "--log-file",
            str(evidence / "ui_tests.log"),
        ],
    )
    smoke = step(
        "boot_smoke",
        [
            "--headless",
            "--path",
            str(ROOT),
            "--quit-after",
            "90",
            "--log-file",
            str(evidence / "boot_smoke.log"),
        ],
    )

    hashes = {}
    for relative in INPUTS:
        path = ROOT / relative
        hashes[relative] = sha256(path) if path.exists() else "missing"

    markers_ok = (
        "G1/G2/G3 headless tests passed" in headless.stdout
        and "G4 headless tests passed" in headless.stdout
        and "G5 headless tests passed" in headless.stdout
        and "ELITE_ENCOUNTERS_SUITE=passed" in headless.stdout
        and "G7 UI tests passed" in ui.stdout
    )
    no_script_errors = all(
        "SCRIPT ERROR" not in completed.stdout + completed.stderr
        and "Parse Error" not in completed.stdout + completed.stderr
        for completed in (headless, ui, smoke)
    )
    passed = (
        results["headless_tests"]["exit_code"] == 0
        and results["ui_tests"]["exit_code"] == 0
        and results["boot_smoke"]["exit_code"] == 0
        and markers_ok
        and no_script_errors
    )

    environment = {
        "os": platform.platform(),
        "python": platform.python_version(),
        "engine": version.stdout.strip(),
        "engine_executable": str(godot),
        "project_root": str(ROOT),
        "timestamp_utc": stamp,
    }
    (evidence / "command.json").write_text(
        json.dumps(
            {
                "run_id": evidence.name,
                "engine": str(godot),
                "steps": results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (evidence / "environment.json").write_text(
        json.dumps(environment, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (evidence / "input_hashes.json").write_text(
        json.dumps(hashes, indent=2) + "\n", encoding="utf-8"
    )
    (evidence / "exit_code.txt").write_text("0\n" if passed else "1\n", encoding="utf-8")
    (evidence / "summary.md").write_text(
        "\n".join(
            [
                "# 精英内容 Godot 运行证据（%s）" % stamp,
                "",
                "- 引擎：`%s`" % environment["engine"],
                "- 编辑器导入：退出码 %d" % results["editor_import"]["exit_code"],
                "- 无头测试：退出码 %d，标记 %s"
                % (results["headless_tests"]["exit_code"], markers_ok),
                "- UI 测试：退出码 %d" % results["ui_tests"]["exit_code"],
                "- 启动冒烟：退出码 %d" % results["boot_smoke"]["exit_code"],
                "- 脚本错误扫描：%s" % ("无" if no_script_errors else "发现 SCRIPT ERROR/Parse Error"),
                "- 结论：%s" % ("通过" if passed else "失败"),
                "",
                "证据只覆盖无头规则/内容/UI 与启动冒烟；平衡、人工视觉与发布验收仍待 G3/G7/G8。",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(evidence.relative_to(ROOT))
    print("passed=%s" % passed)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
