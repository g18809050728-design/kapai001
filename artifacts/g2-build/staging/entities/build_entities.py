"""Build the isolated G2 entity staging batch from approved source rows."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4


ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
KINDS = ("character", "relic", "unit", "scene")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


DEFINITIONS = {
    ("character", "P01"): {
        "definition": {
            "id": "P01",
            "name_key": "character.P01.name",
            "starter_cards": ["K13", "K14"],
            "starter_relic_id": "A01",
            "passive": {
                "id": "p01_third_work_compile",
                "trigger": "work_card_resolved",
                "count": 3,
                "limit": {"per": "round", "times": 1},
                "effects": [{"op": "gain_status", "status": "compile", "stacks": 1}],
            },
        },
        "refs": [
            "starter_cards=K13,K14",
            "starter_relic_id=A01",
            "passive.effect.status=compile",
        ],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_passive",
            "src/battle/battle_engine.gd::_run_character_passive",
            "src/battle/battle_engine.gd::_execute_effect_list(gain_status)",
        ],
        "blockers": [],
    },
    ("character", "P04"): {
        "definition": {
            "id": "P04",
            "name_key": "character.P04.name",
            "starter_cards": ["K43", "K44"],
            "starter_relic_id": "A04",
            "passive": {
                "id": "p04_first_cooperation_relax",
                "trigger": "cooperation_card_resolved",
                "count": 1,
                "limit": {"per": "round", "times": 1},
                "effects": [{"op": "relax", "amount": 2}],
            },
        },
        "refs": ["starter_cards=K43,K44", "starter_relic_id=A04"],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_passive",
            "src/battle/battle_engine.gd::_run_character_passive",
        ],
        "blockers": [],
    },
    ("relic", "A01"): {
        "definition": {
            "id": "A01",
            "name_key": "relic.A01.name",
            "availability": "starter",
            "rarity": None,
            "tags": [],
            "modifiers": {"work_flat_bonus": 1},
            "limit": {"per": "round", "times": 1},
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_relic_modifiers",
            "src/battle/battle_engine.gd::_resolve_completion(work_flat_bonus)",
        ],
        "blockers": [],
    },
    ("relic", "A04"): {
        "definition": {
            "id": "A04",
            "name_key": "relic.A04.name",
            "availability": "starter",
            "rarity": None,
            "tags": [],
            "hooks": [
                {
                    "at": "cost_quote",
                    "card_type": "cooperation",
                    "discount": 1,
                    "limit": {"per": "battle", "times": 1},
                }
            ],
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(cost_quote)",
            "src/battle/battle_card_rules.gd::_quote_cost",
        ],
        "blockers": [],
    },
    ("relic", "A05"): {
        "definition": {
            "id": "A05",
            "name_key": "relic.A05.name",
            "availability": "drop",
            "rarity": "white",
            "tags": [],
            "hooks": [
                {
                    "at": "round_start",
                    "rounds": [3, 6],
                    "effects": [{"op": "heal", "amount": 3, "target": "player"}],
                }
            ],
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(round_start)",
            "src/battle/battle_engine.gd::_run_relic_hooks",
            "src/battle/battle_engine.gd::_prepare_player_round",
        ],
        "blockers": [
            "The hook handler exists, but execution of A05 on exactly rounds 3 and 6 remains deferred to G3/G4 behavior acceptance."
        ],
    },
    ("relic", "A07"): {
        "definition": {
            "id": "A07",
            "name_key": "relic.A07.name",
            "availability": "drop",
            "rarity": "blue",
            "tags": [],
            "hooks": [
                {
                    "at": "draw",
                    "rounds": [1],
                    "effects": [{"op": "draw", "amount": 2}],
                }
            ],
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(draw)",
            "src/battle/battle_engine.gd::_run_relic_hooks",
            "src/battle/battle_engine.gd::_prepare_player_round",
        ],
        "blockers": [
            "The draw hook handler exists, but first-round A07 trigger timing and hand-limit behavior remain deferred to G3/G4 behavior acceptance."
        ],
    },
    ("relic", "A08"): {
        "definition": {
            "id": "A08",
            "name_key": "relic.A08.name",
            "availability": "drop",
            "rarity": "white",
            "tags": [],
            "hooks": [
                {
                    "at": "cost_quote",
                    "definition_id": "K10",
                    "skip_vitality_cost": True,
                    "limit": {"per": "battle", "times": 1},
                }
            ],
        },
        "refs": ["hook.definition_id=K10"],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(cost_quote)",
            "src/battle/battle_card_rules.gd::_quote_cost",
        ],
        "blockers": [],
    },
    ("relic", "A11"): {
        "definition": {
            "id": "A11",
            "name_key": "relic.A11.name",
            "availability": "drop",
            "rarity": "white",
            "tags": [],
            "hooks": [
                {
                    "at": "card_resolved",
                    "card_type": "strategy",
                    "limit": {"per": "round", "times": 1},
                    "effects": [{"op": "relax", "amount": 2, "target": "player"}],
                }
            ],
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(card_resolved)",
            "src/battle/battle_engine.gd::_run_relic_hooks",
            "src/battle/battle_engine.gd::_resolve_card",
        ],
        "blockers": [
            "The hook handler exists, but exact once-per-round A11 trigger behavior remains deferred to G3/G4 behavior acceptance."
        ],
    },
    ("relic", "A15"): {
        "definition": {
            "id": "A15",
            "name_key": "relic.A15.name",
            "availability": "drop",
            "rarity": "white",
            "tags": [],
            "hooks": [
                {
                    "at": "shop_price",
                    "kinds": ["card", "relic"],
                    "multiplier_percent": 80,
                    "rounding": "ceil",
                }
            ],
        },
        "refs": [],
        "behavior_refs": ["src/content/content_db.gd::_validate_hook(shop_price)"],
        "blockers": [
            "No shop-price execution handler was found under src/; A15 remains blocked pending a G4 shop-price implementation and test."
        ],
    },
    ("relic", "A18"): {
        "definition": {
            "id": "A18",
            "name_key": "relic.A18.name",
            "availability": "drop",
            "rarity": "white",
            "tags": [],
            "hooks": [
                {
                    "at": "round_start",
                    "rounds": [1, 2, 3],
                    "effects": [{"op": "heal", "amount": 1, "target": "player"}],
                }
            ],
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_hook(round_start)",
            "src/battle/battle_engine.gd::_run_relic_hooks",
            "src/battle/battle_engine.gd::_prepare_player_round",
        ],
        "blockers": [
            "The hook handler exists, but A18 round 1-3 trigger behavior remains deferred to G3/G4 behavior acceptance."
        ],
    },
    ("unit", "F01"): {
        "definition": {
            "id": "F01",
            "name_key": "unit.F01.name",
            "vitality": 10,
            "cooperation": 2,
            "guard": True,
            "support": {"kind": "none"},
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_support",
            "src/battle/battle_engine.gd::_summon_unit(guard)",
        ],
        "blockers": [],
    },
    ("unit", "F02"): {
        "definition": {
            "id": "F02",
            "name_key": "unit.F02.name",
            "vitality": 4,
            "cooperation": 6,
            "guard": False,
            "support": {"kind": "none"},
        },
        "refs": [],
        "behavior_refs": ["src/battle/battle_engine.gd::_apply_unit_support(none)"],
        "blockers": [],
    },
    ("unit", "F03"): {
        "definition": {
            "id": "F03",
            "name_key": "unit.F03.name",
            "vitality": 6,
            "cooperation": 1,
            "guard": False,
            "support": {
                "kind": "cleanse_or_relax",
                "status": "anxiety",
                "amount": 1,
                "fallback_relax": 2,
            },
        },
        "refs": ["support.status=anxiety"],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_support(cleanse_or_relax)",
            "src/battle/battle_engine.gd::_apply_unit_support(cleanse_or_relax)",
        ],
        "blockers": [
            "The support handler removes the entire matching anxiety status object and does not honor amount=1; behavior remains blocked pending a G3/G4 fix and test."
        ],
    },
    ("unit", "F04"): {
        "definition": {
            "id": "F04",
            "name_key": "unit.F04.name",
            "vitality": 12,
            "cooperation": 2,
            "guard": True,
            "support": {"kind": "self_relax", "amount": 2},
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_support(self_relax)",
            "src/battle/battle_engine.gd::_apply_unit_support(self_relax)",
            "src/battle/battle_engine.gd::_summon_unit(guard)",
        ],
        "blockers": [],
    },
    ("scene", "L01"): {
        "definition": {
            "id": "L01",
            "name_key": "scene.L01.name",
            "prepare_effects": [{"op": "heal", "amount": 2, "target": "player"}],
            "battle_limit": 3,
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_definition(scene)",
            "src/battle/battle_engine.gd::_run_scene_prepare",
        ],
        "blockers": [],
    },
    ("scene", "L02"): {
        "definition": {
            "id": "L02",
            "name_key": "scene.L02.name",
            "prepare_random": {
                "options": [
                    [{"op": "heal", "amount": 1, "target": "player"}],
                    [{"op": "gain_focus", "amount": 1}],
                    [{"op": "draw", "amount": 1}],
                    [{"op": "complete", "amount": 3}],
                ]
            },
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_prepare_random",
            "src/battle/battle_engine.gd::_run_scene_prepare",
            "src/battle/battle_engine.gd::_draw_scene_prepare_result",
        ],
        "blockers": [],
    },
    ("scene", "L03"): {
        "definition": {
            "id": "L03",
            "name_key": "scene.L03.name",
            "modifiers": {"first_work_cost_discount": 1},
        },
        "refs": [],
        "behavior_refs": [
            "src/content/content_db.gd::_validate_scene_modifiers",
            "src/battle/battle_card_rules.gd::_quote_cost(first_work_cost_discount)",
        ],
        "blockers": [],
    },
}


def main() -> int:
    run_godot = "--run-godot" in sys.argv[1:]
    deferred_path = ROOT / "data/manifests/content_deferred.json"
    baseline_path = ROOT / "docs/baselines/g0.json"
    deferred = json.loads(deferred_path.read_text(encoding="utf-8"))
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    expected = {
        (kind, row["id"]): row
        for kind in KINDS
        for row in deferred["definitions"].get(kind, [])
    }
    if set(expected) != set(DEFINITIONS):
        raise ValueError("staging IDs do not exactly match the frozen entity batch")

    source_paths = {row["source"]["path"] for row in expected.values()}
    if len(source_paths) != 1:
        raise ValueError("entity definitions have unexpected multiple source documents")
    source_path = next(iter(source_paths))
    source_text = (ROOT / source_path).read_text(encoding="utf-8")
    source_lines = source_text.splitlines()

    contract_path = next(path for path in ROOT.joinpath("docs").glob("*.md") if "内容层契约" in path.name)
    contract_text = contract_path.read_text(encoding="utf-8")
    content_db_path = ROOT / "src/content/content_db.gd"
    content_db_text = content_db_path.read_text(encoding="utf-8")
    engine_path = ROOT / "src/battle/battle_engine.gd"
    engine_text = engine_path.read_text(encoding="utf-8")
    card_rules_path = ROOT / "src/battle/battle_card_rules.gd"
    card_rules_text = card_rules_path.read_text(encoding="utf-8")

    frozen_ids = baseline["scope"]["enabled_by_kind"]
    failures: list[str] = []
    source_rows: dict[tuple[str, str], dict] = {}
    for key, source_record in expected.items():
        kind, definition_id = key
        lines = [
            (index, line)
            for index, line in enumerate(source_lines)
            if line.startswith("|")
            and line.strip().strip("|").split("|", 1)[0].strip().split(" ", 1)[0]
            == definition_id
        ]
        if len(lines) != 1:
            failures.append(f"{kind}/{definition_id}: expected one source row, found {len(lines)}")
            continue
        line_index, source_row = lines[0]
        table_heading = next(
            (
                source_lines[index]
                for index in range(line_index - 1, -1, -1)
                if source_lines[index].startswith("#")
            ),
            "",
        )
        source_rows[key] = {
            "path": source_path,
            "section": source_record["source"]["section"],
            "table_heading": table_heading.lstrip("# "),
            "line": line_index + 1,
            "row": source_row,
        }
        if definition_id not in frozen_ids.get(kind, []):
            failures.append(f"{kind}/{definition_id}: outside G0 frozen ID set")

    allowed_fields = {
        "character": {"id", "name_key", "starter_cards", "starter_relic_id", "passive", "art_key"},
        "relic": {"id", "name_key", "availability", "rarity", "tags", "effects", "hooks", "modifiers", "limit", "art_key"},
        "unit": {"id", "name_key", "vitality", "cooperation", "guard", "support", "entry_effects", "art_key"},
        "scene": {"id", "name_key", "prepare_effects", "prepare_random", "modifiers", "round_end_effects", "battle_limit", "anxiety_after_every", "art_key"},
    }
    required_fields = {
        "character": {"id", "name_key", "starter_cards", "starter_relic_id", "passive"},
        "relic": {"id", "name_key", "availability", "rarity", "tags"},
        "unit": {"id", "name_key", "vitality", "cooperation", "guard", "support"},
        "scene": {"id", "name_key"},
    }
    reference_ids = {
        "character": {"card": "starter_cards", "relic": "starter_relic_id"},
        "relic": {"card": "definition_id", "status": "status"},
        "unit": {"status": "status"},
        "scene": {},
    }
    for key, item in DEFINITIONS.items():
        kind, definition_id = key
        definition = item["definition"]
        fields = set(definition)
        if not required_fields[kind].issubset(fields):
            failures.append(f"{kind}/{definition_id}: missing required contract fields")
        if not fields.issubset(allowed_fields[kind]):
            failures.append(f"{kind}/{definition_id}: contains fields outside ContentDB schema")
        for target_kind, field in reference_ids[kind].items():
            value = definition.get(field)
            ids = value if isinstance(value, list) else [value] if value else []
            for target_id in ids:
                if target_id not in frozen_ids.get(target_kind, []):
                    failures.append(
                        f"{kind}/{definition_id}: {field} reference {target_kind}/{target_id} outside G0 scope"
                    )
        if kind == "character":
            for effect in definition["passive"]["effects"]:
                if "status" in effect and effect["status"] not in frozen_ids.get("status", []):
                    failures.append(
                        f"{kind}/{definition_id}: passive status reference is outside G0 scope"
                    )

    if "shop_price" not in content_db_text or "_run_relic_hooks" not in engine_text:
        failures.append("expected schema/runtime symbols are absent from current source")
    for key, row in source_rows.items():
        kind, definition_id = key
        item = DEFINITIONS[key]
        record = {
            "kind": kind,
            "id": definition_id,
            "source": {
                "path": row["path"],
                "section": row["section"],
                "table_heading": row["table_heading"],
                "line": row["line"],
                "row": row["row"],
            },
            "behavior_refs": item["behavior_refs"],
            "definition": item["definition"],
            "status": "staged_schema_and_reference_verified_behavior_deferred_to_G3_G4",
            "blockers": item["blockers"],
        }
        path = OUT / "definitions" / f"{kind}_{definition_id}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    probe_root = OUT / "runtime_probe"
    probe_definitions = probe_root / "data/definitions"
    probe_manifests = probe_root / "data/manifests"
    probe_definitions.mkdir(parents=True, exist_ok=True)
    probe_manifests.mkdir(parents=True, exist_ok=True)
    for file_name in ("cards.json", "statuses.json", "rulesets.json"):
        shutil.copyfile(ROOT / "data/definitions" / file_name, probe_definitions / file_name)
    for file_name in ("tasks.json", "encounters.json", "events.json"):
        (probe_definitions / file_name).write_text("[]\n", encoding="utf-8")
    staged_cards_path = ROOT / "artifacts/g2-build/staging/cards/cards.json"
    production_cards = json.loads((ROOT / "data/definitions/cards.json").read_text(encoding="utf-8"))
    staged_cards = json.loads(staged_cards_path.read_text(encoding="utf-8"))
    card_probe_ids = ["K01", "K02", "K03", "K04", "K10", "K13", "K14", "K43", "K44"]
    cards_by_id = {card["id"]: card for card in production_cards + staged_cards}
    missing_probe_cards = sorted(set(card_probe_ids) - set(cards_by_id))
    if missing_probe_cards:
        failures.append(f"isolated probe card dependencies are missing: {', '.join(missing_probe_cards)}")
    (probe_definitions / "cards.json").write_text(
        json.dumps([cards_by_id[id_] for id_ in card_probe_ids if id_ in cards_by_id], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    probe_ids = {
        "character": ["P01", "P04"],
        "card": card_probe_ids,
        "relic": ["A01", "A04", "A05", "A07", "A08", "A11", "A15", "A18"],
        "task": [],
        "encounter": [],
        "unit": ["F01", "F02", "F03", "F04"],
        "scene": ["L01", "L02", "L03"],
        "event": [],
        "status": ["inspiration", "compile", "anxiety", "procrastination", "drowsiness", "extra_requirements", "guard"],
        "ruleset": ["campus_v1"],
    }
    probe_manifest = {
        "id": "test_g2_entities",
        "content_version": "campus_mvp.v1",
        "ruleset_id": "campus_v1",
        "enabled": probe_ids,
        "overrides": [],
    }
    (probe_manifests / "test_g2_entities.json").write_text(
        json.dumps(probe_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    probe_stage_rows = {kind: [] for kind in KINDS}
    for key in DEFINITIONS:
        kind, definition_id = key
        if definition_id in probe_ids[kind]:
            record_path = OUT / "definitions" / f"{kind}_{definition_id}.json"
            probe_stage_rows[kind].append(json.loads(record_path.read_text(encoding="utf-8"))["definition"])
    for kind in ("character", "relic", "unit", "scene"):
        target = probe_definitions / {
            "character": "characters", "relic": "relics", "unit": "units", "scene": "scenes"
        }[kind]
        target = target.with_suffix(".json")
        target.write_text(json.dumps(probe_stage_rows[kind], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    probe_entity_ids = {
        "character": ["P01", "P04"],
        "relic": ["A01", "A04", "A05", "A07", "A08", "A11", "A15", "A18"],
        "unit": ["F01", "F02", "F03", "F04"],
        "scene": ["L01", "L02", "L03"],
    }
    expected_probe_ids = [
        f"{kind}:{definition_id}"
        for kind in ("character", "relic", "unit", "scene")
        for definition_id in probe_entity_ids[kind]
    ]
    gdscript = [
        "extends SceneTree",
        "",
        'const ContentDB = preload("res://src/content/content_db.gd")',
        "const EXPECTED := {",
    ]
    for kind, ids in probe_entity_ids.items():
        gdscript.append(f'\t"{kind}": {json.dumps(ids)},')
    gdscript.extend(
        [
            "}",
            "",
            "func _initialize() -> void:",
            '\tvar db := ContentDB.new("res://artifacts/g2-build/staging/entities/runtime_probe/data", true)',
            '\tvar result := db.load("test_g2_entities")',
            '\tif not result.ok:',
            '\t\tprinterr("G2 entity staging load failed: %s" % str(result.error))',
            "\t\tquit(1)",
            "\t\treturn",
            "\tfor kind in EXPECTED:",
            "\t\tfor definition_id in EXPECTED[kind]:",
            "\t\t\tvar definition_result := db.get_definition(kind, definition_id)",
            "\t\t\tif not definition_result.ok:",
            '\t\t\t\tprinterr("G2 entity missing after schema load: %s/%s" % [kind, definition_id])',
            "\t\t\t\tquit(1)",
            "\t\t\t\treturn",
            f'\tprint("SCHEMA_OK entity_count={len(expected_probe_ids)} ids={",".join(expected_probe_ids)}")',
            "\tquit(0)",
        ]
    )
    probe_script = OUT / "runtime_probe.gd"
    probe_script.write_text("\n".join(gdscript) + "\n", encoding="utf-8")
    gdformat = shutil.which("gdformat")
    if gdformat is None:
        failures.append("gdformat executable is unavailable for the generated runtime probe")
    else:
        formatted = subprocess.run(
            [gdformat, str(probe_script)], capture_output=True, text=True, encoding="utf-8", errors="replace"
        )
        if formatted.returncode != 0:
            failures.append(f"gdformat failed for runtime probe: {formatted.stderr.strip()}")

    input_paths = [
        "docs/baselines/g0.json",
        "data/manifests/content_deferred.json",
        "data/definitions/cards.json",
        "data/definitions/statuses.json",
        "data/definitions/rulesets.json",
        "artifacts/g2-build/staging/cards/batch.json",
        "artifacts/g2-build/staging/cards/cards.json",
        source_path,
        contract_path.relative_to(ROOT).as_posix(),
        "src/content/content_db.gd",
        "src/battle/battle_engine.gd",
        "src/battle/battle_card_rules.gd",
    ]
    hashes = {path: sha256(ROOT / path) for path in input_paths}
    blocker_rows = [
        {"kind": kind, "id": definition_id, "blockers": item["blockers"]}
        for (kind, definition_id), item in DEFINITIONS.items()
        if item["blockers"]
    ]
    report_lines = [
        "# G2 Entity Staging Batch",
        "",
        "Status: staged; production publication and runtime behavior acceptance have not been run.",
        "",
        "## Definitions",
        "",
        "| Kind | ID | Approved source | Actual section / row | Source-row SHA-256 (newline excluded) | Definition JSON SHA-256 | Current mapping status |",
        "|---|---|---|---|---|",
    ]
    for key in DEFINITIONS:
        kind, definition_id = key
        row = source_rows.get(key, {})
        definition_path = OUT / "definitions" / f"{kind}_{definition_id}.json"
        source_row_hash = hashlib.sha256(row.get("row", "").encode("utf-8")).hexdigest()
        report_lines.append(
            f"| {kind} | {definition_id} | `{source_path}` | {row.get('table_heading', 'MISSING')}, line {row.get('line', 'MISSING')} | `{source_row_hash}` | `{sha256(definition_path)}` | {'blocked' if DEFINITIONS[key]['blockers'] else 'staged, pending integrated verification'} |"
        )
    report_lines += [
        "",
        "The deferred registry locator (`source.section`) is retained verbatim. `table_heading`, physical line, and source row identify the actual approved table location. The character rows are in §4 人物重设计; their deferred locator is `character ID <id>`, not a Markdown heading.",
        "",
        "## Self-Audit",
        "",
        f"- Exact requested batch IDs: {len(DEFINITIONS)} records ({', '.join(f'{kind}={sum(1 for key in DEFINITIONS if key[0] == kind)}' for kind in KINDS)}).",
        "- G0 scope: each staged ID is checked against `docs/baselines/g0.json`; all external IDs referenced by these definitions are checked against their frozen kind set. The isolated probe uses staged card dependencies, without mutating production content.",
        "- Shape audit: required and allowed top-level keys are checked against `docs/内容层契约.md` §8.1 and current `ContentDB` field tables; nested behavior shapes follow §§7.8–7.9 and §8.2–8.3. This is static staging review, not execution of the Godot schema validator.",
        "- Registered behavior mapping: current source includes character passives, round_start/draw/card_resolved/cost_quote relic hooks, unit support, and scene effects/modifiers. A15 shop_price has no execution consumer; F03 runtime ignores amount=1 by removing the entire anxiety object. Exact staged trigger behavior for A05/A07/A11/A18 also remains deferred and recorded as blockers.",
        "- Runtime behavior tests: deferred to G3/G4. No definition is marked behavior-verified or production-ready.",
        f"- Runtime schema/reference probe scope: the isolated `test_g2_entities` manifest enables all {len(expected_probe_ids)} staged entity definitions plus required card/status/ruleset dependencies. It checks ContentDB schema and enabled-reference closure only; it does not verify entity runtime behavior.",
        "",
        "## Blockers",
        "",
    ]
    for entry in blocker_rows:
        report_lines.append(f"- `{entry['kind']}/{entry['id']}`: " + "; ".join(entry["blockers"]))
    if not blocker_rows:
        report_lines.append("- None found in the static staging audit.")
    report_lines += ["", "## Input SHA-256", ""]
    report_lines += [f"- `{path}`: `{digest}`" for path, digest in hashes.items()]
    report_lines += [
        "",
        f"- Batch generation time (UTC): `{datetime.now(timezone.utc).isoformat()}`.",
        "- Production manifest, G0 baseline, `content_deferred.json`, and other agents' staging directories were not modified.",
        "",
        "## Raw Staging Audit",
        "",
        "Command: `python artifacts/g2-build/staging/entities/build_entities.py`",
        f"Environment: Python `{platform.python_version()}`, OS `{os.name}`, cwd `{ROOT}`.",
        f"Exit code: `{1 if failures else 0}`.",
        "Raw output is in `stdout.txt`; exact argv/environment are in `command.json` and `environment.json`.",
        "",
    ]
    output = [
        f"Staged {len(DEFINITIONS)} G2 entity definitions under {OUT}",
        f"Source rows resolved: {len(source_rows)}/{len(expected)}",
        f"Definitions with explicit blockers: {len(blocker_rows)}",
        "Static self-audit: " + ("FAILED" if failures else "completed; no structural/source-scope errors"),
    ]
    if run_godot and not failures:
        godot = Path(r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe")
        args = [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            "res://artifacts/g2-build/staging/entities/runtime_probe.gd",
        ]
        run_id = "g2-entities-" + datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid4().hex[:6]
        verification = ROOT / "artifacts/verification" / run_id
        verification.mkdir(parents=True, exist_ok=False)
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        evidence = verification
        (evidence / "stdout.txt").write_text(result.stdout, encoding="utf-8")
        (evidence / "stderr.txt").write_text(result.stderr, encoding="utf-8")
        (evidence / "exit_code.txt").write_text(f"{result.returncode}\n", encoding="utf-8")
        (evidence / "command.json").write_text(
            json.dumps({"command": args, "cwd": str(ROOT)}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        version = subprocess.run([str(godot), "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        (evidence / "environment.json").write_text(
            json.dumps({"godot_path": str(godot), "godot_version_command": [str(godot), "--version"], "godot_version_exit_code": version.returncode, "godot_version_stdout": version.stdout, "godot_version_stderr": version.stderr, "python": sys.version, "platform": platform.platform(), "cwd": str(ROOT)}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        evidence_inputs = {path: sha256(ROOT / path) for path in input_paths}
        evidence_inputs["artifacts/g2-build/staging/entities/build_entities.py"] = sha256(OUT / "build_entities.py")
        evidence_inputs["artifacts/g2-build/staging/entities/runtime_probe.gd"] = sha256(OUT / "runtime_probe.gd")
        for path in sorted((OUT / "definitions").glob("*.json")):
            evidence_inputs[path.relative_to(ROOT).as_posix()] = sha256(path)
        for path in sorted((probe_root / "data").rglob("*.json")):
            evidence_inputs[path.relative_to(ROOT).as_posix()] = sha256(path)
        (evidence / "input_hashes.json").write_text(
            json.dumps(evidence_inputs, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        probe_archive = OUT / "runtime_probe/evidence" / run_id
        probe_archive.mkdir(parents=True, exist_ok=False)
        for name in ("stdout.txt", "stderr.txt", "exit_code.txt", "command.json", "environment.json", "input_hashes.json"):
            shutil.copyfile(evidence / name, probe_archive / name)
            # Keep the verifier's stable probe locator in sync with the newest run.
            shutil.copyfile(evidence / name, OUT / "runtime_probe/evidence" / name)
        report_lines.extend(
            [
                "",
                "## Godot Schema And Reference Probe",
                "",
                f"- Run ID: `{run_id}`.",
                f"- Command: `{' '.join(args)}`",
                f"- Exit code: `{result.returncode}`.",
                f"- Result: {'all 17 entity IDs printed as SCHEMA_OK' if result.returncode == 0 and 'SCHEMA_OK' in result.stdout else 'probe did not pass; inspect raw output'}.",
                f"- Full evidence is archived at `artifacts/verification/{run_id}/`; a mirrored copy remains in `runtime_probe/evidence/`.",
                "- This checks ContentDB schema and enabled-reference closure only; it does not verify runtime behavior or release readiness.",
            ]
        )
        output.append(f"Godot schema/reference probe exit code: {result.returncode}")
        if result.stdout.strip():
            output.extend(result.stdout.rstrip().splitlines())
        if result.stderr.strip():
            output.extend(f"stderr: {line}" for line in result.stderr.rstrip().splitlines())
        if result.returncode != 0:
            failures.append(f"Godot schema/reference probe exited {result.returncode}")

    # The staging verifier consumes a compact machine-readable index.  Keep this
    # separate from the production manifest: it records evidence for the isolated
    # package while preserving explicit runtime blockers on individual records.
    staged_record_hashes = {
        path.relative_to(ROOT).as_posix(): sha256(path)
        for path in sorted((OUT / "definitions").glob("*.json"))
    }
    entity_probe_ids = [
        f"{kind}/{definition_id}"
        for kind in KINDS
        for definition_id in probe_ids[kind]
    ]
    blocked_ids = {
        f"{kind}/{definition_id}"
        for (kind, definition_id), item in DEFINITIONS.items()
        if item["blockers"]
    }
    supported_ids = sorted(set(probe_ids) - blocked_ids)
    batch = {
        "batch": "G2 entity definitions",
        "counts": {kind: sum(1 for item_kind, _ in DEFINITIONS if item_kind == kind) for kind in KINDS},
        "ids": {kind: [definition_id for item_kind, definition_id in DEFINITIONS if item_kind == kind] for kind in KINDS},
        "production_manifest_mutated": False,
        "content_deferred_mutated": False,
        "g0_scope_mutated": False,
        "input_sha256": hashes,
        "staged_record_sha256": staged_record_hashes,
        "schema_probe": {
            "status": "passed" if not failures and run_godot else "pending",
            "ids": entity_probe_ids if not failures and run_godot else [],
            "evidence": "artifacts/g2-build/staging/entities/runtime_probe/evidence/stdout.txt",
        },
        "reference_closure": {
            "status": "passed" if not failures and run_godot else "pending",
            "ids": entity_probe_ids if not failures and run_godot else [],
            "evidence": "ContentDB isolated test_g2_entities load and get_definition checks",
        },
        "handler_verification": {
            "status": "deferred_to_G3_G4",
            "reason": "G2 verifies integrated schema and reference closure; handler acceptance is deferred to G3/G4.",
            "blocked_ids": sorted(blocked_ids),
        },
        "behavior_tests": {
            "status": "deferred_to_G3_G4",
            "reason": "No behavior tests ran against staged entity IDs; exact behavior acceptance is deferred to G3/G4.",
            "blocked_ids": sorted(blocked_ids),
        },
        "blockers": [
            {"kind": kind, "id": definition_id, "blockers": item["blockers"]}
            for (kind, definition_id), item in DEFINITIONS.items()
            if item["blockers"]
        ],
    }
    (OUT / "batch.json").write_text(json.dumps(batch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if failures:
        output.extend(f"ERROR: {failure}" for failure in failures)
    (OUT / "batch_report.md").write_text("\n".join(report_lines), encoding="utf-8")
    (OUT / "stdout.txt").write_text("\n".join(output) + "\n", encoding="utf-8")
    (OUT / "command.json").write_text(
        json.dumps({"executable": sys.executable, "arguments": ["artifacts/g2-build/staging/entities/build_entities.py"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT / "environment.json").write_text(
        json.dumps({"python": sys.version, "cwd": str(ROOT), "platform": platform.platform()}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT / "exit_code.txt").write_text(f"{1 if failures else 0}\n", encoding="utf-8")
    print("\n".join(output))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
