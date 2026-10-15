extends RefCounted


class FixtureSession:
	extends GameSession

	func _is_manifest_allowed(id: String) -> bool:
		return id == "test_run_g4"


class BoundaryStore:
	extends SaveStore
	var current_writes := 0
	var fail_current_write := -1

	func save(slot: String, snapshot: Dictionary) -> GameResult:
		if slot == "current_run":
			current_writes += 1
			if current_writes == fail_current_write:
				return GameResult.failure(
					ApiError.new(GameConstants.ERROR_SAVE_IO_ERROR, "test.boundary")
				)
		return super.save(slot, snapshot)


var _failures: Array[String] = []
var _commands: Array[Dictionary] = []
var _roundtrips: Dictionary = {}
var _faults: Array[Dictionary] = []
var _continuations: Array[Dictionary] = []
var _root: String
var _catalog: ContentDB


func run() -> Array[String]:
	_root = "user://g5-session-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	_catalog = _factory()
	_check(_catalog.load("test_run_g4").ok, "fixture loads")
	for autosave in [false, true]:
		_full_semester(autosave)
		_pending_restart(autosave)
		for boundary in [1, 2, 3]:
			_terminal_fault(autosave, boundary)
	_backup_and_errors()
	_missing_formal_backups()
	print("G5_CONTINUATION_EVIDENCE=", SnapshotCodec.canonical_json(_continuations))
	print(
		"G5_SESSION_EVIDENCE=",
		SnapshotCodec.canonical_json(
			{
				"seed": "42",
				"commands": _commands,
				"roundtrips": _roundtrips,
				"faults": _faults,
				"failures": _failures
			}
		)
	)
	return _failures


func _factory() -> ContentDB:
	return ContentDB.new("res://tests/fixtures/run_flow", true)


func _session(store: SaveStore) -> GameSession:
	return FixtureSession.new(store, Callable(self, "_factory"))


func _start(store: SaveStore, autosave: bool = false) -> GameSession:
	var session := _session(store)
	_check(
		session.update_settings(SettingsPatch.new(true, autosave)).ok, "persist autosave setting"
	)
	var started := session.start_run(
		StartRunRequest.new("test_P01", &"normal", "test_run_g4", "42")
	)
	_check(started.accepted, "public start_run")
	if not started.accepted:
		print("G5_START_ERROR=", started.error.to_dictionary())
	return session


func _full_semester(autosave: bool) -> void:
	var control_store := SaveStore.new(_root + "/control-%s" % autosave)
	var control := _start(control_store, autosave)
	var initial := SnapshotCodec.encode_session(control._state, _catalog.get_info())
	_check(initial.ok, "encode initial snapshot")
	if not initial.ok:
		print("G5_INITIAL_ERROR=", initial.error.to_dictionary())
		control.free()
		return
	var resumed_store := SaveStore.new(_root + "/resumed-%s" % autosave)
	_check(resumed_store.save("current_run", initial.data).ok, "copy identical initial state")
	var resumed := _session(resumed_store)
	_check(resumed.update_settings({"autosave": autosave}).ok, "persist resumed autosave mode")
	_check(resumed.continue_run().ok, "public continue initial snapshot")
	var initial_hash: String = initial.data.checksum
	for layer in range(1, 7):
		var kind: String = ["normal", "event", "shop", "elite", "rest", "boss"][layer - 1]
		var node_id := ""
		for node in control.get_view().run.nodes:
			if node.layer == layer and node.kind == kind:
				node_id = node.node_id
		if not _both(control, resumed, &"enter_node", {"node_id": node_id}):
			break
		resumed = _reload(resumed, resumed_store, "entered_" + kind)
		if kind in ["normal", "elite", "boss"]:
			var view := control.get_view()
			var action := {
				"card_instance_id": view.battle.hand[0].card_id,
				"target_ids": [view.battle.tasks[0].task_id]
			}
			if not _both(control, resumed, &"play_card", action):
				break
			if kind == "boss":
				break
			resumed = _reload(resumed, resumed_store, "after_battle_" + kind)
			var offer: Dictionary = control.get_view().run.pending_reward
			for item in offer.items:
				if not _both(
					control,
					resumed,
					&"skip_reward",
					{"offer_id": offer.offer_id, "item_id": item.item_id}
				):
					break
		elif kind == "event":
			var event: Dictionary = control.get_view().run.event
			_both(
				control,
				resumed,
				&"choose_event",
				{
					"event_instance_id": event.event_instance_id,
					"option_id": "leave",
					"selection_ids": []
				}
			)
		elif kind == "shop":
			var shop: Dictionary = control.get_view().run.shop
			_both(
				control,
				resumed,
				&"buy_item",
				{"shop_id": shop.shop_id, "stock_id": shop.stocks[0].stock_id}
			)
			resumed = _reload(resumed, resumed_store, "purchased_shop")
		elif kind == "rest":
			_both(
				control,
				resumed,
				&"take_rest",
				{
					"node_id": node_id,
					"option_id": "upgrade",
					"card_instance_id": control.get_view().run.cards[0].card_id
				}
			)
		if not _both(control, resumed, &"leave_node", {"node_id": node_id}):
			break
	_check(
		control.get_view().screen == &"summary" and resumed.get_view().screen == &"summary",
		"public commands finish semester"
	)
	# Explicit mode commits here; automatic mode has already committed at the terminal command.
	_check(control.save_current().ok and resumed.save_current().ok, "terminal three-step saves")
	var first := SnapshotCodec.encode_session(control._state, _catalog.get_info())
	var second := SnapshotCodec.encode_session(resumed._state, _catalog.get_info())
	_check(first.ok and second.ok, "final snapshots encode")
	if first.ok and second.ok:
		_check(
			SnapshotCodec.canonical_json(first.data) == SnapshotCodec.canonical_json(second.data),
			"uninterrupted vs restored all fields and four streams"
		)
		_continuations.append(
			{
				"autosave": autosave,
				"initial": initial.data,
				"initial_hash": initial_hash,
				"control_final": first.data,
				"resumed_final": second.data
			}
		)
	_check(
		(
			control.get_profile().completed_run_ids.size() == 1
			and resumed.get_profile().completed_run_ids.size() == 1
		),
		"one summary each"
	)
	control.free()
	resumed.free()


func _both(
	control: GameSession, resumed: GameSession, type: StringName, payload: Dictionary
) -> bool:
	var first := _submit(control, type, payload)
	var second := _submit(resumed, type, payload)
	_check(first.accepted and second.accepted, "paired command " + String(type))
	if not first.accepted or not second.accepted:
		return false
	var a := SnapshotCodec.encode_session(control._state, _catalog.get_info())
	var b := SnapshotCodec.encode_session(resumed._state, _catalog.get_info())
	_check(a.ok and b.ok, "stable paired snapshot " + String(type))
	if a.ok and b.ok:
		_check(a.data == b.data, "paired complete state equality " + String(type))
	_commands.append(
		{"type": String(type), "payload": payload.duplicate(true), "revision": first.revision}
	)
	return true


func _reload(session: GameSession, store: SaveStore, label: String) -> GameSession:
	var encoded := SnapshotCodec.encode_session(session._state, _catalog.get_info())
	_check(encoded.ok, label + " encodes")
	if not encoded.ok:
		return session
	var saved := session.save_and_exit()
	_check(saved.ok and session.get_view().run_id == null, label + " saves and exits")
	session.free()
	var restored := _session(store)
	var loaded := restored.continue_run()
	_check(loaded.ok, label + " continues")
	if not loaded.ok:
		print("G5_RELOAD_ERROR=", label, loaded.error.to_dictionary())
		return restored
	var after := SnapshotCodec.encode_session(restored._state, _catalog.get_info())
	_check(after.ok and encoded.data == after.data, label + " preserves complete state and RNG")
	_roundtrips["%s/%s" % [restored.get_profile().autosave, label]] = {
		"checksum": after.data.checksum if after.ok else "",
		"revision": restored.get_view().revision
	}
	return restored


func _pending_restart(autosave: bool) -> void:
	var store := SaveStore.new(_root + "/choice-%s" % autosave)
	var session := _start(store, autosave)
	_check(session.save_current().ok, "pre-choice stable saved")
	var saved: Dictionary = store.load("current_run").data
	# A real battle effect suspends. Only the test content package is changed in memory.
	var node_id: String = session.get_view().run.reachable_node_ids[0]
	var entered := _submit(session, &"enter_node", {"node_id": node_id})
	_check(entered.accepted, "choice test begins battle")
	if entered.accepted:
		saved = store.load("current_run").data
		var state: BattleState = session._state.battle
		var card_id: String = state.zones.hand[0]
		var definition_id: String = state.card_by_id[card_id].definition_id
		var definition: Dictionary = session._catalog._definitions.card[definition_id]
		definition.effects = [{"op": "discard", "amount": 1}, {"op": "gain_focus", "amount": 1}]
		definition.target = "self"
		var result := _submit(
			session, &"play_card", {"card_instance_id": card_id, "target_ids": []}
		)
		_check(result.accepted and result.pending_choice != null, "genuine effect pending choice")
		if result.pending_choice != null:
			var denied := session.save_current()
			_check(not denied.ok and denied.error.code == &"CHOICE_PENDING", "pending save blocked")
			_check(
				store.load("current_run").data == saved,
				"pending effect never overwrites stable disk"
			)
	session.free()
	var restarted := _session(store)
	_check(restarted.continue_run().ok, "restart last stable snapshot")
	var restored := SnapshotCodec.encode_session(restarted._state, _catalog.get_info())
	_check(
		restored.ok and restored.data == saved, "restart discards only in-memory pending workspace"
	)
	restarted.free()


func _terminal_fault(autosave: bool, boundary: int) -> void:
	var store := BoundaryStore.new(_root + "/fault-%s-%d" % [autosave, boundary])
	var session := _start(store, autosave)
	_check(session.save_current().ok, "fault initial save")
	store.current_writes = 0
	if boundary == 1:
		store.fail_current_write = 1
	elif boundary == 2:
		store.debug_hooks = {"profile": {"fail_write": true}}
	else:
		store.fail_current_write = 2
	var action := _submit(session, &"abandon_run", {"confirmed": true})
	_check(action.accepted, "terminal rules commit survives disk fault")
	var saved: GameResult
	if autosave:
		if boundary == 1:
			_check(
				action.persistence == &"failed" and action.save_error != null,
				"autosave current-run failure distinct"
			)
		else:
			_check(action.persistence == &"saved", "current-run saved before profile failure")
			_check(
				action.profile_merge == (&"failed" if boundary == 2 else &"merged"),
				"autosave merge report"
			)
			_check(
				action.profile_cleanup == (&"pending" if boundary == 2 else &"failed"),
				"autosave cleanup report"
			)
	else:
		_check(
			(
				action.persistence == &"not_attempted"
				and session.get_profile().completed_run_ids.is_empty()
			),
			"autosave false defers terminal profile"
		)
		saved = session.save_and_exit()
		if boundary == 1:
			_check(not saved.ok, "explicit first write error")
		else:
			_check(
				(
					saved.ok
					and saved.data.profile_merge == (&"failed" if boundary == 2 else &"merged")
				),
				"explicit merge partial report"
			)
			_check(
				(
					saved.ok
					and saved.data.profile_cleanup == (&"pending" if boundary == 2 else &"failed")
				),
				"explicit cleanup partial report"
			)
	_check(session.get_view().run_id != null, "failed save-and-exit retains session")
	var run_id: String = session.get_view().run_id
	var report := {
		"autosave": autosave,
		"boundary": boundary,
		"run_id": run_id,
		"profile_count_before_retry": session.get_profile().completed_run_ids.size()
	}
	if autosave:
		report["persistence"] = String(action.persistence)
		report["profile_merge"] = String(action.profile_merge)
		report["profile_cleanup"] = String(action.profile_cleanup)
	else:
		report["persistence"] = "saved" if saved.ok else "failed"
		report["profile_merge"] = String(saved.data.profile_merge) if saved.ok else "pending"
		report["profile_cleanup"] = String(saved.data.profile_cleanup) if saved.ok else "pending"
	_faults.append(report)
	store.debug_hooks = {}
	store.fail_current_write = -1
	if boundary == 1:
		# The summary existed only in memory. Explicit retry must persist it before merging.
		_check(session.save_current().ok, "retry first step without replaying rule")
	else:
		# Model process death at the durable marker; a new session retries on load.
		session.free()
		session = _session(store)
		_check(session.continue_run().ok, "restart retries durable pending summary")
	_check(session.save_current().ok and session.save_current().ok, "idempotent save retries")
	var profile := session.get_profile()
	_check(
		profile.available and profile.completed_run_ids == [run_id],
		"exactly one permanent summary after recovery"
	)
	var persisted := store.load("current_run")
	_check(
		(
			persisted.ok
			and not persisted.data.payload.profile_merge_pending
			and persisted.data.payload.terminal_summary.run_id == run_id
		),
		"cleanup keeps terminal summary"
	)
	var before: String = SnapshotCodec.canonical_json(store.load("profile").data)
	_check(
		session.save_and_exit().ok and session.get_view().run_id == null,
		"successful save-and-exit releases session"
	)
	_check(
		before == SnapshotCodec.canonical_json(store.load("profile").data),
		"retries preserve canonical profile"
	)
	session.free()


func _backup_and_errors() -> void:
	var path := _root + "/backup"
	var store := SaveStore.new(path)
	var session := _start(store)
	_check(session.save_current().ok and session.save_current().ok, "valid formal and backup")
	var initial_revision: int = session.get_view().revision
	_check(
		(
			not session.update_settings({"difficulty": "hard"}).ok
			and not session.update_settings({"autosave": 1}).ok
		),
		"reject unsupported settings"
	)
	_check(session.get_view().revision == initial_revision, "settings do not change revision")
	store.debug_hooks = {"current_run": {"fail_write": true}}
	var action := _submit(
		session, &"enter_node", {"node_id": session.get_view().run.reachable_node_ids[0]}
	)
	_check(action.accepted, "rules progress with autosave disabled")
	_check(
		not session.save_and_exit().ok and session.get_view().run_id != null,
		"disk failure retains session"
	)
	store.debug_hooks = {}
	session.free()
	var file := FileAccess.open(path + "/current_run.json", FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	session = _session(store)
	var inspected := session.inspect_saves()
	_check(
		(
			inspected.ok
			and inspected.data.has_save
			and not inspected.data.save_meta.valid
			and inspected.data.backup_meta.valid
		),
		"corruption diagnostics retain both files"
	)
	_check(
		not session.continue_run().ok and session.get_view().run_id == null,
		"no silent backup fallback"
	)
	_check(
		not (
			session
			. start_run(StartRunRequest.new("test_P01", &"normal", "test_run_g4", "42"))
			. accepted
		),
		"corrupt save cannot be overwritten by new run"
	)
	var original := FileAccess.get_file_as_string(path + "/current_run.json")
	_check(session.restore_backup().ok, "explicit backup restore")
	_check(
		FileAccess.get_file_as_string(path + "/current_run.json") == original,
		"restore leaves formal evidence intact"
	)
	_check(
		not session.restore_backup().ok and not session.continue_run().ok,
		"active memory blocks replacement"
	)
	_check(session.save_current().ok, "explicit save publishes restored state")
	session.free()


func _missing_formal_backups() -> void:
	var path := _root + "/missing-formal"
	var store := SaveStore.new(path)
	var session := _start(store)
	_check(session.save_current().ok and session.save_current().ok, "missing-formal fixture saves")
	session.free()
	_check(DirAccess.remove_absolute(path + "/current_run.json") == OK, "remove formal fixture")
	session = _session(store)
	var request := StartRunRequest.new("test_P01", &"normal", "test_run_g4", "42")
	_check(not session.start_run(request).accepted, "valid orphan backup blocks new run")
	var file := FileAccess.open(path + "/current_run.json.bak", FileAccess.WRITE)
	file.store_string("{broken-backup")
	file.close()
	_check(not session.start_run(request).accepted, "corrupt orphan backup blocks new run")
	_check(
		(
			not FileAccess.file_exists(path + "/current_run.json")
			and FileAccess.get_file_as_string(path + "/current_run.json.bak") == "{broken-backup"
		),
		"new run preserves orphan backup evidence"
	)
	session.free()
	var profile_document := SnapshotCodec.encode_document("profile", ProfileMerge.default_profile())
	_check(
		(
			store.save("profile", profile_document.data).ok
			and store.save("profile", profile_document.data).ok
		),
		"profile backup fixture"
	)
	_check(DirAccess.remove_absolute(path + "/profile.json") == OK, "remove profile formal fixture")
	var profile_backup := FileAccess.get_file_as_string(path + "/profile.json.bak")
	session = _session(store)
	_check(
		not session.get_profile().available and session.get_profile().error != null,
		"missing profile with backup refuses empty initialization"
	)
	_check(
		(
			not FileAccess.file_exists(path + "/profile.json")
			and FileAccess.get_file_as_string(path + "/profile.json.bak") == profile_backup
		),
		"profile history backup retained"
	)
	session.free()
	var settings_document := SnapshotCodec.encode_document("settings", {"autosave": false})
	_check(
		(
			store.save("settings", settings_document.data).ok
			and store.save("settings", settings_document.data).ok
		),
		"settings backup fixture"
	)
	_check(
		DirAccess.remove_absolute(path + "/settings.json") == OK, "remove settings formal fixture"
	)
	var settings_backup := FileAccess.get_file_as_string(path + "/settings.json.bak")
	session = _session(store)
	_check(
		(
			session.get_profile().settings_error != null
			and not session.update_settings({"autosave": true}).ok
		),
		"orphan settings backup blocks default overwrite"
	)
	_check(
		(
			not FileAccess.file_exists(path + "/settings.json")
			and FileAccess.get_file_as_string(path + "/settings.json.bak") == settings_backup
		),
		"settings backup evidence retained"
	)
	session.free()


func _submit(session: GameSession, type: StringName, payload: Dictionary) -> ActionResult:
	var view := session.get_view()
	var result := session.submit(
		CommandContext.new(view.run_id, view.revision), GameAction.new(type, payload)
	)
	if not result.accepted:
		print("G5_COMMAND_ERROR=", type, " ", result.error.to_dictionary())
	return result


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append("G5 session: " + label)
