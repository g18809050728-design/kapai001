#!/usr/bin/env python3
"""Validate the machine-readable v3.1 card catalog.

Checks identity/counts against the design snapshot, the catalog schema, DSL
vocabulary, and the explicit not-runtime-enabled marker.  This validator does
not claim that the battle engine implements the listed mechanics.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "artifacts/redesign-20261030/campus-cards-v3.json"
CATALOG = ROOT / "data/catalog/cards_v3.json"

sys.path.insert(0, str(ROOT / "artifacts/redesign-20261030"))
try:
    import build_cards_v3_runtime as builder
except Exception:  # pragma: no cover - reported as a schema drift in main()
    builder = None

SCHEMA_VERSION = "r3-card-catalog.v1"
TYPE_MAP = {"工作": "work", "策略": "strategy", "能力": "ability", "合作": "cooperation", "场景": "scene"}
RARITY_MAP = {"基础": "basic", "普通": "common", "进阶": "advanced", "稀有": "rare", "衍生": "token"}
TYPES = set(TYPE_MAP.values())
RARITIES = set(RARITY_MAP.values())
TARGETS = {"self", "task", "all_tasks", "unit", "discard", "paper", "earliest_task"}

KNOWN_OPS = {
    "complete", "relax", "heal", "lose_vitality", "gain_focus", "draw", "discard",
    "retain", "exhaust_other", "retrieve", "apply_status", "remove_status",
    "remove_shield", "establish_scene", "gain_synergy", "summon_partner",
    "partner_heal", "partner_retreat", "partner_extra_action", "paper_open",
    "paper_progress", "paper_citation", "paper_modifier", "paper_amplify",
    "paper_publish", "chapter_deploy", "chapter_run", "chapter_return",
    "add_work_bonus", "cost_discount_next", "generate_card", "work_bonus_next",
    "spend_synergy", "spend_synergy_up_to", "spend_all_synergy",
    "swap_chapter_slots", "search_draw_for_type", "shuffle_draw", "spend_citation",
    "copy_chapter_to_hand", "publication_cost_discount",
    "chapter_return_with_modifier", "trigger_erosion", "trigger_induced", "status_complete",
    "modify_erosion_window", "arm_erosion_on_next_draws", "extend_timed_debuffs",
    "change_topic", "source_stacks",
}
KNOWN_CONDITIONS = {
    "link", "prev_card_type_is", "played_type_count_turn", "target_has_status",
    "target_status_kinds", "paper_open", "paper_closed", "paper_progress_min",
    "paper_name_unused", "paper_name_used", "chapter_count_min", "partner_count_min",
    "no_partner", "synergy_min", "independent_exam", "fixed_exam_room",
    "retrieved_strategy_this_turn", "paid_citation_focus_this_turn",
    "citation_min", "hand_other_min",
    "instance_plays_battle", "ddl_lte", "base_cost_min", "no_strategy_played_turn",
    "card_discarded_this_effect", "target_still_alive", "prepare_window", "two_tasks",
    "target_has_any_timed_debuff", "any_task_debuff_kinds_min",
    "target_had_induced_at_play_start", "target_has_induced",
    "erosion_applied_events_min", "first_induced_trigger", "compound_reaction_success",
    "any_task_has_induced", "summoned_partner_turn", "first_cooperation_resolved",
    "healed_partner_turn", "synergy_is_zero", "paper_progress_gained",
    "passive_retrieve_success", "instance_played_before", "previous_strategy_plays_min",
    "other_chapter_ran_window", "link_work_resolved",
}
KNOWN_TRIGGERS = {
    "first_work_card_resolving", "link_work_resolved", "passive_retrieve_success",
    "strategy_resolved", "work_resolved", "paper_progress_gained", "chapter_window_end",
    "first_cooperation_resolved", "prepare", "erosion_applied_event", "induced_trigger",
    "compound_reaction_success", "first_unused_permanent_card_resolved", "passive_rule",
}


def collect(value, key, out):
    if isinstance(value, dict):
        candidate = value.get(key)
        if isinstance(candidate, str):
            out.add(candidate)
        for child in value.values():
            collect(child, key, out)
    elif isinstance(value, list):
        for child in value:
            collect(child, key, out)


def fail(errors, message):
    errors.append(message)


def main() -> int:
    errors: list[str] = []
    if not DESIGN.exists():
        print(f"missing design source: {DESIGN}", file=sys.stderr)
        return 2
    if not CATALOG.exists():
        print(f"missing catalog: {CATALOG}", file=sys.stderr)
        return 2

    design = json.loads(DESIGN.read_text(encoding="utf-8"))
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    design_items = {item["id"]: item for item in design["cards"] + design["tokens"]}
    cards = catalog.get("cards", [])

    if catalog.get("schema_version") != SCHEMA_VERSION:
        fail(errors, f"schema_version must be {SCHEMA_VERSION}")
    if len(cards) != 174:
        fail(errors, f"expected 174 catalog entries, got {len(cards)}")

    seen = set()
    ops = set()
    conditions = set()
    triggers = set()
    for card in cards:
        cid = card.get("id", "")
        if not cid:
            fail(errors, "card without id")
            continue
        if cid in seen:
            fail(errors, f"duplicate id {cid}")
        seen.add(cid)
        if cid not in design_items:
            fail(errors, f"{cid} is not in the design snapshot")
            continue
        source = design_items[cid]
        checks = {
            "name_key": source["name_key"],
            "name": source["name"],
            "owner": source["owner"],
            "character": source["character"],
            "group": source["group"],
            "cost": int(source["cost"]),
            "upgraded_cost": int(source["upgraded_cost"]),
            "type": TYPE_MAP[source["type"]],
            "rarity": RARITY_MAP[source["rarity"]],
            "permanent": bool(source.get("permanent", True)),
            "tags": list(source.get("tags", [])),
            "base_text": source["base"],
            "upgraded_text": source["upgraded"],
            "exam_condition": source.get("exam_condition", ""),
            "exam_text": source.get("exam", ""),
            "exam_upgraded_text": source.get("exam_upgraded", ""),
            "chapter_text": source.get("chapter", ""),
            "chapter_upgraded_text": source.get("chapter_upgraded", ""),
        }
        for field, expected in checks.items():
            if card.get(field) != expected:
                fail(errors, f"{cid}.{field} mismatch: {card.get(field)!r} != {expected!r}")
        if card.get("type") not in TYPES:
            fail(errors, f"{cid}.type is invalid")
        if card.get("rarity") not in RARITIES:
            fail(errors, f"{cid}.rarity is invalid")
        if card.get("target") not in TARGETS:
            fail(errors, f"{cid}.target is invalid: {card.get('target')!r}")
        if card.get("exam") and card["exam"].get("target") not in TARGETS:
            fail(errors, f"{cid}.exam.target is invalid: {card['exam'].get('target')!r}")
        if not isinstance(card.get("effects"), list):
            fail(errors, f"{cid}.effects must be a list")
        if not card.get("effects") and not card.get("ability") and not card.get("chapter") and not card.get("exam"):
            fail(errors, f"{cid} has no effects/ability/chapter/exam")
        implementation = card.get("implementation", {})
        if implementation.get("status") != "catalog_only":
            fail(errors, f"{cid}.implementation.status must be catalog_only")
        if implementation.get("runtime_enabled") is not False:
            fail(errors, f"{cid}.implementation.runtime_enabled must be false")
        collect(card.get("effects", []), "op", ops)
        collect(card.get("upgrade_effects", []), "op", ops)
        collect(card.get("ability", {}), "op", ops)
        collect(card.get("chapter", {}), "op", ops)
        collect(card.get("exam", {}), "op", ops)
        collect(card.get("requirements", []), "kind", conditions)
        collect(card.get("upgrade_requirements", []), "kind", conditions)
        collect(card.get("effects", []), "kind", conditions)
        collect(card.get("upgrade_effects", []), "kind", conditions)
        collect(card.get("ability", {}), "kind", conditions)
        collect(card.get("chapter", {}), "kind", conditions)
        collect(card.get("exam", {}), "kind", conditions)
        for trigger in card.get("ability", {}).get("triggers", []):
            triggers.add(str(trigger.get("on", "")))

    missing = sorted(set(design_items) - seen)
    if missing:
        fail(errors, f"missing catalog entries: {missing}")

    unknown_ops = sorted(ops - KNOWN_OPS)
    unknown_conditions = sorted(conditions - KNOWN_CONDITIONS)
    unknown_triggers = sorted(triggers - KNOWN_TRIGGERS)
    for item in unknown_ops:
        fail(errors, f"unknown op {item}")
    for item in unknown_conditions:
        fail(errors, f"unknown condition {item}")
    for item in unknown_triggers:
        fail(errors, f"unknown trigger {item}")

    if builder is not None:
        for name, local in (
            ("KNOWN_OPS", KNOWN_OPS),
            ("KNOWN_CONDITIONS", KNOWN_CONDITIONS),
            ("KNOWN_TRIGGERS", KNOWN_TRIGGERS),
        ):
            remote = getattr(builder, name, None)
            if remote != local:
                fail(errors, f"builder/validator {name} drift")
    else:
        fail(errors, "builder module could not be imported for DSL drift check")

    permanent = [card for card in cards if card.get("permanent")]
    owner_counts = Counter(card.get("owner") for card in permanent)
    expected_owners = {"C": 12, "P01": 40, "P02": 40, "P03": 40, "P04": 40}
    if dict(owner_counts) != expected_owners:
        fail(errors, f"permanent owner counts mismatch: {dict(owner_counts)}")
    for owner in ("P01", "P02", "P03", "P04"):
        rarity_counts = Counter(card.get("rarity") for card in permanent if card.get("owner") == owner)
        expected = {"common": 20, "advanced": 15, "rare": 5}
        if dict(rarity_counts) != expected:
            fail(errors, f"{owner} rarity counts mismatch: {dict(rarity_counts)}")
    if len([card for card in cards if not card.get("permanent")]) != 2:
        fail(errors, "expected exactly 2 tokens")

    starters = catalog.get("starters", {})
    common = starters.get("common", [])
    common_total = sum(int(item.get("count", 0)) for item in common if isinstance(item, dict))
    if common_total != 10:
        fail(errors, f"common starter total must be 10, got {common_total}")
    card_by_id = {card.get("id"): card for card in cards}
    for item in common:
        if not isinstance(item, dict) or item.get("card") not in card_by_id:
            fail(errors, f"unknown common starter {item!r}")
    characters = starters.get("characters", {})
    if set(characters) != {"P01", "P02", "P03", "P04"}:
        fail(errors, f"starter character keys mismatch: {sorted(characters)}")
    for owner, entries in characters.items():
        if len(entries) != 2:
            fail(errors, f"{owner} starter exclusive card count must be 2")
        exclusive = [card_by_id.get(card_id) for card_id in entries]
        if any(card is None or not card.get("permanent") or card.get("owner") != owner for card in exclusive):
            fail(errors, f"{owner} starter exclusives must be permanent and owned by {owner}")
        if common_total + len(entries) != 12:
            fail(errors, f"{owner} starter deck must total 12")

    summary = {
        "total": len(cards),
        "permanent": len(permanent),
        "tokens": len(cards) - len(permanent),
        "owners": dict(owner_counts),
        "types": dict(Counter(card.get("type") for card in cards)),
        "rarities": dict(Counter(card.get("rarity") for card in cards)),
        "runtime_enabled": sum(1 for card in cards if card.get("implementation", {}).get("runtime_enabled")),
        "ops": len(ops),
        "conditions": len(conditions),
        "triggers": len(triggers),
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("cards_v3_catalog=valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
