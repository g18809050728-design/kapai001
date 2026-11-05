#!/usr/bin/env python3
"""Build the machine-readable v3.1 card catalog.

The source of truth remains campus-cards-v3.json (design prose).  This script
adds a structured, engine-oriented layer: targets, requirements, effects,
ability/chapter/exam faces, and per-card implementation status.  It does not
claim that the runtime engine implements every listed op yet.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "artifacts/redesign-20261030/campus-cards-v3.json"
OUTPUT = ROOT / "data/catalog/cards_v3.json"

SCHEMA_VERSION = "r3-card-catalog.v1"


def fx(op: str, **kw):
    value = {"op": op}
    value.update(kw)
    return value


def complete(amount, **kw):
    return fx("complete", amount=amount, **kw)


def relax(amount, **kw):
    return fx("relax", amount=amount, **kw)


def heal(amount, **kw):
    return fx("heal", amount=amount, **kw)


def lose_vitality(amount, **kw):
    return fx("lose_vitality", amount=amount, can_kill=True, **kw)


def gain_focus(amount, **kw):
    return fx("gain_focus", amount=amount, **kw)


def draw(amount, **kw):
    return fx("draw", amount=amount, **kw)


def discard(amount, up_to=False, **kw):
    return fx("discard", amount=amount, up_to=up_to, mode="choose", **kw)


def retain(amount=1, **kw):
    return fx("retain", amount=amount, choose="other_hand", **kw)


def exhaust_other(amount=1):
    return fx("exhaust_other", amount=amount)


def retrieve(kind, base_cost_min=0, amount=1, zone="discard", **kw):
    value = fx(
        "retrieve",
        card_kind=kind,
        base_cost_min=base_cost_min,
        amount=amount,
        zone=zone,
        permanent_only=True,
    )
    value.update(kw)
    return value


def apply_status(status, stacks, target="task", **kw):
    return fx("apply_status", status=status, stacks=stacks, target=target, **kw)


def remove_status(status, amount, target="self", up_to=True):
    return fx("remove_status", status=status, amount=amount, target=target, up_to=up_to)


def remove_shield(amount, target="task", up_to=True):
    return fx("remove_shield", amount=amount, target=target, up_to=up_to)


def gain_synergy(amount, **kw):
    return fx("gain_synergy", amount=amount, **kw)


def spend_synergy(amount, optional=False, then=None, if_spent=None):
    value = fx("spend_synergy", amount=amount, optional=optional)
    if then:
        value["then"] = then
    if if_spent:
        value["if_spent"] = if_spent
    return value


def spend_synergy_up_to(amount, then=None, after=None):
    value = fx("spend_synergy_up_to", amount=amount)
    if then:
        value["then"] = then
    if after:
        value["after"] = after
    return value


def spend_all_synergy(then=None):
    value = fx("spend_all_synergy")
    if then:
        value["then"] = then
    return value


def summon_partner(unit, vitality=None, max_vitality=None, **kw):
    value = fx("summon_partner", unit=unit)
    if vitality is not None:
        value["vitality"] = vitality
    if max_vitality is not None:
        value["max_vitality"] = max_vitality
    value.update(kw)
    return value


def partner_heal(amount, target="one"):
    return fx("partner_heal", amount=amount, target=target)


def partner_retreat(amount=1):
    return fx("partner_retreat", amount=amount)


def partner_action(amount=1, target="one"):
    return fx("partner_extra_action", amount=amount, target=target)


def paper_open():
    return fx("paper_open")


def paper_progress(amount):
    return fx("paper_progress", amount=amount)


def paper_citation(amount, **kw):
    return fx("paper_citation", amount=amount, **kw)


def paper_modifier(amount, **kw):
    return fx("paper_modifier", amount=amount, **kw)


def paper_amplify(amount):
    return fx("paper_amplify", amount=amount)


def paper_publish():
    return fx("paper_publish")


def chapter_deploy():
    return fx("chapter_deploy")


def chapter_run(amount=1, extra=False):
    return fx("chapter_run", amount=amount, extra=extra)


def chapter_return(amount):
    return fx("chapter_return", amount=amount)


def work_bonus(amount, **kw):
    value = fx("work_bonus_next", amount=amount, first_segment=True)
    value.update(kw)
    return value


def cost_discount(amount, min_base_cost=2):
    return fx("cost_discount_next", amount=amount, min_base_cost=min_base_cost)


def generate_card(card, amount=1, zone="hand"):
    return fx("generate_card", card=card, amount=amount, zone=zone)


def change_topic(optional=True):
    return fx("change_topic", optional=optional, modifier=-1)


def shuffle_draw():
    return fx("shuffle_draw")


def establish_scene(scene):
    return fx("establish_scene", scene=scene)


def trigger_erosion(amount=1, extra=False, decay=True, **kw):
    return fx("trigger_erosion", amount=amount, extra=extra, decay=decay, **kw)


def trigger_induced(amount=1, extra=False, **kw):
    return fx("trigger_induced", amount=amount, extra=extra, **kw)


def status_complete(amount, status=None, target="task", **kw):
    value = fx("status_complete", amount=amount, target=target)
    if status:
        value["status"] = status
    value.update(kw)
    return value


def cond(kind, **kw):
    value = {"kind": kind}
    value.update(kw)
    return value


def all_of(*conditions):
    return {"all": list(conditions)}


def any_of(*conditions):
    return {"any": list(conditions)}


def link():
    return cond("link")


def prev_type(value):
    return cond("prev_card_type_is", value=value)


def played_type_turn(value, minimum):
    return cond("played_type_count_turn", value=value, min=minimum)


def target_has(status):
    return cond("target_has_status", status=status)


def target_kinds(minimum):
    return cond("target_status_kinds", min=minimum)


def paper_open_cond():
    return cond("paper_open")


def paper_closed():
    return cond("paper_closed")


def paper_progress_min(value):
    return cond("paper_progress_min", value=value)


def paper_name_unused():
    return cond("paper_name_unused")


def paper_name_used():
    return cond("paper_name_used")


def chapter_count_min(value):
    return cond("chapter_count_min", value=value)


def partner_count_min(value):
    return cond("partner_count_min", value=value)


def no_partner():
    return cond("no_partner")


def synergy_min(value):
    return cond("synergy_min", value=value)


def independent_exam():
    return cond("independent_exam")


def fixed_exam():
    return cond("fixed_exam_room")


def retrieved_turn():
    return cond("retrieved_strategy_this_turn")


def paid_citation_turn():
    return cond("paid_citation_focus_this_turn")


def citation_min(value):
    return cond("citation_min", value=value)


def hand_other_min(value):
    return cond("hand_other_min", value=value)


def instance_plays(minimum):
    return cond("instance_plays_battle", min=minimum)


def target_no_debuff():
    return cond("target_status_kinds", max=0)


def no_previous_partner():
    return cond("no_partner")


EFFECTS = {}


def card(card_id: str, **kw):
    if card_id in EFFECTS:
        raise SystemExit(f"duplicate card definition: {card_id}")
    EFFECTS[card_id] = kw


# ---------------------------------------------------------------------------
# Common 12
# ---------------------------------------------------------------------------
card("R3-C-01", t="task", e=[complete(6)], u=[complete(9)])
card("R3-C-02", t="self", e=[relax(5)], u=[relax(8)])
card("R3-C-03", t="self", e=[draw(2), discard(1)], u=[draw(3), discard(1)])
card("R3-C-04", t="self", e=[relax(3)], u=[relax(5)], f={"exhaust": True})
card("R3-C-05", t="self", e=[heal(3), relax(3)], u=[heal(4), relax(5)], f={"exhaust": True})
card(
    "R3-C-06",
    t="self",
    e=[fx("add_work_bonus", amount=2, first_segment=True, limit="once_per_turn")],
    u=[fx("add_work_bonus", amount=3, first_segment=True, limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "first_work_card_resolving"},
)
card(
    "R3-C-07",
    t="task",
    e=[complete(8, bonus={"condition": cond("ddl_lte", value=3), "amount": 4, "same_segment": True})],
    u=[complete(11, bonus={"condition": cond("ddl_lte", value=3), "amount": 6, "same_segment": True})],
)
card(
    "R3-C-08",
    t="self",
    e=[establish_scene("R3-S01")],
    u=[establish_scene("R3-S01+")],
    f={"exhaust": True},
    ex={"condition": "fixed_exam_room", "e": [draw(1), relax(5)], "u": [draw(1), relax(8)]},
)
card(
    "R3-C-09",
    t="task",
    e=[apply_status("vulnerability", 1), complete(4)],
    u=[apply_status("vulnerability", 2), complete(6)],
)
card(
    "R3-C-10",
    t="task",
    e=[apply_status("weakness", 1), relax(4)],
    u=[apply_status("weakness", 2), relax(6)],
)
card(
    "R3-C-11",
    t="task",
    e=[remove_shield(6), complete(5)],
    u=[remove_shield(9), complete(7)],
)
card("R3-C-12", t="all_tasks", e=[complete(4)], u=[complete(6)])

# ---------------------------------------------------------------------------
# P01 林序
# ---------------------------------------------------------------------------
card("R3-P01-01", t="self", e=[draw(2), discard(1)], u=[draw(3), discard(1)])
card(
    "R3-P01-02",
    t="task",
    e=[complete(6, bonus={"condition": link(), "amount": 3, "same_segment": True})],
    u=[complete(9, bonus={"condition": link(), "amount": 4, "same_segment": True})],
)
card("R3-P01-03", t="task", e=[complete(3)], u=[complete(5)], l={"per_instance_per_turn": 1})
card("R3-P01-04", t="self", e=[relax(2)], u=[relax(4)], l={"per_instance_per_turn": 1})
card(
    "R3-P01-05",
    t="task",
    e=[complete(5), relax(5, condition=link())],
    u=[complete(8), relax(7, condition=link())],
)
card(
    "R3-P01-06",
    t="task",
    e=[complete(7), draw(1, condition=link(), limit="once_per_turn")],
    u=[complete(10), draw(1, condition=link(), limit="once_per_turn")],
)
card(
    "R3-P01-07",
    t="self",
    e=[relax(5), draw(1, condition=prev_type("work"))],
    u=[relax(8), draw(1, condition=prev_type("work"))],
)
card(
    "R3-P01-08",
    t="all_tasks",
    e=[complete(4, bonus={"condition": link(), "amount": 2, "same_segment": True})],
    u=[complete(6, bonus={"condition": link(), "amount": 3, "same_segment": True})],
)
card(
    "R3-P01-09",
    t="task",
    e=[complete(10, per_link_work=3, cap=3)],
    u=[complete(14, per_link_work=4, cap=3)],
    f={"exhaust": True},
)
card(
    "R3-P01-10",
    t="self",
    e=[relax(3, condition=cond("link_work_resolved"), limit="twice_per_turn")],
    u=[relax(4, condition=cond("link_work_resolved"), limit="twice_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "link_work_resolved"},
)
card("R3-P01-11", t="self", e=[relax(7)], u=[relax(10)])
card("R3-P01-12", t="self", e=[draw(1), relax(4)], u=[draw(2), relax(5)])
card(
    "R3-P01-13",
    t="self",
    e=[remove_status("anxiety", 1), relax(4)],
    u=[remove_status("anxiety", 2), relax(6)],
)
card(
    "R3-P01-14",
    t="task",
    e=[complete(7), draw(1, condition=retrieved_turn(), limit="once_per_turn")],
    u=[complete(10), draw(1, condition=retrieved_turn(), limit="once_per_turn")],
)
card(
    "R3-P01-15",
    t="self",
    e=[relax(5), retain()],
    u=[relax(8), retain()],
)
card(
    "R3-P01-16",
    t="self",
    e=[retrieve("strategy", base_cost_min=1)],
    u=[retrieve("strategy", base_cost_min=1)],
    f={"exhaust": True},
)
card(
    "R3-P01-17",
    t="self",
    e=[relax(6, bonus={"condition": instance_plays(1), "amount": 3})],
    u=[relax(9, bonus={"condition": instance_plays(1), "amount": 4})],
)
card(
    "R3-P01-18",
    t="self",
    e=[draw(1, condition=cond("passive_retrieve_success"), limit="once_per_turn")],
    u=[draw(1, condition=cond("passive_retrieve_success"), limit="once_per_turn"), relax(3)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "passive_retrieve_success"},
)
card(
    "R3-P01-19",
    t="task",
    e=[
        complete(
            8,
            bonus={
                "condition": all_of(link(), cond("previous_strategy_plays_min", value=2)),
                "amount": 5,
                "same_segment": True,
            },
        )
    ],
    u=[
        complete(
            11,
            bonus={
                "condition": all_of(link(), cond("previous_strategy_plays_min", value=2)),
                "amount": 7,
                "same_segment": True,
            },
        )
    ],
)
card(
    "R3-P01-20",
    t="self",
    e=[relax(5, condition=cond("instance_played_before"), limit="once_per_turn"), draw(1, limit="once_per_turn")],
    u=[relax(8, condition=cond("instance_played_before"), limit="once_per_turn"), draw(1, limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "strategy_resolved", "condition": cond("instance_played_before")},
)
card(
    "R3-P01-21",
    t="self",
    e=[relax(4), work_bonus(4)],
    u=[relax(6), work_bonus(6)],
)
card(
    "R3-P01-22",
    t="self",
    e=[draw(1), work_bonus(3)],
    u=[draw(2), work_bonus(4)],
)
card("R3-P01-23", t="task", e=[complete(14)], u=[complete(19)])
card(
    "R3-P01-24",
    t="self",
    e=[draw(2), discard(1), work_bonus(3, condition=played_type_turn("strategy", 1))],
    u=[draw(3), discard(1), work_bonus(4, condition=played_type_turn("strategy", 1))],
)
card(
    "R3-P01-25",
    t="self",
    e=[cost_discount(1, min_base_cost=2)],
    u=[cost_discount(1, min_base_cost=2), relax(3)],
    f={"exhaust": True},
)
card(
    "R3-P01-26",
    t="self",
    e=[relax(6), draw(2, condition=played_type_turn("strategy", 2))],
    u=[relax(9), draw(2, condition=played_type_turn("strategy", 2))],
)
card(
    "R3-P01-27",
    t="task",
    e=[complete(12, bonus={"condition": played_type_turn("strategy", 2), "amount": 8, "same_segment": True})],
    u=[complete(16, bonus={"condition": played_type_turn("strategy", 2), "amount": 10, "same_segment": True})],
)
card(
    "R3-P01-28",
    t="self",
    e=[relax(6, condition=cond("base_cost_min", value=2), limit="once_per_turn")],
    u=[relax(9, condition=cond("base_cost_min", value=2), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "work_resolved", "condition": cond("base_cost_min", value=2)},
)
card(
    "R3-P01-29",
    t="self",
    e=[retrieve("work", base_cost_min=2)],
    u=[retrieve("work", base_cost_min=2)],
    f={"exhaust": True},
)
card(
    "R3-P01-30",
    t="all_tasks",
    e=[complete(10, bonus={"condition": played_type_turn("strategy", 3), "amount": 6, "same_segment": True})],
    u=[complete(14, bonus={"condition": played_type_turn("strategy", 3), "amount": 8, "same_segment": True})],
    f={"exhaust": True},
)
card("R3-P01-31", t="self", e=[draw(2), relax(3)], u=[draw(2), relax(6)])
card(
    "R3-P01-32",
    t="task",
    e=[apply_status("vulnerability", 1), complete(5), relax(2, condition=link())],
    u=[apply_status("vulnerability", 2), complete(7), relax(3, condition=link())],
)
card(
    "R3-P01-33",
    t="task",
    e=[apply_status("weakness", 1), relax(4, bonus={"condition": retrieved_turn(), "amount": 2})],
    u=[apply_status("weakness", 2), relax(6, bonus={"condition": retrieved_turn(), "amount": 3})],
)
card(
    "R3-P01-34",
    t="task",
    e=[complete(8), relax(3, condition=cond("no_strategy_played_turn"))],
    u=[complete(11), relax(5, condition=cond("no_strategy_played_turn"))],
)
card(
    "R3-P01-35",
    t="self",
    e=[relax(5), discard(1, up_to=True), draw(1, condition=cond("card_discarded_this_effect"))],
    u=[relax(8), discard(1, up_to=True), draw(1, condition=cond("card_discarded_this_effect"))],
)
card(
    "R3-P01-36",
    t="self",
    e=[retain(), draw(1)],
    u=[retain(), draw(2)],
)
card(
    "R3-P01-37",
    t="task",
    e=[complete(4, segment=1), complete(4, segment=2, no_transfer=True)],
    u=[complete(6, segment=1), complete(6, segment=2, no_transfer=True)],
)
card(
    "R3-P01-38",
    t="self",
    r=[hand_other_min(1)],
    e=[exhaust_other(1), draw(2)],
    u=[exhaust_other(1), draw(3)],
)
card(
    "R3-P01-39",
    t="self",
    e=[remove_status("anxiety", 1), work_bonus(2)],
    u=[remove_status("anxiety", 2), work_bonus(3)],
    f={"exhaust": True},
)
card(
    "R3-P01-40",
    t="task",
    e=[
        complete(
            13,
            bonus={
                "condition": all_of(retrieved_turn(), played_type_turn("strategy", 3)),
                "amount": 10,
                "same_segment": True,
            },
        )
    ],
    u=[
        complete(
            17,
            bonus={
                "condition": all_of(retrieved_turn(), played_type_turn("strategy", 3)),
                "amount": 13,
                "same_segment": True,
            },
        )
    ],
    f={"exhaust": True},
)

# ---------------------------------------------------------------------------
# P02 许知微
# ---------------------------------------------------------------------------
card(
    "R3-P02-01",
    t="self",
    r=[paper_closed()],
    e=[paper_open()],
    u=[paper_open(), relax(3)],
    f={"innate": True, "permanent": True, "paper_record": False},
    l={"per_instance_per_turn": 1},
)
card("R3-P02-02", t="self", e=[draw(3), discard(1)], u=[draw(4), discard(1)])
card(
    "R3-P02-03",
    t="self",
    e=[relax(5), draw(1, condition=all_of(paper_open_cond(), paper_name_unused()))],
    u=[relax(8), draw(1, condition=all_of(paper_open_cond(), paper_name_unused()))],
)
card(
    "R3-P02-04",
    t="self",
    e=[generate_card("R3-T202", zone="hand"), draw(1)],
    u=[generate_card("R3-T202", zone="hand"), draw(2)],
    f={"exhaust": True},
)
card("R3-P02-05", t="self", e=[relax(6), retain()], u=[relax(9), retain()])
card(
    "R3-P02-06",
    t="self",
    e=[paper_citation(1, layered_payment=True, condition=paper_open_cond()), relax(5)],
    u=[paper_citation(1, layered_payment=True, condition=paper_open_cond()), relax(8)],
)
card(
    "R3-P02-07",
    t="self",
    r=[paper_open_cond()],
    e=[paper_progress(1), relax(3)],
    u=[paper_progress(1), relax(6)],
    f={"exhaust": True},
)
card(
    "R3-P02-08",
    t="self",
    r=[paper_open_cond()],
    e=[paper_modifier(5), draw(1)],
    u=[paper_modifier(8), draw(1)],
    f={"exhaust": True},
)
card(
    "R3-P02-09",
    t="self",
    r=[paper_open_cond(), paper_progress_min(7)],
    e=[paper_modifier(12), relax(6)],
    u=[paper_modifier(16), relax(9)],
    f={"exhaust": True},
)
card(
    "R3-P02-10",
    t="self",
    e=[draw(1, condition=cond("paper_progress_gained"), limit="once_per_turn"), relax(2)],
    u=[draw(1, condition=cond("paper_progress_gained"), limit="once_per_turn"), relax(4)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "paper_progress_gained"},
)
card(
    "R3-P02-11",
    t="self",
    r=[paper_open_cond()],
    e=[relax(3), chapter_deploy()],
    u=[relax(5), chapter_deploy()],
    ch={"resident": {"trigger": "prepare", "e": [draw(1)]}, "upgraded_resident": {"trigger": "prepare", "e": [draw(1), relax(2)]}},
)
card(
    "R3-P02-12",
    t="self",
    r=[paper_open_cond()],
    e=[relax(4), chapter_deploy()],
    u=[relax(6), chapter_deploy()],
    ch={
        "resident": {"trigger": "prepare", "e": [relax(3, bonus={"condition": chapter_count_min(2), "amount": 2})]},
        "upgraded_resident": {"trigger": "prepare", "e": [relax(5, bonus={"condition": chapter_count_min(2), "amount": 3})]},
    },
)
card(
    "R3-P02-13",
    t="self",
    r=[paper_open_cond()],
    e=[draw(1), chapter_deploy()],
    u=[draw(1), relax(2), chapter_deploy()],
    ch={
        "resident": {"trigger": "prepare", "e": [complete(4, target="earliest_task")]},
        "upgraded_resident": {"trigger": "prepare", "e": [complete(6, target="earliest_task")]},
    },
)
card(
    "R3-P02-14",
    t="self",
    r=[paper_open_cond()],
    e=[relax(3), chapter_deploy()],
    u=[relax(5), chapter_deploy()],
    ch={
        "resident": {"trigger": "prepare", "e": [relax(2), draw(1, condition=cond("other_chapter_ran_window"))]},
        "upgraded_resident": {"trigger": "prepare", "e": [relax(4), draw(1, condition=cond("other_chapter_ran_window"))]},
    },
)
card(
    "R3-P02-15",
    t="self",
    r=[paper_open_cond()],
    e=[draw(1), discard(1), chapter_deploy()],
    u=[draw(2), discard(1), chapter_deploy()],
    ch={
        "resident": {"trigger": "prepare", "e": [paper_amplify(1)]},
        "upgraded_resident": {"trigger": "prepare", "e": [paper_amplify(2)]},
    },
)
card(
    "R3-P02-16",
    t="self",
    r=[paper_open_cond()],
    e=[relax(5), chapter_deploy()],
    u=[relax(8), chapter_deploy()],
    ch={
        "resident": {
            "trigger": "prepare",
            "e": [complete(3, target="earliest_task", per_other_chapter=2, cap=2)],
        },
        "upgraded_resident": {
            "trigger": "prepare",
            "e": [complete(5, target="earliest_task", per_other_chapter=3, cap=2)],
        },
    },
)
card(
    "R3-P02-17",
    t="self",
    r=[chapter_count_min(2)],
    e=[fx("swap_chapter_slots", amount=2), relax(3)],
    u=[fx("swap_chapter_slots", amount=2), relax(5)],
    l={"per_instance_per_turn": 1},
)
card(
    "R3-P02-18",
    t="self",
    e=[fx("search_draw_for_type", card_type="strategy", tag="chapter", amount=1, fallback_draw=1), shuffle_draw()],
    u=[fx("search_draw_for_type", card_type="strategy", tag="chapter", amount=1, fallback_draw=1), shuffle_draw(), relax(3)],
)
card(
    "R3-P02-19",
    t="self",
    e=[relax(4, condition=chapter_count_min(2), limit="once_per_turn")],
    u=[relax(6, condition=chapter_count_min(2), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "chapter_window_end"},
)
card(
    "R3-P02-20",
    t="self",
    r=[chapter_count_min(1)],
    e=[chapter_run(1, extra=True)],
    u=[chapter_run(2, extra=True)],
    f={"exhaust": True},
)
card(
    "R3-P02-21",
    t="self",
    r=[paper_open_cond()],
    e=[change_topic(optional=True), draw(1)],
    u=[change_topic(optional=True), draw(1)],
    f={"exhaust": True},
)
card("R3-P02-22", t="self", e=[draw(2), paper_amplify(1)], u=[draw(2), paper_amplify(1)], f={"exhaust": True})
card(
    "R3-P02-23",
    t="self",
    e=[retrieve("strategy", base_cost_min=1)],
    u=[retrieve("strategy", base_cost_min=1), relax(3)],
    f={"exhaust": True},
)
card(
    "R3-P02-24",
    t="self",
    e=[relax(6), draw(1, condition=all_of(paper_open_cond(), paper_name_used()))],
    u=[relax(9), draw(1, condition=all_of(paper_open_cond(), paper_name_used()))],
)
card("R3-P02-25", t="self", e=[relax(5), draw(1)], u=[relax(8), draw(1)])
card(
    "R3-P02-26",
    t="self",
    r=[paper_open_cond(), citation_min(1)],
    e=[fx("spend_citation", amount=1), paper_modifier(3), draw(1)],
    u=[fx("spend_citation", amount=1), paper_modifier(5), draw(1)],
    f={"exhaust": True},
)
card(
    "R3-P02-27",
    t="self",
    r=[chapter_count_min(1)],
    e=[fx("copy_chapter_to_hand", amount=1)],
    u=[fx("copy_chapter_to_hand", amount=1), relax(3)],
    f={"exhaust": True},
)
card(
    "R3-P02-28",
    t="self",
    r=[paper_open_cond()],
    e=[fx("publication_cost_discount", amount=1), relax(3)],
    u=[fx("publication_cost_discount", amount=1), relax(6)],
    f={"exhaust": True},
)
card(
    "R3-P02-29",
    t="self",
    e=[discard(2, up_to=True), fx("draw", amount={"ref": "actual_discarded"}), paper_modifier(3, condition=paper_open_cond())],
    u=[discard(2, up_to=True), fx("draw", amount={"ref": "actual_discarded"}), paper_modifier(5, condition=paper_open_cond())],
    f={"exhaust": True},
)
card(
    "R3-P02-30",
    t="self",
    r=[paper_open_cond(), chapter_count_min(1)],
    e=[fx("chapter_return", amount=2, up_to=True, modifier_per_chapter=4)],
    u=[fx("chapter_return", amount=2, up_to=True, modifier_per_chapter=6)],
    f={"exhaust": True},
)
card("R3-P02-31", t="self", e=[draw(2), relax(3)], u=[draw(2), relax(6)])
card("R3-P02-32", t="self", e=[relax(8)], u=[relax(11)])
card(
    "R3-P02-33",
    t="self",
    e=[remove_status("anxiety", 1), draw(1)],
    u=[remove_status("anxiety", 2), draw(1)],
)
card(
    "R3-P02-34",
    t="task",
    e=[apply_status("weakness", 1), relax(4, bonus={"condition": paid_citation_turn(), "amount": 2})],
    u=[apply_status("weakness", 2), relax(6, bonus={"condition": paid_citation_turn(), "amount": 3})],
)
card(
    "R3-P02-35",
    t="task",
    e=[apply_status("vulnerability", 1), complete(5, bonus={"condition": fixed_exam(), "amount": 3, "same_segment": True})],
    u=[apply_status("vulnerability", 2), complete(7, bonus={"condition": fixed_exam(), "amount": 4, "same_segment": True})],
)
card(
    "R3-P02-36",
    t="self",
    e=[establish_scene("R3-S02")],
    u=[establish_scene("R3-S02+")],
    f={"exhaust": True},
    ex={"condition": "fixed_exam_room", "e": [draw(2), relax(3)], "u": [draw(3), relax(5)]},
)
card(
    "R3-P02-37",
    t="self",
    e=[draw(2), lose_vitality(2)],
    u=[draw(3), lose_vitality(2)],
    f={"exhaust": True},
)
card(
    "R3-P02-38",
    t="self",
    e=[gain_focus(2), lose_vitality(3)],
    u=[gain_focus(3), lose_vitality(3)],
    f={"exhaust": True},
)
card(
    "R3-P02-39",
    t="self",
    r=[paper_closed()],
    e=[retrieve("strategy", card_id="R3-P02-01")],
    u=[retrieve("strategy", card_id="R3-P02-01")],
    f={"exhaust": True},
)
card(
    "R3-P02-40",
    t="self",
    e=[relax(3, condition=all_of(paper_open_cond(), paper_name_unused()), limit="once_per_turn")],
    u=[relax(5, condition=all_of(paper_open_cond(), paper_name_unused()), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "first_unused_permanent_card_resolved"},
)

# ---------------------------------------------------------------------------
# P03 沈见章
# ---------------------------------------------------------------------------
card(
    "R3-P03-01",
    t="task",
    e=[complete(4), apply_status("erosion", 3, condition=cond("target_still_alive"))],
    u=[complete(6), apply_status("erosion", 4, condition=cond("target_still_alive"))],
)
card("R3-P03-02", t="task", e=[apply_status("erosion", 3), relax(4)], u=[apply_status("erosion", 4), relax(6)])
card("R3-P03-03", t="task", e=[apply_status("erosion", 2), draw(1)], u=[apply_status("erosion", 3), draw(1)])
card(
    "R3-P03-04",
    t="self",
    e=[apply_status("erosion", 1, target="all_tasks", condition=cond("prepare_window"))],
    u=[apply_status("erosion", 2, target="all_tasks", condition=cond("prepare_window"))],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "prepare", "no_compound_reaction": True},
)
card(
    "R3-P03-05",
    t="task",
    r=[cond("two_tasks"), target_has("erosion")],
    e=[apply_status("erosion", fx("source_stacks", status="erosion", cap=3), target="other_task")],
    u=[apply_status("erosion", fx("source_stacks", status="erosion", cap=5), target="other_task")],
    f={"exhaust": True},
)
card(
    "R3-P03-06",
    t="task",
    r=[target_has("erosion")],
    e=[apply_status("erosion", 6)],
    u=[apply_status("erosion", 8)],
)
card(
    "R3-P03-07",
    t="task",
    r=[target_has("erosion")],
    e=[trigger_erosion(1, extra=True, decay=False)],
    u=[trigger_erosion(1, extra=True, decay=False), relax(3)],
    f={"exhaust": True},
)
card(
    "R3-P03-08",
    t="task",
    e=[apply_status("erosion", 2), apply_status("weakness", 1)],
    u=[apply_status("erosion", 3), apply_status("weakness", 2)],
)
card(
    "R3-P03-09",
    t="task",
    r=[target_has("erosion")],
    e=[apply_status("erosion", fx("source_stacks", status="erosion", cap=20))],
    u=[apply_status("erosion", fx("source_stacks", status="erosion", cap=20, bonus=3))],
    f={"exhaust": True},
)
card(
    "R3-P03-10",
    t="self",
    e=[fx("modify_erosion_window", times=2)],
    u=[fx("modify_erosion_window", times=3)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "passive_rule"},
)
card(
    "R3-P03-11",
    t="task",
    e=[apply_status("induced", 1), draw(1)],
    u=[apply_status("induced", 2), draw(1)],
    f={"no_trigger_new_induced": True},
)
card("R3-P03-12", t="task", e=[complete(3)], u=[complete(5)], l={"per_instance_per_turn": 1})
card(
    "R3-P03-13",
    t="self",
    e=[draw(1), discard(1)],
    u=[draw(1), discard(1), relax(2)],
    l={"per_instance_per_turn": 1},
)
card(
    "R3-P03-14",
    t="task",
    e=[complete(5), draw(1, condition=cond("target_had_induced_at_play_start"))],
    u=[complete(8), draw(1, condition=cond("target_had_induced_at_play_start"))],
)
card(
    "R3-P03-15",
    t="task",
    e=[apply_status("induced", 1), relax(5)],
    u=[apply_status("induced", 2), relax(7)],
    f={"no_refresh_induced_count": True},
)
card(
    "R3-P03-16",
    t="self",
    e=[fx("arm_erosion_on_next_draws", amount=3, status="erosion", stacks=1, target="all_tasks")],
    u=[fx("arm_erosion_on_next_draws", amount=4, status="erosion", stacks=1, target="all_tasks")],
    f={"exhaust": True, "same_name_once_per_turn": True},
)
card(
    "R3-P03-17",
    t="task",
    e=[apply_status("induced", 1), apply_status("vulnerability", 1)],
    u=[apply_status("induced", 2), apply_status("vulnerability", 2)],
)
card(
    "R3-P03-18",
    t="task",
    e=[complete(6), trigger_induced(1, extra=True, condition=cond("target_has_induced"))],
    u=[complete(9), trigger_induced(1, extra=True, condition=cond("target_has_induced"))],
)
card(
    "R3-P03-19",
    t="self",
    e=[status_complete(4, target="all_tasks", condition=cond("erosion_applied_events_min", value=3), limit="once_per_turn")],
    u=[status_complete(6, target="all_tasks", condition=cond("erosion_applied_events_min", value=3), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "erosion_applied_event"},
)
card(
    "R3-P03-20",
    t="self",
    e=[status_complete(3, condition=cond("first_induced_trigger"), limit="once_per_turn")],
    u=[status_complete(5, condition=cond("first_induced_trigger"), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "induced_trigger"},
)
card(
    "R3-P03-21",
    t="task",
    e=[apply_status("weakness", 1), apply_status("feebleness", 1)],
    u=[apply_status("weakness", 2), apply_status("feebleness", 1)],
)
card(
    "R3-P03-22",
    t="task",
    e=[apply_status("brittle", 1), remove_shield(4), complete(4)],
    u=[apply_status("brittle", 2), remove_shield(6), complete(6)],
)
card("R3-P03-23", t="task", e=[apply_status("vulnerability", 1), draw(1)], u=[apply_status("vulnerability", 2), draw(1)])
card("R3-P03-24", t="task", e=[apply_status("feebleness", 1), relax(5)], u=[apply_status("feebleness", 2), relax(7)])
card(
    "R3-P03-25",
    t="task",
    e=[complete(5, per_debuff_kind=2, cap=4)],
    u=[complete(7, per_debuff_kind=3, cap=4)],
)
card(
    "R3-P03-26",
    t="task",
    e=[apply_status("erosion", 1), apply_status("brittle", 1), apply_status("weakness", 1)],
    u=[apply_status("erosion", 2), apply_status("brittle", 2), apply_status("weakness", 1)],
)
card(
    "R3-P03-27",
    t="all_tasks",
    e=[apply_status("weakness", 1, target="all_tasks"), relax(2)],
    u=[apply_status("weakness", 2, target="all_tasks"), relax(4)],
)
card(
    "R3-P03-28",
    t="task",
    r=[cond("target_has_any_timed_debuff")],
    e=[fx("extend_timed_debuffs", amount=1, cap=3)],
    u=[fx("extend_timed_debuffs", amount=1, cap=3), relax(5)],
    f={"exhaust": True},
)
card(
    "R3-P03-29",
    t="all_tasks",
    e=[complete(4, per_debuff_kind=2, cap=4, per_target=True)],
    u=[complete(6, per_debuff_kind=3, cap=4, per_target=True)],
    f={"exhaust": True},
)
card(
    "R3-P03-30",
    t="self",
    e=[relax(5, condition=cond("any_task_debuff_kinds_min", value=3), limit="once_per_turn")],
    u=[relax(7, condition=cond("any_task_debuff_kinds_min", value=3), limit="once_per_turn")],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "prepare", "extra": [status_complete(5, target="earliest_task", condition=cond("any_task_debuff_kinds_min", value=3))]},
)
card("R3-P03-31", t="self", e=[draw(2), relax(3)], u=[draw(2), relax(6)])
card("R3-P03-32", t="self", e=[relax(8)], u=[relax(11)])
card(
    "R3-P03-33",
    t="self",
    e=[remove_status("anxiety", 1), apply_status("weakness", 1)],
    u=[remove_status("anxiety", 2), apply_status("weakness", 2)],
)
card(
    "R3-P03-34",
    t="self",
    e=[retrieve("strategy", base_cost_min=1)],
    u=[retrieve("strategy", base_cost_min=1)],
    f={"exhaust": True},
)
card(
    "R3-P03-35",
    t="task",
    e=[complete(8, bonus={"condition": target_no_debuff(), "amount": 3, "same_segment": True})],
    u=[complete(11, bonus={"condition": target_no_debuff(), "amount": 4, "same_segment": True})],
)
card(
    "R3-P03-36",
    t="task",
    e=[complete(6), draw(1, condition=target_kinds(2))],
    u=[complete(9), draw(1, condition=target_kinds(2))],
)
card("R3-P03-37", t="self", e=[relax(6), retain()], u=[relax(9), retain()])
card(
    "R3-P03-38",
    t="self",
    r=[hand_other_min(1)],
    e=[exhaust_other(1), draw(2)],
    u=[exhaust_other(1), draw(3)],
)
card(
    "R3-P03-39",
    t="self",
    e=[draw(2), discard(1), relax(3, condition=cond("any_task_has_induced"))],
    u=[draw(3), discard(1), relax(5, condition=cond("any_task_has_induced"))],
)
card(
    "R3-P03-40",
    t="self",
    e=[draw(1, condition=cond("compound_reaction_success"), limit="once_per_turn"), relax(3)],
    u=[draw(1, condition=cond("compound_reaction_success"), limit="once_per_turn"), relax(5)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "compound_reaction_success"},
)

# ---------------------------------------------------------------------------
# P04 唐以宁
# ---------------------------------------------------------------------------
card(
    "R3-P04-01",
    t="self",
    e=[summon_partner("R3-U01")],
    u=[summon_partner("R3-U01", vitality=5, max_vitality=5)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "target": "task", "e": [complete(5), relax(3)], "u": [complete(7), relax(5)]},
)
card("R3-P04-02", t="self", e=[relax(5), gain_synergy(1)], u=[relax(8), gain_synergy(1)])
card(
    "R3-P04-03",
    t="task",
    e=[complete(6, per_partner=2, cap=3)],
    u=[complete(9, per_partner=2, cap=3)],
)
card(
    "R3-P04-04",
    t="self",
    e=[summon_partner("R3-U02")],
    u=[summon_partner("R3-U02", cooperation=2)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "e": [draw(2), discard(1), relax(4)], "u": [draw(3), discard(1), relax(6)]},
)
card(
    "R3-P04-05",
    t="task",
    e=[complete(7), relax(4, condition=played_type_turn("cooperation", 1))],
    u=[complete(10), relax(6, condition=played_type_turn("cooperation", 1))],
)
card(
    "R3-P04-06",
    t="unit",
    r=[partner_count_min(1), synergy_min(1)],
    e=[spend_synergy(1, optional=False, then=[partner_action(1)])],
    u=[spend_synergy(1, optional=False, then=[partner_action(1), relax(3)])],
    ex={"condition": "independent_answer", "target": "task", "e": [spend_synergy(1, optional=False, then=[complete(9), relax(3)])], "u": [spend_synergy(1, optional=False, then=[complete(12), relax(5)])]},
)
card(
    "R3-P04-07",
    t="self",
    e=[relax(6), draw(1, condition=synergy_min(2))],
    u=[relax(9), draw(1, condition=synergy_min(2))],
)
card(
    "R3-P04-08",
    t="self",
    e=[summon_partner("R3-U03")],
    u=[summon_partner("R3-U03", vitality=7, max_vitality=7)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "target": "task", "e": [complete(9), gain_synergy(1)], "u": [complete(12), gain_synergy(1)]},
)
card(
    "R3-P04-09",
    t="task",
    e=[complete(10, per_partner=3), spend_synergy(2, optional=True, if_spent=[complete(8)])],
    u=[complete(14, per_partner=3), spend_synergy(2, optional=True, if_spent=[complete(10)])],
)
card(
    "R3-P04-10",
    t="self",
    e=[summon_partner("R3-U01"), partner_action(1, target="all_eligible")],
    u=[summon_partner("R3-U01", vitality=5, max_vitality=5), partner_action(1, target="all_eligible")],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "target": "all_tasks", "e": [complete(7, target="all_tasks"), relax(4)], "u": [complete(10, target="all_tasks"), relax(6)]},
)
card(
    "R3-P04-11",
    t="self",
    e=[summon_partner("R3-U02", vitality=2, max_vitality=2), draw(1)],
    u=[summon_partner("R3-U02", vitality=3, max_vitality=3), draw(1)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "e": [draw(1), relax(4)], "u": [draw(2), relax(6)]},
)
card(
    "R3-P04-12",
    t="unit",
    r=[partner_count_min(1)],
    e=[partner_heal(2), relax(5)],
    u=[partner_heal(3), relax(7)],
    ex={"condition": "independent_answer", "target": "self", "e": [relax(5), gain_synergy(1)], "u": [relax(8), gain_synergy(1)]},
)
card(
    "R3-P04-13",
    t="task",
    e=[complete(7, bonus={"condition": any_of(partner_count_min(1), independent_exam()), "amount": 3, "same_segment": True})],
    u=[complete(10, bonus={"condition": any_of(partner_count_min(1), independent_exam()), "amount": 4, "same_segment": True})],
)
card(
    "R3-P04-14",
    t="self",
    e=[draw(2), relax(3, condition=any_of(cond("summoned_partner_turn"), independent_exam()))],
    u=[draw(3), relax(5, condition=any_of(cond("summoned_partner_turn"), independent_exam()))],
)
card(
    "R3-P04-15",
    t="unit",
    r=[partner_count_min(1)],
    e=[partner_retreat(1), draw(2), gain_synergy(1)],
    u=[partner_retreat(1), draw(3), gain_synergy(1)],
    ex={"condition": "independent_answer", "target": "self", "e": [draw(2), relax(3)], "u": [draw(3), relax(5)]},
)
card(
    "R3-P04-16",
    t="unit",
    r=[partner_count_min(1)],
    e=[partner_heal(1), relax(6), draw(1)],
    u=[partner_heal(2), relax(8), draw(1)],
    ex={"condition": "independent_answer", "target": "self", "e": [relax(6), draw(1)], "u": [relax(9), draw(1)]},
)
card(
    "R3-P04-17",
    t="self",
    e=[draw(1, condition=cond("first_cooperation_resolved"), limit="once_per_turn")],
    u=[draw(1, condition=cond("first_cooperation_resolved"), limit="once_per_turn"), relax(3)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "first_cooperation_resolved"},
)
card(
    "R3-P04-18",
    t="self",
    r=[partner_count_min(1), synergy_min(1)],
    e=[spend_synergy(1, optional=False, then=[partner_heal(1, target="all"), relax(4)])],
    u=[spend_synergy(1, optional=False, then=[partner_heal(2, target="all"), relax(6)])],
    ex={"condition": "independent_answer", "e": [spend_synergy(1, optional=False, then=[relax(10)])], "u": [spend_synergy(1, optional=False, then=[relax(14)])]},
)
card(
    "R3-P04-19",
    t="task",
    e=[complete(8), relax(5, condition=any_of(cond("healed_partner_turn"), independent_exam()))],
    u=[complete(11), relax(7, condition=any_of(cond("healed_partner_turn"), independent_exam()))],
)
card(
    "R3-P04-20",
    t="self",
    e=[gain_synergy(1, condition=cond("first_cooperation_resolved"), limit="once_per_turn"), relax(4, condition=any_of(partner_count_min(1), independent_exam()))],
    u=[gain_synergy(1, condition=cond("first_cooperation_resolved"), limit="once_per_turn"), relax(6, condition=any_of(partner_count_min(1), independent_exam()))],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "first_cooperation_resolved"},
)
card(
    "R3-P04-21",
    t="self",
    e=[summon_partner("R3-U01"), relax(3)],
    u=[summon_partner("R3-U01"), relax(6)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "e": [relax(6), gain_synergy(1)], "u": [relax(9), gain_synergy(1)]},
)
card(
    "R3-P04-22",
    t="self",
    e=[gain_synergy(1, condition=no_partner(), limit="once_per_turn")],
    u=[gain_synergy(1, condition=no_partner(), limit="once_per_turn"), relax(2)],
    ab={"activate": "next_round", "stack": "unique_name", "trigger": "prepare"},
)
card(
    "R3-P04-23",
    t="task",
    e=[complete(7), gain_synergy(1, condition=no_partner())],
    u=[complete(10), gain_synergy(1, condition=no_partner())],
)
card(
    "R3-P04-24",
    t="task",
    e=[complete(7), draw(1, condition=synergy_min(3))],
    u=[complete(10), draw(1, condition=synergy_min(3))],
)
card(
    "R3-P04-25",
    t="self",
    e=[spend_synergy_up_to(2, then=[relax(5, per_spent=3)], after=[remove_status("anxiety", 1)])],
    u=[spend_synergy_up_to(2, then=[relax(7, per_spent=4)], after=[remove_status("anxiety", 1)])],
)
card(
    "R3-P04-26",
    t="self",
    e=[summon_partner("R3-U02", vitality=2, max_vitality=2), gain_synergy(1)],
    u=[summon_partner("R3-U02", vitality=3, max_vitality=3), gain_synergy(1)],
    f={"exhaust": True},
    ex={"condition": "independent_answer", "e": [draw(2), gain_synergy(1)], "u": [draw(3), gain_synergy(1)]},
)
card(
    "R3-P04-27",
    t="task",
    e=[complete(8, bonus={"condition": played_type_turn("cooperation", 1), "amount": 4, "same_segment": True})],
    u=[complete(11, bonus={"condition": played_type_turn("cooperation", 1), "amount": 6, "same_segment": True})],
)
card(
    "R3-P04-28",
    t="task",
    e=[complete(14, bonus={"condition": synergy_min(3), "amount": 6, "same_segment": True})],
    u=[complete(18, bonus={"condition": synergy_min(3), "amount": 8, "same_segment": True})],
)
card(
    "R3-P04-29",
    t="self",
    r=[synergy_min(1)],
    e=[spend_synergy(1, optional=False, then=[draw(2), relax(4, condition=no_partner())])],
    u=[spend_synergy(1, optional=False, then=[draw(3), relax(6, condition=no_partner())])],
)
card(
    "R3-P04-30",
    t="task",
    e=[spend_all_synergy(then=[complete(12, per_spent=3, allow_zero=True)])],
    u=[spend_all_synergy(then=[complete(16, per_spent=4, allow_zero=True)])],
    f={"exhaust": True},
)
card(
    "R3-P04-31",
    t="task",
    e=[apply_status("weakness", 1), gain_synergy(1), draw(1)],
    u=[apply_status("weakness", 2), gain_synergy(1), draw(2)],
)
card(
    "R3-P04-32",
    t="task",
    e=[spend_synergy(1, optional=True, then=[complete(6), relax(3)], if_spent=[complete(4)])],
    u=[spend_synergy(1, optional=True, then=[complete(9), relax(5)], if_spent=[complete(5)])],
)
card(
    "R3-P04-33",
    t="self",
    e=[draw(2), discard(1), gain_synergy(1, condition=played_type_turn("cooperation", 1))],
    u=[draw(3), discard(1), gain_synergy(1, condition=played_type_turn("cooperation", 1))],
)
card("R3-P04-34", t="self", e=[relax(6), retain()], u=[relax(9), retain()])
card(
    "R3-P04-35",
    t="task",
    e=[apply_status("vulnerability", 1), complete(3, target="all_tasks")],
    u=[apply_status("vulnerability", 2), complete(5, target="all_tasks")],
)
card(
    "R3-P04-36",
    t="self",
    e=[retrieve("work", base_cost_min=1)],
    u=[retrieve("work", base_cost_min=1)],
    f={"exhaust": True},
)
card(
    "R3-P04-37",
    t="self",
    e=[remove_status("anxiety", 1), relax(5)],
    u=[remove_status("anxiety", 2), relax(7)],
)
card(
    "R3-P04-38",
    t="self",
    e=[heal(3), relax(4)],
    u=[heal(4), relax(6)],
    f={"exhaust": True},
)
card(
    "R3-P04-39",
    t="self",
    e=[relax(9), gain_synergy(1, condition=cond("synergy_is_zero"))],
    u=[relax(12), gain_synergy(1, condition=cond("synergy_is_zero"))],
)
card(
    "R3-P04-40",
    t="all_tasks",
    e=[spend_all_synergy(then=[complete(6, target="all_tasks", per_spent=2, allow_zero=True)])],
    u=[spend_all_synergy(then=[complete(9, target="all_tasks", per_spent=2, allow_zero=True)])],
    f={"exhaust": True},
)

# ---------------------------------------------------------------------------
# Paper tokens
# ---------------------------------------------------------------------------
card(
    "R3-T201",
    t="all_tasks",
    r=[paper_open_cond()],
    e=[paper_publish()],
    f={"permanent": False, "unique": True, "upgradable": False, "retain": True, "paper_record": False},
)
card(
    "R3-T202",
    t="self",
    e=[draw(1)],
    f={"permanent": False, "exhaust": True, "paper_record": True, "upgradable": False},
)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
KNOWN_OPS = {
    "complete",
    "relax",
    "heal",
    "lose_vitality",
    "gain_focus",
    "draw",
    "discard",
    "retain",
    "exhaust_other",
    "retrieve",
    "apply_status",
    "remove_status",
    "remove_shield",
    "establish_scene",
    "gain_synergy",
    "summon_partner",
    "partner_heal",
    "partner_retreat",
    "partner_extra_action",
    "paper_open",
    "paper_progress",
    "paper_citation",
    "paper_modifier",
    "paper_amplify",
    "paper_publish",
    "chapter_deploy",
    "chapter_run",
    "chapter_return",
    "add_work_bonus",
    "cost_discount_next",
    "generate_card",
    "work_bonus_next",
    "spend_synergy",
    "spend_synergy_up_to",
    "spend_all_synergy",
    "swap_chapter_slots",
    "search_draw_for_type",
    "shuffle_draw",
    "spend_citation",
    "copy_chapter_to_hand",
    "publication_cost_discount",
    "chapter_return_with_modifier",
    "trigger_erosion",
    "trigger_induced",
    "status_complete",
    "modify_erosion_window",
    "arm_erosion_on_next_draws",
    "extend_timed_debuffs",
    "change_topic",
    "source_stacks",
}

KNOWN_CONDITIONS = {
    "link",
    "prev_card_type_is",
    "played_type_count_turn",
    "target_has_status",
    "target_status_kinds",
    "paper_open",
    "paper_closed",
    "paper_progress_min",
    "paper_name_unused",
    "paper_name_used",
    "chapter_count_min",
    "partner_count_min",
    "no_partner",
    "synergy_min",
    "independent_exam",
    "fixed_exam_room",
    "retrieved_strategy_this_turn",
    "paid_citation_focus_this_turn",
    "citation_min",
    "hand_other_min",
    "instance_plays_battle",
    "ddl_lte",
    "base_cost_min",
    "no_strategy_played_turn",
    "card_discarded_this_effect",
    "target_still_alive",
    "prepare_window",
    "two_tasks",
    "target_has_any_timed_debuff",
    "any_task_debuff_kinds_min",
    "target_had_induced_at_play_start",
    "target_has_induced",
    "erosion_applied_events_min",
    "first_induced_trigger",
    "compound_reaction_success",
    "any_task_has_induced",
    "summoned_partner_turn",
    "first_cooperation_resolved",
    "healed_partner_turn",
    "synergy_is_zero",
    "paper_progress_gained",
    "passive_retrieve_success",
    "instance_played_before",
    "previous_strategy_plays_min",
    "other_chapter_ran_window",
    "link_work_resolved",
}

KNOWN_TRIGGERS = {
    "first_work_card_resolving",
    "link_work_resolved",
    "passive_retrieve_success",
    "strategy_resolved",
    "work_resolved",
    "paper_progress_gained",
    "chapter_window_end",
    "first_cooperation_resolved",
    "prepare",
    "erosion_applied_event",
    "induced_trigger",
    "compound_reaction_success",
    "first_unused_permanent_card_resolved",
    "passive_rule",
}


def collect_conditions(value, out):
    if isinstance(value, dict):
        if "kind" in value and isinstance(value["kind"], str):
            out.add(value["kind"])
        for child in value.values():
            collect_conditions(child, out)
    elif isinstance(value, list):
        for child in value:
            collect_conditions(child, out)


def collect_ops(value, out):
    if isinstance(value, dict):
        op = value.get("op")
        if isinstance(op, str):
            out.add(op)
        for child in value.values():
            collect_ops(child, out)
    elif isinstance(value, list):
        for child in value:
            collect_ops(child, out)


def card_status(entry):
    ops = set()
    conditions = set()
    triggers = set()
    collect_ops(entry.get("effects", []), ops)
    collect_ops(entry.get("upgrade_effects", []), ops)
    for trigger in entry.get("ability", {}).get("triggers", []):
        triggers.add(str(trigger.get("on", "")))
        collect_ops(trigger.get("effects", []), ops)
        collect_ops(trigger.get("upgrade_effects", []), ops)
    collect_ops(entry.get("ability", {}).get("extra_effects", []), ops)
    for chapter_key in ("resident", "upgraded_resident"):
        collect_ops(entry.get("chapter", {}).get(chapter_key, {}).get("effects", []), ops)
    collect_ops(entry.get("exam", {}).get("effects", []), ops)
    collect_ops(entry.get("exam", {}).get("upgrade_effects", []), ops)
    collect_conditions(entry.get("requirements", []), conditions)
    collect_conditions(entry.get("upgrade_requirements", []), conditions)
    collect_conditions(entry.get("effects", []), conditions)
    collect_conditions(entry.get("upgrade_effects", []), conditions)
    collect_conditions(entry.get("ability", {}), conditions)
    collect_conditions(entry.get("chapter", {}), conditions)
    collect_conditions(entry.get("exam", {}), conditions)
    unknown_ops = sorted(op for op in ops if op not in KNOWN_OPS)
    unknown_conditions = sorted(kind for kind in conditions if kind not in KNOWN_CONDITIONS)
    unknown_triggers = sorted(trigger for trigger in triggers if trigger and trigger not in KNOWN_TRIGGERS)
    if unknown_ops or unknown_conditions or unknown_triggers:
        raise SystemExit(
            f"{entry['id']} unknown dsl: ops={unknown_ops} "
            f"conditions={unknown_conditions} triggers={unknown_triggers}"
        )
    return (
        sorted(op for op in ops if op != "source_stacks"),
        sorted(conditions),
        sorted(triggers),
    )


def main():
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    definitions = source["cards"] + source["tokens"]
    missing = [item["id"] for item in definitions if item["id"] not in EFFECTS]
    extra = [card_id for card_id in EFFECTS if card_id not in {item["id"] for item in definitions}]
    if missing or extra:
        raise SystemExit(f"catalog mismatch: missing={missing} extra={extra}")


    type_map = {"工作": "work", "策略": "strategy", "能力": "ability", "合作": "cooperation", "场景": "scene"}
    rarity_map = {"基础": "basic", "普通": "common", "进阶": "advanced", "稀有": "rare", "衍生": "token"}

    cards = []
    for raw in definitions:
        spec = EFFECTS[raw["id"]]
        entry = {
            "id": raw["id"],
            "name_key": raw["name_key"],
            "name": raw["name"],
            "owner": raw["owner"],
            "character": raw["character"],
            "group": raw["group"],
            "type": type_map[raw["type"]],
            "rarity": rarity_map[raw["rarity"]],
            "cost": int(raw["cost"]),
            "upgraded_cost": int(raw["upgraded_cost"]),
            "target": spec.get("t", "self"),
            "permanent": bool(raw.get("permanent", True)),
            "tags": list(raw.get("tags", [])),
            "requirements": spec.get("r", []),
            "effects": spec.get("play_e", []) if spec.get("ab") else spec.get("e", []),
            "upgrade_effects": spec.get("play_u", []) if spec.get("ab") else spec.get("u", []),
            "upgrade_requirements": spec.get("ur", []),
            "base_text": raw["base"],
            "upgraded_text": raw["upgraded"],
            "exam_condition": raw.get("exam_condition", ""),
            "exam_text": raw.get("exam", ""),
            "exam_upgraded_text": raw.get("exam_upgraded", ""),
            "chapter_text": raw.get("chapter", ""),
            "chapter_upgraded_text": raw.get("chapter_upgraded", ""),
        }
        flags = {
            "innate": False,
            "retain": False,
            "exhaust": False,
            "unique": False,
            "upgradable": True,
            "paper_record": True,
        }
        flags.update(spec.get("f", {}))
        entry["flags"] = flags
        entry["limits"] = spec.get("l", {})
        if spec.get("ab"):
            ability = spec["ab"]
            entry["ability"] = {
                "activate": ability.get("activate", "next_round"),
                "stack": ability.get("stack", "unique_name"),
                "condition": ability.get("condition", {}),
                "triggers": [
                    {
                        "on": ability.get("trigger"),
                        "effects": spec.get("e", []),
                        "upgrade_effects": spec.get("u", []),
                        "limit": ability.get("limit", ""),
                        "no_compound_reaction": bool(ability.get("no_compound_reaction", False)),
                    }
                ],
            }
            if ability.get("extra"):
                entry["ability"]["extra_effects"] = ability["extra"]
        if spec.get("ch"):
            chapter = spec["ch"]
            entry["chapter"] = {
                "activate": "next_round",
                "deploy": {"requires": "paper_open"},
                "resident": {
                    "on": chapter.get("resident", {}).get("trigger", "prepare"),
                    "effects": chapter.get("resident", {}).get("e", []),
                },
                "upgraded_resident": {
                    "on": chapter.get("upgraded_resident", {}).get("trigger", "prepare"),
                    "effects": chapter.get("upgraded_resident", {}).get("e", []),
                },
            }
        if spec.get("ex"):
            exam = spec["ex"]
            entry["exam"] = {
                "condition": exam.get("condition", ""),
                "target": exam.get("target", entry["target"]),
                "effects": exam.get("e", []),
                "upgrade_effects": exam.get("u", []),
            }
        status, conditions, triggers = card_status(entry)
        entry["conditions"] = conditions
        entry["triggers"] = triggers
        entry["implementation"] = {
            "status": "catalog_only",
            "runtime_enabled": False,
            "pending_mechanics": status,
        }
        cards.append(entry)

    catalog = {
        "schema_version": SCHEMA_VERSION,
        "source": {
            "file": "artifacts/redesign-20261030/campus-cards-v3.json",
            "version": source.get("version", ""),
            "date": source.get("date", ""),
            "status": source.get("status", ""),
        },
        "counts": {
            "cards": len(source["cards"]),
            "tokens": len(source["tokens"]),
            "total": len(cards),
            "owners": {
                owner: sum(1 for card in cards if card["permanent"] and card["owner"] == owner)
                for owner in sorted({card["owner"] for card in cards})
            },
            "token_owners": {
                owner: sum(1 for card in cards if not card["permanent"] and card["owner"] == owner)
                for owner in sorted({card["owner"] for card in cards})
            },
        },
        "character_rules": {
            "P01": {"strategy_retrieve_on_first_link_work_per_turn": 1, "work_bonus_cap": 12, "cost_discount_cap": 1},
            "P02": {"same_name_once_per_turn": 1, "paper_progress_cap": 10, "citation_cap": 5, "chapter_slots": 3},
            "P03": {"compound_reaction_once_per_turn": 1},
            "P04": {"synergy_cap": 6, "partner_slots": 3},
        },
        "starters": {
            "common": [
                {"card": "R3-C-01", "count": 4},
                {"card": "R3-C-02", "count": 4},
                {"card": "R3-C-03", "count": 1},
                {"card": "R3-C-04", "count": 1},
            ],
            "characters": source.get("starters", {}),
        },
        "cards": cards,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pending = sum(1 for card in cards if card["implementation"]["pending_mechanics"])
    print(f"wrote {OUTPUT}")
    print(f"cards={len(source['cards'])} tokens={len(source['tokens'])} total={len(cards)}")
    print(f"catalog_only={len(cards)} cards_with_mechanics={pending}")


if __name__ == "__main__":
    main()


