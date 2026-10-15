"""Generate the flow-content staging batch from frozen G2 definitions."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from tools.g2_content_builder import ProductionContentBuilder, read_json, sha256


OUTPUT = Path(__file__).resolve().parent
DESIGN_PATH = "docs/交大四年_DDL战争_统一设计文档.md"
CONTRACT_PATH = "docs/内容层契约.md"
DESIGN = ROOT / DESIGN_PATH


def intent(index: int, suffix: str, **values: object) -> dict:
    return {"index": index, "text_key": suffix, **values}


def phase(phase_key: str, work_max: int, intents: list[dict], name_key: str) -> dict:
    return {
        "phase_key": phase_key,
        "name_key": name_key,
        "work_max": work_max,
        "intents": intents,
    }


def task(
    id_: str, name_key: str, kind: str, phases: list[dict]
) -> dict:
    return {"id": id_, "name_key": name_key, "kind": kind, "phases": phases}


TASKS = {
    "N01": task(
        "N01", "task.n01.name", "normal",
        [phase("main", 24, [
            intent(0, "task.n01.intent.pressure5", pressure=5),
            intent(1, "task.n01.intent.pressure7", pressure=7),
        ], "task.n01.phase.main.name")],
    ),
    "N02": task(
        "N02", "task.n02.name", "normal",
        [phase("main", 28, [
            intent(0, "task.n02.intent.shield5", shield=5),
            intent(1, "task.n02.intent.pressure8", pressure=8),
        ], "task.n02.phase.main.name")],
    ),
    "N03": task(
        "N03", "task.n03.name", "normal",
        [phase("main", 30, [
            intent(0, "task.n03.intent.pressure6", pressure=6),
            intent(1, "task.n03.intent.add_x01_pressure4", pressure=4,
                   add_card={"card": "X01", "count": 1, "zone": "discard"}),
        ], "task.n03.phase.main.name")],
    ),
    "N04": task(
        "N04", "task.n04.name", "normal",
        [phase("main", 32, [
            intent(0, "task.n04.intent.anxiety1", gain_status={
                "status": "anxiety", "stacks": 1, "target": "player"
            }),
            intent(1, "task.n04.intent.pressure9", pressure=9),
        ], "task.n04.phase.main.name")],
    ),
    "Q01": task(
        "Q01", "task.q01.name", "elite",
        [phase("main", 38, [
            intent(0, "task.q01.intent.pressure7", pressure=7),
            intent(1, "task.q01.intent.shield6", shield=6),
            intent(2, "task.q01.intent.pressure10", pressure=10),
        ], "task.q01.phase.main.name")],
    ),
    "B01": task(
        "B01", "task.b01.name", "boss",
        [
            phase("limits", 20, [
                intent(0, "task.b01.intent.pressure7", pressure=7),
                intent(1, "task.b01.intent.shield5", shield=5),
                intent(2, "task.b01.intent.pressure9", pressure=9),
            ], "task.b01.phase.limits.name"),
            phase("integrals", 25, [
                intent(0, "task.b01.intent.pressure7", pressure=7),
                intent(1, "task.b01.intent.shield5", shield=5),
                intent(2, "task.b01.intent.pressure9", pressure=9),
            ], "task.b01.phase.integrals.name"),
            phase("proofs", 25, [
                intent(0, "task.b01.intent.pressure7", pressure=7),
                intent(1, "task.b01.intent.shield5", shield=5),
                intent(2, "task.b01.intent.pressure9", pressure=9),
            ], "task.b01.phase.proofs.name"),
        ],
    ),
}


ENCOUNTER_ROWS = {
    "N01": ("normal", ["N01"], 8, [1, 2], []),
    "N02": ("normal", ["N02"], 8, [1, 2], []),
    "N03": ("normal", ["N03"], 8, [1, 2, 3], []),
    "N04": ("normal", ["N04"], 8, [2, 3], []),
    "Q01": ("elite", ["Q01"], 6, [1, 2], ["independent_answer"]),
    "B01": ("boss", ["B01"], 10, [1], ["independent_answer", "fixed_exam_room"]),
}
ENCOUNTERS = {
    id_: {
        "id": id_,
        "name_key": f"encounter.{id_.lower()}.name",
        "kind": values[0],
        "members": values[1],
        "base_ddl": values[2],
        "terms": values[3],
        "exam_flags": values[4],
    }
    for id_, values in ENCOUNTER_ROWS.items()
}


def option(option_id: str, **values: object) -> dict:
    effects = values.pop("effects")
    cost = values.pop("cost", {})
    return {
        "option_id": option_id,
        "label_key": f"event.option.{option_id}",
        "cost": cost,
        "effects": effects,
    }


EVENTS = {
    "V01": {
        "id": "V01", "name_key": "event.v01.name", "terms": list(range(1, 9)),
        "once_per_run": True,
        "options": [
            option("return_home", effects=[{"op": "gain_relic", "rarity": "white",
                                            "count": 1, "fallback_money": 20}]),
            option("travel", effects=[{"op": "gain_card", "rarity": "blue",
                                       "candidate_count": 3}]),
            option("play_games", effects=[{"op": "heal", "amount": 24}]),
            option("leave", effects=[]),
        ],
    },
    "V03": {
        "id": "V03", "name_key": "event.v03.name", "terms": [1, 2, 3],
        "once_per_run": True,
        "options": [
            option("consult", effects=[{"op": "gain_card",
                                         "card_pool": ["K14", "K24", "K34"],
                                         "selection_count": 1, "fallback_money": 20}]),
            option("drop", cost={"vitality": 5},
                   effects=[{"op": "remove_card", "tag_filter": "basic"}]),
            option("leave", effects=[]),
        ],
    },
    "V04": {
        "id": "V04", "name_key": "event.v04.name", "terms": [1, 2, 3, 4],
        "once_per_run": True,
        "options": [
            option("rest", effects=[{"op": "heal", "amount": 10}]),
            option("upgrade_work", cost={"vitality": 6},
                   effects=[{"op": "upgrade_card", "type_filter": "work"}]),
            option("leave", effects=[]),
        ],
    },
    "V10": {
        "id": "V10", "name_key": "event.v10.name", "terms": list(range(1, 9)),
        "once_per_run": True,
        "options": [
            option("return_card", effects=[{"op": "gain_relic", "relic_id": "A15",
                                             "fallback_money": 20}]),
            option("service_desk", effects=[{"op": "heal", "amount": 6}]),
            option("leave", effects=[]),
        ],
    },
}


SOURCE_LINES = {
    ("task", "N01"): [356], ("task", "N02"): [357],
    ("task", "N03"): [358], ("task", "N04"): [359],
    ("task", "Q01"): [375], ("task", "B01"): [386],
    ("encounter", "N01"): [352, 356, 369],
    ("encounter", "N02"): [352, 357, 369],
    ("encounter", "N03"): [358, 369], ("encounter", "N04"): [359, 369],
    ("encounter", "Q01"): [375], ("encounter", "B01"): [382, 386],
    ("event", "V01"): [432, 436, 449],
    ("event", "V03"): [432, 438, 449, 525],
    ("event", "V04"): [432, 439, 449],
    ("event", "V10"): [432, 445, 449],
}


BEHAVIOR_REFS = {
    "task": [
        "docs/内容层契约.md §8.1 TaskDef/TaskPhaseDef and §8.2 IntentSpec",
        "src/battle/battle_engine.gd::_execute_intent_skill",
        "tests/suites/test_g2_state.gd (content package behavior not exercised)",
    ],
    "encounter": [
        "docs/内容层契约.md §8.1 EncounterDef and §8.7 production overrides",
        "src/content/content_db.gd::_validate_enabled_references",
        "src/battle/battle_engine.gd::begin (requires runtime encounter input)",
        "tests/suites/test_battle_engine_begin.gd (not run against this staged batch)",
    ],
    "event": [
        "docs/内容层契约.md §5, §7.9.2 事件效果的目标过滤与显式卡池 (V03 fallback_money=20), §8.1, §8.5",
        "src/content/content_db.gd::EVENT_OP_FIELDS and _validate_event_options (schema registration only)",
        "docs/局流程契约.md §8 choose_event transaction contract",
    ],
}


def source_metadata(kind: str, id_: str, builder: ProductionContentBuilder) -> dict:
    frozen = builder.frozen[(kind, id_)]
    if frozen.source_path != DESIGN_PATH:
        raise ValueError(f"unexpected source path for {kind}/{id_}: {frozen.source_path}")
    text = DESIGN.read_text(encoding="utf-8")
    lines = text.splitlines()
    row_pattern = re.compile(rf"^\|\s*{re.escape(id_)}\s*\|")
    actual = [number for number, line in enumerate(lines, 1) if row_pattern.search(line)]
    expected = SOURCE_LINES[(kind, id_)]
    row = next((lines[number - 1] for number in actual if number in expected), None)
    if row is None:
        raise ValueError(f"no source row at recorded lines for {kind}/{id_}: {actual}")
    section = "§9.1 普通任务" if kind == "task" and id_.startswith("N") else (
        "§9.2 精英" if kind == "task" and id_ == "Q01" else (
            "§9.3 八学期首领" if kind == "task" else (
                "§9.1–§9.3 encounter availability and definition" if kind == "encounter" else "§10.2 随机事件"
            )
        )
    )
    return {
        "path": frozen.source_path,
        "section": frozen.source_section,
        "upstream_section": section,
        "source_lines": expected,
        "source_row": row,
    }


def build_runtime_probe(staged: dict[tuple[str, str], Path]) -> Path:
    """Build a test-only ContentDB package for flow reference-closure checks."""
    probe_root = OUTPUT / "runtime_probe"
    definitions_root = probe_root / "data" / "definitions"
    manifests_root = probe_root / "data" / "manifests"
    definitions_root.mkdir(parents=True, exist_ok=True)
    manifests_root.mkdir(parents=True, exist_ok=True)

    for file_name in ("statuses.json", "rulesets.json"):
        shutil.copyfile(ROOT / "data" / "definitions" / file_name, definitions_root / file_name)

    production_cards = read_json(ROOT / "data" / "definitions" / "cards.json")
    staged_cards = read_json(ROOT / "artifacts" / "g2-build" / "staging" / "cards" / "cards.json")
    cards_by_id = {row["id"]: row for row in [*production_cards, *staged_cards]}
    card_ids = ["K01", "K02", "K03", "K04", "X01"]
    missing_cards = [id_ for id_ in card_ids if id_ not in cards_by_id]
    if missing_cards:
        raise ValueError("flow runtime probe is missing cards: " + ", ".join(missing_cards))
    (definitions_root / "cards.json").write_text(
        json.dumps([cards_by_id[id_] for id_ in card_ids], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    for kind, file_name in (("task", "tasks"), ("encounter", "encounters"), ("event", "events")):
        rows = [read_json(path)["definition"] for (item_kind, _), path in staged.items() if item_kind == kind]
        rows.sort(key=lambda row: row["id"])
        (definitions_root / f"{file_name}.json").write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    for file_name in ("characters.json", "relics.json", "units.json", "scenes.json"):
        (definitions_root / file_name).write_text("[]\n", encoding="utf-8")

    manifest = {
        "id": "test_g2_flow",
        "content_version": "campus_mvp.v1",
        "ruleset_id": "campus_v1",
        "enabled": {
            "character": [],
            "card": card_ids,
            "relic": [],
            "task": ["N01", "N02", "N03", "N04", "Q01", "B01"],
            "encounter": ["N01", "N02", "N03", "N04", "Q01", "B01"],
            "unit": [],
            "scene": [],
            "event": [],
            "status": [
                "inspiration", "compile", "anxiety", "procrastination",
                "drowsiness", "extra_requirements", "guard",
            ],
            "ruleset": ["campus_v1"],
        },
        "overrides": [{
            "kind": "encounter",
            "id": "N04",
            "scope_version": "campus_mvp.v1",
            "source": {"path": "docs/交大四年_DDL战争_项目计划书.md", "section": "§3.1"},
            "patch": {"terms": [1]},
        }],
    }
    manifest_path = manifests_root / "test_g2_flow.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    probe_path = probe_root / "runtime_probe.gd"
    probe_path.write_text(
        """extends SceneTree

const ContentDB = preload(\"res://src/content/content_db.gd\")

const EXPECTED_TASKS := [\"N01\", \"N02\", \"N03\", \"N04\", \"Q01\", \"B01\"]
const EXPECTED_ENCOUNTERS := [\"N01\", \"N02\", \"N03\", \"N04\", \"Q01\", \"B01\"]
const EXPECTED_EVENTS := [\"V01\", \"V03\", \"V04\", \"V10\"]


func _initialize() -> void:
\tvar db: ContentDB = ContentDB.new(\"res://artifacts/g2-build/staging/flow/runtime_probe/data\", true)
\tvar loaded: GameResult = db.load(\"test_g2_flow\")
\tif not loaded.ok:
\t\tprinterr(\"FLOW_REFERENCE_CLOSURE_LOAD_FAILED ", JSON.stringify(loaded.error.to_dictionary()))
\t\tquit(1)
\t\treturn
\tfor definition_id in EXPECTED_TASKS:
\t\tif not _query(db, \"task\", definition_id):
\t\t\tquit(1)
\tfor definition_id in EXPECTED_ENCOUNTERS:
\t\tif not _query(db, \"encounter\", definition_id):
\t\t\tquit(1)
\tvar n03: Dictionary = db.get_definition(\"task\", \"N03\").data as Dictionary
\tif n03.phases[0].intents[1].add_card.card != \"X01\":
\t\tprinterr(\"FLOW_REFERENCE_CLOSURE_FAILED task/N03 add_card.card must resolve to X01\")
\t\tquit(1)
\tvar n04: Dictionary = db.get_definition(\"encounter\", \"N04\").data as Dictionary
\tif n04.terms != [1]:
\t\tprinterr(\"FLOW_OVERRIDE_FAILED encounter/N04 terms must resolve to [1]\")
\t\tquit(1)
\tfor definition_id in EXPECTED_EVENTS:
\t\tif not _query_definition_file(\"events\", definition_id):
\t\t\tquit(1)
\tprint(\"FLOW_REFERENCE_CLOSURE_OK tasks=6 encounters=6 cards=5 override=N04:[1]\")
\tprint(\"FLOW_EVENT_SCHEMA_ONLY_OK events=4 enabled=0 executor=G4\")
\tquit(0)


func _query(db: ContentDB, kind: String, definition_id: String) -> bool:
\tvar result := db.get_definition(kind, definition_id)
\tif result.ok:
\t\treturn true
\tprinterr(\"FLOW_REFERENCE_CLOSURE_FAILED %s/%s\" % [kind, definition_id])
\treturn false


func _query_definition_file(file_name: String, definition_id: String) -> bool:
\tvar file := FileAccess.open(\"res://artifacts/g2-build/staging/flow/runtime_probe/data/definitions/%s.json\" % file_name, FileAccess.READ)
\tif file == null:
\t\tprinterr(\"FLOW_EVENT_SCHEMA_QUERY_FAILED missing %s.json\" % file_name)
\t\treturn false
\tvar parser: JSON = JSON.new()
\tif parser.parse(file.get_as_text()) != OK:
\t\tprinterr(\"FLOW_EVENT_SCHEMA_QUERY_FAILED invalid %s.json\" % file_name)
\t\treturn false
\tfor definition: Dictionary in parser.data:
\t\tif definition.get(\"id\") == definition_id:
\t\t\treturn true
\tprinterr(\"FLOW_EVENT_SCHEMA_QUERY_FAILED missing %s/%s\" % [file_name, definition_id])
\treturn false
""",
        encoding="utf-8",
    )
    return probe_path


def main() -> None:
    builder = ProductionContentBuilder(ROOT)
    staged: list[Path] = []
    definitions = {
        **{("task", id_): value for id_, value in TASKS.items()},
        **{("encounter", id_): value for id_, value in ENCOUNTERS.items()},
        **{("event", id_): value for id_, value in EVENTS.items()},
    }
    for (kind, id_), definition in definitions.items():
        path = builder.stage_definition(
            OUTPUT,
            kind,
            definition,
            f"{kind} ID {id_}",
            BEHAVIOR_REFS[kind],
        )
        record = read_json(path)
        record["source"].update(source_metadata(kind, id_, builder))
        record["status"] = (
            "schema_validated_behavior_and_G2_reference_closure_pending"
            if kind != "event"
            else "schema_validated_runtime_executor_missing"
        )
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        staged.append(path)

    staged_by_key = {
        (record["kind"], record["id"]): path
        for path in staged
        for record in [read_json(path)]
    }
    runtime_probe_path = build_runtime_probe(staged_by_key)

    baseline_path = ROOT / "docs/baselines/g0.json"
    deferred_path = ROOT / "data/manifests/content_deferred.json"
    baseline = read_json(baseline_path)
    deferred = read_json(deferred_path)
    expected = {
        "task": {"N01", "N02", "N03", "N04", "Q01", "B01"},
        "encounter": {"N01", "N02", "N03", "N04", "Q01", "B01"},
        "event": {"V01", "V03", "V04", "V10"},
    }
    if any(set(ids) != expected[kind] for kind, ids in {
        kind: [id_ for (item_kind, id_) in definitions if item_kind == kind]
        for kind in expected
    }.items()):
        raise ValueError("staging ID set does not match the assigned frozen batch")
    for kind, ids in expected.items():
        if not ids.issubset(set(baseline["scope"]["enabled_by_kind"][kind])):
            raise ValueError(f"batch exceeds G0 frozen scope: {kind}")
        holdback_ids = {row["id"] for row in deferred["definitions"][kind]}
        if not ids.issubset(holdback_ids):
            raise ValueError(f"batch includes IDs no longer in holdback: {kind}")

    input_paths = [
        "docs/baselines/g0.json",
        "data/manifests/content_deferred.json",
        DESIGN_PATH,
        CONTRACT_PATH,
        "docs/交大四年_DDL战争_项目计划书.md",
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
    ]
    inputs = {path: sha256(ROOT / path) for path in input_paths}
    record_hashes = {path.relative_to(ROOT).as_posix(): sha256(path) for path in staged}
    batch = {
        "batch": "G2 flow definitions",
        "counts": {kind: len(ids) for kind, ids in expected.items()},
        "ids": {kind: sorted(ids) for kind, ids in expected.items()},
        "production_manifest_mutated": False,
        "content_deferred_mutated": False,
        "g0_scope_mutated": False,
        "verification": {
            "python_staging": "passed",
            "python_compileall": "passed",
            "godot_schema_probe": {
                "status": "passed_per_definition_schema_only",
                "command": "F:\\GoDot\\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://artifacts/g2-build/staging/flow/schema_probe.gd",
                "godot_version": "4.7.2.stable.official.ed1daf0bf",
                "exit_code": 0,
                "raw_output": "schema_probe.stdout.txt",
            },
            "godot_reference_probe": {
                "status": "pending_execution",
                "script": runtime_probe_path.relative_to(ROOT).as_posix(),
                "manifest": "artifacts/g2-build/staging/flow/runtime_probe/data/manifests/test_g2_flow.json",
            },
            "reference_closure": {
                "status": "pending_execution",
                "scope": "test_g2_flow ContentDB enabled tasks and encounters only; events are intentionally disabled",
            },
            "handler_verification": {
                "status": "not_run",
                "reason": "No event executor or production flow handler behavior was exercised by this schema/closure probe.",
            },
            "behavior_tests": {
                "status": "not_run",
                "reason": "Battle and event behavior tests remain outside this isolated content package probe.",
            },
        },
        "input_sha256": inputs,
        "staged_record_sha256": record_hashes,
    }
    (OUTPUT / "batch.json").write_text(json.dumps(batch, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("FLOW_STAGING=passed definitions=16 production_manifest_mutated=false g0_scope_mutated=false")


if __name__ == "__main__":
    main()
