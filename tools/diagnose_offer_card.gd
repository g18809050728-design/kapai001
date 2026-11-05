extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var shell: GameShell = helpers.start_fixture_shell("user://card-geometry")
	helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0]))
	helpers.finish_battle(shell)
	for i in 6:
		await process_frame
	var item: Dictionary = shell.session.get_view().run.pending_reward.items[0]
	var uid := "reward:%s:pick:%s" % [item.item_id, item.candidates[0]]
	for phase in 3:
		var card: UiOfferCard = shell.page._buttons[uid]
		if phase == 1:
			var point := card.get_global_rect().get_center()
			var move := InputEventMouseMotion.new()
			move.position = point
			Input.parse_input_event(move)
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				Input.parse_input_event(click)
		if phase == 2:
			card.grab_focus()
		for frame in 30:
			await process_frame
			card = shell.page._buttons[uid]
			if frame in [0, 5, 15, 29]:
				print("CARD_GEOMETRY ", phase, " ", frame, " size=", card.size, " min=", card.custom_minimum_size, " face=", card._face.size, " facemin=", card._face.get_combined_minimum_size(), " offsets=", card._face.offset_top, ",", card._face.offset_bottom)
				if is_instance_valid(shell.page._card_preview):
					print("PREVIEW_GEOMETRY rect=", shell.page._card_preview.get_global_rect(), " scroll=", shell.page._scroll.get_global_rect(), " page=", shell.page.get_global_rect())
	shell.free()
	quit()
