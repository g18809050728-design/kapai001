extends RefCounted

const OUT := "res://artifacts/verification/card-dwell-20261106/visual"
var capture_enabled := false
var _captures: Array = []
var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _shell: GameShell


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	_shell = _helpers.attach_shell(GameSession.new(SaveStore.new("user://card-dwell-%d" % Time.get_ticks_usec())))
	_shell.session.update_settings({"autosave": false})
	_shell.session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	_shell.show_screen("")
	_helpers.enter_node(_shell, str(_shell.session.get_view().run.reachable_node_ids[0]))
	var fingerprint: String = _helpers.fingerprint(_shell.session)
	for fixture in [
		{"size": Vector2i(1280, 800), "scale": 100, "hand": 5},
		{"size": Vector2i(1280, 800), "scale": 100, "hand": 10},
		{"size": Vector2i(960, 600), "scale": 100, "hand": 5},
		{"size": Vector2i(960, 600), "scale": 150, "hand": 5},
	]:
		tree.root.size = fixture.size
		_shell.session.update_settings({"presentation": {"text_scale": fixture.scale, "reduced_motion": true, "animation_speed": 0}})
		_shell._apply_presentation()
		_shell.refresh()
		await _frames()
		var battle := _shell.page as BattleScreen
		var shown := battle.view.duplicate(true)
		var originals: Array = shown.hand.duplicate(true)
		shown.hand = []
		for index in int(fixture.hand):
			var card: Dictionary = originals[index % originals.size()].duplicate(true)
			card.card_id = "dwell-card-%d" % index
			shown.hand.append(card)
		battle.render(shown)
		await _frames()
		if battle._compact_layout:
			battle._scroll.scroll_vertical = 100000
			await _frames()
		var label := "%d-%d-%d" % [fixture.size.x, fixture.scale, fixture.hand]
		var first: Button = battle._buttons["card:dwell-card-0"]
		var second: Button = battle._buttons["card:dwell-card-1"]
		_move(_point(first))
		await _frames(2)
		_check(not battle._hover_panel.visible, label + " brief hover stays closed")
		await tree.create_timer(.38).timeout
		_move(_point(second))
		await tree.create_timer(.38).timeout
		_check(not battle._hover_panel.visible, label + " switching resets the dwell timer")
		await tree.create_timer(.38).timeout
		_check(battle._hover_panel.visible and battle._hover_body.text == str(battle._hover_target.get("detail", "")), label + " sustained hover opens complete details")
		_check(battle._hover_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + " unfixed details pass pointer input")
		_check_side(battle, battle._hover_target, label)
		await _save("dwell-open-" + label)
		_move(Vector2(5, fixture.size.y * .5))
		_check(not battle._hover_panel.visible, label + " leaving the card immediately hides its introduction")
		_move(_point(first))
		await _frames(2)
		_key(KEY_I)
		await _frames()
		var fixed: Dictionary = battle._pinned_card_detail.duplicate(true)
		_check(str(fixed.get("uid", "")) == "card:dwell-card-0" and battle._hover_panel.visible, label + " I pins the current card immediately")
		_move(Vector2(5, fixture.size.y * .5))
		await tree.create_timer(.75).timeout
		_check(battle._hover_panel.visible and battle._hover_body.text == str(fixed.get("detail", "")), label + " fixed content survives pointer departure")
		_move(_point(second))
		await tree.create_timer(.75).timeout
		_check(battle._pinned_card_detail == fixed and battle._hover_body.text == str(fixed.get("detail", "")), label + " another card cannot replace the fixed introduction")
		_check(not is_instance_valid(battle._card_preview) and battle._panel_text.is_empty(), label + " only one card introduction exists")
		_check_side(battle, fixed, label + " fixed")
		await _save("dwell-fixed-" + label)
		_key(KEY_I)
		_check(battle._pinned_card_detail.is_empty() and not battle._hover_panel.visible, label + " second I cancels fixing")
		await _frames(2)
		_check(not battle._hover_panel.visible, label + " unfixing restarts the dwell timer")
		_key(KEY_I)
		_key(KEY_ESCAPE)
		_check(battle._pinned_card_detail.is_empty() and not battle._hover_panel.visible, label + " Esc also releases the single fixed introduction")
		_move(Vector2(5, fixture.size.y * .5))
	_check(_helpers.fingerprint(_shell.session) == fingerprint, "all dwell/fix/unfix inspection preserves domain, RNG and revision")
	_shell.free()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	print("BATTLE_CARD_DWELL=", JSON.stringify({"delay_seconds": .7, "sizes": ["1280x800", "960x600"], "hand_counts": [5, 10], "real_mouse_and_keys": true, "failures": _failures}))
	return _failures


func _point(card: Button) -> Vector2:
	if card is BattleCard:
		var home := Transform2D(card.home_rotation, card.home_position + card.pivot_offset)
		return card.get_parent().get_global_transform_with_canvas() * (home * (Vector2(24, 90) - card.pivot_offset))
	var bounds := card.get_global_rect()
	var ancestor := card.get_parent()
	while ancestor is Control:
		if ancestor.clip_contents:
			bounds = bounds.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	_check(bounds.has_area(), "fixture card is visible before pointer input")
	return bounds.get_center()


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


func _check_side(battle: BattleScreen, target: Dictionary, label: String) -> void:
	var card: Rect2 = target.get("rect", Rect2())
	var panel := battle._hover_panel.get_global_rect()
	_check(panel.end.x <= card.position.x - 10 or panel.position.x >= card.end.x + 10, label + " introduction sits beside its source card")
	_check(battle.get_global_rect().encloses(panel), label + " side introduction remains inside the window")
	_check(panel.end.y > card.position.y and panel.position.y < card.end.y, label + " introduction stays vertically associated with its source card")


func _frames(count: int = 8) -> void:
	for index in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _save(label: String) -> void:
	if not capture_enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await RenderingServer.frame_post_draw
	var viewport := (Engine.get_main_loop() as SceneTree).root
	var result := viewport.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	_check(result == OK, "screenshot saved: " + label)
	_captures.append({"name": label, "width": viewport.size.x, "height": viewport.size.y, "save_error": result})


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("card dwell: " + message)
