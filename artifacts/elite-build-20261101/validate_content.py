#!/usr/bin/env python3
"""Mirror the ContentDB static checks for the elite content build.

The repository has no Godot binary on this machine, so this script re-implements
the structural checks of src/content/content_db.gd (field whitelists, id safety,
reference closure, numeric status coverage, label coverage) to catch content
mistakes before the engine sees them. It is evidence of static validation only,
not a substitute for the GDScript test suite.

    python artifacts/elite-build-20261101/validate_content.py
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFINITIONS = ROOT / "data" / "definitions"
MANIFEST = ROOT / "data" / "manifests" / "campus_mvp.json"
LABELS = ROOT / "src" / "ui" / "ui_labels.json"

FILE_NAMES = {
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
}

DEFINITION_FIELDS = {
    "character": ["id", "name_key", "starter_cards", "starter_relic_id", "passive", "art_key"],
    "card": ["id", "name_key", "type", "rarity", "tags", "cost", "target", "exhaust",
             "effects", "vitality_cost", "unplayable", "pre_effects", "upgrade", "limit",
             "art_key"],
    "relic": ["id", "name_key", "availability", "rarity", "tags", "effects", "hooks",
              "modifiers", "limit", "art_key"],
    "task": ["id", "name_key", "kind", "phases", "victory_required", "art_key"],
    "encounter": ["id", "name_key", "kind", "members", "base_ddl", "terms", "exam_flags",
                  "initial_members", "absorb_cooperation", "scaling", "art_key"],
    "unit": ["id", "name_key", "vitality", "cooperation", "guard", "support",
             "entry_effects", "art_key"],
    "scene": ["id", "name_key", "prepare_effects", "prepare_random", "modifiers",
              "round_end_effects", "battle_limit", "anxiety_after_every", "art_key"],
    "event": ["id", "name_key", "terms", "once_per_run", "options", "art_key"],
    "status": ["id", "name_key", "target", "stack_policy", "duration_policy",
               "dispel_policy", "numeric_rule_key", "art_key"],
    "ruleset": ["id", "schema_version", "run", "battle", "statuses", "difficulty_overrides",
                "rewards", "shop"],
}

REQUIRED_FIELDS = {
    "character": ["id", "name_key", "starter_cards", "starter_relic_id", "passive"],
    "card": ["id", "name_key", "type", "rarity", "tags", "cost", "target", "exhaust", "effects"],
    "relic": ["id", "name_key", "availability", "rarity", "tags"],
    "task": ["id", "name_key", "kind", "phases"],
    "encounter": ["id", "name_key", "kind", "members", "base_ddl", "terms", "exam_flags"],
    "unit": ["id", "name_key", "vitality", "cooperation", "guard", "support"],
    "scene": ["id", "name_key"],
    "event": ["id", "name_key", "terms", "once_per_run", "options"],
    "status": ["id", "name_key", "target", "stack_policy", "duration_policy", "dispel_policy"],
    "ruleset": ["id", "schema_version", "run", "battle", "statuses", "difficulty_overrides",
                "rewards", "shop"],
}

STATUS_POLICY = {
    "inspiration": ["player", "capped", "work_or_round_end", "explicit"],
    "compile": ["player", "capped", "battle", "explicit"],
    "experiment_data": ["player", "capped", "battle", "explicit"],
    "citation": ["player", "capped", "battle", "explicit"],
    "review": ["player", "capped", "battle", "explicit"],
    "flow": ["player", "capped", "battle", "explicit"],
    "anxiety": ["player", "capped", "next_prepare", "negative"],
    "procrastination": ["player", "capped", "next_draw", "negative"],
    "drowsiness": ["player", "capped", "next_player_action_end", "negative"],
    "extra_requirements": ["task", "capped", "battle", "explicit"],
    "brainstorm": ["task", "capped", "battle", "explicit"],
    "confusion": ["task", "capped", "battle", "explicit"],
    "guard": ["unit", "presence", "unit_departure", "none"],
}

STATUS_RULE_FIELDS = {
    "inspiration": ["cap", "completion_per_stack"],
    "compile": ["cap"],
    "experiment_data": ["cap"],
    "citation": ["cap"],
    "review": ["cap"],
    "flow": ["cap", "completion_per_stack", "focus_bonus_when_present"],
    "anxiety": ["cap", "focus_penalty_per_stack"],
    "procrastination": ["cap", "draw_penalty_per_stack"],
    "drowsiness": ["cap", "completion_penalty_per_stack"],
    "extra_requirements": ["cap", "pressure_per_stack"],
    "brainstorm": ["cap", "pressure_per_stack"],
    "confusion": ["cap", "shield_per_stack"],
}

REFERENCE_KEYS = {
    "card_id": "card",
    "card_pool": "card",
    "starter_cards": "card",
    "common_starter_cards": "card",
    "played_definition": "card",
    "definition_id": "card",
    "card": "card",
    "starter_relic_id": "relic",
    "relic_id": "relic",
    "members": "task",
    "initial_members": "task",
    "task": "task",
    "unit": "unit",
    "scene": "scene",
    "status": "status",
    "ruleset_id": "ruleset",
}

PHASE_FIELDS = ["phase_key", "work_max", "intents", "name_key", "intent_loop"]
INTENT_FIELDS = ["index", "text_key", "pressure", "pressure_times", "pressure_all",
                 "pressure_per_unit", "pressure_per_unit_cap", "shield", "work_restore",
                 "extra_requirements", "gain_status", "add_card", "summon_tasks",
                 "transform_task", "ddl_bonus", "self_destruct"]

ISSUES = []


def issue(message):
    ISSUES.append(message)


def read_json(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def safe_id(value):
    if not isinstance(value, str) or not value or len(value) > 100:
        return False
    if not (value[0].isalpha() or value[0] == "_"):
        return False
    return all(character.isalnum() or character in "_|" for character in value)


def check_fields(value, allowed, required, location):
    if not isinstance(value, dict):
        issue("%s must be an object" % location)
        return
    for key in value:
        if key not in allowed:
            issue("%s.%s is unknown" % (location, key))
    for key in required:
        if key not in value:
            issue("%s.%s is missing" % (location, key))


def check_positive_int(value, location, minimum=1):
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        issue("%s must be an integer >= %d" % (location, minimum))


def main():
    manifest = read_json(MANIFEST)
    definitions = {}
    for kind, file_name in FILE_NAMES.items():
        rows = read_json(DEFINITIONS / ("%s.json" % file_name))
        by_id = {}
        for index, row in enumerate(rows):
            location = "%s[%d]" % (file_name, index)
            check_fields(row, DEFINITION_FIELDS[kind], REQUIRED_FIELDS[kind], location)
            if not safe_id(row.get("id")):
                issue("%s.id is not a safe id" % location)
                continue
            if row["id"] in by_id:
                issue("%s duplicates id %s" % (location, row["id"]))
                continue
            by_id[row["id"]] = row
        definitions[kind] = by_id

    enabled = manifest["enabled"]
    for kind in FILE_NAMES:
        for definition_id in enabled[kind]:
            if definition_id not in definitions[kind]:
                issue("enabled %s/%s is missing" % (kind, definition_id))

    # Task and encounter structural checks.
    for task_id, task in definitions["task"].items():
        location = "task/%s" % task_id
        if task.get("kind") not in ["normal", "elite", "boss"]:
            issue("%s.kind is invalid" % location)
        if "victory_required" in task and not isinstance(task["victory_required"], bool):
            issue("%s.victory_required must be bool" % location)
        phases = task.get("phases")
        if not isinstance(phases, list) or not phases:
            issue("%s.phases must be a non-empty array" % location)
            continue
        seen = set()
        for phase_index, phase in enumerate(phases):
            phase_location = "%s.phases[%d]" % (location, phase_index)
            check_fields(phase, PHASE_FIELDS, ["phase_key", "work_max", "intents"], phase_location)
            if phase.get("phase_key") in seen:
                issue("%s.phase_key is duplicated" % phase_location)
            seen.add(phase.get("phase_key"))
            if phase.get("intent_loop", "cycle") not in ["cycle", "clamp"]:
                issue("%s.intent_loop is invalid" % phase_location)
            check_positive_int(phase.get("work_max"), phase_location + ".work_max")
            intents = phase.get("intents")
            if not isinstance(intents, list) or not intents:
                issue("%s.intents must be a non-empty array" % phase_location)
                continue
            for intent_index, value in enumerate(intents):
                intent_location = "%s.intents[%d]" % (phase_location, intent_index)
                check_fields(value, INTENT_FIELDS, ["index", "text_key"], intent_location)
                if not isinstance(value.get("text_key"), str) or not value["text_key"]:
                    issue("%s.text_key must be non-empty" % intent_location)
                for field in ["pressure", "pressure_times", "shield", "work_restore",
                              "extra_requirements", "pressure_per_unit", "ddl_bonus"]:
                    if field in value:
                        check_positive_int(value[field], "%s.%s" % (intent_location, field))
                if "pressure_times" in value and "pressure" not in value:
                    issue("%s.pressure_times requires pressure" % intent_location)
                if "pressure_per_unit_cap" in value and "pressure_per_unit" not in value:
                    issue("%s.pressure_per_unit_cap requires pressure_per_unit" % intent_location)
                if "pressure_per_unit_cap" in value:
                    check_positive_int(
                        value["pressure_per_unit_cap"], intent_location + ".pressure_per_unit_cap"
                    )
                if "gain_status" in value:
                    check_fields(value["gain_status"], ["status", "stacks", "target"],
                                 ["status", "stacks", "target"], intent_location + ".gain_status")
                    if value["gain_status"].get("target") not in ["player", "unit", "task"]:
                        issue("%s.gain_status.target is invalid" % intent_location)
                if "add_card" in value:
                    check_fields(value["add_card"], ["card", "count", "zone"],
                                 ["card", "count", "zone"], intent_location + ".add_card")
                    if value["add_card"].get("zone") not in ["draw", "hand", "discard", "exhaust"]:
                        issue("%s.add_card.zone is invalid" % intent_location)
                if "summon_tasks" in value:
                    specs = value["summon_tasks"]
                    if not isinstance(specs, list) or not specs:
                        issue("%s.summon_tasks must be a non-empty array" % intent_location)
                    else:
                        for spec in specs:
                            check_fields(spec, ["task", "count"], ["task", "count"],
                                         intent_location + ".summon_tasks[]")
                            check_positive_int(
                                spec.get("count"), intent_location + ".summon_tasks[].count"
                            )
                if "transform_task" in value:
                    check_fields(value["transform_task"], ["task"], ["task"],
                                 intent_location + ".transform_task")
                if "self_destruct" in value and not isinstance(value["self_destruct"], bool):
                    issue("%s.self_destruct must be bool" % intent_location)

    for encounter_id, encounter in definitions["encounter"].items():
        location = "encounter/%s" % encounter_id
        members = encounter.get("members")
        if not isinstance(members, list) or not members:
            issue("%s.members must be a non-empty array" % location)
            continue
        if encounter.get("kind") not in ["normal", "elite", "boss"]:
            issue("%s.kind is invalid" % location)
        check_positive_int(encounter.get("base_ddl"), location + ".base_ddl")
        terms = encounter.get("terms")
        if not isinstance(terms, list) or not terms:
            issue("%s.terms must be a non-empty array" % location)
        else:
            for term in terms:
                if not isinstance(term, int) or isinstance(term, bool) or term < 1 or term > 8:
                    issue("%s.terms contains an invalid term" % location)
        flags = encounter.get("exam_flags")
        if not isinstance(flags, list):
            issue("%s.exam_flags must be an array" % location)
        else:
            for flag in flags:
                if flag not in ["independent_answer", "fixed_exam_room"]:
                    issue("%s.exam_flags contains an unknown flag" % location)
        initial = encounter.get("initial_members")
        if initial is not None:
            if not isinstance(initial, list) or not initial:
                issue("%s.initial_members must be a non-empty array" % location)
            else:
                for member in initial:
                    if member not in members:
                        issue("%s.initial_members must be encounter members" % location)
        absorb = encounter.get("absorb_cooperation")
        if absorb is not None:
            check_fields(absorb, ["draw_per_card", "focus_per_card"],
                         ["draw_per_card", "focus_per_card"],
                         location + ".absorb_cooperation")
            for field in ["draw_per_card", "focus_per_card"]:
                if isinstance(absorb.get(field), int):
                    check_positive_int(absorb[field], "%s.absorb_cooperation.%s" % (location, field), 0)
        for member in members:
            definition = definitions["task"].get(member)
            if definition is None:
                issue("%s references missing task %s" % (location, member))
            elif definition.get("kind") != encounter.get("kind"):
                issue("%s member %s kind disagrees" % (location, member))

    # Status policy and numeric rules.
    for status_id, status in definitions["status"].items():
        policy = STATUS_POLICY.get(status_id)
        if policy is None:
            issue("status/%s is not registered" % status_id)
            continue
        actual = [status.get("target"), status.get("stack_policy"),
                  status.get("duration_policy"), status.get("dispel_policy")]
        if actual != policy:
            issue("status/%s policy %s disagrees with %s" % (status_id, actual, policy))

    rulesets = definitions["ruleset"]
    numeric = rulesets[manifest["ruleset_id"]]["statuses"]
    expected = {
        definitions["status"][status_id]["numeric_rule_key"]
        for status_id in enabled["status"]
        if "numeric_rule_key" in definitions["status"].get(status_id, {})
    }
    for key in expected:
        if key not in numeric:
            issue("ruleset is missing numeric status %s" % key)
    for key in numeric:
        if key not in expected:
            issue("ruleset contains unreferenced numeric status %s" % key)
        else:
            check_fields(numeric[key], STATUS_RULE_FIELDS[key], STATUS_RULE_FIELDS[key],
                         "ruleset.statuses.%s" % key)
            for field, value in numeric[key].items():
                if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                    issue("ruleset.statuses.%s.%s must be a non-negative integer" % (key, field))

    # Manifest overrides run before reference validation in ContentDB.
    for override in manifest.get("overrides", []):
        target = definitions.get(override.get("kind"), {}).get(override.get("id"))
        if target is None:
            issue("override %s/%s target is missing" % (override.get("kind"), override.get("id")))
            continue
        for key, value in override.get("patch", {}).items():
            target[key] = value

    # Reference closure over every enabled definition.
    def walk(owner, value, path):
        if isinstance(value, dict):
            for key, item in value.items():
                target_kind = REFERENCE_KEYS.get(key)
                if target_kind:
                    references = item if isinstance(item, list) else [item]
                    for reference in references:
                        if isinstance(reference, str) and (
                            reference not in enabled.get(target_kind, [])
                            or reference not in definitions.get(target_kind, {})
                        ):
                            issue("%s references disabled or missing %s/%s"
                                  % (owner, target_kind, reference))
                walk(owner, item, path + "." + str(key))
        elif isinstance(value, list):
            for item in value:
                walk(owner, item, path + "[]")

    for kind in FILE_NAMES:
        for definition_id in enabled[kind]:
            definition = definitions[kind].get(definition_id)
            if definition is not None:
                walk("%s/%s" % (kind, definition_id), definition, "")

    # Labels: every name_key and intent text_key must resolve through UiStyle.label.
    labels = read_json(LABELS)["labels"]

    def resolves(key):
        if not isinstance(key, str) or not key:
            return False
        if key in labels:
            return True
        if "." in key:
            parts = key.split(".")
            if len(parts) >= 2:
                candidate = parts[1]
                if candidate.upper() in labels or candidate in labels:
                    return True
        return key.upper() in labels

    for kind in FILE_NAMES:
        for definition_id in enabled[kind]:
            definition = definitions[kind].get(definition_id) or {}
            name_key = definition.get("name_key")
            if isinstance(name_key, str) and name_key and not resolves(name_key):
                issue("label is missing for %s/%s (%s)" % (kind, definition_id, name_key))
            if not resolves(definition_id) and "name_key" in definition:
                issue("label is missing for id %s/%s" % (kind, definition_id))
    for task in definitions["task"].values():
        for phase in task.get("phases", []):
            for value in phase.get("intents", []):
                key = value.get("text_key")
                if isinstance(key, str) and key and not resolves(key):
                    issue("label is missing for intent text %s" % key)

    if ISSUES:
        for message in ISSUES:
            print("ISSUE:", message)
        print("RESULT: %d issue(s)" % len(ISSUES))
        return 1
    counts = {kind: len(definitions[kind]) for kind in sorted(definitions)}
    print("RESULT: content mirror checks passed")
    print("DEFINITIONS:", json.dumps(counts, sort_keys=True))
    print("ENABLED:", json.dumps({kind: len(enabled[kind]) for kind in sorted(enabled)},
                                 sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
