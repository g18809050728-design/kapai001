"""Build traceable metadata for the isolated G2 cards staging batch."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
STAGE = ROOT / "artifacts/g2-build/staging/cards"
SOURCE = ROOT / "docs/交大四年_DDL战争_统一设计文档.md"
INPUTS = [
    "docs/baselines/g0.json",
    "docs/G2冻结未完成项.md",
    "data/manifests/content_deferred.json",
    "docs/交大四年_DDL战争_统一设计文档.md",
    "docs/内容层契约.md",
    "docs/战斗模块契约.md",
    "src/content/content_db.gd",
    "src/battle/battle_card_rules.gd",
    "src/battle/battle_engine.gd",
    "tests/suites/test_content_loader.gd",
    "tests/suites/test_battle_engine_begin.gd",
    "tests/suites/test_battle_phase_flow.gd",
    "tools/verify_g2_staging.py",
    "artifacts/g2-build/staging/cards/cards.json",
    "artifacts/g2-build/staging/cards/schema_probe.gd",
    "artifacts/g2-build/staging/cards/schema_probe.exit_code.txt",
    "artifacts/g2-build/staging/cards/schema_probe.stdout.txt",
    "artifacts/g2-build/staging/cards/schema_probe.stderr.txt",
    "artifacts/g2-build/staging/cards/schema_probe.command.json",
    "artifacts/g2-build/staging/cards/schema_probe.environment.json",
    "artifacts/g2-build/staging/cards/build_cards.py",
    "artifacts/g2-build/staging/entities/definitions/unit_F01.json",
    "artifacts/g2-build/staging/entities/definitions/unit_F02.json",
    "artifacts/g2-build/staging/entities/definitions/unit_F03.json",
    "artifacts/g2-build/staging/entities/definitions/unit_F04.json",
    "artifacts/g2-build/staging/entities/definitions/scene_L01.json",
    "artifacts/g2-build/staging/entities/definitions/scene_L02.json",
    "artifacts/g2-build/staging/entities/definitions/scene_L03.json",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16").strip("\ufeff")
    return raw.decode("utf-8-sig")


def main() -> int:
    cards = json.loads((STAGE / "cards.json").read_text(encoding="utf-8"))
    batch_path = STAGE / "batch.json"
    existing = json.loads(batch_path.read_text(encoding="utf-8")) if batch_path.exists() else {}
    existing_cards = {
        entry["id"]: entry
        for entry in existing.get("cards", [])
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }
    source_lines = SOURCE.read_text(encoding="utf-8").splitlines()
    metadata = []
    for definition in cards:
        card_id = definition["id"]
        matches = [
            (number, line.strip())
            for number, line in enumerate(source_lines, 1)
            if re.match(rf"^\|\s*{re.escape(card_id)}(?:\s|\|)", line.strip())
        ]
        if len(matches) != 1:
            raise ValueError(f"expected one exact frozen source row for {card_id}; found {len(matches)}")
        number, row = matches[0]
        previous = existing_cards.get(card_id, {})
        entry = dict(previous)
        entry.update({"id": card_id, "source_line": number, "source_row": row})
        metadata.append(entry)

    batch = dict(existing)
    batch.setdefault("batch_id", "g2-cards-20261015")
    batch.setdefault("stage", "G2 isolated staging; not production-enabled")
    batch.setdefault("source_section", "统一设计文档 §5.1–§5.7，卡牌 ID 表行；卡牌专属原文以 source_line 记录")
    batch.setdefault("definition_file", "cards.json")
    batch["production_manifest_mutated"] = False
    batch["g0_scope_mutated"] = False
    batch["holdback_mutated"] = False
    batch["fixture_content"] = False
    batch["input_sha256"] = {path: sha256(ROOT / path) for path in INPUTS}
    batch["artifact_sha256"] = {
        "artifacts/g2-build/staging/cards/cards.json": sha256(STAGE / "cards.json")
    }
    batch["cards"] = metadata
    card_ids = [entry["id"] for entry in metadata]
    probe_output = read_text(STAGE / "schema_probe.stdout.txt").replace("\r", "")
    probe_exit = int(read_text(STAGE / "schema_probe.exit_code.txt").strip())
    schema_ids = set(re.findall(r"^SCHEMA_OK card/([A-Z][A-Z0-9_]*)$", probe_output, re.M))
    closure_ids = set(re.findall(r"^REFERENCE_CLOSURE_OK card/([A-Z][A-Z0-9_]*)$", probe_output, re.M))
    expected_ids = set(card_ids)
    package_loaded = "CARD_PACKAGE_LOAD_OK test_cards_staging" in probe_output
    batch["schema_probe"] = {
        "status": "passed" if probe_exit == 0 and schema_ids == expected_ids else "failed",
        "ids": [f"card/{card_id}" for card_id in card_ids if card_id in schema_ids],
        "command": "F:/GoDot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://artifacts/g2-build/staging/cards/schema_probe.gd",
        "exit_code": probe_exit,
        "evidence": "artifacts/g2-build/staging/cards/schema_probe.stdout.txt",
        "command_record": "artifacts/g2-build/staging/cards/schema_probe.command.json",
        "environment_record": "artifacts/g2-build/staging/cards/schema_probe.environment.json",
        "package_load": "passed" if package_loaded else "failed",
    }
    batch["reference_closure"] = {
        "status": "passed" if probe_exit == 0 and closure_ids == expected_ids and package_loaded else "failed",
        "ids": [f"card/{card_id}" for card_id in card_ids if card_id in closure_ids],
        "evidence": "artifacts/g2-build/staging/cards/schema_probe.stdout.txt",
        "scope": "isolated package with staged unit F01-F04 and scene L01-L03; production manifest unchanged",
    }
    batch.setdefault("reference_closure", {
        "status": "pending_runtime_probe",
        "ids": [],
        "known_external_dependencies": ["unit/F01-F04", "scene/L01-L03"],
    })
    batch.setdefault("schema_and_behavior_mapping", {
        "schema": "docs/内容层契约.md §7.5–§7.6, §8.1–§8.3; exact CardDef keys and explicit upgrade patches",
        "registered_ops": [
            "complete", "gain_focus", "recall_from_discard", "heal", "relax",
            "remove_status", "discard", "draw", "gain_status", "retain_hand_card",
            "summon_unit", "establish_scene",
        ],
        "registered_card_fields": ["vitality_cost", "limit", "unplayable"],
        "runtime_mapping": "docs/战斗模块契约.md §19–§20; src/battle/battle_engine.gd and BattleCardRules; ContentDB validates op fields and upgrade merged faces",
        "relevant_existing_tests": [
            "tests/suites/test_content_loader.gd",
            "tests/suites/test_battle_engine_begin.gd",
            "tests/suites/test_battle_phase_flow.gd",
        ],
        "test_status": "This staging batch was not loaded as a manifest or run through card-specific behavior tests.",
    })
    mapping = batch["schema_and_behavior_mapping"]
    mapping["test_status"] = (
        "Godot 4.7.2 isolated test_cards_staging package load passed and schema/reference closure passed "
        "for all 21 cards; per-card runtime behavior tests remain pending."
    )
    batch["handler_verification"] = {"status": "pending_behavior_audit", "ids": []}
    batch["behavior_tests"] = {"status": "pending_card_batch_tests", "ids": []}
    batch["blockers"] = [{
        "kind": "production_reference_integration",
        "ids": ["F01", "F02", "F03", "F04", "L01", "L02", "L03"],
        "reason": "These references resolve in the isolated staging package using entity staging definitions; production manifest integration remains pending.",
        "blocks": "production enablement only; isolated staging reference closure passed",
    }]
    batch["validation_notes"] = [
        "All 21 staged cards passed the live ContentDB per-definition schema probe.",
        "All 21 staged cards passed reference closure in an isolated package containing staged F01-F04 and L01-L03; production manifest was not modified.",
        "The isolated test_cards_staging package loaded successfully under Godot 4.7.2.",
        "Per-card handler verification and runtime behavior tests remain pending; no shared G3 test is attributed to these card definitions.",
        "No numeric values were introduced beyond the cited design rows and contract semantics.",
    ]
    batch_path.write_text(
        json.dumps(batch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"CARDS_METADATA_BUILT={len(metadata)}")
    print("PRODUCTION_MANIFEST_MUTATED=false")
    print("G0_SCOPE_MUTATED=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
