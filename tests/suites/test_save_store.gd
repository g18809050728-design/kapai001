extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var directory := "user://g5_store_test_%d" % Time.get_ticks_usec()
	var store := SaveStore.new(directory)
	var first_result := SnapshotCodec.encode_document("settings", {"autosave": true})
	var second_result := SnapshotCodec.encode_document("settings", {"autosave": false})
	_check(first_result.ok and second_result.ok, "store document fixtures encode", failures)
	if not first_result.ok or not second_result.ok:
		return failures
	var first: Dictionary = first_result.data
	var second: Dictionary = second_result.data
	var missing := store.load("settings")
	_check(
		not missing.ok and missing.error.code == &"SAVE_NOT_FOUND",
		"missing save reports not found",
		failures
	)
	_check(not store.save("../outside", first).ok, "slot path traversal refused", failures)
	var original := SnapshotCodec.canonical_json(first)
	var initial := store.save("settings", first)
	_check(initial.ok and initial.data is SaveReceipt, "first save returns receipt", failures)
	_check(
		original == SnapshotCodec.canonical_json(first), "save preserves caller snapshot", failures
	)
	_check(_same(store.load("settings"), first), "first save loads exactly", failures)
	_check(store.save("settings", second).ok, "second save succeeds", failures)
	_check(
		_same(store.load_backup("settings"), first),
		"backup holds previous valid snapshot",
		failures
	)
	var inspected := store.inspect("settings")
	_check(inspected.ok and inspected.data.valid, "inspect reports valid formal", failures)
	for hook in ["fail_write", "truncate_temp", "fail_after_backup", "fail_rename"]:
		store.debug_hooks = {"settings": {hook: true}}
		var rejected := store.save("settings", first)
		_check(not rejected.ok, "injected failure reports error " + hook, failures)
		_check(_same(store.load("settings"), second), "old formal survives " + hook, failures)
		_check(
			store.load_backup("settings").ok, "at least one valid backup survives " + hook, failures
		)
	store.debug_hooks = {}
	var tampered := first.duplicate(true)
	tampered.payload.autosave = false
	var rejected := store.save("settings", tampered)
	_check(
		not rejected.ok and rejected.error.code == &"SAVE_CORRUPT",
		"wrong checksum rejected before write",
		failures
	)
	_check(
		_same(store.load("settings"), second),
		"bad snapshot does not replace valid formal",
		failures
	)
	var backup_before := store.load_backup("settings")
	var formal_path := ProjectSettings.globalize_path(directory).path_join("settings.json")
	var corrupt := FileAccess.open(formal_path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var metadata := store.inspect("settings")
	_check(
		metadata.ok and not metadata.data.valid and not metadata.data.problems.is_empty(),
		"inspect preserves corrupt file diagnostics",
		failures
	)
	_check(not store.load("settings").ok, "load does not silently use backup", failures)
	_check(store.load_backup("settings").ok, "explicit backup remains loadable", failures)
	_check(store.save("settings", first).ok, "valid snapshot can replace corrupt formal", failures)
	_check(
		_same(store.load_backup("settings"), backup_before.data),
		"corrupt formal never overwrites valid backup",
		failures
	)
	_test_profile_merge(failures)
	for slot in ["current_run", "profile", "settings"]:
		for suffix in [".json", ".json.bak", ".json.tmp", ".json.bak.tmp"]:
			var path := ProjectSettings.globalize_path(directory).path_join(slot + suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print(
		(
			"G5_STORE_EVIDENCE="
			+ JSON.stringify(
				{
					"hooks": ["fail_write", "truncate_temp", "fail_after_backup", "fail_rename"],
					"filesystem": "real",
					"profile": "idempotent and conflicting summaries",
					"passed": failures.is_empty()
				}
			)
		)
	)
	return failures


func _test_profile_merge(failures: Array[String]) -> void:
	var profile := ProfileMerge.default_profile()
	profile.unlocked_ids = ["P01"]
	profile.tutorial_flags["intro"] = true
	var summary := RunSummary.create(
		{
			"run_id": "store_test_run",
			"result": "won",
			"reason": "first_term_completed",
			"character_id": "P01",
			"difficulty": "normal",
			"manifest_id": "campus_mvp",
			"term": 1,
			"statistics": {"money": 15},
			"unlocked_ids": ["P04"],
			"seen_content_ids": ["V03"]
		}
	)
	var before := profile.duplicate(true)
	var merged := ProfileMerge.merge(profile, summary)
	_check(
		merged.ok,
		(
			"profile finalized summary merges: "
			+ (JSON.stringify(merged.error.details) if not merged.ok else "ok")
		),
		failures
	)
	_check(profile == before, "profile merge preserves input", failures)
	if not merged.ok:
		return
	_check(
		(
			merged.data.completed_runs == 1
			and merged.data.unlocked_ids == ["P01", "P04"]
			and merged.data.seen_content_ids == ["V03"]
		),
		"profile counts unique summaries and unions unlocks",
		failures
	)
	_check(merged.data.tutorial_flags.intro, "profile tutorial flags preserved", failures)
	var repeated := ProfileMerge.merge(merged.data, summary)
	_check(repeated.ok and repeated.data == merged.data, "same summary merge idempotent", failures)
	var conflicting := summary.copy()
	conflicting.statistics.money = 99
	var rejected := ProfileMerge.merge(merged.data, conflicting)
	_check(
		not rejected.ok and rejected.error.code == &"SAVE_CORRUPT",
		"different summary with same run ID refused",
		failures
	)
	var malformed: Dictionary = merged.data.duplicate(true)
	malformed.completed_runs = 7
	_check(
		not ProfileMerge.validate(malformed).is_empty(),
		"profile derived count mismatch refused",
		failures
	)


func _same(result: GameResult, snapshot: Dictionary) -> bool:
	return (
		result.ok
		and SnapshotCodec.canonical_json(result.data) == SnapshotCodec.canonical_json(snapshot)
	)


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
