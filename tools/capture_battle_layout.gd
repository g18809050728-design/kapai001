extends SceneTree

const OUT := "res://artifacts/verification/battle-layout-20261104/visual"
var shell: GameShell
var screens: Array = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var session := GameSession.new(SaveStore.new("user://battle-layout-capture-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "0"))
	shell = GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	if not helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])):
		push_error("capture could not enter battle")
		quit(1)
		return
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		for scale in [100, 125, 150]:
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			shell._apply_presentation()
			shell.refresh()
			_mouse_move(Vector2(10, 150))
			var suffix := "-%d-text%d" % [dimensions.x, scale]
			await _save("battle" + suffix)
			for kind in ["deck", "log", "draw", "discard", "exhaust"]:
				var entry: Button = shell.page._buttons["battle:" + kind]
				_mouse_move(entry.get_global_rect().get_center())
				await _save("hover-" + kind + suffix)
	root.size = Vector2i(1280, 800)
	session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await process_frame
	var base := shell.page.view.duplicate(true)
	for amount in [5, 10]:
		var display := base.duplicate(true)
		display.hand = []
		for i in amount:
			var card: Dictionary = base.hand[i % base.hand.size()].duplicate(true)
			card.card_id = "capture-card-%d" % i
			display.hand.append(card)
		_mouse_move(Vector2(10, 150))
		shell.page.render(display)
		await _save("hand-%d" % amount)
		for index in [0, amount / 2, amount - 1]:
			var card: BattleCard = shell.page._hand_cards[index]
			_mouse_move(card.get_parent().get_global_transform_with_canvas() * (card.home_position + Vector2(25 if index < amount - 1 else 100, 80)))
			await create_timer(0.4).timeout
			await _save("hand-%d-hover-%d" % [amount, index])
			_mouse_move(Vector2(10, 150))
			await create_timer(0.3).timeout
	for phases in [1, 2]:
		var display := base.duplicate(true)
		display.tasks[0].phase_count = phases
		display.tasks[0].phase_index = 1
		var target_id := str(display.tasks[0].task_id)
		display.statuses.append({"target_id": target_id, "status_id": "weakness", "stacks": 1})
		display.statuses.append({"target_id": target_id, "status_id": "feebleness", "stacks": 2})
		display.statuses.append({"target_id": display.player.entity_id, "status_id": "weakness", "stacks": 1})
		shell.page.render(display)
		await _save("status-%d-phases" % phases)
	shell.free()
	var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(screens, "\t"))
	file.close()
	print("BATTLE_LAYOUT_CAPTURE=", screens.size())
	quit(0)


func _mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)


func _save(label: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	screens.append({"name": label, "size": [root.size.x, root.size.y], "save_error": code, "controlled_presentation_fixture": label.begins_with("hand-") or label.begins_with("status-")})
	if code != OK:
		push_error("capture failed: " + label)
