extends SceneTree

const OUT := "res://artifacts/verification/ui-125-20261120"
const SCALE := 125
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	await _capture_menu_setup_map()
	await _capture_battle_and_choice()
	await _capture_reward()
	await _capture_node("shop", "08-shop")
	await _capture_node("rest", "09-rest")
	await _capture_node("event", "10-event")
	await _capture_settings_compendium()
	print("UI125_CAPTURE=passed")
	quit(0)


func _new_shell(tag: String) -> GameShell:
	var session := GameSession.new(
		SaveStore.new("user://ui125-%s-%d" % [tag, Time.get_ticks_usec()])
	)
	session.update_settings(
		{
			"autosave": false,
			"presentation":
			{"text_scale": SCALE, "reduced_motion": true, "animation_speed": 0}
		}
	)
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	return shell


func _capture_menu_setup_map() -> void:
	var shell := _new_shell("main")
	shell.show_screen("")
	await _save("01-menu")
	shell.press("menu:new")
	await _save("02-setup")
	shell.session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	shell.show_screen("")
	await _save("03-map")
	var node_id := str(shell.session.get_view().run.reachable_node_ids[0])
	_helpers.enter_node(shell, node_id)
	await _save("04-production-battle")
	shell.free()


func _capture_battle_and_choice() -> void:
	var shell := _new_shell("testroom")
	shell.session.start_test_room(
		{
			"character_id": "P01",
			"cards": ["R3-P01-11", "R3-P01-11", "R3-P01-02", "R3-P01-02", "R3-P01-02"],
			"seed": "42",
		}
	)
	shell.show_screen("")
	await _save("05-testroom-battle")
	var strategy_id := _hand(shell, "R3-P01-11")
	var work_id := _hand(shell, "R3-P01-02")
	if not strategy_id.is_empty() and not work_id.is_empty():
		shell.press("card:" + strategy_id)
		shell.press("card:" + work_id)
		var tasks: Array = shell.session.get_test_view().get("battle", {}).get("tasks", [])
		if not tasks.is_empty():
			shell.press("task:" + str(tasks[0].get("task_id", "")))
			await _save("06-p01-retrieve-choice")
	shell.free()


func _capture_reward() -> void:
	var shell: GameShell = _helpers.start_fixture_shell(
		"user://ui125-reward-%d" % Time.get_ticks_usec()
	)
	_helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0]))
	_helpers.finish_battle(shell)
	await _save("07-reward")
	shell.free()


func _capture_node(kind: String, label: String) -> void:
	var shell := _new_shell(kind)
	shell.session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	var run := shell.session._state.run
	run.campaign = CampaignService.initial()
	run.nodes = CampaignMap.build(run.run_id)
	var target: RunNodeState = null
	for node: RunNodeState in run.nodes:
		if node.term == 1 and node.kind == kind:
			target = node
			break
	if target == null:
		push_error("UI125 missing node: " + kind)
		shell.free()
		return
	for node: RunNodeState in run.nodes:
		if node.term == 1 and node.layer < target.layer and node.node_id.ends_with("s0"):
			node.status = "completed"
			run.node_path.append(node.node_id)
			run.current_node_id = node.node_id
	shell.show_screen("")
	_helpers.enter_node(shell, target.node_id)
	await _save(label)
	shell.free()


func _capture_settings_compendium() -> void:
	var shell := _new_shell("pages")
	shell.show_screen("settings")
	await _save("11-settings")
	shell.page._scroll.scroll_vertical = int(shell.page._scroll.get_v_scroll_bar().max_value)
	await _save("11b-settings-bottom")
	shell.show_screen("compendium")
	await _save("12-compendium")
	shell.free()


func _hand(shell: GameShell, definition_id: String) -> String:
	for card in shell.session.get_test_view().get("battle", {}).get("hand", []):
		if str(card.get("definition_id", "")) == definition_id:
			return str(card.get("card_id", ""))
	return ""


func _save(label: String) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT.path_join(label + ".png"))
	if code != OK:
		push_error("UI125 capture failed: " + label)
		quit(1)
