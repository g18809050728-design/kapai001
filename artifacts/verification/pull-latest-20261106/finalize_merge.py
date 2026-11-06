from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import subprocess

EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[2]
EXPECTED_HEAD = "a2aaa69727b660ced6c9d36ca6715e42f285bd92"
EXPECTED_MERGE = "e5315e92ae39b8600058cf524a841bfba227c2bd"
RESOLVED = [
    "实施计划与验收基线.md",
    "docs/局流程契约.md",
    "docs/界面层契约.md",
    "动作或者图片描述/需求台账.md",
    "src/ui/game_shell.gd",
    "src/ui/battle_screen.gd",
    "tests/run_ui_tests.gd",
    "docs/G0需求追踪.md",
    "tests/suites/test_ui_damage_popup.gd",
]


def git(*arguments):
    result = subprocess.run(["git", "-C", str(ROOT), "-c", "core.safecrlf=false", *arguments], capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace"))
    return result.stdout


assert git("rev-parse", "HEAD").decode().strip() == EXPECTED_HEAD
assert git("rev-parse", "MERGE_HEAD").decode().strip() == EXPECTED_MERGE
records = {}
for name in ("import", "rules", "ui"):
    record = json.loads((EVIDENCE / f"{name}.result.json").read_text(encoding="utf-8"))
    assert record["exit_code"] == 0, name
    for relative, expected in record["input_sha256"].items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == expected, (name, relative)
    for stream in ("stdout", "stderr"):
        output = (EVIDENCE / f"{name}.{stream}.log").read_text(encoding="utf-8", errors="replace")
        assert not re.search(r"SCRIPT ERROR|Parse Error|Failed to load script", output), name
    records[name] = {k: record[k] for k in ("exit_code", "elapsed_seconds", "engine_version")}

manifest = json.loads((EVIDENCE / "before-abort/manifest.json").read_text(encoding="utf-8"))
preserved = []
for item in manifest["files"]:
    if len(item["status"]) > 1 and item["status"][1] != " " and item["status"] != "??":
        assert hashlib.sha256((ROOT / item["path"]).read_bytes()).hexdigest() == item["sha256"], item["path"]
        preserved.append(item["path"])

marker = re.compile(rb"^(?:<<<<<<<|=======|>>>>>>>)", re.M)
scanned = 0
for directory, patterns in [("src", ("*.gd",)), ("tests", ("*.gd",)), ("docs", ("*.md",)), ("动作或者图片描述", ("*.md",))]:
    for pattern in patterns:
        for path in (ROOT / directory).rglob(pattern):
            assert not marker.search(path.read_bytes()), str(path)
            scanned += 1
assert not marker.search((ROOT / "实施计划与验收基线.md").read_bytes())

git("add", "--", *RESOLVED)
assert not git("ls-files", "--unmerged")
git("diff", "--cached", "--check")

status = git("status", "--porcelain=v1", "-z")
unstaged = []
for entry in status.split(b"\0"):
    if len(entry) >= 4 and entry[:2] != b"??" and entry[1:2] != b" ":
        unstaged.append(entry[3:].decode("utf-8"))
assert set(unstaged) == set(preserved), "unexpected unstaged changes"
evidence_names = ["README.md", "run_verification.py", "finalize_merge.py", "pull.stdout.log", "pull.stderr.log", "pull.exit"]
for name in ("import", "rules", "ui"):
    evidence_names.extend(f"{name}.{suffix}" for suffix in ("stdout.log", "stderr.log", "exit", "result.json"))
evidence_names.extend(["rules.godot.log", "ui.godot.log"])
git("add", "-f", "--", *[str((EVIDENCE / name).relative_to(ROOT)) for name in evidence_names])
git("diff", "--cached", "--check")
report = {
    "checked_at": datetime.now().astimezone().isoformat(),
    "head": git("rev-parse", "HEAD").decode().strip(),
    "merge_head": git("rev-parse", "MERGE_HEAD").decode().strip(),
    "origin_main": git("rev-parse", "origin/main").decode().strip(),
    "resolved_files_staged": RESOLVED,
    "unmerged_entries": 0,
    "conflict_marker_files_scanned": scanned + 1,
    "staged_whitespace_check_exit": 0,
    "original_unstaged_files_preserved": len(preserved),
    "original_unstaged_paths": preserved,
    "verification": records,
    "staged_evidence_sha256": {name: hashlib.sha256((EVIDENCE / name).read_bytes()).hexdigest() for name in evidence_names},
    "commit_created": False,
    "push_performed": False,
}
assert report["head"] == EXPECTED_HEAD and report["merge_head"] == EXPECTED_MERGE
(EVIDENCE / "final-checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
git("add", "-f", "--", str((EVIDENCE / "final-checks.json").relative_to(ROOT)))
git("diff", "--cached", "--check")
print(json.dumps({k: v for k, v in report.items() if k not in ("original_unstaged_paths", "staged_evidence_sha256")}, ensure_ascii=False, indent=2))
