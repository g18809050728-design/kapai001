#!/usr/bin/env python3
"""Prepare the v3.1 P04 (Tang Yining) battle fixture.

Includes the common 12 plus all 40 P04 cards, three partners, vulnerability,
weakness and anxiety.  Test-only; never enabled by a production manifest.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/catalog/cards_v3.json"
OUT = ROOT / "tests/fixtures/cards_v3_p04"

CARDS = [f"R3-C-{index:02d}" for index in range(1, 13)] + [
    f"R3-P04-{index:02d}" for index in range(1, 41)
]


def write(name: str, data) -> None:
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def ruleset() -> dict:
    return {
        "id": "campus_v1",
        "schema_version": 1,
        "run": {
            "starting_vitality": 72,
            "starting_money": 60,
            "common_starter_cards": [
                "R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01",
                "R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02",
                "R3-C-03", "R3-C-04",
            ],
            "starter_deck_size": 12,
            "minimum_deck_size": 5,
            "max_card_upgrades": 1,
            "relic_slots": 6,
            "term_count": 1,
            "term_heal_percent": 20,
            "rest_heal_percent": 25,
            "career_cap": 100,
        },
        "battle": {
            "starting_focus": 0,
            "focus_per_round": 3,
            "focus_cap": 10,
            "draw_per_round": 5,
            "hand_limit": 10,
            "unit_slots": 3,
            "scene_slots": 1,
            "base_retention_count": 0,
            "minimum_vitality_after_payment": 1,
            "unit_action_vitality_cost": 1,
            "cooperation_exam_relax": [5, 7],
            "scene_exam_draw": 1,
            "scene_exam_relax": [2, 4],
            "minimum_ddl": 1,
        },
        "rewards": {
            "normal_money_by_term": [15],
            "elite_money_bonus": 20,
            "nonfinal_boss_money": 50,
            "candidate_count": 3,
            "empty_relic_pool_money": 30,
            "card_rarity_weights": {
                "normal": {"white": 60, "blue": 30, "purple": 9, "gold": 1},
                "elite": {"white": 20, "blue": 45, "purple": 30, "gold": 5},
                "boss": {"white": 0, "blue": 30, "purple": 50, "gold": 20},
                "term": {"white": 50, "blue": 50, "purple": 0, "gold": 0},
            },
            "relic_rarity_weights": {
                "general": {"white": 50, "blue": 35, "purple": 13, "gold": 2},
                "boss": {"white": 20, "blue": 40, "purple": 35, "gold": 5},
            },
        },
        "shop": {
            "card_stock": {"white": 2, "blue": 2, "purple": 1},
            "relic_stock": {"white": 1, "blue": 1},
            "meal_stock": 1,
            "card_prices": {"white": 35, "blue": 55, "purple": 85},
            "relic_prices": {"white": 80, "blue": 120},
            "meal_price": 25,
            "meal_heal": 12,
            "removals_per_shop": 1,
            "first_removal_price": 60,
            "removal_price_increment": 20,
        },
        "statuses": {
            "vulnerability": {"cap": 3, "completion_percent": 125},
            "weakness": {"cap": 3, "pressure_percent": 75},
            "anxiety": {"cap": 2, "focus_penalty_per_stack": 1},
        },
        "difficulty_overrides": {
            "normal": {"starting_vitality": 72, "ddl_offset": 0, "pressure_percent": 100}
        },
    }


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_id = {card["id"]: card for card in catalog["cards"]}
    cards = []
    for card_id in CARDS:
        raw = by_id[card_id]
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
            "permanent": True,
            "limits": raw.get("limits", {}),
            "requirements": raw.get("requirements", []),
        }
        if raw.get("ability"):
            entry["ability"] = raw["ability"]
        if raw.get("exam"):
            entry["exam"] = raw["exam"]
        cards.append(entry)

    write("definitions/cards.json", cards)
    write("definitions/characters.json", [
        {
            "id": "P04",
            "name_key": "character.P04.name",
            "starter_cards": ["R3-P04-01", "R3-P04-02"],
            "starter_relic_id": "R3_TEST_RELIC",
            "passive": {
                "id": "r3_p04_test_passive",
                "trigger": "cooperation_card_resolved",
                "count": 99,
                "limit": {"per": "battle", "times": 1},
                "effects": [{"op": "heal", "amount": 1}],
            },
        }
    ])
    write("definitions/relics.json", [
        {
            "id": "R3_TEST_RELIC",
            "name_key": "relic.R3_TEST_RELIC.name",
            "availability": "starter",
            "rarity": None,
            "tags": [],
            "hooks": [
                {
                    "at": "round_start",
                    "effects": [{"op": "draw", "amount": 0, "per_discarded": 1}],
                }
            ],
        }
    ])
    write("definitions/units.json", [
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
    ])
    write("definitions/tasks.json", [
        {
            "id": "R3_TEST_TASK_A",
            "name_key": "task.R3_TEST_TASK_A.name",
            "kind": "normal",
            "phases": [
                {
                    "phase_key": "main",
                    "work_max": 50,
                    "intents": [{"index": 0, "text_key": "task.R3_TEST_TASK_A.intent.a"}],
                }
            ],
        },
        {
            "id": "R3_TEST_TASK_B",
            "name_key": "task.R3_TEST_TASK_B.name",
            "kind": "normal",
            "phases": [
                {
                    "phase_key": "main",
                    "work_max": 50,
                    "intents": [{"index": 0, "text_key": "task.R3_TEST_TASK_B.intent.a"}],
                }
            ],
        },
    ])
    write("definitions/encounters.json", [
        {
            "id": "R3_TEST",
            "name_key": "encounter.R3_TEST.name",
            "kind": "normal",
            "members": ["R3_TEST_TASK_A", "R3_TEST_TASK_B"],
            "base_ddl": 20,
            "terms": [1],
            "exam_flags": [],
        }
    ])
    write("definitions/scenes.json", [
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
    ])
    write("definitions/statuses.json", [
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
            "id": "anxiety",
            "name_key": "status.anxiety.name",
            "target": "player",
            "stack_policy": "capped",
            "duration_policy": "next_prepare",
            "dispel_policy": "negative",
            "numeric_rule_key": "anxiety",
        },
    ])
    write("definitions/events.json", [])
    write("definitions/rulesets.json", [ruleset()])
    write("manifests/test_cards_v3_p04.json", {
        "id": "test_cards_v3_p04",
        "content_version": "test_cards_v3_p04.v1",
        "ruleset_id": "campus_v1",
        "enabled": {
            "card": CARDS,
            "character": ["P04"],
            "relic": ["R3_TEST_RELIC"],
            "task": ["R3_TEST_TASK_A", "R3_TEST_TASK_B"],
            "encounter": ["R3_TEST"],
            "unit": ["R3-U01", "R3-U02", "R3-U03"],
            "scene": ["R3-S01", "R3-S01+"],
            "event": [],
            "status": ["vulnerability", "weakness", "anxiety"],
            "ruleset": ["campus_v1"],
        },
        "overrides": [],
    })
    print(f"wrote {OUT}")
    print(f"cards={len(cards)}")


if __name__ == "__main__":
    main()
