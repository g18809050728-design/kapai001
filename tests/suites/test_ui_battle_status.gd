extends RefCounted

var failures: Array[String] = []
var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var capture_enabled := false
var checks := 0
const OUT := "res://artifacts/verification/battle-buff-20261126"


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	var shell: GameShell = helpers.attach_shell(
		GameSession.new(SaveStore.new("user://buff-%d" % Time.get_ticks_usec()))
	)
	shell.session.update_settings(
		{"autosave": false, "presentation": {"reduced_motion": true, "animation_speed": 0}}
	)
	_check(
		(
			shell
			. session
			. start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
			. accepted
		),
		"start P03"
	)
	shell.show_screen("")
	_check(
		helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])),
		"enter actual battle"
	)
	await _frames()
	var page := shell.page as BattleScreen
	page._finish_event_presentation()
	# Locate the authored erosion starter through ordinary draws, then play it.
	for round_index in 4:
		var poison := ""
		for card in page.view.hand:
			if card.definition_id == "R3-P03-01":
				poison = str(card.card_id)
		if not poison.is_empty():
			_check(shell.press("card:" + poison), "select poison starter")
			_check(
				shell.press("task:" + str(page.view.tasks[0].task_id)),
				"play poison on living target"
			)
			break
		shell.press("battle:end_turn")
		await _frames()
		page._finish_event_presentation()
	page = shell.page as BattleScreen
	_check(
		page._buttons.values().any(
			func(button): return button is BattleStatusSlot and button.entry.key == "erosion"
		),
		"real card command creates monster erosion slot"
	)
	var original: String = helpers.fingerprint(shell.session)
	var base := page.view.duplicate(true)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			tree.root.size = dimensions
			UiStyle.text_scale = scale / 100.0
			await _frames()
			var display := base.duplicate(true)
			display.statuses = []
			for key in ["anxiety", "procrastination", "drowsiness", "inspiration", "work_boost"]:
				display.statuses.append(
					{"target_id": display.player.entity_id, "status_id": key, "stacks": 2}
				)
			display.v3.abilities = [
				{
					"definition_id": "R3-C-06",
					"activate_round": int(display.round_index) + 1,
					"trigger": "first_work",
					"effects": [{"op": "add_work_bonus", "amount": 2}]
				}
			]
			display.v3.pending_work_bonus = 5
			display.tasks = []
			for index in 3:
				var task: Dictionary = base.tasks[0].duplicate(true)
				task.task_id = "status-task-%d" % index
				display.tasks.append(task)
				for key in [
					"erosion",
					"induced",
					"brittle",
					"feebleness",
					"weakness",
					"vulnerability",
					"attack_immunity"
				]:
					display.statuses.append(
						{"target_id": task.task_id, "status_id": key, "stacks": index + 1}
					)
			page.render(display)
			await _frames()
			for name in [
				"PlayerStatusBar",
				"TaskStatusBar_status-task-0",
				"TaskStatusBar_status-task-1",
				"TaskStatusBar_status-task-2"
			]:
				var bar := page._stage.get_node(name) as ScrollContainer
				_check(
					page.get_global_rect().encloses(bar.get_global_rect()),
					name + " inside viewport"
				)
				_check(bar.position.y + bar.size.y <= 548, name + " ends before resting hand")
				_check(bar.get_h_scroll_bar().max_value > bar.size.x, name + " overflow scrolls")
				for slot: BattleStatusSlot in bar.find_children("*", "Button", true, false):
					_check(
						(
							slot.get_global_rect().size.x >= 43.9
							and slot.get_global_rect().size.y >= 43.9
						),
						"physical target >=44"
					)
			var uid := "buff:status-task-1:feebleness"
			var slot: BattleStatusSlot = page._buttons[uid]
			var away := InputEventMouseMotion.new()
			away.position = Vector2(10, 150)
			away.global_position = away.position
			tree.root.push_input(away, true)
			slot.grab_focus()
			await _frames()
			_check(
				page._hover_target.get("uid", "") == uid,
				"keyboard focus explains individual status"
			)
			_check(
				page._buff_hover_target(uid).body.contains("×2"), "description uses actual ruleset"
			)
			_check(page.press(uid) and page._panel_text.contains("乏力"), "click opens effect detail")
			_check(
				helpers.fingerprint(shell.session) == original,
				"inspection preserves domain/RNG/revision"
			)
			page._close_panel()
			await _frames()
			_check(
				tree.root.gui_get_focus_owner() == page._buttons[uid], "close restores status focus"
			)
			# Actual pointer and wheel input must address the status, not its task/card.
			var visible_uid := "buff:status-task-0:erosion"
			var visible_slot: BattleStatusSlot = page._buttons[visible_uid]
			var point := visible_slot.get_global_rect().get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = point
			tree.root.push_input(motion, true)
			await _frames()
			_check(page._hover_target.get("uid", "") == visible_uid, "pointer identifies status")
			_check(page._hover_panel.visible, "status hover explanation is visible")
			for down in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = point
				click.global_position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = down
				tree.root.push_input(click, true)
			await _frames()
			_check(page._panel_text.contains("侵蚀"), "real click opens status instead of targeting")
			page._close_panel()
			await _frames()
			var visible_bar: ScrollContainer = page._buttons[visible_uid].get_meta("status_scroll")
			var wheel := InputEventMouseButton.new()
			wheel.position = point
			wheel.global_position = point
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			tree.root.push_input(wheel, true)
			await _frames()
			_check(visible_bar.scroll_horizontal > 0, "wheel scroll exposes additional buffs")
			_check(
				helpers.fingerprint(shell.session) == original, "pointer and wheel are read only"
			)
			if capture_enabled:
				await _capture(tree, "battle-%d-%d" % [dimensions.x, scale])
			# Same target changes and phase replacement remove stale badges.
			display.statuses = [
				{"target_id": "status-task-0", "status_id": "erosion", "stacks": 7},
				{"target_id": "status-task-0", "status_id": "weakness", "stacks": 0}
			]
			page.render(display)
			await _frames()
			_check(
				page._buttons["buff:status-task-0:erosion"].entry.count == 7,
				"layer changes refresh"
			)
			_check(
				(
					not page._buttons.has("buff:status-task-0:weakness")
					and not page._buttons.has("buff:status-task-1:erosion")
				),
				"zero and removed target statuses disappear"
			)
			_check(
				(
					(
						page
						. _stage
						. get_node("TaskStatusBar_status-task-1")
						. find_children("*", "Label", true, false)[0]
						. text
					)
					== "暂无状态"
				),
				"empty slot is retained"
			)
	shell.free()
	tree.root.size = old_size
	UiStyle.text_scale = 1
	print(
		"BATTLE_BUFF_CHECKS=",
		JSON.stringify(
			{
				"checks": checks,
				"failures": failures,
				"sizes": [1280, 960],
				"scales": [100, 125, 150]
			}
		)
	)
	return failures


func _frames() -> void:
	for i in 8:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _capture(tree: SceneTree, label: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await RenderingServer.frame_post_draw
	_check(
		tree.root.get_texture().get_image().save_png(OUT.path_join(label + ".png")) == OK,
		"capture " + label
	)


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
