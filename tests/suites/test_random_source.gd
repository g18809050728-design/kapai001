extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_check(
		GameConstants.RANDOM_ALGORITHM == &"godot_pcg32_sha256_stream_v1",
		"random algorithm is explicitly pinned",
		failures
	)
	var source := RandomSource.new("42")
	var same_seed := RandomSource.new("42")
	_check(
		source.export_state().to_dictionary() == same_seed.export_state().to_dictionary(),
		"same seed creates identical independent stream snapshots",
		failures
	)
	var before_noop := source.export_state().to_dictionary()
	var fixed_draw := source.draw_int("map", 7, 7)
	_check(
		fixed_draw.ok and fixed_draw.data == 7,
		"equal draw bounds return their only value",
		failures
	)
	_check(
		source.export_state().to_dictionary() == before_noop,
		"equal draw bounds do not advance random state",
		failures
	)
	var before_map_draw := source.export_state().to_dictionary()
	source.draw_int("map", 0, 100)
	var after_map_draw := source.export_state().to_dictionary()
	for stream in ["reward", "event", "battle"]:
		_check(
			before_map_draw.streams[stream] == after_map_draw.streams[stream],
			"drawing from map leaves %s stream unchanged" % stream,
			failures
		)
	before_noop = after_map_draw
	var bad_range := source.draw_int("map", 2, 1)
	_check(not bad_range.ok, "invalid draw bounds are rejected", failures)
	var bad_stream := source.draw_int("not_registered", 0, 3)
	_check(not bad_stream.ok, "unregistered random streams are rejected", failures)
	_check(
		source.export_state().to_dictionary() == before_noop,
		"invalid draws do not change random state",
		failures
	)
	var ids: Array[String] = ["one", "two", "three", "four"]
	var shuffled := source.shuffle("battle", ids)
	_check(shuffled.ok, "registered random stream can shuffle", failures)
	_check(
		ids == ["one", "two", "three", "four"], "shuffle leaves its input array unchanged", failures
	)
	var checkpoint := source.export_state()
	var next_value := source.draw_int("battle", 0, 1000)
	var restored := RandomSource.new("other")
	var restore_result := restored.restore_state(checkpoint)
	var replay_value := restored.draw_int("battle", 0, 1000)
	_check(restore_result.ok, "complete random snapshots restore", failures)
	_check(
		next_value.data == replay_value.data, "restored stream reproduces the next draw", failures
	)
	var before_invalid_restore := restored.export_state().to_dictionary()
	var invalid_snapshot := checkpoint.to_dictionary()
	invalid_snapshot.streams.erase("event")
	var rejected_restore := restored.restore_state(invalid_snapshot)
	_check(not rejected_restore.ok, "incomplete random snapshots are rejected", failures)
	_check(
		restored.export_state().to_dictionary() == before_invalid_restore,
		"invalid snapshot restoration is atomic",
		failures
	)
	var out_of_range_snapshot := checkpoint.to_dictionary()
	out_of_range_snapshot.streams.event.state = "9223372036854775808"
	_check(
		(
			not restored.restore_state(out_of_range_snapshot).ok
			and restored.export_state().to_dictionary() == before_invalid_restore
		),
		"out-of-range 64-bit snapshot fields are rejected atomically",
		failures
	)
	var invalid_version := checkpoint.to_dictionary()
	invalid_version.algorithm_version += 1
	_check(
		not restored.restore_state(invalid_version).ok,
		"unsupported random algorithm versions are rejected",
		failures
	)
	var replay_source := RandomSource.new("all-streams")
	var replay_control := RandomSource.new("all-streams")
	for stream in RandomSource.STREAMS:
		var first_draw := replay_source.draw_int(stream, 0, 1000000)
		var control_draw := replay_control.draw_int(stream, 0, 1000000)
		_check(
			first_draw.ok and first_draw.data == control_draw.data,
			"independent stream reproduces its seeded draw: %s" % stream,
			failures
		)
	var all_stream_checkpoint := replay_source.export_state()
	var replay := RandomSource.new("different-seed")
	_check(
		replay.restore_state(all_stream_checkpoint).ok,
		"four-stream snapshot restores into an independent source",
		failures
	)
	for stream in RandomSource.STREAMS:
		var expected_draw := replay_source.draw_int(stream, 0, 1000000)
		var actual_draw := replay.draw_int(stream, 0, 1000000)
		_check(
			expected_draw.ok and expected_draw.data == actual_draw.data,
			"restored stream reproduces its next draw: %s" % stream,
			failures
		)
	_check(
		replay_source.export_state().to_dictionary() == replay.export_state().to_dictionary(),
		"all four restored streams match field-for-field after replay",
		failures
	)
	return failures


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
