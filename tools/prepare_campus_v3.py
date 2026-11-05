#!/usr/bin/env python3
"""Build the standalone v3.1 content package under data/v3.

The package is loadable through ContentDB with root res://data/v3 and manifest
campus_v3.  It does not change the v1 campus_mvp production manifest.
"""

from __future__ import annotations

import copy
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/catalog/cards_v3.json"
V1 = ROOT / "data/definitions"
OUT = ROOT / "data/v3"
DEFS = OUT / "definitions"
MANIFESTS = OUT / "manifests"

CHARACTERS = {
    "P01": {
        "starter_cards": ["R3-P01-01", "R3-P01-02"],
        "starter_relic_id": "A01",
        "passive": {
            "id": "r3_p01_link_replay",
            "trigger": "work_card_resolved",
            "count": 1,
            "limit": {"per": "round", "times": 1},
            "effects": [{"op": "relax", "amount": 1}],
        },
    },
    "P02": {
        "starter_cards": ["R3-P02-01", "R3-P02-11"],
        "starter_relic_id": "A01",
        "passive": {
            "id": "r3_p02_paper_record",
            "trigger": "work_card_resolved",
            "count": 1,
            "limit": {"per": "round", "times": 1},
            "effects": [{"op": "relax", "amount": 1}],
        },
    },
    "P03": {
        "starter_cards": ["R3-P03-01", "R3-P03-21"],
        "starter_relic_id": "A01",
        "passive": {
            "id": "r3_p03_compound_reaction",
            "trigger": "work_card_resolved",
            "count": 1,
            "limit": {"per": "round", "times": 1},
            "effects": [{"op": "relax", "amount": 1}],
        },
    },
    "P04": {
        "starter_cards": ["R3-P04-01", "R3-P04-02"],
        "starter_relic_id": "A04",
        "passive": {
            "id": "r3_p04_teamwork",
            "trigger": "cooperation_card_resolved",
            "count": 1,
            "limit": {"per": "round", "times": 1},
            "effects": [{"op": "relax", "amount": 2}],
        },
    },
}

V3_STATUSES = [
    {
        "id": "vulnerability",
        "name_key": "status.vulnerability.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "pressure_window",
        "dispel_policy": "explicit",
        "numeric_rule_key": "vulnerability",
    },
    {
        "id": "weakness",
        "name_key": "status.weakness.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "pressure_window",
        "dispel_policy": "explicit",
        "numeric_rule_key": "weakness",
    },
    {
        "id": "brittle",
        "name_key": "status.brittle.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "pressure_window",
        "dispel_policy": "explicit",
        "numeric_rule_key": "brittle",
    },
    {
        "id": "feebleness",
        "name_key": "status.feebleness.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "feebleness",
    },
    {
        "id": "erosion",
        "name_key": "status.erosion.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "battle",
        "dispel_policy": "explicit",
        "numeric_rule_key": "erosion",
    },
    {
        "id": "induced",
        "name_key": "status.induced.name",
        "target": "task",
        "stack_policy": "capped",
        "duration_policy": "next_player_action_end",
        "dispel_policy": "explicit",
        "numeric_rule_key": "induced",
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
]

V3_UNITS = [
    {
        "id": "R3-U01",
        "name_key": "unit.R3-U01.name",
        "vitality": 3,
        "cooperation": 2,
        "guard": False,
        "support": {"kind": "none"},
    },
    {
        "id": "R3-U02",
        "name_key": "unit.R3-U02.name",
        "vitality": 4,
        "cooperation": 1,
        "guard": False,
        "support": {"kind": "relax", "amount": 2},
    },
    {
        "id": "R3-U03",
        "name_key": "unit.R3-U03.name",
        "vitality": 5,
        "cooperation": 3,
        "guard": True,
        "support": {"kind": "none"},
    },
]

V3_SCENES = [
    {
        "id": "R3-S01",
        "name_key": "scene.R3-S01.name",
        "prepare_effects": [{"op": "relax", "amount": 3}],
        "battle_limit": 2,
    },
    {
        "id": "R3-S01+",
        "name_key": "scene.R3-S01+.name",
        "prepare_effects": [{"op": "relax", "amount": 5}],
        "battle_limit": 2,
    },
    {
        "id": "R3-S02",
        "name_key": "scene.R3-S02.name",
        "prepare_effects": [{"op": "draw", "amount": 1}],
        "battle_limit": 2,
    },
    {
        "id": "R3-S02+",
        "name_key": "scene.R3-S02+.name",
        "prepare_effects": [
            {"op": "draw", "amount": 1},
            {"op": "relax", "amount": 3},
        ],
        "battle_limit": 2,
    },
]


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def card_entry(raw: dict) -> dict:
    entry = {
        "id": raw["id"],
        "name_key": raw["id"],
        "type": raw["type"],
        "rarity": raw["rarity"],
        "tags": raw["tags"],
        "cost": raw["cost"],
        "target": raw["target"],
        "exhaust": bool(raw["flags"]["exhaust"]) or raw["type"] == "ability",
        "effects": raw["effects"],
        "upgrade": {"cost": raw["upgraded_cost"], "effects": raw["upgrade_effects"]},
        "v3": True,
        "owner": raw["owner"],
        "permanent": raw["permanent"],
        "flags": raw["flags"],
        "limits": raw.get("limits", {}),
        "requirements": raw.get("requirements", []),
    }
    for key in ("ability", "chapter", "exam"):
        if raw.get(key):
            entry[key] = raw[key]
    if raw["owner"] == "P02":
        entry["requirements"].append({"kind": "paper_name_turn_unused"})
    return entry


def main() -> None:
    catalog = load(CATALOG)
    DEFS.mkdir(parents=True, exist_ok=True)
    MANIFESTS.mkdir(parents=True, exist_ok=True)

    write(DEFS / "cards.json", [card_entry(raw) for raw in catalog["cards"]])

    characters = []
    for character_id in ["P01", "P02", "P03", "P04"]:
        data = CHARACTERS[character_id]
        characters.append(
            {
                "id": character_id,
                "name_key": "character.%s.name" % character_id,
                "starter_cards": data["starter_cards"],
                "starter_relic_id": data["starter_relic_id"],
                "passive": data["passive"],
            }
        )
    write(DEFS / "characters.json", characters)

    v1_statuses = load(V1 / "statuses.json")
    status_by_id = {status["id"]: status for status in v1_statuses}
    for status in V3_STATUSES:
        status_by_id[status["id"]] = status
    write(DEFS / "statuses.json", list(status_by_id.values()))
    write(DEFS / "units.json", load(V1 / "units.json") + V3_UNITS)
    write(DEFS / "scenes.json", load(V1 / "scenes.json") + V3_SCENES)

    for name in ["tasks.json", "encounters.json", "relics.json", "events.json"]:
        write(DEFS / name, load(V1 / name))

    tasks = load(DEFS / "tasks.json")
    tasks.extend(
        [
            {
                "id": "R3-AC-TASK-A",
                "name_key": "task.R3-AC-TASK-A.name",
                "kind": "normal",
                "phases": [
                    {
                        "phase_key": "main",
                        "work_max": 50,
                        "intents": [{"index": 0, "text_key": "task.R3-AC-TASK-A.intent.a", "pressure": 5}],
                    }
                ],
            },
            {
                "id": "R3-AC-TASK-B",
                "name_key": "task.R3-AC-TASK-B.name",
                "kind": "normal",
                "phases": [
                    {
                        "phase_key": "main",
                        "work_max": 50,
                        "intents": [{"index": 0, "text_key": "task.R3-AC-TASK-B.intent.a", "pressure": 7}],
                    }
                ],
            },
        ]
    )
    replacements = {"N03": "R3-C-05", "E02": "R3-C-06", "N26": "R3-C-07", "E06": "R3-C-08"}
    for task in tasks:
        for phase in task.get("phases", []):
            for intent in phase.get("intents", []):
                add_card = intent.get("add_card")
                if isinstance(add_card, dict) and task["id"] in replacements:
                    add_card["card"] = replacements[task["id"]]
    write(DEFS / "tasks.json", tasks)
    events = load(DEFS / "events.json")
    for event in events:
        if event["id"] != "V03":
            continue
        for option in event.get("options", []):
            for effect in option.get("effects", []):
                if effect.get("op") == "gain_card":
                    effect["card_pool"] = ["R3-C-05", "R3-C-06", "R3-C-07"]
    write(DEFS / "events.json", events)
    relics = load(DEFS / "relics.json")
    for relic in relics:
        if relic["id"] == "A08":
            for hook in relic.get("hooks", []):
                if hook.get("definition_id") == "K10":
                    hook["definition_id"] = "R3-C-06"
    write(DEFS / "relics.json", relics)
    encounters = load(DEFS / "encounters.json")
    encounters.append(
        {
            "id": "R3-AC",
            "name_key": "encounter.R3-AC.name",
            "kind": "normal",
            "members": ["R3-AC-TASK-A", "R3-AC-TASK-B"],
            "base_ddl": 20,
            "terms": [1],
            "exam_flags": [],
        }
    )
    for exam_id, flags in [
        ("R3-AC-INDEP", ["independent_answer"]),
        ("R3-AC-FIXED", ["fixed_exam_room"]),
        ("R3-AC-BOTH", ["independent_answer", "fixed_exam_room"]),
    ]:
        encounters.append(
            {
                "id": exam_id,
                "name_key": "encounter.%s.name" % exam_id,
                "kind": "normal",
                "members": ["R3-AC-TASK-A", "R3-AC-TASK-B"],
                "base_ddl": 20,
                "terms": [8],
                "exam_flags": flags,
            }
        )
    write(DEFS / "encounters.json", encounters)

    ruleset = copy.deepcopy(load(V1 / "rulesets.json")[0])
    ruleset["id"] = "campus_v1"
    ruleset["run"]["common_starter_cards"] = [
        "R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01",
        "R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02",
        "R3-C-03", "R3-C-04",
    ]
    ruleset["battle"]["starting_focus"] = 0
    ruleset["battle"]["focus_per_round"] = 3
    ruleset["battle"]["focus_cap"] = 10
    ruleset["battle"]["draw_per_round"] = 5
    ruleset["statuses"].update(
        {
            "vulnerability": {"cap": 3, "completion_percent": 125},
            "weakness": {"cap": 3, "pressure_percent": 75},
            "brittle": {"cap": 3, "shield_percent": 50},
            "feebleness": {"cap": 4, "pressure_flat": 2},
            "erosion": {"cap": 20, "completion_per_stack": 1},
            "induced": {"cap": 3, "max_triggers_per_turn": 4},
        }
    )
    write(DEFS / "rulesets.json", [ruleset])

    card_ids = [card["id"] for card in catalog["cards"]]
    relic_ids = [row["id"] for row in load(DEFS / "relics.json")]
    unit_ids = [row["id"] for row in load(DEFS / "units.json")]
    scene_ids = [row["id"] for row in load(DEFS / "scenes.json")]
    task_ids = [row["id"] for row in load(DEFS / "tasks.json")]
    encounter_ids = [row["id"] for row in load(DEFS / "encounters.json")]
    event_ids = [row["id"] for row in load(DEFS / "events.json")]
    manifest = {
        "id": "campus_v3",
        "content_version": "campus_v3.v1",
        "ruleset_id": "campus_v1",
        "enabled": {
            "character": ["P01", "P02", "P03", "P04"],
            "card": card_ids,
            "relic": relic_ids,
            "task": task_ids,
            "encounter": encounter_ids,
            "unit": unit_ids,
            "scene": scene_ids,
            "event": event_ids,
            "status": list(status_by_id.keys()),
            "ruleset": ["campus_v1"],
        },
        "overrides": [],
    }
    write(MANIFESTS / "campus_v3.json", manifest)
    print("wrote", OUT)
    print("cards=%d characters=%d statuses=%d" % (len(card_ids), len(characters), len(status_by_id)))


if __name__ == "__main__":
    main()
