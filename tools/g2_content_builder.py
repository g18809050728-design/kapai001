"""Stage frozen G2 production definitions without mutating the live manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import re
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "docs/baselines/g0.json"
DEFERRED = ROOT / "data/manifests/content_deferred.json"
DESIGN = ROOT / "docs/交大四年_DDL战争_统一设计文档.md"
STAGING = ROOT / "artifacts/g2-build"


@dataclass(frozen=True)
class FrozenDefinition:
    kind: str
    id: str
    source_path: str
    source_section: str
    blocking: tuple[str, ...]
    status: str = "pending"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def frozen_definitions() -> list[FrozenDefinition]:
    deferred = read_json(DEFERRED)
    result: list[FrozenDefinition] = []
    for kind, entries in deferred["definitions"].items():
        for entry in entries:
            source = entry["source"]
            result.append(
                FrozenDefinition(
                    kind=kind,
                    id=entry["id"],
                    source_path=source["path"],
                    source_section=source["section"],
                    blocking=tuple(entry.get("blocking", ["G2"])),
                )
            )
    return result


class ProductionContentBuilder:
    """Build a verified staging batch before any production manifest mutation."""

    def __init__(self, root: Path = ROOT) -> None:
        self.root = root
        self.baseline = read_json(root / "docs/baselines/g0.json")
        self.frozen = {
            (item.kind, item.id): item for item in frozen_definitions()
        }
        self.source_cache: dict[str, str] = {}

    def plan(self) -> list[FrozenDefinition]:
        return list(self.frozen.values())

    def stage_definition(
        self,
        output: Path,
        kind: str,
        definition: dict[str, Any],
        source_section: str,
        behavior_refs: list[str],
    ) -> Path:
        definition_id = definition.get("id")
        key = (kind, definition_id)
        if key not in self.frozen:
            raise ValueError(f"{kind}/{definition_id} is outside the frozen G2 holdback")
        if not isinstance(definition_id, str) or definition_id.startswith("test_"):
            raise ValueError("production definition ids cannot use the test_ namespace")
        frozen = self.frozen[key]
        if source_section != frozen.source_section:
            raise ValueError(
                f"{kind}/{definition_id} source section mismatch: "
                f"expected {frozen.source_section}, got {source_section}"
            )
        source_path = self.root / frozen.source_path
        source_text = self.source_cache.setdefault(frozen.source_path, source_path.read_text(encoding="utf-8"))
        row_pattern = rf"^\|\s*{re.escape(definition_id)}\s*\|"
        if not re.search(row_pattern, source_text, re.MULTILINE):
            raise ValueError(
                f"source definition row not found: {frozen.source_path}::{source_section}"
            )
        if any(not isinstance(ref, str) or not ref for ref in behavior_refs):
            raise ValueError(f"{kind}/{definition_id} has an invalid behavior reference")
        record = {
            "kind": kind,
            "id": definition_id,
            "source": {"path": frozen.source_path, "section": source_section},
            "behavior_refs": behavior_refs,
            "definition": definition,
            "status": "staged_pending_schema_and_behavior_verification",
        }
        path = output / "definitions" / f"{kind}_{definition_id}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return path

    def write_plan(self, output: Path) -> None:
        entries = [asdict(item) for item in self.plan()]
        plan = {
            "manifest_id": self.baseline["scope"]["production_manifest_id"],
            "scope_version": self.baseline["scope"]["scope_version"],
            "production_manifest_mutated": False,
            "fixture_namespace": "test_",
            "entries": entries,
            "counts": {
                "total": len(entries),
                "by_kind": {
                    kind: sum(1 for item in entries if item["kind"] == kind)
                    for kind in sorted({item["kind"] for item in entries})
                },
            },
            "inputs": {
                "docs/baselines/g0.json": sha256(self.root / "docs/baselines/g0.json"),
                "data/manifests/content_deferred.json": sha256(self.root / "data/manifests/content_deferred.json"),
                "docs/交大四年_DDL战争_统一设计文档.md": sha256(self.root / "docs/交大四年_DDL战争_统一设计文档.md"),
            },
        }
        output.mkdir(parents=True, exist_ok=True)
        (output / "plan.json").write_text(
            json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    builder = ProductionContentBuilder()
    run_id = "g2-build-" + datetime.now().strftime("%Y%m%d-%H%M%S")
    output = (args.output or STAGING / run_id).resolve()
    builder.write_plan(output)
    plan = read_json(output / "plan.json")
    lines = [
        f"G2 production build plan: {output}",
        f"Frozen definitions staged for construction: {plan['counts']['total']}",
        f"Production manifest mutated: {plan['production_manifest_mutated']}",
        f"Fixture namespace: {plan['fixture_namespace']}",
    ]
    (output / "stdout.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "command.json").write_text(
        json.dumps({"executable": sys.executable, "arguments": sys.argv}, indent=2) + "\n",
        encoding="utf-8",
    )
    (output / "environment.json").write_text(
        json.dumps(
            {"python": sys.version, "cwd": str(ROOT), "platform": os.name},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (output / "exit_code.txt").write_text("0\n", encoding="utf-8")
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
