"""Build the G2 starter ruleset and explicit production holdback from G0."""

from __future__ import annotations

from copy import deepcopy

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "docs/baselines/g0.json"
DATA = ROOT / "data"
TEST_FIXTURE = ROOT / "tests/fixtures/content_loader"
DESIGN_SOURCE = "docs/交大四年_DDL战争_统一设计文档.md"

STATUS_DEFINITIONS = [
    {
        "id": "inspiration",
        "name_key": "status.inspiration.name",
        "target": "player",
        "stack_policy": "capped",
        "duration_policy": "work_or_round_end",
        "dispel_policy": "explicit",
        "numeric_rule_key": "inspiration",
    },
    {
        "id": "compile",
        "name_key": "status.compile.name",
        "target": "player",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "compile",
    },
    {
        "id": "anxiety",
        "name_key": "status.anxiety.name",
        "target": "player",
        "stack_policy": "capped",
        "duration_policy": "next_prepare",
        "dispel_policy": "negative",
        "numeric_rule_key": "anxiety",
    },
    {
        "id": "procrastination",
        "name_key": "status.procrastination.name",
        "target": "player",
        "stack_policy": "capped",
        "duration_policy": "next_draw",
        "dispel_policy": "negative",
        "numeric_rule_key": "procrastination",
    },
    {
        "id": "drowsiness",
        "name_key": "status.drowsiness.name",
        "target": "player",
        "stack_policy": "capped",
        "duration_policy": "next_player_action_end",
        "dispel_policy": "negative",
        "numeric_rule_key": "drowsiness",
    },
    {
        "id": "extra_requirements",
        "name_key": "status.extra_requirements.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "extra_requirements",
    },
    {
        "id": "guard",
        "name_key": "status.guard.name",
        "target": "unit",
        "stack_policy": "presence",
        "duration_policy": "unit_departure",
        "dispel_policy": "none",
    },
]
TEST_CARD_DEFINITION = {
    "id": "test_card_001",
    "name_key": "card.test_content_loader.name",
    "type": "work",
    "rarity": "white",
    "tags": ["test"],
    "cost": 0,
    "target": "task",
    "exhaust": False,
    "effects": [{"op": "complete", "amount": 1}],
    "upgrade": {"effects": [{"op": "complete", "amount": 2}]},
}


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def make_ruleset(baseline: dict) -> dict:
    ruleset: dict = {"id": "campus_v1", "schema_version": 1}
    for binding in baseline["scope"]["numeric_bindings"]:
        parts = binding["config_key"].split(".")
        cursor = ruleset
        for part in parts[:-1]:
            cursor = cursor.setdefault(part, {})
        cursor[parts[-1]] = binding["expected"]
    return ruleset


def make_manifest(baseline: dict, definitions_dir: Path) -> tuple[dict, dict]:
    frozen = baseline["scope"]["enabled_by_kind"]
    enabled: dict[str, list[str]] = {}
    for kind, frozen_ids in frozen.items():
        path = definitions_dir / f"{kind_file(kind)}.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(rows, list):
            raise ValueError(f"Expected an array in {path}")
        available: set[str] = set()
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                raise ValueError(f"Every definition in {path} must have a string id")
            if row["id"] not in frozen_ids:
                raise ValueError(f"Definition {kind}/{row['id']} is outside the frozen G0 scope")
            available.add(row["id"])
        enabled[kind] = [id_ for id_ in frozen_ids if id_ in available]
    holdback = {kind: [id_ for id_ in ids if id_ not in enabled[kind]] for kind, ids in frozen.items()}
    manifest = {
        "id": baseline["scope"]["production_manifest_id"],
        "content_version": baseline["scope"]["scope_version"],
        "ruleset_id": "campus_v1",
        "enabled": enabled,
        "overrides": [],
    }
    for entry in baseline["scope"]["overrides"]:
        if entry["id"] not in enabled[entry["kind"]]:
            continue
        if entry["kind"] == "encounter" and entry["id"] == "N04":
            patch = {"terms": entry["value"]}
        elif entry["kind"] == "event" and entry["id"] == "V03":
            events = json.loads((definitions_dir / "events.json").read_text(encoding="utf-8"))
            options = deepcopy(next(row["options"] for row in events if row["id"] == "V03"))
            consult = next(option for option in options if option["option_id"] == "consult")
            effect = next(effect for effect in consult["effects"] if effect["op"] == "gain_card")
            effect["card_pool"] = entry["value"]
            patch = {"options": options}
        else:
            raise ValueError(f"Unregistered MVP override: {entry['kind']}/{entry['id']}")
        manifest["overrides"].append({
            **{key: entry[key] for key in ["kind", "id", "scope_version", "source"]},
            "patch": patch,
        })
    rulesets = json.loads((definitions_dir / "rulesets.json").read_text(encoding="utf-8"))
    ruleset = next((row for row in rulesets if row.get("id") == manifest["ruleset_id"]), None)
    if ruleset is None:
        raise ValueError(f"Missing Ruleset definition: {manifest['ruleset_id']}")
    starter_cards = ruleset["run"]["common_starter_cards"]
    missing_starters = list(dict.fromkeys(id_ for id_ in starter_cards if id_ not in enabled["card"]))
    deferred = {
        "manifest_id": manifest["id"],
        "scope_version": manifest["content_version"],
        "definitions": {
            kind: [
                {
                    "id": id_,
                    "source": {"path": DESIGN_SOURCE, "section": f"{kind} ID {id_}"},
                    "missing": (
                        f"No verified JSON definition exists in data/definitions/{kind_file(kind)}.json; "
                        "no registered behavior mapping is available for publication."
                    ),
                    "blocking": ["G2"],
                }
                for id_ in ids
            ]
            for kind, ids in holdback.items()
            if ids
        },
        "manifest_holdback": holdback,
        "manifest_enable_after_mapping": {},
        "package_blockers": ([
            {
                "id": f"ruleset/{manifest['ruleset_id']}",
                "missing_references": missing_starters,
                "reason": "Ruleset starter references are not present in the enabled production card definitions.",
                "blocking": ["G2"],
            }
        ] if missing_starters else []),
        "pending_overrides": [
            {
                **entry,
                "blocked_by": "Override target definition is currently in manifest_holdback.",
            }
            for entry in baseline["scope"]["overrides"]
            if entry["id"] not in enabled[entry["kind"]]
        ],
    }
    return manifest, deferred


def make_test_manifest() -> dict:
    enabled = {
        kind: []
        for kind in [
            "character", "card", "relic", "task", "encounter", "unit", "scene", "event", "status", "ruleset"
        ]
    }
    enabled["card"] = [TEST_CARD_DEFINITION["id"]]
    enabled["status"] = [status["id"] for status in STATUS_DEFINITIONS]
    enabled["ruleset"] = ["campus_v1"]
    return {
        "id": "test_content_loader",
        "content_version": "campus_mvp.v1",
        "ruleset_id": "campus_v1",
        "enabled": enabled,
        "overrides": [],
    }


def make_test_ruleset(baseline: dict) -> dict:
    ruleset = make_ruleset(baseline)
    ruleset["run"]["common_starter_cards"] = [TEST_CARD_DEFINITION["id"]] * 10
    return ruleset


def kind_file(kind: str) -> str:
    return {
        "character": "characters",
        "card": "cards",
        "relic": "relics",
        "task": "tasks",
        "encounter": "encounters",
        "unit": "units",
        "scene": "scenes",
        "event": "events",
        "status": "statuses",
        "ruleset": "rulesets",
    }.get(kind, kind + "s")


def main() -> None:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    definition_files = {
        "character": "characters",
        "card": "cards",
        "relic": "relics",
        "task": "tasks",
        "encounter": "encounters",
        "unit": "units",
        "scene": "scenes",
        "event": "events",
    }
    definitions_dir = DATA / "definitions"
    for file_name in definition_files.values():
        path = definitions_dir / f"{file_name}.json"
        if not path.exists():
            write_json(path, [])
    write_json(definitions_dir / "statuses.json", STATUS_DEFINITIONS)
    write_json(definitions_dir / "rulesets.json", [make_ruleset(baseline)])
    manifest, deferred = make_manifest(baseline, definitions_dir)
    write_json(DATA / "manifests/campus_mvp.json", manifest)
    write_json(DATA / "manifests/content_deferred.json", deferred)
    fixture_definitions = TEST_FIXTURE / "definitions"
    for file_name in definition_files.values():
        write_json(fixture_definitions / f"{file_name}.json", [])
    write_json(fixture_definitions / "cards.json", [TEST_CARD_DEFINITION])
    write_json(fixture_definitions / "statuses.json", STATUS_DEFINITIONS)
    write_json(fixture_definitions / "rulesets.json", [make_test_ruleset(baseline)])
    write_json(TEST_FIXTURE / "manifests/test_content_loader.json", make_test_manifest())
    print(f"Wrote G2 ruleset from {len(baseline['scope']['numeric_bindings'])} G0 bindings")
    print(
        "Production enabled: "
        f"cards={len(manifest['enabled']['card'])}, "
        f"statuses={len(manifest['enabled']['status'])}, rulesets=1"
    )
    print(f"Production holdback definitions: {sum(map(len, deferred['manifest_holdback'].values()))}")
    print("Test manifest and card are isolated under tests/fixtures/content_loader")


if __name__ == "__main__":
    main()
