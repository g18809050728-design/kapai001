extends RefCounted

var _failures: Array[String] = []


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var script := load("res://src/ui/battle/battle_damage_popup_layer.gd")
	_check(script != null, "damage popup layer loads")
	if script == null:
		return _failures
	var layer: Control = script.new()
	layer.size = Vector2(1280, 800)
	tree.root.add_child(layer)
	var before := Vector2(540, 280)
	var anchors := {"task_a": before, "task_b": Vector2(820, 280)}
	layer.queue_events([
		{"type": "completion_applied", "target_ids": ["task_a"], "data": {"amount": 12, "shield_before": 7, "shield_after": 0, "work_before": 10, "work_after": 5}},
		{"type": "completion_applied", "target_ids": ["task_b"], "data": {"amount": 8, "shield_before": 8, "shield_after": 0, "work_before": 10, "work_after": 10}},
		{"type": "completion_applied", "target_ids": ["task_a"], "data": {"amount": 20, "shield_before": 0, "shield_after": 0, "work_before": 3, "work_after": 0}}
	], anchors, true, 1.0)
	_check(layer.active_popup_snapshot().size() == 1 and layer.active_popup_snapshot()[0].text == "-5", "popup uses actual work loss after shield")
	layer.advance(0.13)
	_check(layer.active_popup_snapshot().size() == 2 and layer.active_popup_snapshot()[1].text == "-3", "shield-only event omitted and overkill capped")
	_check(layer.active_popup_snapshot()[0].position != layer.active_popup_snapshot()[1].position, "successive hits do not overlap")
	layer.clear_popups()
	layer.queue_events([
		RuleEvent.new(1, &"completion_applied", "unit_partner", ["task_a"], {"work_before": 10, "work_after": 6}),
		RuleEvent.new(2, &"completion_applied", "", ["task_b"], {"work_before": 8, "work_after": 5})
	], anchors, true, 1.0)
	layer.advance(0.13)
	var sourced: Array = layer.active_popup_snapshot()
	_check(sourced.size() == 2 and sourced[0].text == "-4" and sourced[1].text == "-3", "partner and ongoing effect events use actual work loss")
	layer.clear_popups()
	layer.queue_events([{"type": "completion_applied", "target_ids": ["task_a"], "data": {"work_before": 9, "work_after": 4}}], anchors, false, 1.0)
	var static_position: Vector2 = layer.active_popup_snapshot()[0].position
	layer.advance(0.1)
	_check(layer.active_popup_snapshot()[0].position == static_position, "reduced motion keeps feedback static")
	layer.clear_popups()
	layer.size = Vector2(960, 600)
	layer.queue_events([{"type": "completion_applied", "target_ids": ["task_b"], "data": {"work_before": 5, "work_after": 0}}], {"task_b": Vector2(945, 35)}, true, 1.0)
	var edge: Vector2 = layer.active_popup_snapshot()[0].position
	_check(edge.x >= 0 and edge.x + 100 <= layer.size.x and edge.y >= 0, "popup fits compact viewport at edge")
	layer.free()
	await _real_battle_hit()
	return _failures


func _real_battle_hit() -> void:
	var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
	var session := GameSession.new(SaveStore.new("user://damage-hit-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "damage popup production run starts")
	var shell := helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	_check(helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])), "damage popup fixture enters battle")
	var battle := shell.session._state.battle
	_check(battle != null, "damage popup has active battle state")
	if battle == null:
		shell.free()
		return
	var task_id := str(battle.tasks[0].task_id)
	battle.tasks[0].work_remaining = 20
	battle.tasks[0].shield = 0
	battle.player.focus = 10
	var card_id := str(battle.zones.hand[0]) if not battle.zones.hand.is_empty() else ""
	_check(not card_id.is_empty(), "damage popup fixture has a work card")
	if not card_id.is_empty():
		battle.card_by_id[card_id].definition_id = "R3-C-01"
		shell.refresh()
		await (Engine.get_main_loop() as SceneTree).process_frame
		var anchor: Vector2 = shell.page.damage_target_anchors()[task_id]
		var before := int(battle.tasks[0].work_remaining)
		_check(shell.press("card:" + card_id), "real work card is selected")
		_check(shell.press("task:" + task_id), "real work card hits task")
		var after := int(shell.session.get_view().battle.tasks[0].work_remaining)
		var popups: Array = shell._damage_layer.active_popup_snapshot()
		_check(popups.size() == 1 and popups[0].text == "-%d" % (before - after), "real battle popup matches committed work loss")
		if popups.size() == 1:
			_check(Vector2(popups[0].position).distance_to(anchor) < 110, "real battle popup stays near its task")
	shell.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
