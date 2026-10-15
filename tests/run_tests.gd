extends SceneTree


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--force-failure"):
		push_error("Forced failure probe")
		quit(1)
		return
	var suite_script: Script = load("res://tests/suites/test_g1_bootstrap.gd")
	var failures: Array[String] = []
	if suite_script != null and suite_script.can_instantiate():
		var suite = suite_script.new()
		failures.append_array(suite.run())
	else:
		failures.append("G1 bootstrap suite failed to load")
	var content_suite_script: Script = load("res://tests/suites/test_content_loader.gd")
	if content_suite_script != null and content_suite_script.can_instantiate():
		var content_suite = content_suite_script.new()
		failures.append_array(content_suite.run())
	else:
		failures.append("Content loader suite failed to load")
	var random_suite_script: Script = load("res://tests/suites/test_random_source.gd")
	if random_suite_script != null and random_suite_script.can_instantiate():
		var random_suite = random_suite_script.new()
		failures.append_array(random_suite.run())
	else:
		failures.append("Random source suite failed to load")
	var state_suite_script: Script = load("res://tests/suites/test_g2_state.gd")
	if state_suite_script != null and state_suite_script.can_instantiate():
		var state_suite = state_suite_script.new()
		failures.append_array(state_suite.run())
	else:
		failures.append("G2 state suite failed to load")
	var battle_phase_suite_script: Script = load("res://tests/suites/test_battle_phase_flow.gd")
	if battle_phase_suite_script != null and battle_phase_suite_script.can_instantiate():
		var battle_phase_suite = battle_phase_suite_script.new()
		failures.append_array(battle_phase_suite.run())
	else:
		failures.append("G3 battle phase suite failed to load")
	var battle_begin_suite_script: Script = load("res://tests/suites/test_battle_engine_begin.gd")
	if battle_begin_suite_script != null and battle_begin_suite_script.can_instantiate():
		var battle_begin_suite = battle_begin_suite_script.new()
		failures.append_array(battle_begin_suite.run())
	else:
		failures.append("G3 battle engine begin suite failed to load")
	for path in [
		"test_run_transactions",
		"test_run_nodes",
		"test_run_flow",
		"test_save_codec",
		"test_save_store",
		"test_snapshot_codec",
		"test_session_storage",
		"test_production_boss"
	]:
		var run_script: Script = load("res://tests/suites/%s.gd" % path)
		if run_script != null and run_script.can_instantiate():
			failures.append_array(run_script.new().run())
		else:
			failures.append("G4/G5 suite failed to load: " + path)
	if failures.is_empty():
		print("G1/G2/G3 headless tests passed")
		print("G4 headless tests passed")
		print("G5 headless tests passed")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
