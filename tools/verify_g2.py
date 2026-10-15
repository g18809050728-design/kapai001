"""Check complete G2 production scope, isolated fixtures, and frozen bindings."""

from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = ROOT / "docs/baselines/g0.json"
DATA = ROOT / "data"
FIXTURE = ROOT / "tests/fixtures/content_loader"
STARTER_CARD_EXPECTATIONS = {
    "K01": {
        "type": "work",
        "target": "task",
        "effects": [{"op": "complete", "amount": 6}],
        "upgrade": {"effects": [{"op": "complete", "amount": 8}]},
    },
    "K02": {
        "type": "strategy",
        "target": "self",
        "effects": [{"op": "relax", "amount": 5}],
        "upgrade": {"effects": [{"op": "relax", "amount": 8}]},
    },
    "K03": {
        "type": "strategy",
        "target": "self",
        "effects": [{"op": "draw", "amount": 2}, {"op": "discard", "amount": 1}],
        "upgrade": {
            "effects": [{"op": "draw", "amount": 3}, {"op": "discard", "amount": 1}]
        },
    },
    "K04": {
        "type": "strategy",
        "target": "self",
        "effects": [
            {"op": "gain_status", "status": "inspiration", "stacks": 2},
            {"op": "draw", "amount": 1},
        ],
        "upgrade": {
            "effects": [{"op": "gain_status", "status": "inspiration", "stacks": 3}]
        },
    },
}


class Audit:
    def __init__(self) -> None:
        self.checks = 0
        self.errors: list[str] = []

    def check(self, condition: bool, message: str) -> None:
        self.checks += 1
        if not condition:
            self.errors.append(message)

    @staticmethod
    def read_json(path: Path) -> object:
        return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value_at(root: dict, key: str) -> object:
    value: object = root
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(f"missing Ruleset path: {key}")
        value = value[part]
    return value


def main() -> int:
    audit = Audit()
    baseline = audit.read_json(BASELINE_PATH)
    scope = baseline["scope"]
    expected = scope["enabled_by_kind"]
    production = audit.read_json(DATA / "manifests/campus_mvp.json")
    deferred = audit.read_json(DATA / "manifests/content_deferred.json")
    fixture_manifest = audit.read_json(FIXTURE / "manifests/test_content_loader.json")

    audit.check(production["id"] == "campus_mvp", "production manifest id")
    audit.check(
        production["content_version"] == scope["scope_version"] == "campus_mvp.v1",
        "production scope version",
    )
    audit.check(production["ruleset_id"] == "campus_v1", "production ruleset id")
    audit.check(set(production["enabled"]) == set(expected), "production enabled kinds")
    audit.check(deferred["manifest_id"] == production["id"], "holdback manifest id")
    audit.check(deferred["scope_version"] == production["content_version"], "holdback version")
    audit.check(set(deferred["manifest_holdback"]) == set(expected), "holdback kinds")

    held = deferred["manifest_holdback"]
    audit.check(not any(held.values()), "G2 completion requires zero holdback IDs")
    audit.check(not deferred.get("package_blockers"), "G2 completion requires no package blockers")
    audit.check(not deferred.get("pending_overrides"), "G2 completion requires applied MVP overrides")
    overrides = production.get("overrides", [])
    audit.check(len(overrides) == len(scope["overrides"]), "approved MVP override count")
    for planned in scope["overrides"]:
        actual = next((entry for entry in overrides if entry.get("kind") == planned["kind"] and entry.get("id") == planned["id"]), {})
        if planned["kind"] == "encounter":
            expected_patch = {"terms": planned["value"]}
        else:
            events = audit.read_json(DATA / "definitions/events.json")
            options = deepcopy(next(row["options"] for row in events if row["id"] == planned["id"]))
            consult = next(option for option in options if option["option_id"] == "consult")
            next(effect for effect in consult["effects"] if effect["op"] == "gain_card")["card_pool"] = planned["value"]
            expected_patch = {"options": options}
        audit.check(actual == {**{key: planned[key] for key in ["kind", "id", "scope_version", "source"]}, "patch": expected_patch}, f"{planned['kind']}/{planned['id']}: only approved G0 override is applied")
    for kind, expected_ids in expected.items():
        enabled_ids = production["enabled"].get(kind, [])
        held_ids = held.get(kind, [])
        audit.check(len(enabled_ids) == len(set(enabled_ids)), f"{kind}: duplicate enabled IDs")
        audit.check(len(held_ids) == len(set(held_ids)), f"{kind}: duplicate holdback IDs")
        audit.check(not set(enabled_ids).intersection(held_ids), f"{kind}: enabled/holdback overlap")
        audit.check(set(enabled_ids).union(held_ids) == set(expected_ids), f"{kind}: G0 ID partition")
        audit.check(set(enabled_ids) == set(expected_ids), f"{kind}: complete G0 production scope")
        declared = deferred["definitions"].get(kind, [])
        audit.check(
            {entry["id"] for entry in declared} == set(held_ids)
            and all(
                entry.get("blocking") == ["G2"]
                and entry.get("missing")
                and entry.get("source", {}).get("path") == "docs/交大四年_DDL战争_统一设计文档.md"
                and entry.get("source", {}).get("section") == f"{kind} ID {entry['id']}"
                for entry in declared
            ),
            f"{kind}: holdback definition reasons",
        )

    for filename in sorted((DATA / "definitions").glob("*.json")):
        rows = audit.read_json(filename)
        audit.check(isinstance(rows, list), f"{filename.relative_to(ROOT)}: top level array")
        if not isinstance(rows, list):
            continue
        ids = [row.get("id") for row in rows if isinstance(row, dict)]
        audit.check(len(ids) == len(set(ids)), f"{filename.relative_to(ROOT)}: duplicate definition IDs")
        audit.check(not any(str(id_).startswith("test_") for id_ in ids), "test definition in production data")
        kind = filename.stem
        kind_by_file = {
            "characters": "character", "cards": "card", "relics": "relic", "tasks": "task",
            "encounters": "encounter", "units": "unit", "scenes": "scene", "events": "event",
            "statuses": "status", "rulesets": "ruleset",
        }
        content_kind = kind_by_file[kind]
        available = set(ids)
        audit.check(
            set(production["enabled"].get(content_kind, [])) == available,
            f"{content_kind}: definitions exactly match enabled IDs",
        )

    production_manifest_ids = {path.stem for path in (DATA / "manifests").glob("*.json")}
    audit.check(production_manifest_ids == {"campus_mvp", "content_deferred"}, "test manifest leaked to production")
    audit.check(fixture_manifest["id"].startswith("test_"), "fixture manifest has test_ prefix")
    audit.check(fixture_manifest["id"] not in production_manifest_ids, "fixture manifest is isolated")
    audit.check(set(fixture_manifest["enabled"]) == set(expected), "fixture manifest kinds")
    audit.check(fixture_manifest["enabled"]["card"] == ["test_card_001"], "fixture card allowlist")

    ruleset_rows = audit.read_json(DATA / "definitions/rulesets.json")
    audit.check(len(ruleset_rows) == 1 and ruleset_rows[0]["id"] == "campus_v1", "single production Ruleset")
    if ruleset_rows:
        ruleset = ruleset_rows[0]
        starter_cards = ruleset.get("run", {}).get("common_starter_cards", [])
        missing_starters = list(dict.fromkeys(
            id_ for id_ in starter_cards if id_ not in production["enabled"].get("card", [])
        ))
        blockers = deferred.get("package_blockers", [])
        blocker_valid = (
            not blockers if not missing_starters else
            len(blockers) == 1
            and blockers[0].get("id") == f"ruleset/{ruleset['id']}"
            and blockers[0].get("missing_references") == missing_starters
            and set(missing_starters).issubset(set(held["card"]))
        )
        audit.check(blocker_valid, "production starter reference-closure status is explicit")
        bindings = scope["numeric_bindings"]
        audit.check(len(bindings) == 57, "G0 numeric binding count")
        for binding in bindings:
            key = binding["config_key"]
            try:
                actual = value_at(ruleset, key)
                valid = actual == binding["expected"] and type(actual) is type(binding["expected"])
            except (KeyError, TypeError):
                valid = False
            audit.check(valid, f"Ruleset binding mismatch: {key}")
        numeric_status_ids = {
            binding["config_key"].split(".")[1]
            for binding in bindings
            if binding["config_key"].startswith("statuses.")
        }
        audit.check(set(ruleset["statuses"]) == numeric_status_ids, "Ruleset numeric status ID set")
        status_rows = audit.read_json(DATA / "definitions/statuses.json")
        audit.check(
            {row["id"] for row in status_rows} == set(production["enabled"]["status"]),
            "production status definitions exactly match enabled IDs",
        )

    cards = audit.read_json(DATA / "definitions/cards.json")
    card_by_id = {row.get("id"): row for row in cards if isinstance(row, dict)}
    audit.check(
        set(STARTER_CARD_EXPECTATIONS).issubset(production["enabled"].get("card", [])),
        "production includes frozen starter cards",
    )
    for card_id, expected_card in STARTER_CARD_EXPECTATIONS.items():
        card = card_by_id.get(card_id, {})
        audit.check(
            card.get("name_key") == f"card.{card_id}.name"
            and card.get("type") == expected_card["type"]
            and card.get("rarity") == "white"
            and card.get("tags") == ["basic"]
            and card.get("cost") == 1
            and card.get("target") == expected_card["target"]
            and card.get("exhaust") is False
            and card.get("effects") == expected_card["effects"]
            and card.get("upgrade") == expected_card["upgrade"],
            f"{card_id}: frozen card face and upgrade match G0 design",
        )

    fixture_files = sorted(
        [FIXTURE / "manifests/test_content_loader.json", *list((FIXTURE / "definitions").glob("*.json"))]
    )
    fixture_digest = hashlib.sha256()
    for path in fixture_files:
        fixture_digest.update(path.relative_to(FIXTURE).as_posix().encode("utf-8"))
        fixture_digest.update(b"\0")
        fixture_digest.update(path.read_bytes())
    print(f"G2_STATIC_CHECKS={audit.checks}")
    print(f"G2_PRODUCTION_MANIFEST_SHA256={sha256(DATA / 'manifests/campus_mvp.json')}")
    print(f"G2_TEST_FIXTURE_SHA256={fixture_digest.hexdigest()}")
    print(f"G2_ENABLED_IDS={sum(len(ids) for ids in production['enabled'].values())}")
    print(f"G2_HOLDBACK_IDS={sum(len(ids) for ids in held.values())}")
    for error in audit.errors:
        print(f"FAIL: {error}")
    print(f"G2_STATIC_STATUS={'passed' if not audit.errors else 'failed'}")
    return 0 if not audit.errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
