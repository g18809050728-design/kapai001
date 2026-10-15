class_name BattleCodec
extends RefCounted

const FIELDS := {
	"battle_id": TYPE_STRING,
	"node_id": TYPE_STRING,
	"encounter_id": TYPE_STRING,
	"character_id": TYPE_STRING,
	"difficulty": TYPE_STRING,
	"exam_flags": TYPE_ARRAY,
	"phase": TYPE_STRING,
	"round_index": TYPE_INT,
	"ddl": TYPE_INT,
	"player": TYPE_DICTIONARY,
	"card_by_id": TYPE_DICTIONARY,
	"relics": TYPE_ARRAY,
	"zones": TYPE_DICTIONARY,
	"units": TYPE_ARRAY,
	"tasks": TYPE_ARRAY,
	"statuses": TYPE_ARRAY,
	"retained_card_ids": TYPE_ARRAY,
	"scene": -1,
	"counters": TYPE_DICTIONARY,
	"resolution": -1,
	"outcome": -1,
	"next_creation_order": TYPE_INT,
	"next_instance_seq": TYPE_INT,
	"source_registry": TYPE_DICTIONARY,
}
const PLAYER_FIELDS := {
	"entity_id": TYPE_STRING,
	"vitality": TYPE_INT,
	"max_vitality": TYPE_INT,
	"relax": TYPE_INT,
	"focus": TYPE_INT,
}
const CARD_FIELDS := {
	"card_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"origin_card_id": TYPE_STRING,
	"upgrade_level": TYPE_INT,
	"temporary_modifiers": TYPE_DICTIONARY,
}
const TASK_FIELDS := {
	"task_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"phase_key": TYPE_STRING,
	"work_remaining": TYPE_INT,
	"work_max": TYPE_INT,
	"shield": TYPE_INT,
	"intent_cursor": TYPE_INT,
	"intent_snapshot": TYPE_DICTIONARY,
	"entered_order": TYPE_INT,
	"eligible_round": TYPE_INT,
}
const UNIT_FIELDS := {
	"id": TYPE_STRING,
	"name_key": TYPE_STRING,
	"vitality": TYPE_INT,
	"cooperation": TYPE_INT,
	"guard": TYPE_BOOL,
	"support": TYPE_DICTIONARY,
	"entry_effects": TYPE_ARRAY,
	"art_key": TYPE_STRING,
	"unit_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"max_vitality": TYPE_INT,
	"entered_order": TYPE_INT,
	"actions_taken": TYPE_INT,
	"target_id": TYPE_STRING,
	"relax": TYPE_INT,
	"support_replaces_cooperation": TYPE_BOOL,
}
const STATUS_FIELDS := {
	"status_id": TYPE_STRING,
	"instance_id": TYPE_STRING,
	"source_id": TYPE_STRING,
	"target_id": TYPE_STRING,
	"stacks": TYPE_INT,
	"expiry": TYPE_STRING,
}
const SCENE_FIELDS := {
	"scene_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"established_round": TYPE_INT,
	"pending_random_result": -2,
}


static func encode(state: BattleState) -> GameResult:
	if state == null:
		return RunCodec.corrupt(["battle is required"])
	if state.resolution != null or state.phase == "awaiting_choice":
		return GameResult.failure(
			ApiError.new(GameConstants.ERROR_CHOICE_PENDING, "save.battle.choice_pending")
		)
	var record := state.to_dictionary()
	var issues := _validate_structure(record)
	if not issues.is_empty():
		return RunCodec.corrupt(issues)
	issues.append_array(state.validate())
	return GameResult.success(record) if issues.is_empty() else RunCodec.corrupt(issues)


static func decode(data: Dictionary, catalog: ContentDB) -> GameResult:
	var record: Dictionary = RunCodec.normalize_numbers(data)
	var issues := _validate_structure(record)
	if not issues.is_empty():
		return RunCodec.corrupt(issues)
	if record.resolution != null or record.phase == "awaiting_choice":
		return RunCodec.corrupt(["stable battle cannot contain resolution"])
	if catalog == null or catalog.get_info() == null:
		return RunCodec.missing(["catalog is not loaded"])
	var references: Array[String] = []
	RunCodec._reference(
		catalog, "character", record.character_id, "battle.character_id", references
	)
	RunCodec._reference(
		catalog, "encounter", record.encounter_id, "battle.encounter_id", references
	)
	for id in record.relics:
		RunCodec._reference(catalog, "relic", id, "battle.relics", references)
	for card in record.card_by_id.values():
		RunCodec._reference(catalog, "card", card.definition_id, "battle.card_by_id", references)
	for unit in record.units:
		RunCodec._reference(catalog, "unit", unit.definition_id, "battle.units", references)
	for task in record.tasks:
		RunCodec._reference(catalog, "task", task.definition_id, "battle.tasks", references)
	for status in record.statuses:
		RunCodec._reference(catalog, "status", status.status_id, "battle.statuses", references)
	if record.scene != null:
		RunCodec._reference(
			catalog, "scene", record.scene.definition_id, "battle.scene", references
		)
	for source in record.source_registry.values():
		RunCodec._reference(
			catalog, source.kind, source.definition_id, "battle.source_registry", references
		)
	if not references.is_empty():
		return RunCodec.missing(references)
	var rules: Dictionary = catalog.get_definition("ruleset", catalog.get_info().ruleset_id).data
	if not rules.difficulty_overrides.has(record.difficulty):
		issues.append("battle difficulty is unknown")
	var encounter: Dictionary = catalog.get_definition("encounter", record.encounter_id).data
	if record.exam_flags != encounter.exam_flags:
		issues.append("battle exam flags disagree with encounter")
	if record.player.focus > int(rules.battle.focus_cap):
		issues.append("battle player focus exceeds cap")
	if record.zones.hand.size() > int(rules.battle.hand_limit):
		issues.append("battle hand capacity exceeded")
	if record.relics.size() > int(rules.run.relic_slots):
		issues.append("battle relic capacity exceeded")
	for card in record.card_by_id.values():
		if card.upgrade_level < 0 or card.upgrade_level > int(rules.run.max_card_upgrades):
			issues.append("battle card upgrade exceeds cap")
		if (
			card.upgrade_level > 0
			and not catalog.get_definition("card", card.definition_id).data.has("upgrade")
		):
			issues.append("battle upgraded card has no upgrade definition")
	for task in record.tasks:
		_validate_task_content(task, encounter, catalog, issues)
	for unit in record.units:
		var definition: Dictionary = catalog.get_definition("unit", unit.definition_id).data
		for key in definition:
			if key not in ["vitality", "cooperation"] and unit.get(key) != definition[key]:
				issues.append("battle unit definition snapshot differs at " + str(key))
	for status in record.statuses:
		var cap := int(rules.statuses.get(status.status_id, {"cap": 1}).get("cap", 2147483647))
		if status.stacks > cap:
			issues.append("battle status stacks exceed cap")
		var definition: Dictionary = catalog.get_definition("status", status.status_id).data
		var holders: Array = []
		match str(definition.target):
			"player":
				holders.append(record.player.entity_id)
			"unit":
				for unit in record.units:
					holders.append(unit.unit_id)
			"task":
				for task in record.tasks:
					holders.append(task.task_id)
		if not holders.has(status.target_id):
			issues.append("battle status holder type disagrees with definition")
	if record.scene != null:
		_validate_scene_content(record.scene, catalog, issues)
	if not issues.is_empty():
		return RunCodec.corrupt(issues)
	var state := BattleState.new(record)
	issues.append_array(state.validate(int(rules.battle.unit_slots)))
	return GameResult.success(state) if issues.is_empty() else RunCodec.corrupt(issues)


static func _validate_structure(data: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	RunCodec.shape(data, FIELDS, "battle", issues)
	if not issues.is_empty():
		return issues
	RunCodec.shape(data.player, PLAYER_FIELDS, "battle.player", issues)
	RunCodec.shape(
		data.zones,
		{
			"draw": TYPE_ARRAY,
			"hand": TYPE_ARRAY,
			"discard": TYPE_ARRAY,
			"exhaust": TYPE_ARRAY,
			"resolving": TYPE_ARRAY
		},
		"battle.zones",
		issues
	)
	for zone in data.zones.values():
		RunCodec.strings(zone, "battle.zone", issues)
	for key in ["exam_flags", "relics", "retained_card_ids"]:
		RunCodec.strings(data[key], "battle." + key, issues)
	for id in data.card_by_id:
		if typeof(id) != TYPE_STRING:
			issues.append("battle.card_by_id key must be string")
		RunCodec.shape(data.card_by_id[id], CARD_FIELDS, "battle.card_by_id[]", issues)
	for task in data.tasks:
		RunCodec.shape(task, TASK_FIELDS, "battle.tasks[]", issues)
	for unit in data.units:
		RunCodec.shape(
			unit,
			UNIT_FIELDS,
			"battle.units[]",
			issues,
			["entry_effects", "art_key", "relax", "support_replaces_cooperation"]
		)
	for status in data.statuses:
		RunCodec.shape(status, STATUS_FIELDS, "battle.statuses[]", issues)
	for id in data.source_registry:
		if typeof(id) != TYPE_STRING or str(id).is_empty():
			issues.append("battle.source_registry key must be nonempty string")
		RunCodec.shape(
			data.source_registry[id],
			{"kind": TYPE_STRING, "definition_id": TYPE_STRING, "creation_order": TYPE_INT},
			"battle.source_registry[]",
			issues
		)
	for value in data.counters.values():
		if typeof(value) != TYPE_INT or value < 0:
			issues.append("battle.counters must contain non-negative integers")
	if data.scene != null:
		if typeof(data.scene) != TYPE_DICTIONARY:
			issues.append("battle.scene must be object or null")
		else:
			var scene_fields := SCENE_FIELDS.duplicate()
			scene_fields.erase("pending_random_result")
			scene_fields["pending_random_result"] = (
				TYPE_NIL if data.scene.get("pending_random_result") == null else TYPE_ARRAY
			)
			RunCodec.shape(data.scene, scene_fields, "battle.scene", issues)
	if data.outcome != null:
		RunCodec.shape(
			data.outcome,
			{
				"battle_id": TYPE_STRING,
				"result": TYPE_STRING,
				"reason": TYPE_STRING,
				"remaining_vitality": TYPE_INT,
				"summary": TYPE_DICTIONARY
			},
			"battle.outcome",
			issues
		)
	RunCodec.json_tree(data, "battle", issues)
	return issues


static func _validate_task_content(
	task: Dictionary, encounter: Dictionary, catalog: ContentDB, issues: Array[String]
) -> void:
	if not encounter.members.has(task.definition_id):
		issues.append("battle task is not a member of encounter")
	var definition: Dictionary = catalog.get_definition("task", task.definition_id).data
	var phase: Dictionary = {}
	for candidate in definition.phases:
		if candidate.phase_key == task.phase_key:
			phase = candidate
	if phase.is_empty():
		issues.append("battle task phase is unknown")
		return
	if task.work_max != phase.work_max:
		issues.append("battle task work_max disagrees with phase")
	var intents: Array = phase.intents
	if task.intent_cursor < 0 or task.intent_cursor >= intents.size():
		issues.append("battle intent cursor is outside the phase")
	elif task.intent_snapshot != intents[task.intent_cursor]:
		issues.append("battle frozen intent disagrees with cursor")


static func _validate_scene_content(
	scene: Dictionary, catalog: ContentDB, issues: Array[String]
) -> void:
	var definition: Dictionary = catalog.get_definition("scene", scene.definition_id).data
	if definition.has("prepare_random"):
		if not definition.prepare_random.options.has(scene.pending_random_result):
			issues.append("battle scene frozen random result is not an option")
	elif scene.pending_random_result != null:
		issues.append("battle scene has unexpected frozen random result")
