class_name ContentDB
extends RefCounted

const CONTENT_KINDS := [
	"character", "card", "relic", "task", "encounter", "unit", "scene", "event", "status", "ruleset"
]
const FILE_NAMES := {
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
const DEFINITION_FIELDS := {
	"character": ["id", "name_key", "starter_cards", "starter_relic_id", "passive", "art_key"],
	"card":
	[
		"id",
		"name_key",
		"type",
		"rarity",
		"tags",
		"cost",
		"target",
		"exhaust",
		"effects",
		"vitality_cost",
		"unplayable",
		"pre_effects",
		"upgrade",
		"limit",
		"art_key"
	],
	"relic":
	[
		"id",
		"name_key",
		"availability",
		"rarity",
		"tags",
		"effects",
		"hooks",
		"modifiers",
		"limit",
		"art_key"
	],
	"task": ["id", "name_key", "kind", "phases", "victory_required", "art_key"],
	"encounter":
	[
		"id",
		"name_key",
		"kind",
		"members",
		"base_ddl",
		"terms",
		"exam_flags",
		"initial_members",
		"absorb_cooperation",
		"scaling",
		"art_key"
	],
	"unit":
	["id", "name_key", "vitality", "cooperation", "guard", "support", "entry_effects", "art_key"],
	"scene":
	[
		"id",
		"name_key",
		"prepare_effects",
		"prepare_random",
		"modifiers",
		"round_end_effects",
		"battle_limit",
		"anxiety_after_every",
		"art_key"
	],
	"event": ["id", "name_key", "terms", "once_per_run", "options", "art_key"],
	"status":
	[
		"id",
		"name_key",
		"target",
		"stack_policy",
		"duration_policy",
		"dispel_policy",
		"numeric_rule_key",
		"art_key"
	],
	"ruleset":
	[
		"id",
		"schema_version",
		"run",
		"battle",
		"statuses",
		"difficulty_overrides",
		"rewards",
		"shop"
	],
}
const REQUIRED_FIELDS := {
	"character": ["id", "name_key", "starter_cards", "starter_relic_id", "passive"],
	"card": ["id", "name_key", "type", "rarity", "tags", "cost", "target", "exhaust", "effects"],
	"relic": ["id", "name_key", "availability", "rarity", "tags"],
	"task": ["id", "name_key", "kind", "phases"],
	"encounter": ["id", "name_key", "kind", "members", "base_ddl", "terms", "exam_flags"],
	"unit": ["id", "name_key", "vitality", "cooperation", "guard", "support"],
	"scene": ["id", "name_key"],
	"event": ["id", "name_key", "terms", "once_per_run", "options"],
	"status": ["id", "name_key", "target", "stack_policy", "duration_policy", "dispel_policy"],
	"ruleset":
	[
		"id",
		"schema_version",
		"run",
		"battle",
		"statuses",
		"difficulty_overrides",
		"rewards",
		"shop"
	],
}
const MANIFEST_FIELDS := ["id", "content_version", "ruleset_id", "enabled", "overrides"]
const MANIFEST_REQUIRED := ["id", "content_version", "ruleset_id", "enabled", "overrides"]
const OP_FIELDS := {
	"complete": ["amount", "bonus_if", "target"],
	"relax": ["amount", "target"],
	"heal": ["amount", "target"],
	"lose_vitality": ["amount", "target"],
	"gain_focus": ["amount"],
	"draw": ["amount", "per_discarded"],
	"discard": ["amount", "up_to"],
	"recall_from_discard": ["amount", "zone_from", "zone_to"],
	"retain_hand_card": ["amount"],
	"gain_status": ["status", "stacks", "target"],
	"remove_status": ["amount", "status", "target", "category"],
	"summon_unit": ["unit", "vitality_bonus", "cooperation_bonus"],
	"establish_scene": ["scene"],
	"restore_work": ["amount", "target"],
	"pressure": ["amount", "target", "times"],
}
const EVENT_OP_FIELDS := {
	"gain_money": ["amount"],
	"heal": ["amount"],
	"lose_vitality": ["amount"],
	"gain_card":
	["card_id", "rarity", "candidate_count", "card_pool", "selection_count", "fallback_money"],
	"gain_relic": ["relic_id", "rarity", "count", "fallback_money"],
	"upgrade_card": ["type_filter"],
	"remove_card": ["tag_filter"],
	"career": ["track", "amount"],
}
const RULESET_FIELDS := {
	"run":
	[
		"starting_vitality",
		"starting_money",
		"common_starter_cards",
		"starter_deck_size",
		"minimum_deck_size",
		"max_card_upgrades",
		"relic_slots",
		"term_count",
		"term_heal_percent",
		"rest_heal_percent",
		"career_cap"
	],
	"battle":
	[
		"starting_focus",
		"focus_per_round",
		"focus_cap",
		"draw_per_round",
		"hand_limit",
		"unit_slots",
		"scene_slots",
		"base_retention_count",
		"minimum_vitality_after_payment",
		"unit_action_vitality_cost",
		"cooperation_exam_relax",
		"scene_exam_draw",
		"scene_exam_relax",
		"minimum_ddl"
	],
	"difficulty_overrides": ["normal", "relaxed", "hard"],
	"difficulty": ["starting_vitality", "ddl_offset", "pressure_percent"],
	"rewards":
	[
		"normal_money_by_term",
		"elite_money_bonus",
		"nonfinal_boss_money",
		"candidate_count",
		"card_rarity_weights",
		"relic_rarity_weights",
		"empty_relic_pool_money"
	],
	"card_rarity_weights": ["normal", "elite", "boss", "term"],
	"relic_rarity_weights": ["general", "boss"],
	"rarity_weights": ["white", "blue", "purple", "gold"],
	"shop":
	[
		"card_stock",
		"relic_stock",
		"meal_stock",
		"card_prices",
		"relic_prices",
		"meal_price",
		"meal_heal",
		"removals_per_shop",
		"first_removal_price",
		"removal_price_increment"
	],
	"card_stock": ["white", "blue", "purple"],
	"relic_stock": ["white", "blue"],
	"card_prices": ["white", "blue", "purple"],
	"relic_prices": ["white", "blue"],
}
const REFERENCE_KEYS := {
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
	"unit": "unit",
	"scene": "scene",
	"status": "status",
	"ruleset_id": "ruleset",
}
const STATUS_POLICY := {
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
const STATUS_RULE_FIELDS := {
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

var _data_root: String
var _allow_test_manifests: bool
var _definitions: Dictionary = {}
var _enabled: Dictionary = {}
var _info: ContentInfo


func _init(data_root: String = "res://data", allow_test_manifests: bool = false) -> void:
	_data_root = data_root.trim_suffix("/")
	_allow_test_manifests = allow_test_manifests


func load(manifest_id: String) -> GameResult:
	if (
		not _is_safe_id(manifest_id)
		or (manifest_id.begins_with("test_") and not _allow_test_manifests)
	):
		return _content_error("content.manifest.invalid_id", {"id": manifest_id})
	var manifest_result := _read_json("manifests/%s.json" % manifest_id)
	if not manifest_result.ok:
		return manifest_result
	var manifest: Variant = manifest_result.data
	var issues: Array[String] = []
	if not _is_dictionary(manifest):
		issues.append("manifest must be an object")
		return _invalid_package(issues)
	_validate_fields(manifest, MANIFEST_FIELDS, MANIFEST_REQUIRED, "manifest", issues)
	if (
		manifest.get("id") != manifest_id
		or not _is_safe_token(str(manifest.get("content_version", "")))
	):
		issues.append("manifest id/content_version mismatch")
	if manifest_id == "campus_mvp" and manifest.get("content_version") != "campus_mvp.v1":
		issues.append("campus_mvp content_version must be campus_mvp.v1")
	var raw_overrides: Variant = manifest.get("overrides")
	if _is_array(raw_overrides):
		for index in raw_overrides.size():
			var override: Variant = raw_overrides[index]
			if (
				_is_dictionary(override)
				and override.get("scope_version") != manifest.get("content_version")
			):
				issues.append(
					(
						"manifest.overrides[%d].scope_version must match manifest content_version"
						% index
					)
				)
	var enabled := _validate_enabled(manifest.get("enabled"), issues)
	var definitions: Dictionary = {}
	for kind in CONTENT_KINDS:
		var loaded := _read_json("definitions/%s.json" % FILE_NAMES[kind])
		if not loaded.ok:
			issues.append("definitions/%s.json could not be loaded" % FILE_NAMES[kind])
			definitions[kind] = {}
			continue
		if not _is_array(loaded.data):
			issues.append("definitions/%s.json must contain an array" % FILE_NAMES[kind])
			definitions[kind] = {}
			continue
		definitions[kind] = _validate_definition_file(kind, loaded.data, issues)
	if not issues.is_empty():
		return _invalid_package(issues)
	var ruleset_id := str(manifest.get("ruleset_id", ""))
	if not enabled.get("ruleset", []).has(ruleset_id):
		issues.append("manifest ruleset is not enabled")
	_apply_overrides(manifest.get("overrides"), enabled, definitions, issues)
	_validate_enabled_references(enabled, definitions, issues)
	_validate_numeric_statuses(enabled, definitions, issues)
	if not issues.is_empty():
		return _invalid_package(issues)
	var indexes := _build_indexes(enabled, definitions)
	var hash_manifest: Dictionary = manifest.duplicate(true)
	for kind in hash_manifest.enabled:
		hash_manifest.enabled[kind].sort()
	var canonical := _canonical_json(
		{"manifest": hash_manifest, "definitions": _enabled_definitions(indexes)}
	)
	var digest := _sha256(canonical)
	var info := ContentInfo.new(manifest_id, manifest.content_version, digest, ruleset_id, enabled)
	_definitions = indexes
	_enabled = enabled.duplicate(true)
	_info = info
	return GameResult.success(info.copy())


func get_definition(kind: String, id: String) -> GameResult:
	if not _definitions.has(kind) or not _definitions[kind].has(id):
		return _content_error("content.definition.not_enabled", {"kind": kind, "id": id})
	return GameResult.success(_definitions[kind][id].duplicate(true))


func get_candidates(query: Dictionary) -> Array[String]:
	var allowed := ["kind", "rarity", "tags_all", "exclude_ids", "terms", "availability"]
	for key in query:
		if not allowed.has(key):
			return []
	if typeof(query.get("kind")) != TYPE_STRING:
		return []
	var kind: String = query.kind
	if not CONTENT_KINDS.has(kind) or not _definitions.has(kind):
		return []
	if query.has("rarity") and not [null, "white", "blue", "purple", "gold"].has(query.rarity):
		return []
	if query.has("availability") and not ["starter", "drop"].has(query.availability):
		return []
	if query.has("terms") and (typeof(query.terms) != TYPE_INT or query.terms < 1):
		return []
	if query.has("rarity") and kind not in ["card", "relic"]:
		return []
	if query.has("availability") and kind != "relic":
		return []
	if query.has("terms") and kind not in ["encounter", "event"]:
		return []
	if query.has("tags_all") and kind not in ["card", "relic"]:
		return []
	for field in ["tags_all", "exclude_ids"]:
		if not query.has(field):
			continue
		if not _is_array(query[field]):
			return []
		var seen := {}
		for value in query[field]:
			if typeof(value) != TYPE_STRING or not _is_safe_id(value) or seen.has(value):
				return []
			seen[value] = true
	var ids: Array[String] = []
	for id in _definitions[kind]:
		var definition: Dictionary = _definitions[kind][id]
		if query.has("rarity") and definition.get("rarity") != query.rarity:
			continue
		if query.has("availability") and definition.get("availability") != query.availability:
			continue
		var tags: Array = query.get("tags_all", [])
		var definition_tags: Array = definition.get("tags", [])
		if tags.any(func(tag): return not definition_tags.has(tag)):
			continue
		if query.get("exclude_ids", []).has(id):
			continue
		if query.has("terms") and not definition.get("terms", []).has(query.terms):
			continue
		ids.append(id)
	ids.sort()
	return ids


func get_info() -> ContentInfo:
	return _info.copy() if _info != null else null


func _read_json(relative_path: String) -> GameResult:
	var path := "%s/%s" % [_data_root, relative_path]
	if not FileAccess.file_exists(path):
		return _content_error("content.file.missing", {"path": relative_path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _content_error("content.file.read_failed", {"path": relative_path})
	var source := file.get_as_text()
	if _contains_non_integer_number(source):
		return _content_error("content.number.non_integer", {"path": relative_path})
	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK:
		return _content_error(
			"content.json.invalid",
			{
				"path": relative_path,
				"line": parser.get_error_line(),
				"message": parser.get_error_message()
			}
		)
	return GameResult.success(_normalize_json_numbers(parser.data))


func _contains_non_integer_number(source: String) -> bool:
	var in_string := false
	var escaped := false
	var index := 0
	while index < source.length():
		var character := source[index]
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				in_string = false
			index += 1
			continue
		if character == '"':
			in_string = true
			index += 1
			continue
		if character == "-" or character.is_valid_int():
			var start := index
			index += 1
			while index < source.length():
				var number_character := source[index]
				if not (
					number_character.is_valid_int() or number_character in [".", "e", "E", "+", "-"]
				):
					break
				index += 1
			var number_token := source.substr(start, index - start)
			if (
				number_token.contains(".")
				or number_token.contains("e")
				or number_token.contains("E")
			):
				return true
			continue
		index += 1
	return false


func _normalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, round(value)):
		return int(value)
	if _is_dictionary(value):
		var normalized := {}
		for key in value:
			normalized[key] = _normalize_json_numbers(value[key])
		return normalized
	if _is_array(value):
		var normalized: Array = []
		for item in value:
			normalized.append(_normalize_json_numbers(item))
		return normalized
	return value


func _validate_enabled(raw: Variant, issues: Array[String]) -> Dictionary:
	if not _is_dictionary(raw):
		issues.append("manifest.enabled must be an object")
		return {}
	for kind in raw:
		if not CONTENT_KINDS.has(kind):
			issues.append("manifest.enabled has unknown kind %s" % kind)
	for kind in CONTENT_KINDS:
		if not raw.has(kind) or not _is_array(raw[kind]):
			issues.append("manifest.enabled.%s must be an array" % kind)
			continue
		var ids: Array = raw[kind]
		var unique := {}
		for id in ids:
			if typeof(id) != TYPE_STRING:
				issues.append("manifest.enabled.%s contains an invalid id" % kind)
				continue
			if not _is_safe_id(id):
				issues.append("manifest.enabled.%s contains an invalid id" % kind)
			if unique.has(id):
				issues.append("manifest.enabled.%s contains duplicate %s" % [kind, id])
			unique[id] = true
	return raw.duplicate(true)


func _validate_definition_file(kind: String, rows: Array, issues: Array[String]) -> Dictionary:
	var by_id := {}
	for index in rows.size():
		var definition: Variant = rows[index]
		var location := "%s[%d]" % [FILE_NAMES[kind], index]
		if not _is_dictionary(definition):
			issues.append("%s must be an object" % location)
			continue
		_validate_fields(
			definition, DEFINITION_FIELDS[kind], REQUIRED_FIELDS[kind], location, issues
		)
		var id: Variant = definition.get("id")
		if typeof(id) != TYPE_STRING or not _is_safe_id(id):
			issues.append("%s.id must be a non-empty safe id" % location)
			continue
		if by_id.has(id):
			issues.append("%s duplicates id %s" % [location, id])
			continue
		by_id[id] = definition.duplicate(true)
		_validate_definition(kind, by_id[id], location, issues)
		if kind == "card" and by_id[id].has("upgrade"):
			var upgraded := _merge_card_upgrade(by_id[id], location, issues)
			if not upgraded.is_empty():
				upgraded["upgrade"] = {}
				_validate_definition("card", upgraded, location + ".upgrade.result", issues)
	return by_id


func _validate_definition(
	kind: String, definition: Dictionary, location: String, issues: Array[String]
) -> void:
	if (
		kind != "ruleset"
		and (
			typeof(definition.get("name_key")) != TYPE_STRING
			or str(definition.get("name_key", "")).is_empty()
		)
	):
		issues.append("%s.name_key must be non-empty" % location)
	match kind:
		"card":
			if not ["work", "strategy", "ability", "cooperation", "scene"].has(
				definition.get("type")
			):
				issues.append("%s.type is invalid" % location)
			if not ["white", "blue", "purple", "gold", null].has(definition.get("rarity")):
				issues.append("%s.rarity is invalid" % location)
			if not ["self", "task", "unit", "all_tasks"].has(definition.get("target")):
				issues.append("%s.target is invalid" % location)
			_validate_string_array(definition.get("tags"), "%s.tags" % location, issues)
			_validate_int(definition.get("cost"), "%s.cost" % location, 0, issues)
			_validate_bool(definition.get("exhaust"), "%s.exhaust" % location, issues)
			if definition.has("vitality_cost"):
				_validate_int(definition.vitality_cost, "%s.vitality_cost" % location, 0, issues)
			if definition.has("unplayable"):
				_validate_bool(definition.unplayable, "%s.unplayable" % location, issues)
			if definition.has("limit"):
				_validate_limit(definition.limit, "%s.limit" % location, issues)
			_validate_effects(
				definition.get("effects"),
				"battle",
				"%s.effects" % location,
				issues,
				bool(definition.get("unplayable", false))
			)
			if definition.has("pre_effects"):
				_validate_effects(
					definition.pre_effects, "battle", "%s.pre_effects" % location, issues, true
				)
			var has_effects: bool = (
				definition.get("effects") is Array and not definition.effects.is_empty()
			)
			var has_pre_effects: bool = (
				definition.get("pre_effects", []) is Array
				and not definition.get("pre_effects", []).is_empty()
			)
			if (
				not has_effects
				and not has_pre_effects
				and not bool(definition.get("unplayable", false))
			):
				issues.append("%s must have an effect" % location)
			if definition.has("upgrade"):
				_validate_upgrade(definition.upgrade, location, issues)
			if (
				not definition.has("upgrade")
				and not (
					definition.get("tags") is Array
					and definition.tags.any(func(tag): return tag in ["special", "temporary"])
				)
			):
				issues.append("%s.upgrade is required for permanent cards" % location)
		"character":
			_validate_string_array(
				definition.get("starter_cards"), "%s.starter_cards" % location, issues
			)
			if _is_array(definition.get("starter_cards")) and definition.starter_cards.size() != 2:
				issues.append("%s.starter_cards must contain two card ids" % location)
			if not _is_safe_id(str(definition.get("starter_relic_id", ""))):
				issues.append("%s.starter_relic_id must be a safe id" % location)
			_validate_passive(definition.get("passive"), location, issues)
		"unit":
			_validate_int(definition.get("vitality"), "%s.vitality" % location, 1, issues)
			_validate_int(definition.get("cooperation"), "%s.cooperation" % location, 0, issues)
			_validate_bool(definition.get("guard"), "%s.guard" % location, issues)
			_validate_support(definition.get("support"), location, issues)
			if definition.has("entry_effects"):
				_validate_effects(
					definition.entry_effects, "battle", "%s.entry_effects" % location, issues, true
				)
		"scene":
			for field in ["prepare_effects", "round_end_effects"]:
				if definition.has(field):
					_validate_effects(
						definition[field], "battle", "%s.%s" % [location, field], issues, true
					)
			if definition.has("prepare_random"):
				_validate_prepare_random(definition.prepare_random, location, issues)
			if definition.has("modifiers"):
				_validate_scene_modifiers(definition.modifiers, location, issues)
			if definition.has("battle_limit"):
				_validate_int(definition.battle_limit, "%s.battle_limit" % location, 1, issues)
			if definition.has("anxiety_after_every"):
				_validate_int(
					definition.anxiety_after_every, "%s.anxiety_after_every" % location, 1, issues
				)
			if definition.has("prepare_random") and definition.has("prepare_effects"):
				issues.append(
					"%s.prepare_random and prepare_effects are mutually exclusive" % location
				)
			var prepare_effects: Variant = definition.get("prepare_effects", [])
			var round_end_effects: Variant = definition.get("round_end_effects", [])
			if (
				not (_is_array(prepare_effects) and not prepare_effects.is_empty())
				and not (_is_array(round_end_effects) and not round_end_effects.is_empty())
				and not definition.has("prepare_random")
				and not (
					definition.get("modifiers") is Dictionary
					and not definition.modifiers.is_empty()
				)
			):
				issues.append("%s must have a behavior" % location)
		"relic":
			if not ["starter", "drop"].has(definition.get("availability")):
				issues.append("%s.availability is invalid" % location)
			if definition.get("availability") == "starter":
				if definition.get("rarity") != null:
					issues.append("%s starter rarity must be null" % location)
			elif not ["white", "blue", "purple", "gold"].has(definition.get("rarity")):
				issues.append("%s drop rarity is invalid" % location)
			if definition.has("limit"):
				_validate_limit(definition.limit, "%s.limit" % location, issues)
			if definition.has("modifiers"):
				_validate_relic_modifiers(definition, location, issues)
			if definition.has("effects"):
				_validate_effects(
					definition.effects, "battle", "%s.effects" % location, issues, true
				)
			if definition.has("hooks"):
				if not _is_array(definition.hooks):
					issues.append("%s.hooks must be an array" % location)
				else:
					for hook in definition.hooks:
						_validate_hook(hook, location, issues)
			if (
				(not (definition.get("effects") is Array and not definition.effects.is_empty()))
				and not (definition.get("hooks") is Array and not definition.hooks.is_empty())
				and not (
					definition.get("modifiers") is Dictionary
					and not definition.modifiers.is_empty()
				)
			):
				issues.append("%s must have a behavior" % location)
		"task":
			_validate_task(definition, location, issues)
		"encounter":
			if not ["normal", "elite", "boss"].has(definition.get("kind")):
				issues.append("%s.kind is invalid" % location)
			_validate_string_array(definition.get("members"), "%s.members" % location, issues)
			_validate_int(definition.get("base_ddl"), "%s.base_ddl" % location, 1, issues)
			_validate_int_array(definition.get("terms"), "%s.terms" % location, 1, issues)
			if (
				_is_array(definition.get("terms"))
				and definition.terms.any(func(term): return term > 8)
			):
				issues.append("%s.terms values must be <= 8" % location)
			_validate_string_array(definition.get("exam_flags"), "%s.exam_flags" % location, issues)
			if (
				_is_array(definition.get("exam_flags"))
				and definition.exam_flags.any(
					func(flag): return not ["independent_answer", "fixed_exam_room"].has(flag)
				)
			):
				issues.append("%s.exam_flags contains an unknown flag" % location)
			if definition.has("initial_members"):
				_validate_string_array(
					definition.initial_members, "%s.initial_members" % location, issues
				)
				if _is_array(definition.get("initial_members")):
					if definition.initial_members.is_empty():
						issues.append("%s.initial_members must not be empty" % location)
					elif (
						_is_array(definition.get("members"))
						and definition.initial_members.any(
							func(member): return not definition.members.has(member)
						)
					):
						issues.append(
							"%s.initial_members must be encounter members" % location
						)
			if definition.has("absorb_cooperation"):
				_validate_fields(
					definition.absorb_cooperation,
					["draw_per_card", "focus_per_card"],
					["draw_per_card", "focus_per_card"],
					"%s.absorb_cooperation" % location,
					issues
				)
				if _is_dictionary(definition.absorb_cooperation):
					for field in ["draw_per_card", "focus_per_card"]:
						_validate_int(
							definition.absorb_cooperation.get(field),
							"%s.absorb_cooperation.%s" % [location, field],
							0,
							issues
						)
			if definition.has("scaling"):
				_validate_fields(
					definition.scaling,
					["work_percent", "pressure_percent", "ddl_bonus"],
					["work_percent", "pressure_percent", "ddl_bonus"],
					"%s.scaling" % location,
					issues
				)
		"event":
			_validate_int_array(definition.get("terms"), "%s.terms" % location, 1, issues)
			if (
				_is_array(definition.get("terms"))
				and definition.terms.any(func(term): return term > 8)
			):
				issues.append("%s.terms values must be <= 8" % location)
			if not _is_bool(definition.get("once_per_run")):
				issues.append("%s.once_per_run must be bool" % location)
			_validate_event_options(definition.get("options"), location, issues)
		"status":
			var policy: Array = STATUS_POLICY.get(str(definition.get("id", "")), [])
			if policy.size() != 4:
				issues.append("%s.id has no registered lifecycle policy" % location)
			elif (
				[
					definition.get("target"),
					definition.get("stack_policy"),
					definition.get("duration_policy"),
					definition.get("dispel_policy")
				]
				!= policy
			):
				issues.append("%s lifecycle does not match registered policy" % location)
			if not ["player", "unit", "task"].has(definition.get("target")):
				issues.append("%s.target is invalid" % location)
			if not ["capped", "presence"].has(definition.get("stack_policy")):
				issues.append("%s.stack_policy is invalid" % location)
			if not (
				[
					"battle",
					"next_prepare",
					"next_draw",
					"next_player_action_end",
					"work_or_round_end",
					"unit_departure"
				]
				. has(definition.get("duration_policy"))
			):
				issues.append("%s.duration_policy is invalid" % location)
			if not ["negative", "explicit", "none"].has(definition.get("dispel_policy")):
				issues.append("%s.dispel_policy is invalid" % location)
			var numeric_fields: Array = STATUS_RULE_FIELDS.get(str(definition.get("id", "")), [])
			if numeric_fields.is_empty() and definition.has("numeric_rule_key"):
				issues.append("%s must not define numeric_rule_key" % location)
			elif not numeric_fields.is_empty() and not definition.has("numeric_rule_key"):
				issues.append("%s.numeric_rule_key is required" % location)
			elif (
				definition.has("numeric_rule_key") and definition.numeric_rule_key != definition.id
			):
				issues.append("%s.numeric_rule_key must equal status id" % location)
		"ruleset":
			_validate_ruleset(definition, location, issues)


func _validate_fields(
	value: Variant, allowed: Array, required: Array, location: String, issues: Array[String]
) -> void:
	if not _is_dictionary(value):
		issues.append("%s must be an object" % location)
		return
	for key in required:
		if not value.has(key):
			issues.append("%s.%s is required" % [location, key])
	for key in value:
		if not allowed.has(key):
			issues.append("%s.%s is unknown" % [location, key])


func _validate_limit(value: Variant, location: String, issues: Array[String]) -> void:
	_validate_fields(value, ["per", "times"], ["per", "times"], location, issues)
	if not _is_dictionary(value):
		return
	if not ["round", "instance_round", "battle"].has(value.get("per")):
		issues.append("%s.per is invalid" % location)
	_validate_int(value.get("times"), "%s.times" % location, 1, issues)


func _validate_support(value: Variant, location: String, issues: Array[String]) -> void:
	if not _is_dictionary(value):
		issues.append("%s.support must be an object" % location)
		return
	var kind := str(value.get("kind", ""))
	var fields_by_kind := {
		"none": ["kind"],
		"relax": ["kind", "amount"],
		"self_relax": ["kind", "amount"],
		"heal": ["kind", "amount"],
		"cleanse_or_relax": ["kind", "status", "amount", "fallback_relax"],
		"gain_status_on_actions": ["kind", "status", "stacks", "every"],
	}
	if not fields_by_kind.has(kind):
		issues.append("%s.support.kind is invalid" % location)
		return
	_validate_fields(
		value, fields_by_kind[kind], fields_by_kind[kind], "%s.support" % location, issues
	)
	match kind:
		"relax", "self_relax", "heal":
			_validate_int(value.get("amount"), "%s.support.amount" % location, 1, issues)
		"cleanse_or_relax":
			if typeof(value.get("status")) != TYPE_STRING:
				issues.append("%s.support.status must be an id" % location)
			_validate_int(value.get("amount"), "%s.support.amount" % location, 1, issues)
			_validate_int(
				value.get("fallback_relax"), "%s.support.fallback_relax" % location, 1, issues
			)
		"gain_status_on_actions":
			if typeof(value.get("status")) != TYPE_STRING:
				issues.append("%s.support.status must be an id" % location)
			_validate_int(value.get("stacks"), "%s.support.stacks" % location, 1, issues)
			_validate_int(value.get("every"), "%s.support.every" % location, 1, issues)


func _validate_prepare_random(value: Variant, location: String, issues: Array[String]) -> void:
	_validate_fields(value, ["options"], ["options"], "%s.prepare_random" % location, issues)
	if not _is_dictionary(value) or not _is_array(value.get("options")):
		issues.append("%s.prepare_random.options must be an array" % location)
		return
	if value.options.is_empty():
		issues.append("%s.prepare_random.options must not be empty" % location)
	for index in value.options.size():
		_validate_effects(
			value.options[index],
			"battle",
			"%s.prepare_random.options[%d]" % [location, index],
			issues,
			false
		)


func _validate_scene_modifiers(value: Variant, location: String, issues: Array[String]) -> void:
	var fields := ["first_work_cost_discount", "work_first_segment_bonus", "heal_percent"]
	_validate_fields(value, fields, [], "%s.modifiers" % location, issues)
	if not _is_dictionary(value):
		return
	for key in value:
		_validate_int(value[key], "%s.modifiers.%s" % [location, key], 0, issues)
		if key == "heal_percent" and typeof(value[key]) == TYPE_INT and value[key] > 100:
			issues.append("%s.modifiers.heal_percent must be <= 100" % location)


func _validate_relic_modifiers(
	definition: Dictionary, location: String, issues: Array[String]
) -> void:
	_validate_fields(
		definition.modifiers, ["work_flat_bonus"], [], "%s.modifiers" % location, issues
	)
	if not _is_dictionary(definition.modifiers):
		return
	if definition.modifiers.has("work_flat_bonus"):
		_validate_int(
			definition.modifiers.work_flat_bonus,
			"%s.modifiers.work_flat_bonus" % location,
			1,
			issues
		)
		if not definition.has("limit"):
			issues.append("%s.modifiers.work_flat_bonus requires limit" % location)
		elif (
			_is_dictionary(definition.limit)
			and (definition.limit.get("per") != "round" or definition.limit.get("times") != 1)
		):
			issues.append("%s work_flat_bonus limit must be round/1" % location)


func _validate_effects(
	value: Variant, domain: String, location: String, issues: Array[String], allow_empty: bool
) -> void:
	if not _is_array(value):
		issues.append("%s must be an array" % location)
		return
	if not allow_empty and value.is_empty():
		issues.append("%s must not be empty" % location)
	var registry: Dictionary = EVENT_OP_FIELDS if domain == "event" else OP_FIELDS
	for index in value.size():
		var effect: Variant = value[index]
		var effect_location := "%s[%d]" % [location, index]
		if not _is_dictionary(effect):
			issues.append("%s must be an object" % effect_location)
			continue
		var op := str(effect.get("op", ""))
		if not registry.has(op):
			issues.append("%s.op is unknown: %s" % [effect_location, op])
			continue
		var allowed: Array = ["op"] + registry[op]
		var required_by_op := {
			"complete": ["amount"],
			"relax": ["amount"],
			"heal": ["amount"],
			"lose_vitality": ["amount"],
			"gain_focus": ["amount"],
			"draw": ["amount"],
			"discard": ["amount"],
			"recall_from_discard": ["amount", "zone_from", "zone_to"],
			"retain_hand_card": ["amount"],
			"gain_status": ["status", "stacks"],
			"remove_status": ["amount"],
			"summon_unit": ["unit"],
			"establish_scene": ["scene"],
			"restore_work": ["amount"],
			"pressure": ["amount"],
			"gain_money": ["amount"]
		}
		var required: Array = ["op"] + required_by_op.get(op, [])
		_validate_fields(effect, allowed, required, effect_location, issues)
		if effect.has("amount"):
			_validate_int(
				effect.amount,
				"%s.amount" % effect_location,
				0 if op == "complete" or (op == "draw" and effect.has("per_discarded")) else 1,
				issues
			)
		if op == "gain_status" and typeof(effect.get("status")) != TYPE_STRING:
			issues.append("%s.status must be an id" % effect_location)
		if effect.has("bonus_if"):
			_validate_bonus_if(effect.bonus_if, effect_location, issues)
		if op == "gain_card":
			var selection_modes := (
				int(effect.has("card_id"))
				+ int(effect.has("rarity"))
				+ int(effect.has("card_pool"))
			)
			if selection_modes != 1:
				issues.append("%s.gain_card requires exactly one selection mode" % effect_location)
			elif effect.has("rarity") and not effect.has("candidate_count"):
				issues.append("%s.gain_card rarity mode requires candidate_count" % effect_location)
			elif (
				effect.has("card_pool")
				and not effect.has_all(["selection_count", "fallback_money"])
			):
				issues.append(
					(
						"%s.gain_card card_pool mode requires selection_count/fallback_money"
						% effect_location
					)
				)
			var allowed_mode_fields: Array = (
				["op", "card_id"]
				if effect.has("card_id")
				else (
					["op", "rarity", "candidate_count"]
					if effect.has("rarity")
					else ["op", "card_pool", "selection_count", "fallback_money"]
				)
			)
			for key in effect:
				if not allowed_mode_fields.has(key):
					issues.append(
						"%s.gain_card field %s is invalid for its mode" % [effect_location, key]
					)
		if op == "gain_relic":
			var selection_modes := int(effect.has("relic_id")) + int(effect.has("rarity"))
			if selection_modes != 1:
				issues.append("%s.gain_relic requires exactly one selection mode" % effect_location)
			if not effect.has("fallback_money"):
				issues.append("%s.gain_relic requires fallback_money" % effect_location)
			if effect.has("rarity") and not effect.has("count"):
				issues.append("%s.gain_relic rarity mode requires count" % effect_location)
			var allowed_mode_fields: Array = (
				["op", "relic_id", "fallback_money"]
				if effect.has("relic_id")
				else ["op", "rarity", "count", "fallback_money"]
			)
			for key in effect:
				if not allowed_mode_fields.has(key):
					issues.append(
						"%s.gain_relic field %s is invalid for its mode" % [effect_location, key]
					)
		_validate_effect_semantics(op, effect, domain, effect_location, issues)


func _validate_bonus_if(value: Variant, location: String, issues: Array[String]) -> void:
	var fields := ["amount", "status", "min_stacks", "played_definition", "scope", "ddl_lte"]
	_validate_fields(value, fields, ["amount"], "%s.bonus_if" % location, issues)
	if not _is_dictionary(value):
		return
	_validate_int(value.get("amount"), "%s.bonus_if.amount" % location, 1, issues)
	var conditions := ["status", "played_definition", "ddl_lte"].filter(
		func(field): return value.has(field)
	)
	if conditions.is_empty():
		issues.append("%s.bonus_if requires at least one condition" % location)
	if value.has("status"):
		if typeof(value.status) != TYPE_STRING:
			issues.append("%s.bonus_if.status must be an id" % location)
		if value.has("min_stacks"):
			_validate_int(value.min_stacks, "%s.bonus_if.min_stacks" % location, 1, issues)
	elif value.has("min_stacks"):
		issues.append("%s.bonus_if.min_stacks requires status" % location)
	if value.has("played_definition"):
		if typeof(value.played_definition) != TYPE_STRING:
			issues.append("%s.bonus_if.played_definition must be an id" % location)
		if value.get("scope", "round") != "round":
			issues.append("%s.bonus_if.scope must be round" % location)
	elif value.has("scope"):
		issues.append("%s.bonus_if.scope requires played_definition" % location)
	if value.has("ddl_lte"):
		_validate_int(value.ddl_lte, "%s.bonus_if.ddl_lte" % location, 1, issues)


func _validate_effect_semantics(
	op: String, effect: Dictionary, domain: String, location: String, issues: Array[String]
) -> void:
	for field in [
		"fallback_money", "candidate_count", "selection_count", "count", "per_discarded", "times"
	]:
		if effect.has(field):
			_validate_int(
				effect[field],
				"%s.%s" % [location, field],
				0 if field == "fallback_money" else 1,
				issues
			)
	if effect.has("target"):
		var targets := ["player", "self", "unit", "task", "all_tasks", "all", "default"]
		if not targets.has(effect.target):
			issues.append("%s.target is invalid" % location)
	if effect.has("status") and typeof(effect.status) != TYPE_STRING:
		issues.append("%s.status must be an id" % location)
	if effect.has("unit") and typeof(effect.unit) != TYPE_STRING:
		issues.append("%s.unit must be an id" % location)
	if effect.has("scene") and typeof(effect.scene) != TYPE_STRING:
		issues.append("%s.scene must be an id" % location)
	if domain == "event":
		match op:
			"gain_card":
				if effect.has("card_id") and typeof(effect.card_id) != TYPE_STRING:
					issues.append("%s.card_id must be an id" % location)
				if (
					effect.has("rarity")
					and not ["white", "blue", "purple", "gold"].has(effect.rarity)
				):
					issues.append("%s.rarity is invalid" % location)
				if effect.has("card_pool"):
					_validate_string_array(effect.card_pool, "%s.card_pool" % location, issues)
					if effect.get("selection_count") != 1:
						issues.append("%s.selection_count must equal 1" % location)
			"gain_relic":
				if effect.has("relic_id") and typeof(effect.relic_id) != TYPE_STRING:
					issues.append("%s.relic_id must be an id" % location)
				if (
					effect.has("rarity")
					and not ["white", "blue", "purple", "gold"].has(effect.rarity)
				):
					issues.append("%s.rarity is invalid" % location)
			"upgrade_card":
				if (
					effect.has("type_filter")
					and not ["work", "strategy", "ability", "cooperation", "scene"].has(
						effect.type_filter
					)
				):
					issues.append("%s.type_filter is invalid" % location)
			"remove_card":
				if (
					effect.has("tag_filter")
					and not ["basic", "special", "temporary"].has(effect.tag_filter)
				):
					issues.append("%s.tag_filter is invalid" % location)
			"career":
				if not ["research", "competition", "internship", "grad_exam"].has(
					effect.get("track")
				):
					issues.append("%s.track is invalid" % location)
				_validate_int(effect.get("amount"), "%s.amount" % location, 1, issues)
		return
	match op:
		"discard":
			if effect.has("up_to"):
				_validate_bool(effect.up_to, "%s.up_to" % location, issues)
		"draw":
			if effect.has("per_discarded") and effect.get("amount") != 0:
				_validate_int(effect.amount, "%s.amount" % location, 0, issues)
		"gain_status":
			_validate_int(effect.get("stacks"), "%s.stacks" % location, 1, issues)
			if effect.has("target") and not ["player", "self", "unit", "task"].has(effect.target):
				issues.append("%s.target is invalid for gain_status" % location)
		"remove_status":
			var has_status := effect.has("status")
			var has_category := effect.has("category")
			if has_status == has_category:
				issues.append("%s requires exactly one of status or category" % location)
			if has_category and effect.category != "negative":
				issues.append("%s.category must be negative" % location)
			if effect.has("target") and not ["player", "self", "unit", "task"].has(effect.target):
				issues.append("%s.target is invalid for remove_status" % location)
			if has_category and effect.has("target"):
				issues.append("%s category removal cannot define target" % location)
		"recall_from_discard":
			if effect.get("zone_from") != "discard" or effect.get("zone_to") != "hand":
				issues.append("%s recall zones must be discard to hand" % location)
		"summon_unit":
			for field in ["vitality_bonus", "cooperation_bonus"]:
				if effect.has(field):
					_validate_int(effect[field], "%s.%s" % [location, field], 0, issues)
		"pressure":
			if effect.has("times"):
				_validate_int(effect.times, "%s.times" % location, 1, issues)


func _validate_upgrade(value: Variant, location: String, issues: Array[String]) -> void:
	var allowed := ["cost", "vitality_cost", "exhaust", "target", "effects", "pre_effects", "limit"]
	_validate_fields(value, allowed, [], "%s.upgrade" % location, issues)
	if _is_dictionary(value):
		_validate_no_null(value, "%s.upgrade" % location, issues)
		if value.has("effects"):
			_validate_effects(
				value.effects, "battle", "%s.upgrade.effects" % location, issues, false
			)
		if value.has("pre_effects"):
			_validate_effects(
				value.pre_effects, "battle", "%s.upgrade.pre_effects" % location, issues, true
			)
		if value.has("cost"):
			_validate_int(value.cost, "%s.upgrade.cost" % location, 0, issues)
		if value.has("vitality_cost"):
			_validate_int(value.vitality_cost, "%s.upgrade.vitality_cost" % location, 0, issues)
		if value.has("exhaust"):
			_validate_bool(value.exhaust, "%s.upgrade.exhaust" % location, issues)


func _merge_card_upgrade(
	definition: Dictionary, location: String, issues: Array[String]
) -> Dictionary:
	var upgrade: Variant = definition.get("upgrade")
	if not _is_dictionary(upgrade):
		issues.append("%s.upgrade must be a patch object" % location)
		return {}
	var merged := definition.duplicate(true)
	merged.erase("upgrade")
	for key in upgrade:
		if typeof(upgrade[key]) == TYPE_NIL:
			issues.append("%s.upgrade.%s cannot be null" % [location, key])
			return {}
		if _is_dictionary(merged.get(key)) and _is_dictionary(upgrade[key]):
			merged[key] = _merge_dictionary(merged[key], upgrade[key])
		elif _is_array(upgrade[key]) or _is_dictionary(upgrade[key]):
			merged[key] = upgrade[key].duplicate(true)
		else:
			merged[key] = upgrade[key]
	return merged


func _merge_dictionary(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in patch:
		if _is_dictionary(merged.get(key)) and _is_dictionary(patch[key]):
			merged[key] = _merge_dictionary(merged[key], patch[key])
		elif _is_array(patch[key]) or _is_dictionary(patch[key]):
			merged[key] = patch[key].duplicate(true)
		else:
			merged[key] = patch[key]
	return merged


func _validate_no_null(value: Variant, location: String, issues: Array[String]) -> void:
	if typeof(value) == TYPE_NIL:
		issues.append("%s cannot be null" % location)
	elif _is_dictionary(value):
		for key in value:
			_validate_no_null(value[key], "%s.%s" % [location, key], issues)
	elif _is_array(value):
		for index in value.size():
			_validate_no_null(value[index], "%s[%d]" % [location, index], issues)


func _validate_passive(value: Variant, location: String, issues: Array[String]) -> void:
	var fields := ["id", "trigger", "count", "limit", "effects"]
	_validate_fields(value, fields, fields, "%s.passive" % location, issues)
	if _is_dictionary(value):
		if typeof(value.get("id")) != TYPE_STRING or not _is_safe_id(value.id):
			issues.append("%s.passive.id must be a safe id" % location)
		if not ["work_card_resolved", "cooperation_card_resolved"].has(value.get("trigger")):
			issues.append("%s.passive.trigger is invalid" % location)
		_validate_int(value.get("count"), "%s.passive.count" % location, 1, issues)
		_validate_limit(value.get("limit"), "%s.passive.limit" % location, issues)
		_validate_effects(
			value.get("effects"), "battle", "%s.passive.effects" % location, issues, false
		)


func _validate_task(value: Dictionary, location: String, issues: Array[String]) -> void:
	if not ["normal", "elite", "boss"].has(value.get("kind")):
		issues.append("%s.kind is invalid" % location)
	if value.has("victory_required"):
		_validate_bool(value.victory_required, "%s.victory_required" % location, issues)
	var phases: Variant = value.get("phases")
	if not _is_array(phases) or phases.is_empty():
		issues.append("%s kind/phases are invalid" % location)
		return
	var seen := {}
	for index in phases.size():
		var phase: Variant = phases[index]
		var phase_location := "%s.phases[%d]" % [location, index]
		_validate_fields(
			phase,
			["phase_key", "work_max", "intents", "name_key", "intent_loop"],
			["phase_key", "work_max", "intents"],
			phase_location,
			issues
		)
		if not _is_dictionary(phase):
			continue
		if typeof(phase.get("phase_key")) != TYPE_STRING or str(phase.phase_key).is_empty():
			issues.append("%s.phase_key must be non-empty" % phase_location)
		if (
			phase.has("name_key")
			and (typeof(phase.name_key) != TYPE_STRING or str(phase.name_key).is_empty())
		):
			issues.append("%s.name_key must be non-empty" % phase_location)
		if phase.has("intent_loop") and not ["cycle", "clamp"].has(phase.intent_loop):
			issues.append("%s.intent_loop is invalid" % phase_location)
		if seen.has(phase.get("phase_key")):
			issues.append("%s.phase_key is duplicated" % phase_location)
		seen[phase.get("phase_key")] = true
		_validate_int(phase.get("work_max"), "%s.work_max" % phase_location, 1, issues)
		if not _is_array(phase.get("intents")) or phase.intents.is_empty():
			issues.append("%s.intents must be a non-empty array" % phase_location)
		else:
			for intent_index in phase.intents.size():
				_validate_intent(
					phase.intents[intent_index],
					"%s.intents[%d]" % [phase_location, intent_index],
					issues
				)


func _validate_intent(value: Variant, location: String, issues: Array[String]) -> void:
	var fields := [
		"index",
		"text_key",
		"pressure",
		"pressure_times",
		"pressure_all",
		"pressure_per_unit",
		"pressure_per_unit_cap",
		"shield",
		"work_restore",
		"extra_requirements",
		"gain_status",
		"add_card",
		"summon_tasks",
		"transform_task",
		"ddl_bonus",
		"self_destruct"
	]
	_validate_fields(value, fields, ["index", "text_key"], location, issues)
	if not _is_dictionary(value):
		return
	_validate_int(value.get("index"), "%s.index" % location, 0, issues)
	if typeof(value.get("text_key")) != TYPE_STRING or str(value.text_key).is_empty():
		issues.append("%s.text_key must be non-empty" % location)
	for field in ["pressure", "pressure_times", "shield", "work_restore", "extra_requirements"]:
		if value.has(field):
			_validate_int(value[field], "%s.%s" % [location, field], 1, issues)
	if value.has("pressure_times") and not value.has("pressure"):
		issues.append("%s.pressure_times requires pressure" % location)
	if value.has("pressure_all"):
		_validate_bool(value.pressure_all, "%s.pressure_all" % location, issues)
	if value.has("pressure_per_unit"):
		_validate_int(value.pressure_per_unit, "%s.pressure_per_unit" % location, 1, issues)
		if not value.has("pressure"):
			issues.append("%s.pressure_per_unit requires pressure" % location)
		if value.has("pressure_per_unit_cap"):
			_validate_int(
				value.pressure_per_unit_cap, "%s.pressure_per_unit_cap" % location, 1, issues
			)
	elif value.has("pressure_per_unit_cap"):
		issues.append("%s.pressure_per_unit_cap requires pressure_per_unit" % location)
	if value.has("ddl_bonus"):
		_validate_int(value.ddl_bonus, "%s.ddl_bonus" % location, 1, issues)
	if value.has("self_destruct"):
		_validate_bool(value.self_destruct, "%s.self_destruct" % location, issues)
	if value.has("summon_tasks"):
		if not _is_array(value.summon_tasks) or value.summon_tasks.is_empty():
			issues.append("%s.summon_tasks must be a non-empty array" % location)
		else:
			for spec in value.summon_tasks:
				_validate_fields(
					spec,
					["task", "count"],
					["task", "count"],
					"%s.summon_tasks[]" % location,
					issues
				)
				if _is_dictionary(spec):
					var summoned_task: Variant = spec.get("task")
					if (
						typeof(summoned_task) != TYPE_STRING
						or str(summoned_task).is_empty()
					):
						issues.append("%s.summon_tasks[].task must be an id" % location)
					_validate_int(
						spec.get("count"), "%s.summon_tasks[].count" % location, 1, issues
					)
	if value.has("transform_task"):
		_validate_fields(
			value.transform_task, ["task"], ["task"], "%s.transform_task" % location, issues
		)
		if _is_dictionary(value.transform_task):
			var transform_target: Variant = value.transform_task.get("task")
			if typeof(transform_target) != TYPE_STRING or str(transform_target).is_empty():
				issues.append("%s.transform_task.task must be an id" % location)
	if value.has("gain_status"):
		_validate_fields(
			value.gain_status,
			["status", "stacks", "target"],
			["status", "stacks", "target"],
			"%s.gain_status" % location,
			issues
		)
		if _is_dictionary(value.gain_status):
			if typeof(value.gain_status.status) != TYPE_STRING:
				issues.append("%s.gain_status.status must be an id" % location)
			_validate_int(
				value.gain_status.get("stacks"), "%s.gain_status.stacks" % location, 1, issues
			)
			if not ["player", "unit", "task"].has(value.gain_status.get("target")):
				issues.append("%s.gain_status.target is invalid" % location)
	if value.has("add_card"):
		_validate_fields(
			value.add_card,
			["card", "count", "zone"],
			["card", "count", "zone"],
			"%s.add_card" % location,
			issues
		)
		if _is_dictionary(value.add_card):
			if typeof(value.add_card.card) != TYPE_STRING:
				issues.append("%s.add_card.card must be an id" % location)
			_validate_int(value.add_card.get("count"), "%s.add_card.count" % location, 1, issues)
			if not ["draw", "hand", "discard", "exhaust"].has(value.add_card.get("zone")):
				issues.append("%s.add_card.zone is invalid" % location)


func _validate_event_options(value: Variant, location: String, issues: Array[String]) -> void:
	if not _is_array(value) or value.is_empty():
		issues.append("%s.options must be a non-empty array" % location)
		return
	var ids := {}
	var has_exit := false
	for option in value:
		_validate_fields(
			option,
			["option_id", "label_key", "cost", "effects"],
			["option_id", "label_key", "cost", "effects"],
			location + ".options[]",
			issues
		)
		if not _is_dictionary(option):
			continue
		if typeof(option.get("option_id")) != TYPE_STRING or str(option.option_id).is_empty():
			issues.append("%s option_id must be non-empty" % location)
		if typeof(option.get("label_key")) != TYPE_STRING or str(option.label_key).is_empty():
			issues.append("%s label_key must be non-empty" % location)
		if ids.has(option.get("option_id")):
			issues.append("%s has duplicate option_id" % location)
		ids[option.get("option_id")] = true
		_validate_fields(
			option.get("cost"), ["money", "vitality"], [], location + ".options[].cost", issues
		)
		if _is_dictionary(option.get("cost")):
			for cost_key in option.cost:
				_validate_int(
					option.cost[cost_key], "%s.options[].cost.%s" % [location, cost_key], 0, issues
				)
		_validate_effects(
			option.get("effects"), "event", location + ".options[].effects", issues, true
		)
		if (
			_is_dictionary(option.get("cost"))
			and option.cost.is_empty()
			and _is_array(option.get("effects"))
			and option.effects.is_empty()
		):
			has_exit = true
	if not has_exit:
		issues.append("%s has no no-op exit option" % location)


func _validate_hook(value: Variant, location: String, issues: Array[String]) -> void:
	if not _is_dictionary(value) or not value.has("at"):
		issues.append("%s hook.at is required" % location)
		return
	var at := str(value.at)
	var fields_by_at := {
		"round_start": ["at", "effects", "rounds", "limit"],
		"draw": ["at", "effects", "rounds", "limit"],
		"card_resolved": ["at", "effects", "card_type", "definition_id", "limit"],
		"cost_quote":
		["at", "limit", "card_type", "definition_id", "discount", "skip_vitality_cost"],
		"shop_price": ["at", "kinds", "multiplier_percent", "rounding"],
	}
	if not fields_by_at.has(at):
		issues.append("%s hook.at is not registered" % location)
		return
	var required := (
		["at", "kinds", "multiplier_percent", "rounding"]
		if at == "shop_price"
		else ["at", "limit"] if at == "cost_quote" else ["at", "effects"]
	)
	_validate_fields(value, fields_by_at[at], required, "%s.hooks[]" % location, issues)
	if value.has("limit"):
		_validate_limit(value.limit, "%s.hooks[].limit" % location, issues)
	if at in ["round_start", "draw", "card_resolved"] and value.has("effects"):
		_validate_effects(value.effects, "battle", "%s.hooks[].effects" % location, issues, false)
	if value.has("rounds"):
		_validate_int_array(value.rounds, "%s.hooks[].rounds" % location, 1, issues)
	if (
		value.has("card_type")
		and not ["work", "strategy", "ability", "cooperation", "scene"].has(value.card_type)
	):
		issues.append("%s hook.card_type is invalid" % location)
	if at == "cost_quote":
		if not value.has("card_type") and not value.has("definition_id"):
			issues.append("%s cost_quote requires a card filter" % location)
		if value.has("discount") == value.has("skip_vitality_cost"):
			issues.append("%s cost_quote requires exactly one cost effect" % location)
		if value.has("discount"):
			_validate_int(value.discount, "%s.hooks[].discount" % location, 1, issues)
		if value.has("skip_vitality_cost") and value.skip_vitality_cost != true:
			issues.append("%s skip_vitality_cost must be true" % location)
	if at == "shop_price":
		_validate_string_array(value.get("kinds"), "%s.hooks[].kinds" % location, issues)
		if (
			_is_array(value.get("kinds"))
			and value.kinds.any(func(kind): return not ["card", "relic"].has(kind))
		):
			issues.append("%s hook.kinds contains an invalid kind" % location)
		_validate_int(
			value.get("multiplier_percent"), "%s.hooks[].multiplier_percent" % location, 1, issues
		)
		if typeof(value.get("multiplier_percent")) == TYPE_INT and value.multiplier_percent > 100:
			issues.append("%s hook.multiplier_percent must be <= 100" % location)
		if value.get("rounding") != "ceil":
			issues.append("%s hook.rounding must be ceil" % location)


func _validate_ruleset(value: Dictionary, location: String, issues: Array[String]) -> void:
	if value.get("id") != "campus_v1":
		issues.append("%s.id must be campus_v1" % location)
	_validate_int(value.get("schema_version"), "%s.schema_version" % location, 1, issues)
	for field in ["run", "battle", "difficulty_overrides", "rewards", "shop"]:
		var sub: Variant = value.get(field)
		var allowed: Array = RULESET_FIELDS[field]
		var required: Array = allowed.filter(
			func(key):
				return not (
					(field == "run" and key == "career_cap")
					or (field == "difficulty_overrides" and key in ["relaxed", "hard"])
				)
		)
		_validate_fields(sub, allowed, required, "%s.%s" % [location, field], issues)
		if not _is_dictionary(sub):
			return
	if not _is_dictionary(value.get("statuses")):
		issues.append("%s.statuses must be an object" % location)
		return
	for key in value.statuses:
		var allowed_status_fields: Array = STATUS_RULE_FIELDS.get(str(key), [])
		if allowed_status_fields.is_empty():
			issues.append("%s.statuses.%s is not a registered numeric status" % [location, key])
			continue
		_validate_nested_object(
			value.statuses[key], allowed_status_fields, "%s.statuses.%s" % [location, key], issues
		)
		_validate_fields(
			value.statuses[key],
			allowed_status_fields,
			allowed_status_fields,
			"%s.statuses.%s" % [location, key],
			issues
		)
		if _is_dictionary(value.statuses[key]):
			for numeric_key in value.statuses[key]:
				_validate_int(
					value.statuses[key][numeric_key],
					"%s.statuses.%s.%s" % [location, key, numeric_key],
					0,
					issues
				)
	for difficulty in value.get("difficulty_overrides", {}):
		if not _is_dictionary(value.difficulty_overrides[difficulty]):
			issues.append("%s.difficulty_overrides.%s must be an object" % [location, difficulty])
		else:
			_validate_fields(
				value.difficulty_overrides[difficulty],
				RULESET_FIELDS.difficulty,
				RULESET_FIELDS.difficulty,
				"%s.difficulty_overrides.%s" % [location, difficulty],
				issues
			)
	for group in ["card_rarity_weights", "relic_rarity_weights"]:
		var rarities: Variant = value.get("rewards", {}).get(group, {})
		if not _is_dictionary(rarities):
			issues.append("%s.rewards.%s must be an object" % [location, group])
			continue
		var allowed_groups: Array = RULESET_FIELDS[group]
		_validate_fields(
			rarities, allowed_groups, allowed_groups, "%s.rewards.%s" % [location, group], issues
		)
		for rarity_group in rarities:
			if not _is_dictionary(rarities[rarity_group]):
				issues.append(
					"%s.rewards.%s.%s must be an object" % [location, group, rarity_group]
				)
			else:
				_validate_fields(
					rarities[rarity_group],
					RULESET_FIELDS.rarity_weights,
					RULESET_FIELDS.rarity_weights,
					"%s.rewards.%s.%s" % [location, group, rarity_group],
					issues
				)
	for object_name in ["card_stock", "relic_stock", "card_prices", "relic_prices"]:
		var table: Variant = value.get("shop", {}).get(object_name, {})
		if not _is_dictionary(table):
			issues.append("%s.shop.%s must be an object" % [location, object_name])
			continue
		_validate_fields(
			table,
			RULESET_FIELDS[object_name],
			RULESET_FIELDS[object_name],
			"%s.shop.%s" % [location, object_name],
			issues
		)
	_validate_integer_tree(value, location, issues)


func _validate_integer_tree(value: Variant, location: String, issues: Array[String]) -> void:
	if _is_dictionary(value):
		for key in value:
			_validate_integer_tree(value[key], "%s.%s" % [location, key], issues)
	elif _is_array(value):
		for index in value.size():
			_validate_integer_tree(value[index], "%s[%d]" % [location, index], issues)
	elif typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL:
		issues.append("%s must use integer values" % location)
	elif typeof(value) == TYPE_INT and value < 0 and not location.ends_with(".ddl_offset"):
		issues.append("%s must not be negative" % location)


func _validate_enabled_references(
	enabled: Dictionary, definitions: Dictionary, issues: Array[String]
) -> void:
	for kind in CONTENT_KINDS:
		for id in enabled.get(kind, []):
			if not definitions.get(kind, {}).has(id):
				issues.append("enabled %s/%s is missing" % [kind, id])
	for kind in CONTENT_KINDS:
		for id in enabled.get(kind, []):
			if not definitions.get(kind, {}).has(id):
				continue
			_validate_references_recursive(
				kind, definitions[kind][id], id, enabled, definitions, issues
			)
	if enabled.get("ruleset", []).is_empty():
		issues.append("enabled ruleset list is empty")


func _validate_references_recursive(
	owner_kind: String,
	value: Variant,
	owner_id: String,
	enabled: Dictionary,
	definitions: Dictionary,
	issues: Array[String]
) -> void:
	if _is_dictionary(value):
		for key in value:
			var target_kind: String = REFERENCE_KEYS.get(key, "")
			var references: Array = []
			if not target_kind.is_empty():
				references = value[key] if _is_array(value[key]) else [value[key]]
			for reference in references:
				if (
					typeof(reference) == TYPE_STRING
					and (
						not enabled.get(target_kind, []).has(reference)
						or not definitions.get(target_kind, {}).has(reference)
					)
				):
					issues.append(
						(
							"%s/%s references disabled or missing %s/%s"
							% [owner_kind, owner_id, target_kind, reference]
						)
					)
			_validate_references_recursive(
				owner_kind, value[key], owner_id, enabled, definitions, issues
			)
	elif _is_array(value):
		for item in value:
			_validate_references_recursive(owner_kind, item, owner_id, enabled, definitions, issues)


func _validate_numeric_statuses(
	enabled: Dictionary, definitions: Dictionary, issues: Array[String]
) -> void:
	if enabled.get("ruleset", []).is_empty():
		return
	var ruleset_id := str(enabled.ruleset[0])
	if not definitions.get("ruleset", {}).has(ruleset_id):
		return
	var numeric_statuses: Dictionary = definitions.ruleset[ruleset_id].get("statuses", {})
	var expected: Dictionary = {}
	for id in enabled.get("status", []):
		if not definitions.get("status", {}).has(id):
			continue
		var status: Dictionary = definitions.status[id]
		if status.has("numeric_rule_key"):
			expected[status.numeric_rule_key] = true
	for id in expected:
		if not numeric_statuses.has(id):
			issues.append("ruleset is missing numeric status %s" % id)
	for id in numeric_statuses:
		if not expected.has(id):
			issues.append("ruleset contains unreferenced numeric status %s" % id)


func _apply_overrides(
	raw: Variant, enabled: Dictionary, definitions: Dictionary, issues: Array[String]
) -> void:
	if not _is_array(raw):
		issues.append("manifest.overrides must be an array")
		return
	for index in raw.size():
		var override: Variant = raw[index]
		var location := "manifest.overrides[%d]" % index
		_validate_fields(
			override,
			["kind", "id", "scope_version", "source", "patch"],
			["kind", "id", "scope_version", "source", "patch"],
			location,
			issues
		)
		if not _is_dictionary(override):
			continue
		var kind := str(override.get("kind", ""))
		var id := str(override.get("id", ""))
		if (
			not CONTENT_KINDS.has(kind)
			or not enabled.get(kind, []).has(id)
			or not definitions.get(kind, {}).has(id)
		):
			issues.append("%s target must be enabled and defined" % location)
			continue
		var source: Variant = override.get("source")
		_validate_fields(
			source, ["path", "section"], ["path", "section"], location + ".source", issues
		)
		if (
			not _is_dictionary(source)
			or source.get("path") != "docs/交大四年_DDL战争_项目计划书.md"
			or source.get("section") != "§3.1"
		):
			issues.append("%s source is not the approved project scope" % location)
		if override.get("scope_version") != "campus_mvp.v1":
			issues.append("%s scope_version is not campus_mvp.v1" % location)
		if kind == "encounter" and id == "N04":
			_validate_fields(override.patch, ["terms"], ["terms"], location + ".patch", issues)
			if _is_dictionary(override.patch):
				_validate_int_array(
					override.patch.get("terms"), location + ".patch.terms", 1, issues
				)
				if override.patch.get("terms") != [1]:
					issues.append("%s N04 override must be terms=[1]" % location)
				definitions[kind][id]["terms"] = override.patch.get("terms", [])
		elif kind == "event" and id == "V03":
			_validate_fields(override.patch, ["options"], ["options"], location + ".patch", issues)
			if not _is_dictionary(override.patch) or not _is_array(override.patch.get("options")):
				issues.append("%s V03 override must replace options" % location)
				continue
			var full_options: Array = definitions[kind][id].get("options", [])
			var replacement: Array = override.patch.options
			if replacement.size() != full_options.size():
				issues.append("%s V03 override must preserve every option" % location)
				continue
			var full_by_id := {}
			var replacement_by_id := {}
			for option in full_options:
				full_by_id[option.get("option_id")] = option
			for option in replacement:
				if not _is_dictionary(option) or typeof(option.get("option_id")) != TYPE_STRING:
					issues.append("%s V03 override contains an invalid option" % location)
					continue
				replacement_by_id[option.option_id] = option
			if (
				replacement_by_id.keys().size() != full_by_id.keys().size()
				or replacement_by_id.keys().any(
					func(option_id): return not full_by_id.has(option_id)
				)
			):
				issues.append("%s V03 override changes option ids" % location)
				continue
			var old_consult: Dictionary = full_by_id.get("consult", {})
			var new_consult: Dictionary = replacement_by_id.get("consult", {})
			var old_effects: Array = old_consult.get("effects", [])
			var new_effects: Array = new_consult.get("effects", [])
			if (
				old_effects.size() != new_effects.size()
				or old_effects.is_empty()
				or old_effects[0].get("op") != "gain_card"
				or new_effects[0].get("op") != "gain_card"
			):
				issues.append("%s V03 consult patch changes effect structure" % location)
				continue
			var old_effect: Dictionary = old_effects[0]
			var new_effect: Dictionary = new_effects[0]
			if (
				old_effect.get("card_pool") != ["K14", "K24", "K34"]
				or new_effect.get("card_pool") != ["K14", "K05", "K60"]
			):
				issues.append("%s V03 consult pool is not the approved MVP override" % location)
				continue
			definitions[kind][id]["options"] = replacement.duplicate(true)
		else:
			issues.append("%s is not an approved campus_mvp.v1 override" % location)


func _build_indexes(enabled: Dictionary, definitions: Dictionary) -> Dictionary:
	var indexes := {}
	for kind in CONTENT_KINDS:
		indexes[kind] = {}
		for id in enabled.get(kind, []):
			indexes[kind][id] = definitions[kind][id].duplicate(true)
	return indexes


func _enabled_definitions(indexes: Dictionary) -> Dictionary:
	var result := {}
	for kind in CONTENT_KINDS:
		result[kind] = {}
		var ids: Array = indexes[kind].keys()
		ids.sort()
		for id in ids:
			result[kind][id] = indexes[kind][id]
	return result


func _canonical_json(value: Variant) -> String:
	if _is_dictionary(value):
		var keys: Array = value.keys()
		keys.sort()
		var pairs: Array[String] = []
		for key in keys:
			pairs.append("%s:%s" % [JSON.stringify(str(key)), _canonical_json(value[key])])
		return "{%s}" % ",".join(pairs)
	if _is_array(value):
		var items: Array[String] = []
		for item in value:
			items.append(_canonical_json(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _validate_nested_object(
	value: Variant, allowed: Array, location: String, issues: Array[String]
) -> void:
	if not _is_dictionary(value):
		issues.append("%s must be an object" % location)
		return
	for key in value:
		if not allowed.has(key):
			issues.append("%s.%s is unknown" % [location, key])


func _validate_int(value: Variant, location: String, minimum: int, issues: Array[String]) -> void:
	if typeof(value) != TYPE_INT or value < minimum:
		issues.append("%s must be integer >= %d" % [location, minimum])


func _validate_bool(value: Variant, location: String, issues: Array[String]) -> void:
	if not _is_bool(value):
		issues.append("%s must be bool" % location)


func _validate_string_array(value: Variant, location: String, issues: Array[String]) -> void:
	if not _is_array(value):
		issues.append("%s must be an array" % location)
		return
	var seen := {}
	for item in value:
		if typeof(item) != TYPE_STRING or str(item).is_empty():
			issues.append("%s items must be non-empty strings" % location)
		elif seen.has(item):
			issues.append("%s has duplicate %s" % [location, item])
		seen[item] = true


func _validate_int_array(
	value: Variant, location: String, minimum: int, issues: Array[String]
) -> void:
	if not _is_array(value):
		issues.append("%s must be an array" % location)
		return
	var seen := {}
	for item in value:
		if typeof(item) != TYPE_INT or item < minimum:
			issues.append("%s items must be integer >= %d" % [location, minimum])
		elif seen.has(item):
			issues.append("%s has duplicate %s" % [location, item])
		seen[item] = true


func _is_safe_id(value: String) -> bool:
	if value in ["campus_mvp", "campus_v1"]:
		return true
	return not value.is_empty() and value.length() <= 100 and value.is_valid_identifier()


func _is_safe_token(value: String) -> bool:
	if value.is_empty() or value.length() > 100:
		return false
	for character in value:
		if not (
			character.is_valid_identifier()
			or character.is_valid_int()
			or character == "."
			or character == "-"
		):
			return false
	return true


func _is_dictionary(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY


func _is_array(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY


func _is_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL


func _content_error(message_key: String, details: Dictionary) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_CONTENT_INVALID, message_key, details)
	)


func _invalid_package(issues: Array[String]) -> GameResult:
	return _content_error("content.package.invalid", {"issues": issues})
