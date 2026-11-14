"""Apply the scoped, versioned rules changes; historical generators stay byte-exact."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

def edit(name, old, new, count=1):
    p = ROOT / name
    s = p.read_text(encoding="utf-8")
    assert s.count(old) >= count, (name, old[:100])
    p.write_text(s.replace(old, new, count), encoding="utf-8")

original = ROOT / "src/run/annual_map_generator.gd"
legacy = ROOT / "src/run/annual_map_generator_v2.gd"
assert not legacy.exists()
legacy.write_bytes(original.read_bytes().replace(b"class_name AnnualMapGenerator", b"class_name AnnualMapGeneratorV2", 1))
edit("src/app/game_session.gd", 'or request.difficulty != &"normal"', 'or request.difficulty not in [&"relaxed", &"normal", &"hard"]', 2)
edit("src/app/game_session.gd", 'options.difficulties = [&"normal"]', '''for id in [&"relaxed", &"normal", &"hard"]:
		if rules.difficulty_overrides.has(String(id)):
			options.difficulties.append(id)
	options.difficulty_details = rules.difficulty_overrides.duplicate(true)''')
edit("src/common/setup_options.gd", 'var default_difficulty:', 'var difficulty_details: Dictionary = {}\nvar default_difficulty:')
edit("src/ui/game_shell.gd", '"difficulties": options.data.difficulties,', '"difficulties": options.data.difficulties,\n\t\t\t\t"difficulty_details": options.data.difficulty_details,\n\t\t\t\t"default_difficulty": String(options.data.default_difficulty),')
edit("src/ui/page_flow.gd", '{"easy": "轻松", "normal":', '{"easy": "宽松", "relaxed": "宽松", "normal":')
edit("src/run/campaign_progression.gd", 'const MAP_VERSION := 2\nconst SUPPORTED_MAP_VERSIONS := [1, 2]', 'const MAP_VERSION := 3\nconst SUPPORTED_MAP_VERSIONS := [1, 2, 3]')

rules_path = ROOT / "data/four_year/definitions/rulesets.json"
rules = json.loads(rules_path.read_text(encoding="utf-8-sig"))
additions = dict(relaxed=dict(starting_vitality=84, ddl_offset=2, pressure_percent=80),
                 hard=dict(starting_vitality=60, ddl_offset=-1, pressure_percent=120))
rules[0]["difficulty_overrides"].update(additions)
rules_path.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
edit("tools/build_four_year_content.py", 'rules["run"].update(term_count=4, relic_slots=3)', '''rules["run"].update(term_count=4, relic_slots=3)
    rules["difficulty_overrides"].update(
        relaxed=dict(starting_vitality=84, ddl_offset=2, pressure_percent=80),
        hard=dict(starting_vitality=60, ddl_offset=-1, pressure_percent=120))''')

# Scale total intent pressure once, before flat/weakness modifiers. The view calls
# the same function, so dynamic intent modifiers and actual damage cannot diverge.
edit("src/battle/battle_engine.gd", '\t\t\tvar feeble := _status_stacks(state, "feebleness", task_id)', '\t\t\tpressure = DifficultyRules.scale_pressure(pressure, state.difficulty, ruleset_result.data)\n\t\t\tvar feeble := _status_stacks(state, "feebleness", task_id)')

# This is a strict additive compatibility proof, not an allowlist for arbitrary
# changes. Reconstruct the exact previous enabled package before accepting it.
edit("src/content/content_db.gd", 'var _legacy_four_year_hash := ""', 'var _legacy_four_year_hash := ""\nvar _previous_four_year_hash := ""\nconst PREVIOUS_FOUR_YEAR_HASH := "53beb845aca6a5a97e7934252b3fa42fd24c3be8262031ba23073abe1edfce8c"')
edit("src/content/content_db.gd", '\t_legacy_four_year_hash = ""\n\tif manifest_id', '\t_legacy_four_year_hash = ""\n\t_previous_four_year_hash = ""\n\tif manifest_id')
edit("src/content/content_db.gd", '\t\tfor destination in ["job", "exam", "research", "abroad"]:', '''		var previous_indexes: Dictionary = indexes.duplicate(true)
		for ruleset in previous_indexes.ruleset.values():
			for added in ["relaxed", "hard"]:
				ruleset.difficulty_overrides.erase(added)
		if _sha256(_canonical_json({"manifest": hash_manifest, "definitions": _enabled_definitions(previous_indexes)})) == PREVIOUS_FOUR_YEAR_HASH:
			_previous_four_year_hash = PREVIOUS_FOUR_YEAR_HASH
			old_indexes = previous_indexes
		for destination in ["job", "exam", "research", "abroad"]:''')
edit("src/content/content_db.gd", 'func get_definition(kind:', '''func accepts_previous_four_year_hash(digest: String) -> bool:
	return not _previous_four_year_hash.is_empty() and digest == _previous_four_year_hash


func get_definition(kind:''')
edit("src/storage/snapshot_codec.gd", '\tif (\n\t\tsnapshot.content_version != info.content_version', '''	var additive_hash: bool = (
		legacy_campaign is Dictionary
		and legacy_campaign.get("difficulty") == "normal"
		and catalog.accepts_previous_four_year_hash(str(snapshot.content_hash))
	)
	if (
		snapshot.content_version != info.content_version''')
edit("src/storage/snapshot_codec.gd", 'snapshot.content_hash != info.content_hash and not legacy_hash', 'snapshot.content_hash != info.content_hash and not legacy_hash and not additive_hash')
print("Applied versioned rules and exact additive compatibility")
