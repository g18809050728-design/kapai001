extends SceneTree

const OUT := "res://artifacts/verification/v04-damage-20261105/visual"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var records: Array = []
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		await _capture_event(dimensions, records)
		await _capture_battle(dimensions, false, records)
		await _capture_battle(dimensions, true, records)
	var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	print("V04_DAMAGE_CAPTURE=", JSON.stringify(records))
	quit(0)


func _capture_event(dimensions: Vector2i, records: Array) -> void:
	var session := GameSession.new(SaveStore.new("user://capture-v04-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	if not session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted:
		push_error("event capture run failed")
		quit(1)
		return
	var state := session._state.run
	var node: RunNodeState = state.nodes.filter(func(value): return value.kind == "event" and value.term == 1)[0]
	var first: RunNodeState = state.nodes.filter(func(value): return value.term == 1 and value.layer == 1)[0]
	first.status = "completed"
	first.context["encounter_id"] = "N13"
	first.context["settled"] = true
	state.settled_battle_ids.append(first.node_id)
	state.node_path.append(first.node_id)
	node.status = "active"
	state.current_node_id = node.node_id
	state.seen_event_ids.append("V04")
	node.context["event"] = EventState.create({"event_instance_id": state.next_instance_id("event"), "node_id": node.node_id, "definition_id": "V04", "frozen_candidates": {"rest": {}, "upgrade_work": {}, "leave": {}}})
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	shell.press("event:upgrade_work")
	await _save("event-preview-%dx%d" % [dimensions.x, dimensions.y], shell, records)
	shell.free()
	await process_frame


func _capture_battle(dimensions: Vector2i, lethal: bool, records: Array) -> void:
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var session := GameSession.new(SaveStore.new("user://capture-damage-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false, "presentation": {"animation_speed": 1, "reduced_motion": false}})
	if not session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted:
		push_error("battle capture run failed")
		quit(1)
		return
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	if not helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])):
		push_error("battle capture entry failed")
		quit(1)
		return
	var battle := session._state.battle
	var task_id := str(battle.tasks[0].task_id)
	battle.tasks[0].work_remaining = 1 if lethal else 20
	battle.tasks[0].shield = 0
	battle.player.focus = 10
	var card_id := str(battle.zones.hand[0])
	battle.card_by_id[card_id].definition_id = "R3-C-01"
	shell.refresh()
	root.size = dimensions
	for index in 3:
		await process_frame
	print("V04_CAPTURE_ANCHOR=", dimensions, " ", shell.page.damage_target_anchors(), " layer=", shell._damage_layer.get_global_rect())
	if not shell.press("card:" + card_id):
		push_error("battle capture selection failed")
		quit(1)
		return
	for index in 2:
		await process_frame
	print("V04_CAPTURE_SELECTED_ANCHOR=", dimensions, " ", shell.page.damage_target_anchors())
	if not shell.press("task:" + task_id):
		push_error("battle capture hit failed")
		quit(1)
		return
	print("V04_CAPTURE_POPUP=", dimensions, " ", shell._damage_layer.active_popup_snapshot())
	await _save(("lethal" if lethal else "hit") + "-%dx%d" % [dimensions.x, dimensions.y], shell, records)
	shell.free()
	await process_frame


func _save(label: String, shell: GameShell, records: Array) -> void:
	for index in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT.path_join(label + ".png"))
	records.append({"label": label, "size": [root.size.x, root.size.y], "screen": str(shell.session.get_view().screen), "page": shell.page.get_class(), "popups": shell._damage_layer.active_popup_snapshot().map(func(value): return value.text), "save_error": code})
	if code != OK:
		push_error("capture failed: " + label)
		quit(1)
