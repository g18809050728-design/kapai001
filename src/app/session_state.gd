class_name SessionState
extends RefCounted

var revision: int = 0
var run: RunState
var battle: BattleState
var random_snapshot: Dictionary = {}
var terminal_summary: Variant = null
var profile_merge_pending: bool = false
var event_log: Array[Dictionary] = []
var pending_choice: ChoiceRequest


func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	if run == null:
		issues.append("session.run is required")
		return issues
	if revision < 0:
		issues.append("session.revision must be nonnegative")
	var rng := RandomSource.new()
	if not rng.restore_state(random_snapshot).ok:
		issues.append("session random snapshot is invalid")
	if pending_choice != null or (battle != null and battle.resolution != null):
		issues.append("session must be stable")
	if battle == null:
		if not run.active_battle_id.is_empty() or not run.active_encounter_id.is_empty():
			issues.append("active battle reference is missing")
	else:
		if (
			battle.battle_id != run.active_battle_id
			or battle.encounter_id != run.active_encounter_id
			or battle.node_id != run.current_node_id
		):
			issues.append("battle does not match active run node")
		if battle.character_id != run.character_id or battle.difficulty != run.difficulty:
			issues.append("battle character or difficulty mismatch")
		if run.settled_battle_ids.has(battle.battle_id) or not run.outcome.is_empty():
			issues.append("settled battle must not remain active")
		var permanent_ids := {}
		for card in run.cards:
			permanent_ids[card.card_id] = true
		var origins := {}
		for card in battle.card_by_id.values():
			var origin: Variant = card.get("origin_card_id")
			if origin != null and not str(origin).is_empty():
				if not permanent_ids.has(origin) or origins.has(origin):
					issues.append("battle card origin is missing or repeated")
				origins[origin] = true
	if terminal_summary != null:
		if not terminal_summary is RunSummary:
			issues.append("terminal summary must be RunSummary")
		elif (
			terminal_summary.run_id != run.run_id
			or terminal_summary.result != run.outcome
			or terminal_summary.character_id != run.character_id
			or terminal_summary.manifest_id != run.manifest_id
			or terminal_summary.term != run.term
			or terminal_summary.difficulty != run.difficulty
		):
			issues.append("terminal summary does not match finalized run")
		if run.outcome.is_empty() or run.awaiting_ending:
			issues.append("summary requires a finalized run")
	elif profile_merge_pending or not run.outcome.is_empty():
		issues.append("finalized run or pending profile requires summary")
	if event_log.size() > GameSession.EVENT_LOG_LIMIT:
		issues.append("event log exceeds limit")
	var previous_revision := -1
	var previous_index := -1
	var fields := [
		"run_id",
		"revision",
		"index",
		"type",
		"source_id",
		"target_ids",
		"data",
		"source_label",
		"target_labels"
	]
	for entry in event_log:
		for key in fields:
			if not entry.has(key):
				issues.append("event log field is required: " + key)
		for key in entry:
			if not fields.has(key):
				issues.append("unknown event log field: " + str(key))
		if (
			entry.get("run_id") != run.run_id
			or not entry.get("revision") is int
			or not entry.get("index") is int
		):
			issues.append("event log run or cursor is invalid")
			continue
		if (
			entry.revision < 0
			or entry.revision > revision
			or entry.index < 0
			or entry.revision < previous_revision
			or (entry.revision == previous_revision and entry.index <= previous_index)
		):
			issues.append("event log order is invalid")
		previous_revision = entry.revision
		previous_index = entry.index
		for key in ["type", "source_id", "source_label"]:
			if not entry.get(key) is String:
				issues.append("event log %s must be a string" % key)
		if not entry.get("data") is Dictionary:
			issues.append("event log data must be an object")
		for key in ["target_ids", "target_labels"]:
			if not entry.get(key) is Array:
				issues.append("event log %s must be an array" % key)
			else:
				for item in entry[key]:
					if not item is String:
						issues.append("event log targets must be strings")
		if (
			entry.get("target_ids") is Array
			and entry.get("target_labels") is Array
			and entry.target_ids.size() != entry.target_labels.size()
		):
			issues.append("event log target labels mismatch")
	return issues


func copy_for_write() -> SessionState:
	var result := SessionState.new()
	result.revision = revision
	result.run = run.copy_for_write() if run != null else null
	result.battle = battle.copy() if battle != null else null
	result.random_snapshot = random_snapshot.duplicate(true)
	result.terminal_summary = terminal_summary.copy() if terminal_summary != null else null
	result.profile_merge_pending = profile_merge_pending
	result.event_log.assign(event_log.duplicate(true))
	result.pending_choice = pending_choice.copy() if pending_choice != null else null
	return result
