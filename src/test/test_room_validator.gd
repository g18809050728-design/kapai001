class_name TestRoomValidator
extends RefCounted

## Test files share the production shapes and content validators, but retain
## sandbox permissions (extra cards/tasks, custom intents and frozen outcomes).
const CORE_FIELDS := {
	"test_id": TYPE_STRING, "branch_id": TYPE_INT, "revision": TYPE_INT,
	"attempt": TYPE_INT, "seed": TYPE_STRING, "config": TYPE_DICTIONARY,
	"battle": -1, "run": -1, "run_rng": TYPE_DICTIONARY,
	"pending_choice": -1, "rng": TYPE_DICTIONARY, "switches": TYPE_DICTIONARY,
	"overlay": TYPE_DICTIONARY, "result": TYPE_DICTIONARY,
	"paused": TYPE_BOOL, "editing": TYPE_BOOL, "interventions": TYPE_INT,
	"player_locks": TYPE_DICTIONARY, "pending_turn": TYPE_DICTIONARY,
	"relic_origins": TYPE_ARRAY,
}
const PHASES := [
	"player_prepare", "draw", "player_action", "ally_action", "discard",
	"enemy_prepare", "enemy_skill", "enemy_pressure", "player_action_end", "enemy_turn",
	"round_end", "awaiting_choice", "finished",
]
## Free navigation deliberately skips the normal campaign traversal history.
## Keep production validation for local shapes, identities and references, while
## excluding only the history invariants that sandbox node/year jumps bypass.
const SANDBOX_RUN_HISTORY_ISSUES := [
	"campaign generated years disagree with current year",
	"campaign completed year summaries missing",
	"campaign direction disagrees with decision history/year",
	"campaign destination disagrees with decision history/year",
	"run active node skips the first layer",
	"run active node is unreachable from path",
	"run path must start at the first layer",
	"run path contains an illegal edge",
]


static func validate_core(raw: Variant, source: ContentDB) -> Array[String]:
	var issues: Array[String] = []
	if not raw is Dictionary:
		issues.append("core must be an object")
		return issues
	var core: Dictionary = RunCodec.normalize_numbers(raw)
	RunCodec.shape(core, CORE_FIELDS, "core", issues, ["run", "run_rng", "player_locks", "pending_turn", "relic_origins"])
	RunCodec.json_tree(core, "core", issues)
	if not issues.is_empty():
		return issues
	if core.test_id.is_empty() or core.seed.is_empty():
		issues.append("core identity/seed is missing")
	for key in ["branch_id", "revision", "interventions"]:
		if core[key] < 0:
			issues.append("core.%s must not be negative" % key)
	if core.attempt < 1:
		issues.append("core.attempt must be positive")
	for key in core.switches:
		if not TestRoomService.SWITCHES.has(key) or not core.switches[key] is bool:
			issues.append("core.switches.%s is invalid" % key)
	for key in core.get("player_locks", {}):
		if not TestRoomService.PLAYER_FIELDS.has(key) or not core.player_locks[key] is bool:
			issues.append("core.player_locks.%s is invalid" % key)
	RunCodec.shape(core.get("pending_turn", {}), {"retained_card_ids": TYPE_ARRAY}, "core.pending_turn", issues, ["retained_card_ids"])
	if core.get("pending_turn", {}).get("retained_card_ids") is Array:
		RunCodec.strings(core.pending_turn.retained_card_ids, "core.pending_turn.retained_card_ids", issues)
	if core.has("relic_origins"):
		for origin in core.relic_origins:
			if not origin is String:
				issues.append("core.relic_origins must contain strings")
	RunCodec.shape(core.result, {"source": TYPE_STRING, "outcome": TYPE_STRING, "editable": TYPE_BOOL}, "core.result", issues)
	issues.append_array(validate_overlay_value(core.overlay, source))
	_check_rng(core.rng, "core.rng", issues)
	if core.pending_choice != null:
		issues.append("core.pending_choice cannot be restored from a stable test file")
	if core.battle != null:
		if not core.battle is Dictionary:
			issues.append("core.battle must be an object or null")
		else:
			var battle_record: Dictionary = core.battle.duplicate(true)
			# Earlier manual outcomes omitted these production-only report fields.
			if battle_record.get("outcome") is Dictionary:
				if not battle_record.outcome.has("reason"):
					battle_record.outcome["reason"] = ""
				if not battle_record.outcome.has("summary"):
					battle_record.outcome["summary"] = {}
			var battle_issues := BattleCodec._validate_structure(battle_record)
			for issue in battle_issues:
				if bool(core.switches.get("ignore_relic_unique", false)) and battle_record.get("relics") is Array and _relic_duplicate_issue(issue, "battle.relics", battle_record.relics):
					continue
				issues.append(issue)
			if core.battle.get("resolution") != null or (core.battle.get("phase") is String and core.battle.phase == "awaiting_choice"):
				issues.append("core.battle must be at a stable boundary")
			_check_v3(core.battle.get("v3", {}), issues)
	if core.get("run") != null:
		if not core.run is Dictionary:
			issues.append("core.run must be an object or null")
		else:
			issues.append_array(RunCodec._validate_structure(core.run))
			_check_rng(core.get("run_rng", {}), "core.run_rng", issues)
	if core.battle == null and core.get("run") == null:
		issues.append("core requires a battle or campus run")
	if not issues.is_empty():
		return issues
	# Construction only happens after the complete raw shape is safe.
	issues.append_array(validate_state(TestRoomState.from_core(core), source))
	return issues


static func validate_overlay_value(raw: Variant, source: ContentDB) -> Array[String]:
	var issues: Array[String] = []
	if not raw is Dictionary:
		issues.append("overlay must be an object")
		return issues
	RunCodec.shape(raw, {"definitions": TYPE_DICTIONARY, "fields": TYPE_DICTIONARY, "hash": TYPE_STRING}, "overlay", issues, ["definitions", "fields", "hash"])
	if not issues.is_empty():
		return issues
	for bucket in ["definitions", "fields"]:
		for kind in raw.get(bucket, {}):
			if not TestOverlay.KINDS.has(kind) or not raw[bucket][kind] is Dictionary:
				issues.append("overlay.%s.%s is invalid" % [bucket, kind])
				continue
			for id in raw[bucket][kind]:
				if not id is String or not TestOverlay._is_safe_id(id) or not raw[bucket][kind][id] is Dictionary:
					issues.append("overlay.%s.%s definition/id is invalid" % [bucket, kind])
					continue
				if bucket == "definitions":
					if not id.begins_with("TEST.") or id.length() > 64 or raw[bucket][kind][id].get("id") != id:
						issues.append("overlay.definitions.%s.%s identity is invalid" % [kind, id])
				else:
					for path in raw[bucket][kind][id]:
						if not path is String or not TestOverlay.FIELDS[kind].has(path.get_slice(".", 0)):
							issues.append("overlay.fields.%s.%s path is unsupported" % [kind, id])
	if issues.is_empty():
		var overlay := TestOverlay.from_dictionary(raw)
		if not str(raw.get("hash", "")).is_empty() and raw.hash != overlay.hash:
			issues.append("overlay.hash disagrees with definitions/fields")
		issues.append_array(validate_overlay(overlay, source))
	return issues


static func validate_definition(kind: String, id: String, definition: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not TestOverlay.KINDS.has(kind):
		issues.append("definition kind is invalid: " + kind)
		return issues
	var value := _legacy_defaults(kind, definition)
	var validator := ContentDB.new()
	# Full runtime schema validates operation registries, nested fields and ranges.
	validator._validate_fields(value, ContentDB.DEFINITION_FIELDS[kind], ContentDB.REQUIRED_FIELDS[kind], "%s/%s" % [kind, id], issues)
	validator._validate_definition(kind, value, "%s/%s" % [kind, id], issues, true)
	_check_effect_scalars(value, "%s/%s" % [kind, id], issues)
	if kind == "ruleset":
		_check_rule_values(value, "", issues)
	RunCodec.json_tree(value, "%s/%s" % [kind, id], issues)
	return issues


static func validate_overlay(overlay: TestOverlay, source: ContentDB) -> Array[String]:
	var issues: Array[String] = []
	if source == null:
		issues.append("overlay base catalog is missing")
		return issues
	if overlay.is_empty():
		return issues
	var merged: Dictionary = source._definitions.duplicate(true)
	var enabled: Dictionary = source._enabled.duplicate(true)
	var changed := {}
	for bucket in [overlay.definitions, overlay.fields]:
		for kind in bucket:
			if not TestOverlay.KINDS.has(kind):
				issues.append("overlay kind is invalid: " + str(kind))
				continue
			if not changed.has(kind):
				changed[kind] = {}
			for id in bucket[kind]:
				changed[kind][id] = true
	for kind in changed:
		if not merged.has(kind):
			merged[kind] = {}
		if not enabled.has(kind):
			enabled[kind] = []
		for id in changed[kind]:
			var base: Dictionary = merged[kind].get(id, {})
			if base.is_empty() and not overlay.definitions.get(kind, {}).has(id):
				issues.append("overlay.fields.%s.%s definition is missing" % [kind, id])
				continue
			var path_base: Dictionary = overlay.definitions.get(kind, {}).get(id, base)
			for path in overlay.fields.get(kind, {}).get(id, {}):
				if not _valid_path(path_base, path):
					issues.append("overlay.fields.%s.%s.%s path is invalid" % [kind, id, path])
			var value := overlay.apply(kind, id, base)
			issues.append_array(validate_definition(kind, id, value))
			if kind == "ruleset":
				_check_shape_like(value, base, "ruleset/" + str(id), issues)
			merged[kind][id] = value
			if not enabled[kind].has(id):
				enabled[kind].append(id)
	if issues.is_empty():
		source._validate_enabled_references(enabled, merged, issues)
	return issues


static func _valid_path(value: Variant, path: String) -> bool:
	if path.is_empty() or path.begins_with(".") or path.ends_with(".") or path.contains(".."):
		return false
	var current: Variant = value
	for segment in path.split(".", false):
		if current is Array:
			if not segment.is_valid_int() or str(int(segment)) != segment or int(segment) < 0 or int(segment) >= current.size():
				return false
			current = current[int(segment)]
		elif current is Dictionary:
			current = current.get(segment, {})
		else:
			return false
	return true


static func _check_shape_like(value: Variant, template: Variant, path: String, issues: Array[String]) -> void:
	if typeof(value) != typeof(template):
		issues.append(path + " has wrong rule value type")
		return
	if value is Dictionary:
		for key in value:
			if template.has(key):
				_check_shape_like(value[key], template[key], path + "." + str(key), issues)
	elif value is Array and not template.is_empty():
		for item in value:
			_check_shape_like(item, template[0], path + "[]", issues)


static func _check_rule_values(value: Variant, path: String, issues: Array[String]) -> void:
	if value is Dictionary:
		for key in value:
			_check_rule_values(value[key], path + "." + str(key), issues)
	elif value is Array:
		for entry in value:
			_check_rule_values(entry, path + "[]", issues)
	elif path != ".id" and path != ".run.common_starter_cards[]" and not value is int:
		issues.append("ruleset%s must be an integer" % path)


static func _check_effect_scalars(value: Variant, path: String, issues: Array[String]) -> void:
	if value is Dictionary:
		if value.has("op"):
			for key in ["amount", "count", "stacks", "times", "cost"]:
				if not value.has(key):
					continue
				var scalar: Variant = value[key]
				# The draw handler explicitly supports this authored expression.
				if key == "amount" and str(value.op) == "draw" and scalar is Dictionary and scalar == {"ref": "actual_discarded"}:
					continue
				if not scalar is int or scalar < 0:
					issues.append("%s.%s must be a non-negative integer" % [path, key])
		for key in value:
			_check_effect_scalars(value[key], path + "." + str(key), issues)
	elif value is Array:
		for i in value.size():
			_check_effect_scalars(value[i], "%s[%d]" % [path, i], issues)


static func validate_state(state: TestRoomState, source: ContentDB) -> Array[String]:
	var issues := validate_overlay(state.overlay, source)
	if not issues.is_empty():
		return issues
	var wrapped := TestContent.new(source, state.overlay)
	issues.append_array(_relic_origin_links(state.relic_origins, state.battle, state.run))
	if state.battle != null:
		var battle := state.battle
		issues.append_array(_battle_links(battle))
		if not PHASES.has(battle.phase):
			issues.append("battle.phase is invalid")
		RunCodec._reference(wrapped, "character", battle.character_id, "battle.character_id", issues)
		RunCodec._reference(wrapped, "encounter", battle.encounter_id, "battle.encounter_id", issues)
		var encounter := wrapped.get_definition("encounter", battle.encounter_id)
		if encounter.ok and battle.exam_flags != encounter.data.get("exam_flags", []):
			issues.append("battle.exam_flags disagree with encounter")
		for id in battle.retained_card_ids:
			if not battle.zones.get("hand", []).has(id):
				issues.append("battle retained card is not in hand: " + id)
		for card in battle.card_by_id.values():
			RunCodec._reference(wrapped, "card", str(card.get("definition_id", "")), "battle.card_by_id", issues)
		for task in battle.tasks:
			var definition := wrapped.get_definition("task", str(task.get("definition_id", "")))
			if not definition.ok:
				issues.append("battle.tasks definition is missing")
			else:
				var found := false
				for phase in definition.data.get("phases", []):
					if phase.get("phase_key") == task.get("phase_key"):
						found = true
				if not found:
					issues.append("battle.tasks phase_key is missing: " + str(task.get("phase_key")))
		for unit in battle.units:
			RunCodec._reference(wrapped, "unit", str(unit.get("definition_id", "")), "battle.units", issues)
		for status in battle.statuses:
			RunCodec._reference(wrapped, "status", str(status.get("status_id", "")), "battle.statuses", issues)
		for id in battle.relics:
			RunCodec._reference(wrapped, "relic", id, "battle.relics", issues)
		for entry in battle.source_registry.values():
			RunCodec._reference(wrapped, str(entry.get("kind", "")), str(entry.get("definition_id", "")), "battle.source_registry", issues)
		if battle.scene is Dictionary:
			RunCodec._reference(wrapped, "scene", str(battle.scene.get("definition_id", "")), "battle.scene", issues)
	if state.run != null:
		var run_result := RunCodec.decode(state.run.to_dictionary(), wrapped)
		if not run_result.ok:
			var run_issues: Array = run_result.error.details.get("issues", [])
			if run_issues.is_empty():
				issues.append("run is invalid: " + str(run_result.error.details))
			for issue in run_issues:
				if not _sandbox_run_issue(str(issue), state):
					issues.append("run is invalid: " + str(issue))
	return issues


static func _sandbox_run_issue(issue: String, state: TestRoomState) -> bool:
	if SANDBOX_RUN_HISTORY_ISSUES.has(issue):
		return true
	if bool(state.switches.get("ignore_relic_slots", false)):
		if issue == "run relic capacity exceeded":
			return true
		if issue == "run relic slot is invalid or repeated":
			# Production combines the upper bound with negative/repeated slots.
			# The switch bypasses only the upper bound, preserving slot identity.
			var occupied := {}
			for relic in state.run.relics:
				var slot := int(relic.get("slot", -1))
				if slot < 0 or occupied.has(slot):
					return false
				occupied[slot] = true
			return true
	if bool(state.switches.get("ignore_relic_unique", false)):
		for relic in state.run.relics:
			var id := str(relic.get("definition_id", ""))
			if not id.is_empty() and issue == "run.relic.definition must be nonempty and unique: " + id:
				return true
	return false


static func _relic_duplicate_issue(issue: String, path: String, ids: Array) -> bool:
	for id in ids:
		if id is String and not id.is_empty() and issue == path + " must be nonempty and unique: " + id:
			return true
	return false


static func _relic_origin_links(origins: Array, battle: BattleState, run: RunState) -> Array[String]:
	var issues: Array[String] = []
	var count := 0 if battle == null else battle.relics.size()
	if origins.size() != count:
		issues.append("relic_origins must align with battle.relics")
		return issues
	var known := {}
	if run != null:
		for relic in run.relics:
			known[str(relic.get("relic_id", ""))] = str(relic.get("definition_id", ""))
	var seen := {}
	for i in origins.size():
		var id: Variant = origins[i]
		if not id is String:
			issues.append("relic_origins must contain strings")
			continue
		if id.is_empty():
			continue
		if seen.has(id):
			issues.append("relic_origins nonempty instance IDs must be unique")
		seen[id] = true
		if not known.has(id) or known[id] != battle.relics[i]:
			issues.append("relic_origins must reference a matching run relic instance")
	return issues


static func _battle_links(battle: BattleState) -> Array[String]:
	var issues: Array[String] = []
	if battle.round_index < 1 or battle.ddl < 0 or battle.next_instance_seq < 1 or battle.next_creation_order < 1:
		issues.append("battle sequence/DDL is invalid")
	if int(battle.player.get("max_vitality", 0)) < 1 or int(battle.player.get("vitality", -1)) < 0 or int(battle.player.get("vitality", 0)) > int(battle.player.get("max_vitality", 0)):
		issues.append("battle player vitality is invalid")
	for key in ["focus", "relax"]:
		if int(battle.player.get(key, -1)) < 0:
			issues.append("battle player resource is invalid: " + key)
	var zoned := {}
	for ids in battle.zones.values():
		for id in ids:
			if zoned.has(id) or not battle.card_by_id.has(id):
				issues.append("battle zone references a missing/duplicated card: " + str(id))
			zoned[id] = true
	for chapter in battle.v3.get("paper", {}).get("chapters", []):
		var id: String = chapter.card_id
		if zoned.has(id) or not battle.card_by_id.has(id):
			issues.append("battle chapter references a missing/duplicated card: " + id)
		zoned[id] = true
	for id in battle.card_by_id:
		if not zoned.has(id) or battle.card_by_id[id].get("card_id") != id:
			issues.append("battle card instance/zone disagrees: " + str(id))
	var holders := {str(battle.player.get("entity_id", "")): true}
	for unit in battle.units:
		var id: String = unit.unit_id
		if id.is_empty() or holders.has(id):
			issues.append("battle unit id is missing/duplicated")
		holders[id] = true
		if unit.vitality < 0 or unit.vitality > unit.max_vitality or unit.cooperation < 0 or int(unit.get("relax", 0)) < 0:
			issues.append("battle unit resources are invalid")
	for task in battle.tasks:
		var id: String = task.task_id
		if id.is_empty() or holders.has(id):
			issues.append("battle task id is missing/duplicated")
		holders[id] = true
		if task.work_max < 1 or task.work_remaining < 0 or task.work_remaining > task.work_max or task.shield < 0 or task.eligible_round < 1:
			issues.append("battle task resources are invalid")
	var pairs := {}
	for status in battle.statuses:
		var pair: String = "%s/%s" % [status.status_id, status.target_id]
		if not holders.has(status.target_id) or pairs.has(pair) or status.stacks < 1 or not battle.source_registry.has(status.instance_id):
			issues.append("battle status holder/source/stacks is invalid")
		pairs[pair] = true
	var orders := {}
	for source in battle.source_registry.values():
		if source.creation_order < 1 or source.creation_order >= battle.next_creation_order or orders.has(source.creation_order):
			issues.append("battle source creation order is invalid/duplicated")
		orders[source.creation_order] = true
	if battle.outcome is Dictionary and (battle.outcome.battle_id != battle.battle_id or not battle.outcome.result in ["won", "lost"]):
		issues.append("battle outcome is invalid")
	return issues


static func _check_rng(value: Variant, path: String, issues: Array[String]) -> void:
	if not RandomSource.new().restore_state(value).ok:
		issues.append(path + " is invalid")


static func _check_v3(value: Variant, issues: Array[String]) -> void:
	if not value is Dictionary:
		issues.append("battle.v3 must be an object")
		return
	if value.has("paper"):
		if not value.paper is Dictionary or not value.paper.get("chapters", []) is Array:
			issues.append("battle.v3.paper.chapters must be an array")
		else:
			for chapter in value.paper.get("chapters", []):
				if not chapter is Dictionary or not chapter.get("card_id") is String:
					issues.append("battle.v3.paper.chapters entry is invalid")
	if value.has("abilities") and not value.abilities is Array:
		issues.append("battle.v3.abilities must be an array")


static func _legacy_defaults(kind: String, definition: Dictionary) -> Dictionary:
	# The original sandbox accepted compact custom cards/tasks. Apply omitted
	# presentation/schema defaults only while validating, preserving stored bytes.
	# JSON editors deserialize integer literals as floats. Canonicalize integral
	# values before strict schema checks; fractional values remain invalid.
	var value: Dictionary = RunCodec.normalize_numbers(definition)
	if kind == "card" and not value.has("rarity"):
		value["v3"] = true
		value["rarity"] = "token"
		if not value.has("tags"):
			value["tags"] = []
		if not value.has("exhaust"):
			value["exhaust"] = false
	if kind == "task":
		if not value.has("kind"):
			value["kind"] = "normal"
		if value.get("phases") is Array:
			for phase in value.phases:
				if not phase is Dictionary or not phase.get("intents") is Array:
					continue
				for i in phase.intents.size():
					if not phase.intents[i] is Dictionary:
						continue
					if not phase.intents[i].has("index"):
						phase.intents[i]["index"] = i
					if not phase.intents[i].has("text_key"):
						phase.intents[i]["text_key"] = str(value.get("name_key", value.get("id", "test")))
	return value
