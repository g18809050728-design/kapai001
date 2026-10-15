class_name GameSession
extends Node

const BATTLE_ACTIONS := [&"play_card", &"end_turn", &"confirm_choice", &"set_ally_target"]
const PRODUCTION_MANIFESTS := ["campus_mvp"]
const EVENT_LOG_LIMIT := 1000

var _catalog: ContentDB
var _run_service: RunService
var _battle_engine: BattleEngine
var _state: SessionState
var _store: SaveStore
var _catalog_factory: Callable
var _autosave: bool = true
var _settings_error: ApiError
var _last_receipt: SaveReceipt
var _profile_status: Dictionary = {}


func _init(store: SaveStore = null, catalog_factory: Callable = Callable()) -> void:
	_store = store if store != null else SaveStore.new()
	_catalog_factory = catalog_factory
	var settings := _store.load("settings")
	if settings.ok:
		var decoded := SnapshotCodec.decode_document(settings.data, "settings")
		if decoded.ok and _valid_settings(decoded.data.payload):
			_autosave = decoded.data.payload.autosave
		else:
			_settings_error = (
				decoded.error
				if not decoded.ok
				else ApiError.new(GameConstants.ERROR_SAVE_CORRUPT, "error.settings.invalid")
			)
	elif settings.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
		_settings_error = settings.error
	else:
		var backup := _store.load_backup("settings")
		if backup.ok:
			_settings_error = ApiError.new(
				GameConstants.ERROR_SAVE_CORRUPT, "error.settings.backup_requires_recovery"
			)
		elif backup.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
			_settings_error = backup.error


func _is_manifest_allowed(manifest_id: String) -> bool:
	return PRODUCTION_MANIFESTS.has(manifest_id)


func _load_catalog(manifest_id: String) -> GameResult:
	if not _is_manifest_allowed(manifest_id):
		return _failure(GameConstants.ERROR_VERSION_MISMATCH, "error.run.manifest")
	var candidate: ContentDB = (
		_catalog_factory.call() if _catalog_factory.is_valid() else ContentDB.new()
	)
	var loaded := candidate.load(manifest_id)
	return GameResult.success(candidate) if loaded.ok else loaded


func start_run(request: StartRunRequest) -> ActionResult:
	if _state != null:
		return _reject(GameConstants.ERROR_RUN_ACTIVE, "error.run.active")
	if (
		request == null
		or not _is_manifest_allowed(request.manifest_id)
		or request.difficulty != &"normal"
	):
		return _reject(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.manifest")
	var previous := _store.load("current_run")
	if previous.ok:
		var previous_catalog := _load_catalog(previous.data.manifest_id)
		if not previous_catalog.ok:
			return ActionResult.rejected(previous_catalog.error, get_view())
		var previous_session := SnapshotCodec.decode_session(previous.data, previous_catalog.data)
		if not previous_session.ok:
			return ActionResult.rejected(previous_session.error, get_view())
		if (
			previous_session.data.terminal_summary == null
			or previous_session.data.profile_merge_pending
		):
			return _reject(GameConstants.ERROR_RUN_ACTIVE, "error.run.saved_active")
	elif previous.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
		return ActionResult.rejected(previous.error, get_view())
	else:
		var backup := _store.load_backup("current_run")
		if backup.ok:
			return _reject(GameConstants.ERROR_RUN_ACTIVE, "error.run.backup_requires_choice")
		if backup.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
			return ActionResult.rejected(backup.error, get_view())
	var prepared := _prepare_run(request)
	if not prepared.ok:
		return ActionResult.rejected(prepared.error, get_view())
	_activate_run(prepared.data)
	return _accepted(prepared.data.events)


func restart_run(request: StartRunRequest, confirmed: bool = false) -> ActionResult:
	if not confirmed:
		return _reject(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.restart_confirmation")
	var prepared := _prepare_run(request)
	if not prepared.ok:
		return ActionResult.rejected(prepared.error, get_view())
	var merged := _merge_previous_summary()
	if not merged.ok:
		return ActionResult.rejected(merged.error, get_view())
	# Persist the replacement before publishing it, even when autosave is off.
	# A pending old battle is discarded, never serialized as a stable snapshot.
	var saved := _save_state(prepared.data.state, prepared.data.catalog)
	if not saved.ok:
		return ActionResult.rejected(saved.error, get_view())
	_activate_run(prepared.data)
	_last_receipt = saved.data
	var result := ActionResult.new(get_view())
	result.accepted = true
	result.events.assign(prepared.data.events)
	result.persistence = GameConstants.PERSISTENCE_SAVED
	return result


func _prepare_run(request: StartRunRequest) -> GameResult:
	if (
		request == null
		or not _is_manifest_allowed(request.manifest_id)
		or request.difficulty != &"normal"
	):
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.manifest")
	var loaded := _load_catalog(request.manifest_id)
	if not loaded.ok:
		return loaded
	var candidate: ContentDB = loaded.data
	var service := RunService.new(candidate)
	var created := (
		service
		. create(
			{
				"character_id": request.character_id,
				"difficulty": String(request.difficulty),
				"manifest_id": request.manifest_id,
				"seed": request.seed,
			},
			{"unlocked_ids": []}
		)
	)
	if not created.ok:
		return created
	var working := SessionState.new()
	_publish_run_step(working, created.data)
	return GameResult.success(
		{"catalog": candidate, "service": service, "state": working, "events": created.data.events}
	)


func _activate_run(prepared: Dictionary) -> void:
	_catalog = prepared.catalog
	_run_service = prepared.service
	_battle_engine = BattleEngine.new(_catalog)
	_state = prepared.state
	_last_receipt = null
	_profile_status = {}


func _merge_previous_summary() -> GameResult:
	var previous := _state
	if previous == null:
		var loaded := _store.load("current_run")
		if not loaded.ok and loaded.error.code == GameConstants.ERROR_SAVE_NOT_FOUND:
			loaded = _store.load_backup("current_run")
		if not loaded.ok:
			return (
				GameResult.success(true)
				if loaded.error.code == GameConstants.ERROR_SAVE_NOT_FOUND
				else loaded
			)
		var catalog := _load_catalog(loaded.data.manifest_id)
		if not catalog.ok:
			return catalog
		var decoded := SnapshotCodec.decode_session(loaded.data, catalog.data)
		if not decoded.ok:
			return decoded
		previous = decoded.data
	if not previous.profile_merge_pending:
		return GameResult.success(true)
	var profile := _read_profile()
	if not profile.ok:
		return profile
	var merged := ProfileMerge.merge(profile.data, previous.terminal_summary)
	if not merged.ok:
		return merged
	var encoded := SnapshotCodec.encode_document("profile", merged.data)
	return _store.save("profile", encoded.data) if encoded.ok else encoded


func continue_run() -> GameResult:
	return _restore(false)


func get_view() -> SessionView:
	var view := SessionView.new()
	if _state == null:
		return view
	view.run_id = _state.run.run_id
	view.revision = _state.revision
	view.run = _run_service.make_view(_state.run)
	view.screen = StringName(view.run.screen)
	view.node = view.run.get("node")
	view.battle = _battle_view(_state.battle) if _state.battle != null else null
	view.pending_choice = _state.pending_choice.copy() if _state.pending_choice != null else null
	view.can_save = _state.pending_choice == null
	view.terminal_summary = (
		_state.terminal_summary.to_dictionary() if _state.terminal_summary != null else null
	)
	view.event_log.assign(_state.event_log.duplicate(true))
	view.profile_commit_status = _profile_status.duplicate(true)
	return view


func preview_action(draft: ActionDraft) -> GameResult:
	if _state == null:
		return _failure(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.not_found")
	if draft == null:
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "error.command.missing")
	if _state.pending_choice != null and draft.type != &"confirm_choice":
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending")
	var result: GameResult
	if _state.battle != null:
		if draft.type in BATTLE_ACTIONS and draft.type != &"play_card":
			# apply uses independent state and RNG copies; discard the simulated step.
			# Only validity is exposed, never future draws or resolution outcomes.
			var checked := _battle_engine.apply(_state.battle, draft, _state.random_snapshot)
			var preview := ActionPreview.new()
			preview.can_submit = checked.ok
			if not checked.ok:
				preview.blocking_errors.append(checked.error)
			result = GameResult.success(preview)
		else:
			result = _battle_engine.preview(_state.battle, draft)
	else:
		result = _run_service.preview(_state.run, draft)
	if result.ok:
		result.data.revision = _state.revision
	return result


func submit(context: CommandContext, action: GameAction) -> ActionResult:
	if _state == null:
		return _reject(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.not_found")
	if context == null or action == null:
		return _reject(GameConstants.ERROR_INVALID_ARGUMENT, "error.command.missing")
	if context.run_id != _state.run.run_id or context.expected_revision != _state.revision:
		return _reject(GameConstants.ERROR_STALE_STATE, "error.command.stale")
	if _state.pending_choice != null and action.type != &"confirm_choice":
		return _reject(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending")
	var working := _state.copy_for_write()
	var events: Array[RuleEvent] = []
	var labels := _capture_labels(_state)
	if working.battle != null:
		if not BATTLE_ACTIONS.has(action.type):
			return _reject(GameConstants.ERROR_WRONG_PHASE, "error.battle.active")
		var battle_result := _battle_engine.apply(
			working.battle, ActionDraft.new(action.type, action.payload), working.random_snapshot
		)
		if not battle_result.ok:
			return ActionResult.rejected(battle_result.error, get_view())
		var battle_step: BattleStep = battle_result.data
		working.battle = battle_step.state
		labels.merge(_capture_labels(working), true)
		working.random_snapshot = battle_step.rng_state.duplicate(true)
		working.pending_choice = _choice(battle_step.pending_choice)
		events.append_array(battle_step.events)
		if battle_step.outcome != null:
			var settled := _run_service.settle_battle(
				working.run, battle_step.outcome, working.random_snapshot
			)
			if not settled.ok:
				return ActionResult.rejected(settled.error, get_view())
			_publish_run_step(working, settled.data)
			working.battle = null
			working.pending_choice = null
			events.append_array(settled.data.events)
	else:
		var run_result := _run_service.apply(working.run, action, working.random_snapshot)
		if not run_result.ok:
			return ActionResult.rejected(run_result.error, get_view())
		var run_step: RunStep = run_result.data
		_publish_run_step(working, run_step)
		events.append_array(run_step.events)
		if run_step.battle_input != null:
			var begun := _battle_engine.begin(run_step.battle_input)
			if not begun.ok:
				return ActionResult.rejected(begun.error, get_view())
			working.battle = begun.data.state
			working.random_snapshot = begun.data.rng_state.duplicate(true)
			working.pending_choice = _choice(begun.data.pending_choice)
			events.append_array(begun.data.events)
	working.revision += 1
	labels.merge(_capture_labels(working), true)
	_state = working
	return _accepted(events, labels)


func save_current() -> GameResult:
	if _state == null:
		return _failure(GameConstants.ERROR_RUN_NOT_FOUND, "error.run.not_found")
	if _state != null and _state.pending_choice != null:
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending")
	var saved := _save_state(_state)
	if not saved.ok:
		return saved
	_last_receipt = saved.data
	var committed := _commit_pending_profile()
	if not committed.ok:
		return committed
	var result := SessionSaveResult.new()
	result.current_run_receipt = _last_receipt
	result.profile_merge = StringName(committed.data.profile_merge)
	result.profile_cleanup = StringName(committed.data.profile_cleanup)
	result.profile_error = committed.data.profile_error
	result.cleanup_error = committed.data.cleanup_error
	return GameResult.success(result)


func save_and_exit() -> GameResult:
	var saved := save_current()
	if (
		saved.ok
		and saved.data.profile_merge not in [&"failed", &"pending"]
		and saved.data.profile_cleanup not in [&"failed", &"pending"]
	):
		_state = null
		_catalog = null
		_run_service = null
		_battle_engine = null
		_profile_status = {}
	return saved


func get_profile() -> ProfileView:
	var view := ProfileView.new()
	view.autosave = _autosave
	view.settings_error = _settings_error
	var profile := _read_profile()
	if not profile.ok:
		view.error = profile.error
		return view
	view.available = true
	view.unlocked_ids.assign(profile.data.unlocked_ids)
	view.seen_content_ids.assign(profile.data.seen_content_ids)
	view.tutorial_flags = profile.data.tutorial_flags.duplicate(true)
	view.completed_run_ids.assign(profile.data.summaries_by_run_id.keys())
	view.completed_run_ids.sort()
	for id in view.unlocked_ids:
		if id.begins_with("P"):
			view.unlocked_characters.append(id)
		elif id.begins_with("E"):
			view.unlocked_endings.append(id)
	return view


func update_settings(settings: Variant) -> GameResult:
	var patch: Variant = settings.to_dictionary() if settings is SettingsPatch else settings
	if not patch is Dictionary:
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "error.settings.invalid")
	for key in patch:
		if key != "autosave" or not patch[key] is bool:
			return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "error.settings.invalid")
	if _settings_error != null:
		return GameResult.failure(_settings_error)
	var candidate := {"autosave": patch.get("autosave", _autosave)}
	var encoded := SnapshotCodec.encode_document("settings", candidate)
	if not encoded.ok:
		return encoded
	var saved := _store.save("settings", encoded.data)
	if not saved.ok:
		return saved
	_autosave = candidate.autosave
	return GameResult.success(get_profile())


func inspect_saves() -> GameResult:
	var view := SessionStorageView.new()
	view.has_active_session = _state != null
	var formal := _store.inspect("current_run")
	if formal.ok:
		view.has_save = true
		view.save_meta = formal.data.duplicate(true)
		if not formal.data.valid:
			view.save_error = ApiError.new(
				GameConstants.ERROR_SAVE_CORRUPT,
				"error.save.corrupt",
				{"issues": formal.data.problems}
			)
	else:
		view.has_save = formal.error.code != GameConstants.ERROR_SAVE_NOT_FOUND
		view.save_error = formal.error
	var backup := _store.inspect_backup("current_run")
	if backup.ok:
		view.backup_meta = backup.data.duplicate(true)
		if not backup.data.valid:
			view.backup_error = ApiError.new(
				GameConstants.ERROR_SAVE_CORRUPT,
				"error.save.corrupt",
				{"issues": backup.data.problems}
			)
	else:
		view.backup_error = backup.error
	return GameResult.success(view)


func get_setup_options() -> GameResult:
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	if not loaded.ok:
		return loaded
	var info := catalog.get_info()
	var options := SetupOptions.new()
	for id in info.enabled.character:
		var definition: Dictionary = catalog.get_definition("character", id).data
		(
			options
			. characters
			. append(
				{
					"id": id,
					"name_key": definition.name_key,
					"starter_cards": definition.starter_cards,
					"starter_relic_id": definition.starter_relic_id,
					"locked": false,
					"reason": null,
				}
			)
		)
	options.difficulties = [&"normal"]
	options.manifests = [
		{"id": info.id, "content_version": info.content_version, "content_hash": info.content_hash}
	]
	return GameResult.success(options)


func restore_backup() -> GameResult:
	return _restore(true)


func _restore(backup: bool) -> GameResult:
	if _state != null:
		return _failure(GameConstants.ERROR_RUN_ACTIVE, "error.run.active")
	var loaded := _store.load_backup("current_run") if backup else _store.load("current_run")
	if not loaded.ok:
		return loaded
	var catalog_result := _load_catalog(loaded.data.manifest_id)
	if not catalog_result.ok:
		return catalog_result
	var decoded := SnapshotCodec.decode_session(loaded.data, catalog_result.data)
	if not decoded.ok:
		return decoded
	_catalog = catalog_result.data
	_run_service = RunService.new(_catalog)
	_battle_engine = BattleEngine.new(_catalog)
	_state = decoded.data
	_last_receipt = null
	# A backup is already durable, so merging is safe. Its marker stays pending
	# until an explicit save; restoring never replaces the formal current_run.
	if _state.profile_merge_pending:
		_commit_pending_profile(backup)
	return GameResult.success(get_view())


func _save_state(state: SessionState, catalog: ContentDB = null) -> GameResult:
	if catalog == null:
		catalog = _catalog
	var encoded := SnapshotCodec.encode_session(state, catalog.get_info())
	if not encoded.ok:
		return encoded
	var checked := SnapshotCodec.decode_session(encoded.data, catalog)
	if not checked.ok:
		return checked
	return _store.save("current_run", encoded.data)


func _read_profile() -> GameResult:
	var loaded := _store.load("profile")
	if not loaded.ok:
		if loaded.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
			return loaded
		var backup := _store.load_backup("profile")
		if backup.ok:
			return _failure(
				GameConstants.ERROR_SAVE_CORRUPT, "error.profile.backup_requires_recovery"
			)
		if backup.error.code != GameConstants.ERROR_SAVE_NOT_FOUND:
			return backup
		return GameResult.success(ProfileMerge.default_profile())
	var decoded := SnapshotCodec.decode_document(loaded.data, "profile")
	if not decoded.ok:
		return decoded
	var issues := ProfileMerge.validate(decoded.data.payload)
	if not issues.is_empty():
		return GameResult.failure(
			ApiError.new(
				GameConstants.ERROR_SAVE_CORRUPT, "error.profile.invalid", {"issues": Array(issues)}
			)
		)
	return GameResult.success(decoded.data.payload)


func _commit_pending_profile(defer_cleanup: bool = false) -> GameResult:
	var status := {
		"profile_merge": "not_pending",
		"profile_cleanup": "not_needed",
		"profile_error": null,
		"cleanup_error": null
	}
	if not _state.profile_merge_pending:
		_set_profile_status(status)
		return GameResult.success(status)
	status.profile_merge = "failed"
	status.profile_cleanup = "pending"
	var profile := _read_profile()
	var merged: GameResult = (
		ProfileMerge.merge(profile.data, _state.terminal_summary) if profile.ok else profile
	)
	if merged.ok:
		var encoded := SnapshotCodec.encode_document("profile", merged.data)
		merged = _store.save("profile", encoded.data) if encoded.ok else encoded
	if not merged.ok:
		status.profile_error = merged.error
		_set_profile_status(status)
		return GameResult.success(status)
	status.profile_merge = "merged"
	if not defer_cleanup:
		var working := _state.copy_for_write()
		working.profile_merge_pending = false
		var cleaned := _save_state(working)
		if cleaned.ok:
			_state = working
			_last_receipt = cleaned.data
			status.profile_cleanup = "cleared"
		else:
			status.profile_cleanup = "failed"
			status.cleanup_error = cleaned.error
	_set_profile_status(status)
	return GameResult.success(status)


func _set_profile_status(status: Dictionary) -> void:
	_profile_status = status.duplicate(true)
	for key in ["profile_error", "cleanup_error"]:
		if _profile_status[key] is ApiError:
			_profile_status[key] = _profile_status[key].to_dictionary()


func _valid_settings(payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("autosave") is bool


func _publish_run_step(working: SessionState, step: RunStep) -> void:
	working.run = step.state
	working.random_snapshot = step.rng_states.duplicate(true)
	if step.run_summary != null:
		working.terminal_summary = step.run_summary.copy()
		working.profile_merge_pending = true


func _accepted(events: Array[RuleEvent], labels: Dictionary = {}) -> ActionResult:
	for index in events.size():
		var event := events[index]
		event.index = index
		_state.event_log.append(
			{
				"run_id": _state.run.run_id,
				"revision": _state.revision,
				"index": index,
				"type": String(event.type),
				"source_id": event.source_id,
				"target_ids": event.target_ids.duplicate(),
				"data": event.data.duplicate(true),
				"source_label": labels.get(event.source_id, _label(event.source_id)),
				"target_labels": event.target_ids.map(func(id): return labels.get(id, _label(id))),
			}
		)
	while _state.event_log.size() > EVENT_LOG_LIMIT:
		_state.event_log.pop_front()
	var result := ActionResult.new(get_view())
	result.accepted = true
	result.events.assign(events)
	result.stable = _state.pending_choice == null
	result.profile_merge = &"pending" if _state.profile_merge_pending else &"not_pending"
	result.profile_cleanup = &"pending" if _state.profile_merge_pending else &"not_needed"
	if result.stable and _autosave:
		var saved := save_current()
		if saved.ok:
			result.persistence = GameConstants.PERSISTENCE_SAVED
			result.profile_merge = saved.data.profile_merge
			result.profile_error = saved.data.profile_error
			result.profile_cleanup = saved.data.profile_cleanup
			result.cleanup_error = saved.data.cleanup_error
		else:
			result.persistence = GameConstants.PERSISTENCE_FAILED
			result.save_error = saved.error
		result.view = get_view()
	return result


func _capture_labels(state: SessionState) -> Dictionary:
	var labels := {}
	for card in state.run.cards:
		labels[card.card_id] = "card.%s.name" % card.definition_id
	if state.battle != null:
		for id in state.battle.source_registry:
			var source: Dictionary = state.battle.source_registry[id]
			labels[id] = "%s.%s.name" % [source.get("kind", ""), source.get("definition_id", "")]
	return labels


func _label(instance_id: String) -> String:
	if instance_id.is_empty():
		return ""
	if _state.battle != null:
		var source: Dictionary = _state.battle.source_registry.get(instance_id, {})
		if not source.is_empty():
			return "%s.%s.name" % [source.get("kind", ""), source.get("definition_id", "")]
	for card in _state.run.cards:
		if card.get("card_id", "") == instance_id:
			return "card.%s.name" % card.definition_id
	return instance_id


func _choice(value: Variant) -> ChoiceRequest:
	if value == null:
		return null
	var candidates: Array[ChoiceOption] = []
	for option in value.get("candidates", []):
		candidates.append(
			ChoiceOption.new(option.id, option.get("label_key", ""), option.get("preview", {}))
		)
	return ChoiceRequest.new(
		value.choice_id,
		StringName(value.kind),
		candidates,
		value.get("min_count", 0),
		value.get("max_count", 0),
		value.get("prompt_key", ""),
		value.get("source_card_id"),
		value.get("effect_amount")
	)


func _battle_view(battle: BattleState) -> Dictionary:
	var hand: Array[Dictionary] = []
	for id in battle.zones.get("hand", []):
		hand.append(_card_view(battle, id))
	var zones_public := {}
	for zone in ["discard", "exhaust"]:
		var cards: Array[Dictionary] = []
		for id in battle.zones.get(zone, []):
			cards.append(_card_view(battle, id))
		zones_public[zone] = cards
	var counts := {}
	for zone in battle.zones:
		counts[zone] = battle.zones[zone].size()
	return {
		"battle_id": battle.battle_id,
		"node_id": battle.node_id,
		"encounter_id": battle.encounter_id,
		"phase": battle.phase,
		"round_index": battle.round_index,
		"ddl": battle.ddl,
		"player": battle.player.duplicate(true),
		"hand": hand,
		"units": battle.units.duplicate(true),
		"tasks": battle.tasks.duplicate(true),
		"statuses": battle.statuses.duplicate(true),
		"scene": battle.scene.duplicate(true) if battle.scene is Dictionary else null,
		"zone_counts": counts,
		"zones_public": zones_public,
	}


func _card_view(battle: BattleState, card_id: String) -> Dictionary:
	var card: Dictionary = battle.card_by_id[card_id].duplicate(true)
	var face := _battle_engine.resolve_face(battle, card_id)
	card["effective_card"] = face.data if face.ok else null
	card["face"] = face.data.duplicate(true) if face.ok else {}
	var quote := _battle_engine.calculate_cost(battle, card_id)
	card["effective_cost"] = quote.data.cost if quote.ok else 0
	card["effective_vitality_cost"] = quote.data.vitality_cost if quote.ok else 0
	return card


func _reject(code: StringName, key: String) -> ActionResult:
	return ActionResult.rejected(ApiError.new(code, key), get_view())


func _failure(code: StringName, key: String) -> GameResult:
	return GameResult.failure(ApiError.new(code, key))
