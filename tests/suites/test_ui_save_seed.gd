extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _root := ""
var _cases: Array[Dictionary] = []


func run() -> Array[String]:
	_root = "user://g7-save-seed-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	_check_clean_and_random()
	for kind in ["corrupt", "content_hash", "schema", "backup_only"]:
		_check_unreadable_restart(kind)
	print(
		"G7_SAVE_SEED_EVIDENCE=",
		SnapshotCodec.canonical_json(
			{"cases": _cases, "failures": _failures, "isolated_store": _root}
		)
	)
	return _failures


func _check_clean_and_random() -> void:
	var store := SaveStore.new(_root + "/fresh")
	var shell := _helpers.attach_shell(GameSession.new(store)) as GameShell
	_check(not shell.press("menu:continue"), "clean download has no resumable run")
	_check(not store.load("current_run").ok, "opening menu creates no player save")
	_check(shell.press("menu:new"), "clean menu offers new run")
	var first := _seed(shell)
	_check(first.is_valid_int() and first.length() <= 19, "default seed is a decimal int64")
	shell.refresh()
	_check(_seed(shell) == first, "ordinary refresh preserves generated seed")
	var seen := {first: true}
	for index in range(32):
		_check(shell.press("setup:seed_random"), "random seed button responds")
		var generated := _seed(shell)
		_check(generated.is_valid_int() and int(generated) >= 0, "generated seed is nonnegative")
		_check(not seen.has(generated), "rapid random clicks do not repeat the second timestamp")
		seen[generated] = true
	_set_seed(shell, "9223372036854775807")
	shell.refresh()
	_check(_seed(shell) == "9223372036854775807", "manual seed survives refresh without float loss")
	_check(shell.press("setup:start"), "fresh production run starts")
	_check(shell.session.get_view().screen == &"map", "fresh start reaches map")
	var expected := RandomSource.new("9223372036854775807").export_state().to_dictionary()
	_check(shell.session._state.random_snapshot == expected, "manual seed reaches gameplay exactly")
	var before := _helpers.fingerprint(shell.session) as String
	_check(shell.press("map:menu") and shell.press("menu:new"), "active run can open setup")
	_check(_seed(shell) != "9223372036854775807", "new configuration gets fresh default seed")
	_check(shell.press("setup:seed_random"), "active run permits seed draft changes")
	_set_seed(shell, "1234567890123456789")
	_check(shell.press("setup:start"), "old run requests replacement confirmation")
	_check(_seed(shell) == "1234567890123456789", "confirmation preserves manual seed")
	_check(shell.press("setup:restart_cancel"), "restart confirmation can be cancelled")
	_check(_seed(shell) == "1234567890123456789", "cancelling confirmation preserves draft")
	_check(
		_helpers.fingerprint(shell.session) == before,
		"configuration does not change live RNG or state"
	)
	_check(
		shell.press("setup:back") and shell.press("menu:settings"),
		"cancelled setup returns to settings"
	)
	_check(
		shell.page.view.seed == "9223372036854775807",
		"settings shows active seed, not abandoned draft"
	)
	shell.free()
	var resumed := GameSession.new(store)
	_check(resumed.inspect_saves().data.can_continue, "saved production run is resumable")
	_check(resumed.continue_run().ok, "fresh process restores save")
	_check(
		resumed._state.random_snapshot == expected, "save reload preserves all four random streams"
	)
	var generated := resumed.generate_run_seed()
	_check(generated.ok, "public seed generator returns entropy")
	_check(resumed._state.random_snapshot == expected, "seed generation cannot advance saved RNG")
	var replay_a := RandomSource.new(generated.data)
	var replay_b := RandomSource.new(generated.data)
	for stream in RandomSource.STREAMS:
		for index in range(16):
			_check(
				(
					replay_a.draw_int(stream, 0, 10000).data
					== replay_b.draw_int(stream, 0, 10000).data
				),
				"generated seed remains deterministic in " + stream
			)
	resumed.free()
	_cases.append(
		{"case": "fresh_and_seed", "rapid_unique_seeds": seen.size(), "replay": "four_streams"}
	)


func _check_unreadable_restart(kind: String) -> void:
	var path := _root + "/" + kind
	var store := SaveStore.new(path)
	var initial := GameSession.new(store)
	var request := StartRunRequest.new("P01", &"normal", "campus_mvp", "42")
	_check(initial.start_run(request).accepted, kind + " initial run")
	_check(initial.save_current().ok, kind + " initial backup")
	var original := store.load("current_run").data as Dictionary
	initial.free()
	var formal_path := ProjectSettings.globalize_path(path).path_join("current_run.json")
	var backup_path := formal_path + ".bak"
	if kind == "corrupt" or kind == "backup_only":
		_write(formal_path, "{broken download save")
	else:
		var changed := original.duplicate(true)
		if kind == "content_hash":
			changed.content_hash = "outdated-content-hash"
		else:
			changed.schema_version += 1
		changed.checksum = SnapshotCodec.compute_checksum(changed)
		_write(formal_path, SnapshotCodec.canonical_json(changed))
	if kind == "backup_only":
		_write(backup_path, FileAccess.get_file_as_string(formal_path))
		DirAccess.remove_absolute(formal_path)
	var old_formal := (
		FileAccess.get_file_as_bytes(formal_path)
		if FileAccess.file_exists(formal_path)
		else PackedByteArray()
	)
	var old_backup := FileAccess.get_file_as_bytes(backup_path)
	var shell := _helpers.attach_shell(GameSession.new(store)) as GameShell
	_check(not shell.press("menu:continue"), kind + " cannot advertise a resumable disk run")
	_check(
		shell.press("menu:new") and shell.press("setup:start"),
		kind + " permits setup and confirmation"
	)
	_check(shell.session.get_view().run_id == null, kind + " confirmation does not publish a run")
	for hook in ["fail_archive", "fail_write"]:
		store.debug_hooks = {"current_run": {hook: true}}
		_check(shell.press("setup:restart_confirm"), kind + " tries " + hook)
		_check(
			shell.session.get_view().run_id == null, kind + " failure never publishes replacement"
		)
		_check(
			FileAccess.get_file_as_bytes(backup_path) == old_backup,
			kind + " failure preserves backup"
		)
		if not old_formal.is_empty():
			_check(
				FileAccess.get_file_as_bytes(formal_path) == old_formal,
				kind + " failure preserves formal"
			)
	store.debug_hooks = {}
	_check(shell.press("setup:restart_confirm"), kind + " confirmed restart")
	_check(shell.session.get_view().screen == &"map", kind + " starts fresh map")
	_check(shell.session.get_view().run_id != original.run_id, kind + " has new run id")
	_check(shell.session.get_view().revision == 0, kind + " begins at revision zero")
	_check(store.load("current_run").ok, kind + " replacement is durable")
	var archive_root := ProjectSettings.globalize_path(path).path_join("recovery")
	var found := false
	for directory in DirAccess.get_directories_at(archive_root):
		var archived := archive_root.path_join(directory)
		if not FileAccess.file_exists(archived.path_join("current_run.json.bak")):
			continue
		if FileAccess.get_file_as_bytes(archived.path_join("current_run.json.bak")) != old_backup:
			continue
		if (
			not old_formal.is_empty()
			and FileAccess.get_file_as_bytes(archived.path_join("current_run.json")) != old_formal
		):
			continue
		found = true
	_check(found, kind + " retains byte-identical original and backup in recovery")
	_check(shell.notice.contains("旧存档原件已保留"), kind + " reports archive location")
	_check(
		shell.session.get_profile().completed_run_ids.is_empty(),
		kind + " never invents completion rewards"
	)
	_cases.append(
		{
			"case": kind,
			"archived_original_bytes": found,
			"new_run": str(shell.session.get_view().run_id)
		}
	)
	shell.free()
	var restored := GameSession.new(store)
	_check(restored.continue_run().ok, kind + " new game restores after relaunch")
	restored.free()


func _seed(shell: GameShell) -> String:
	return str(
		(
			shell
			. page
			. action_draft(
				(
					"setup:restart_confirm"
					if shell.page.button_uids().has("setup:restart_confirm")
					else "setup:start"
				)
			)
			. payload
			. seed
		)
	)


func _set_seed(shell: GameShell, value: String) -> void:
	var input := _helpers._line_edit(shell.page) as LineEdit
	_check(input != null, "seed field exists")
	if input != null:
		input.text = value
		input.text_changed.emit(value)


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fault fixture can be written")
	if file != null:
		file.store_string(value)
		file.close()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("G7 save/seed: " + message)
