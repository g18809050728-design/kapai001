extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = await _run_suites()
	# Release suite/script references before the tree exits and retires renderer resources.
	for _frame in 6:
		await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("G7 UI tests passed")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_suites() -> Array[String]:
	var failures: Array[String] = []
	for path in [
		"test_ui_compendium",
		"test_ui_text_editor",
		"test_web_account_permissions",
		"test_ui_account_navigation",
		"test_ui_character_art",
		"test_ui_enemy_art",
		"test_run_content_views",
		"test_ui_card_categories",
		"test_ui_semantic_vfx",
		"test_ui_shell_pages",
		"test_ui_save_seed",
		"test_ui_flow_feedback",
		"test_ui_flow_revision",
		"test_ui_battle_choice",
		"test_ui_choice_v3",
		"test_ui_battle_pointer",
		"test_ui_battle_polish",
		"test_ui_battle_layout",
		"test_ui_battle_status",
		"test_ui_battle_card_inspection",
		"test_ui_four_year",
		"test_ui_adaptive_maps",
		"test_ui_map_activation",
		"test_ui_navigation_revision",
		"test_ui_menu_relic_revision",
		"test_ui_usability",
		"test_ui_experience",
		"test_ui_followup",
		"test_ui_damage_popup",
		"test_ui_battle_map_feedback",
		"test_test_room_ui",
		"test_test_room_e2e"
	]:
		var script: Script = load("res://tests/suites/%s.gd" % path)
		if script == null or not script.can_instantiate():
			failures.append("G7 UI suite failed to load: " + path)
			continue
		var suite = script.new()
		var result = await suite.run()
		failures.append_array(result)
		suite = null
		script = null
	return failures

