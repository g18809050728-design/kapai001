class_name TestRoomState
extends RefCounted

const CHECKPOINT_LIMIT := 50
const JOURNAL_LIMIT := 2000

var test_id: String = ""
var branch_id: int = 0
var revision: int = 0
var attempt: int = 1
var seed: String = "0"
var config: Dictionary = {}
var battle: BattleState
var pending_choice: ChoiceRequest
var rng: Dictionary = {}
var switches: Dictionary = {}
var overlay: TestOverlay
var result: Dictionary = {"source": "none", "outcome": "", "editable": true}
var paused: bool = false
var editing: bool = false
var interventions: int = 0
var dirty: bool = false
var journal: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []


func core_snapshot() -> Dictionary:
	return {
		"test_id": test_id,
		"branch_id": branch_id,
		"revision": revision,
		"attempt": attempt,
		"seed": seed,
		"config": config.duplicate(true),
		"battle": battle.to_dictionary() if battle != null else null,
		"pending_choice": choice_to_dictionary(pending_choice),
		"rng": rng.duplicate(true),
		"switches": switches.duplicate(true),
		"overlay": overlay.to_dictionary() if overlay != null else {},
		"result": result.duplicate(true),
		"paused": paused,
		"editing": editing,
		"interventions": interventions,
	}


static func from_core(snapshot: Dictionary) -> TestRoomState:
	var state := TestRoomState.new()
	state.test_id = str(snapshot.get("test_id", ""))
	state.branch_id = int(snapshot.get("branch_id", 0))
	state.revision = int(snapshot.get("revision", 0))
	state.attempt = int(snapshot.get("attempt", 1))
	state.seed = str(snapshot.get("seed", "0"))
	var config_value: Variant = snapshot.get("config", {})
	if typeof(config_value) == TYPE_DICTIONARY:
		state.config = config_value.duplicate(true)
	var battle_value: Variant = snapshot.get("battle")
	if typeof(battle_value) == TYPE_DICTIONARY:
		state.battle = BattleState.new(battle_value)
	state.pending_choice = choice_from_dictionary(snapshot.get("pending_choice"))
	var rng_value: Variant = snapshot.get("rng", {})
	if typeof(rng_value) == TYPE_DICTIONARY:
		state.rng = rng_value.duplicate(true)
	var switches_value: Variant = snapshot.get("switches", {})
	if typeof(switches_value) == TYPE_DICTIONARY:
		state.switches = switches_value.duplicate(true)
	state.overlay = TestOverlay.from_dictionary(snapshot.get("overlay", {}))
	var result_value: Variant = snapshot.get("result", {})
	if typeof(result_value) == TYPE_DICTIONARY:
		state.result = result_value.duplicate(true)
	state.paused = bool(snapshot.get("paused", false))
	state.editing = bool(snapshot.get("editing", false))
	state.interventions = int(snapshot.get("interventions", 0))
	return state


func copy() -> TestRoomState:
	var copied := TestRoomState.from_core(core_snapshot())
	copied.dirty = dirty
	copied.journal.assign(journal.duplicate(true))
	copied.checkpoints.assign(checkpoints.duplicate(true))
	copied.undo_stack.assign(undo_stack.duplicate(true))
	copied.redo_stack.assign(redo_stack.duplicate(true))
	return copied


func make_checkpoint(label: String, kind: String = "auto") -> Dictionary:
	var checkpoint := {
		"id": "cp-%d" % (checkpoints.size() + 1),
		"label": label,
		"kind": kind,
		"revision": revision,
		"branch_id": branch_id,
		"round_index": battle.round_index if battle != null else 0,
		"state": core_snapshot(),
	}
	checkpoints.append(checkpoint)
	while checkpoints.size() > CHECKPOINT_LIMIT:
		checkpoints.pop_front()
	return checkpoint


func append_journal(kind: String, summary: Dictionary, before_hash: String, after_hash: String) -> void:
	journal.append(
		{
			"seq": journal.size(),
			"kind": kind,
			"revision": revision,
			"branch_id": branch_id,
			"summary": summary.duplicate(true),
			"before_hash": before_hash,
			"after_hash": after_hash,
		}
	)
	while journal.size() > JOURNAL_LIMIT:
		journal.pop_front()


func state_hash() -> String:
	return SnapshotCodec.canonical_json(
		{
			"battle": battle.to_dictionary() if battle != null else null,
			"pending_choice": choice_to_dictionary(pending_choice),
			"rng": rng,
			"switches": switches,
			"overlay": {
				"definitions": overlay.definitions if overlay != null else {},
				"fields": overlay.fields if overlay != null else {},
			},
			"result": result,
		}
	).sha256_text()


func battle_hash() -> String:
	return (
		SnapshotCodec.canonical_json(battle.to_dictionary()).sha256_text()
		if battle != null
		else ""
	)


static func choice_to_dictionary(choice: ChoiceRequest) -> Variant:
	if choice == null:
		return null
	var candidates: Array[Dictionary] = []
	for option in choice.candidates:
		candidates.append(
			{
				"id": option.id,
				"label_key": option.label_key,
				"preview": option.preview.duplicate(true),
			}
		)
	return {
		"choice_id": choice.choice_id,
		"kind": String(choice.kind),
		"candidates": candidates,
		"min_count": choice.min_count,
		"max_count": choice.max_count,
		"prompt_key": choice.prompt_key,
		"source_card_id": choice.source_card_id,
		"effect_amount": choice.effect_amount,
	}


static func choice_from_dictionary(value: Variant) -> ChoiceRequest:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var candidates: Array[ChoiceOption] = []
	for raw in value.get("candidates", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var preview: Dictionary = raw.get("preview", {}) if raw.get("preview") is Dictionary else {}
		candidates.append(
			ChoiceOption.new(str(raw.get("id", "")), str(raw.get("label_key", "")), preview)
		)
	return ChoiceRequest.new(
		str(value.get("choice_id", "")),
		StringName(value.get("kind", "")),
		candidates,
		int(value.get("min_count", 0)),
		int(value.get("max_count", 0)),
		str(value.get("prompt_key", "")),
		value.get("source_card_id"),
		value.get("effect_amount")
	)
