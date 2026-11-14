"""Preserve independent inputs for the composition correction before any edits."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/map-composition-feedback-20261114"
OUT.mkdir(parents=True, exist_ok=True)
files = [p for folder in ["src", "data", "tests", "tools", "assets", "ui-plan", "docs", "output/文档提交_20261114", "动作或者图片描述"]
         for p in (ROOT / folder).rglob("*") if p.is_file()]
files += [ROOT / name for name in ["AGENTS.md", "agent.md", "实施计划与验收基线.md", "README.md", "project.godot", "output/交大四年_DDL战争_文档提交包_20261114.zip"]]
target = OUT / "before.json"
assert not target.exists(), "Keep existing evidence immutable"
target.write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
    "scope": "UIR-019/063: coherent icon and route composition; user rejected the material-only interpretation",
    "files": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(files))}}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Recorded", len(set(files)), "input hashes")
