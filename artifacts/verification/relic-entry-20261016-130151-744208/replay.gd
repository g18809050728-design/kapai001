extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var folder: String = get_script().resource_path.get_base_dir()
	var isolated := "user://relic-entry-replay-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(folder.path_join("player_snapshot.json")), ProjectSettings.globalize_path(isolated.path_join("current_run.json")))
	assert(copy_error == OK)
	var store := SaveStore.new(isolated)
	var session := GameSession.new(store)
	var restored := session.continue_run()
	if not restored.ok:
		print("REPLAY_RESTORE_ERROR=", JSON.stringify(restored.error.to_dictionary()))
		session.free()
		quit(2)
		return
	var before := SnapshotCodec.encode_session(session._state, session._catalog.get_info()).data as Dictionary
	var view := session.get_view()
	var boss_id: String = view.run.reachable_node_ids[0]
	var result := session.submit(CommandContext.new(str(view.run_id), view.revision), GameAction.new(&"enter_node", {"node_id": boss_id}))
	var report := {"accepted": result.accepted, "error": result.error.to_dictionary() if result.error != null else null, "input_revision": view.revision, "boss_node": boss_id, "isolated_store": isolated}
	var valid: bool = result.accepted and result.view.screen == &"battle" and result.view.battle.encounter_id == "B01"
	if result.accepted:
		var after := SnapshotCodec.encode_session(session._state, session._catalog.get_info()).data as Dictionary
		report.relics_preserved = before.payload.run.relics == after.payload.run.relics
		report.revision_advanced_once = result.revision == view.revision + 1
		var stable := session.save_and_exit()
		session.free()
		session = GameSession.new(store)
		var reloaded := session.continue_run()
		var roundtrip := SnapshotCodec.encode_session(session._state, session._catalog.get_info()) if reloaded.ok else reloaded
		report.save_restore_equal = stable.ok and roundtrip.ok and roundtrip.data == after
		valid = valid and report.relics_preserved and report.revision_advanced_once and report.save_restore_equal
	else:
		report.rejection_preserves_state_rng = SnapshotCodec.encode_session(session._state, session._catalog.get_info()).data == before
	print("PLAYER_BOSS_ENTRY_REPLAY=", JSON.stringify(report))
	session.free()
	quit(0 if valid else 1)
