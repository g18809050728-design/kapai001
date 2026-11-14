"""Record this batch's actual inputs before editing; never reads player data."""
from pathlib import Path
import hashlib
import json
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/verification/ui-flow-feedback-20261114"
OUT.mkdir(parents=True, exist_ok=True)
files = [p for folder in ["src", "data", "tests", "tools", "assets", "ui-plan", "动作或者图片描述", "docs"]
         for p in (ROOT / folder).rglob("*") if p.is_file()]
files += [ROOT / n for n in ["AGENTS.md", "agent.md", "实施计划与验收基线.md", "README.md", "project.godot", "image copy 4.png"]]
frozen = ROOT / "output/交大四年_DDL战争_文档提交包_20261114.zip"
files += [frozen] + [p for p in (ROOT / "output/文档提交_20261114").rglob("*") if p.is_file()]
before = OUT / "before.json"
if not before.exists():
    before.write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(), "files": {
        p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(files))
    }}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Recorded", len(files), "input files")
else:
    print("Existing before.json retained")
