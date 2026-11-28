extends SceneTree

const ShellFixtures = preload("res://tests/suites/test_ui_shell_pages.gd")
const SIZES := [Vector2i(568, 320), Vector2i(667, 375), Vector2i(844, 390), Vector2i(932, 430)]

var _failures: Array[String] = []
var _checks := 0
var _actor_heights: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	UiStyle.web_touch = true
	node_added.connect(MobileScroll.prepare_node)
	root.size = SIZES[1]
	var fixtures := ShellFixtures.new()
	var shell := fixtures.attach_shell(GameSession.new(SaveStore.new("user://mobile-layout-%s" % Time.get_ticks_usec())))
	await _verify_setup_and_compendium(shell)
	var started := shell.session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "starts a production game")
	shell.show_screen("")
	await _settle()
	var reachable: String = str(shell.session.get_view().run.reachable_node_ids[0])
	var before_map: String = fixtures.fingerprint(shell.session)
	for viewport_size in SIZES:
		root.size = viewport_size
		await _settle()
		var map := shell.page as UiExperiencePage
		for uid in ["map:enter", "map:current", "map:overview", "map:details", "map:abandon"]:
			_check_target(map, uid, viewport_size)
		_check(map._scroll.size.x >= viewport_size.x - 28 and map._scroll.size.y >= viewport_size.y - 124, "mobile route uses most of the landscape window at %s" % viewport_size)
	await _verify_route_details(shell, reachable)
	await _verify_abandon(shell, false)
	_check(before_map == fixtures.fingerprint(shell.session), "resizing and reading the map preserve run state")
	await _tap(shell.page._buttons["node:" + reachable])
	_check(shell.page is BattleScreen, "second tap on the same selected route node starts the first real battle")
	if not shell.page is BattleScreen:
		quit(1)
		return
	var before_battle: String = fixtures.fingerprint(shell.session)
	for percent in [100, 125, 150]:
		shell.session.update_settings({"presentation": {"text_scale": percent, "reduced_motion": true, "animation_speed": 0}})
		shell._apply_presentation()
		shell.refresh()
		for viewport_size in SIZES:
			root.size = viewport_size
			await _settle()
			var battle := shell.page as BattleScreen
			_check(battle._stage.size.is_equal_approx(battle.size) and battle._stage.scale.is_equal_approx(Vector2.ONE), "battle uses window coordinates at %s / %s%%" % [viewport_size, percent])
			for uid in ["battle:map", "battle:deck", "battle:options", "battle:draw", "battle:discard", "battle:exhaust", "battle:end_turn"]:
				_check_target(battle, uid, viewport_size)
			var hand := battle._touch_hand
			var hand_content := hand.get_child(-1) as HBoxContainer
			_check(hand.size.x > 200 and hand_content != null and hand.get_h_scroll_bar().max_value >= hand_content.get_combined_minimum_size().x, "entire hand is visible or scrollable at %s / %s%%" % [viewport_size, percent])
			var hand_bounds := hand.get_global_rect()
			var focus_bounds := (battle.find_child("FocusDevice", true, false) as Control).get_global_rect()
			var draw_bounds := (battle._buttons["battle:draw"] as Control).get_global_rect()
			_check(focus_bounds.end.x + 8 <= hand_bounds.position.x and hand_bounds.end.x + 8 <= draw_bounds.position.x, "focus, hand and piles each have their own space")
			for hand_card: BattleCard in battle._hand_cards:
				var bounds := hand_card.get_global_rect()
				if hand_bounds.intersects(bounds):
					_check(hand_bounds.encloses(bounds) and bounds.size.x < 128 and bounds.size.y > bounds.size.x, "resting hand shows whole portrait-shaped cards")
			for actor: BattleActorView in battle._actors.values():
				_check_actor(actor, viewport_size)
			var ddl := battle.find_child("TurnDdlValue", true, false) as Label
			_check(is_instance_valid(ddl) and ddl.get_theme_font_size("font_size") >= 17 and ddl.get_global_rect().size.x >= 134, "readable round and DDL in the top rail at %s / %s%%" % [viewport_size, percent])
			for intent: Label in battle.find_children("TaskIntent_*", "Label", true, false):
				_check(intent.get_theme_font_size("font_size") >= 14 and intent.get_global_rect().end.y < battle._touch_hand.global_position.y, "intent labels stay on the battlefield")
			_check(battle.tutorial_anchor("battle_intents").has_area() and battle.tutorial_anchor("battle_focus").has_area(), "tutorial anchors follow mobile controls")
			var card := battle._hand_cards.front() as BattleCard
			battle._pin_card_detail(battle._card_hover_target(card))
			await _settle()
			_check(battle._hover_panel.visible and battle.get_global_rect().encloses(battle._hover_panel.get_global_rect()), "full card detail fits at %s / %s%%" % [viewport_size, percent])
			battle.close_card_preview()
			_check(shell.press("battle:map"), "can open the read-only battle map")
			await _settle()
			_check(is_instance_valid(battle._full_map) and battle._full_map._content.vertical == UiStyle.narrow_touch(battle.size), "map adapts its route and details")
			_check(not shell.press("battle:end_turn"), "read-only map blocks the battle")
			await _tap(battle._buttons["battle:close_panel"])
			_check(not is_instance_valid(battle._full_map), "tapping return closes the read-only map")
			for pile in ["draw", "discard", "exhaust", "deck"]:
				await _tap(battle._buttons["battle:" + pile])
				_check(battle._panel_zone == pile, "touch opens " + pile)
				if battle._panel_zone != pile:
					continue
				if pile == "draw":
					for uid in battle._buttons:
						if str(uid).begins_with("pile:card:"):
							await _tap_point(battle._visible_card_rect(battle._buttons[uid]).get_center())
							_check(battle._hover_panel.visible, "tap a pile card to open its full detail")
							await _tap(battle._touch_detail_close)
							_check(not battle._hover_panel.visible and battle._panel_zone == "draw", "tapping the card close returns to the open pile")
							break
				await _tap(battle._buttons["battle:close_panel"])
				_check(battle._panel_zone.is_empty(), "tapping return closes " + pile + " at %s" % viewport_size)
				if not battle._panel_zone.is_empty():
					battle._close_panel()
					await _settle()
	_check(before_battle == fixtures.fingerprint(shell.session), "reading, resizing and settings preserve the battle state")
	root.size = SIZES[2]
	await _settle()
	var current := shell.page as BattleScreen
	var first_card := current._hand_cards.front() as BattleCard
	var press := InputEventScreenTouch.new()
	press.position = first_card.get_global_rect().get_center()
	press.pressed = true
	Input.parse_input_event(press)
	await create_timer(.62).timeout
	_check(current._hover_panel.visible and not current._pinned_card_detail.is_empty(), "stationary touch opens the full card detail")
	var release := InputEventScreenTouch.new()
	release.position = press.position
	Input.parse_input_event(release)
	await _settle()
	_check(before_battle == fixtures.fingerprint(shell.session), "releasing after a long press preserves the run state")
	current.close_card_preview()
	await _verify_selection_restore(current)
	await _verify_hand_snap(current)
	_verify_roster(current)
	shell.queue_free()
	await process_frame
	UiStyle.web_touch = false
	node_added.disconnect(MobileScroll.prepare_node)
	root.size = Vector2i(960, 600)
	var desktop := fixtures.attach_shell(GameSession.new(SaveStore.new("user://desktop-abandon-%s" % Time.get_ticks_usec())))
	_check(desktop.session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "desktop fixture starts a production run")
	desktop.show_screen("")
	await _settle()
	await _verify_abandon(desktop, true)
	desktop.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("UI_MOBILE_ACTOR_HEIGHTS ", JSON.stringify(_actor_heights))
	print("UI_MOBILE_LAYOUT checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _verify_setup_and_compendium(shell: GameShell) -> void:
	_check(shell.press("menu:compendium"), "mobile guest opens the actual compendium")
	for percent in [100, 125, 150]:
		shell.session.update_settings({"presentation": {"text_scale": percent, "reduced_motion": true, "animation_speed": 0}})
		shell._apply_presentation()
		shell.refresh()
		for viewport_size in [SIZES[0], SIZES[2]]:
			root.size = viewport_size
			await _settle()
			var gallery := shell.page as UiCompendiumPage
			for tab in ["cards", "monsters", "relics"]:
				gallery.show_tab(tab)
				await _settle()
				var tile: Button = gallery._grid.get_child(0)
				_check(gallery._scroll.get_global_rect().encloses(tile.get_global_rect()), "first %s tile fits completely in %s at %d%%" % [tab, viewport_size, percent])
				_check(gallery.get_global_rect().encloses(gallery._filters.get_global_rect()), "all %s filters fit in %s at %d%%" % [tab, viewport_size, percent])
				await _tap(tile)
				var detail := gallery.detail
				_check(is_instance_valid(detail), "tap opens %s detail" % tab)
				if is_instance_valid(detail):
					_check(detail._visual.size.y >= 130 and detail._scroll.size.y >= 130 and detail._visual.get_global_rect().end.x <= detail._scroll.global_position.x, "%s model and description fit side by side" % tab)
					_check_target(detail, "compendium:detail:close", viewport_size)
					await _tap(detail._buttons["compendium:detail:close"])
					_check(not is_instance_valid(gallery.detail), "tap closes %s detail" % tab)
	await _tap(shell.page._buttons["compendium:back"])
	_check(shell.press("menu:new"), "mobile guest opens the real setup screen")
	for percent in [100, 125, 150]:
		shell.session.update_settings({"presentation": {"text_scale": percent}})
		shell._apply_presentation()
		shell.refresh()
		for viewport_size in [SIZES[0], SIZES[2]]:
			root.size = viewport_size
			await _settle()
			var setup := shell.page as UiExperiencePage
			for uid in ["setup:back", "setup:deck", "setup:advanced", "setup:start", "setup:difficulty:relaxed", "setup:difficulty:normal", "setup:difficulty:hard"]:
				_check_target(setup, uid, viewport_size)
			for id in ["P01", "P02", "P03", "P04"]:
				_check_target(setup, "setup:character:" + id, viewport_size)
				await _tap(setup._buttons["setup:character:" + id])
				var actor := setup._room_figure
				var rig := actor.rig
				_check(is_instance_valid(rig), "%s uses the production rig" % id)
				if not is_instance_valid(rig):
					continue
				var art := Transform2D(0, rig.scale, 0, rig.position) * rig._rest_art_bounds
				_check(actor.definition_id == id and setup.action_draft("setup:start").payload.character_id == id, "touch selection is used by the real start draft")
				_check(art.size.y >= 100 and Rect2(Vector2.ZERO, actor.size).encloses(art) and actor.get_global_rect().end.x < setup._scroll.global_position.x, "%s model fits beside the introduction at %s / %d%%" % [id, viewport_size, percent])
	shell.session.update_settings({"presentation": {"text_scale": 100}})
	shell._apply_presentation()
	await _tap(shell.page._buttons["setup:back"])


func _verify_route_details(shell: GameShell, id: String) -> void:
	var map := shell.page as UiExperiencePage
	var node: Button = map._buttons["node:" + id]
	var bounds := node.get_global_rect()
	var scroll := map._scroll.scroll_vertical
	await _tap(node)
	_check(map._choices.get("map:node") == id and node.get_global_rect() == bounds, "tap selects the route node without moving it")
	await _tap(map._buttons["map:details"])
	_check(map._map_details_layer.visible and map._map_preview_scroll.size.x >= 480 and map._map_preview_scroll.scroll_vertical == 0, "touch opens a wide detail panel starting at the selected node")
	_check((map.find_child("PreviewNodeTitle", true, false) as Label).text == map._map_node_title(map.view.nodes.filter(func(value): return value.node_id == id)[0]), "detail shows the selected node title")
	await _tap(map._buttons["map:close_details"])
	_check(not map._map_details_layer.visible and node.get_global_rect() == bounds and map._scroll.scroll_vertical == scroll, "closing details preserves map position and selection")


func _verify_abandon(shell: GameShell, desktop: bool) -> void:
	var map := shell.page as UiExperiencePage
	var before := ShellFixtures.new().fingerprint(shell.session)
	var original: Button = map._buttons["map:abandon"]
	var bounds := original.get_global_rect()
	var scroll := map._scroll.scroll_vertical
	_check(not map.button_uids().has("map:abandon_confirm"), "abandon is initially unarmed")
	if desktop:
		shell.press("map:abandon")
	else:
		await _tap(original)
	var confirm: Button = map._buttons.get("map:abandon_confirm")
	_check(is_instance_valid(confirm) and not confirm.disabled and confirm.get_global_rect() == bounds, "confirmation uses the exact original target on desktop=%s" % desktop)
	_check(ShellFixtures.new().fingerprint(shell.session) == before and map._scroll.scroll_vertical == scroll, "opening abandon confirmation preserves run and route position")
	if desktop:
		shell.press("map:abandon")
	else:
		await _tap(original)
	_check(not map.button_uids().has("map:abandon_confirm") and original.get_global_rect() == bounds and ShellFixtures.new().fingerprint(shell.session) == before, "cancel restores the original map action on desktop=%s" % desktop)
	if desktop:
		_check(shell.press("map:abandon") and shell.press("map:abandon_confirm") and shell.session.get_view().terminal_summary.result == "abandoned", "the armed desktop button submits one actual abandon command")


func _verify_selection_restore(battle: BattleScreen) -> void:
	for card: BattleCard in battle._hand_cards:
		var id := str(card.card_data.card_id)
		var draft := {"type": "play_card", "payload": {"card_instance_id": id, "target_ids": [], "replace_unit_id": null}}
		var preview: Variant = battle._preview(draft)
		if not battle._may_select(preview) or battle._required(preview).is_empty():
			continue
		await _tap(card)
		_check(battle._selected_card_id == id and battle._feedback_text.is_empty(), "selecting a target card keeps its highlight without an instruction")
		await _tap(battle._buttons["battle:draw"])
		await _tap(battle._buttons["battle:close_panel"])
		_check(battle._selected_card_id == id, "returning from a pile preserves the selected hand card")
		_check(root.gui_get_focus_owner() == battle._buttons["battle:draw"], "returning from a pile restores the opening button's focus")
		battle._cancel_selection()
		await _settle()
		return
	_check(false, "the production fixture offers a playable targeted card")


func _verify_hand_snap(battle: BattleScreen) -> void:
	var original := battle.view.duplicate(true)
	var crowded := original.duplicate(true)
	crowded.hand = []
	for index in 10:
		var data: Dictionary = original.hand[index % original.hand.size()].duplicate(true)
		data.card_id = "mobile-hand-%d" % index
		crowded.hand.append(data)
	battle.render(crowded)
	await _settle()
	var hand := battle._touch_hand
	var stride := roundi(battle._hand_cards[1].position.x - battle._hand_cards[0].position.x)
	hand.scroll_horizontal = stride + 12
	hand.scroll_ended.emit()
	await _settle()
	_check(hand.scroll_horizontal == stride, "partial scroll settles at a whole-card boundary")
	var visible := hand.get_global_rect()
	for card: BattleCard in battle._hand_cards:
		var bounds := card.get_global_rect()
		if visible.intersects(bounds):
			_check(visible.encloses(bounds), "the crowded hand leaves only full cards visible after settling")
	battle.render(original)
	await _settle()


func _verify_roster(battle: BattleScreen) -> void:
	var original := battle.view.duplicate(true)
	var sample := original.duplicate(true)
	var enemy_ids := ["N01", "N03", "E01", "B01"]
	var roster := EnemyArt.ids()
	var seed_task: Dictionary = original.tasks[0]
	for i in 4:
		sample.character_id = "P%02d" % (i + 1)
		sample.tasks = []
		for index in range(1, mini(4, i + 2)):
			var task := seed_task.duplicate(true)
			task.task_id = "mobile-preview-%d" % index
			task.definition_id = enemy_ids[(i + index) % 4] if roster.has(enemy_ids[(i + index) % 4]) else roster[index + i]
			sample.tasks.append(task)
		battle.render(sample)
		for actor: BattleActorView in battle._actors.values():
			_check_actor(actor, SIZES[2])
		if sample.tasks.size() == 3:
			var lane := battle._touch_tasks
			var content := lane.get_child(-1) as HBoxContainer
			_check(content.get_combined_minimum_size().x <= lane.size.x, "three enemies fit together at 844×390")
	battle.render(original)


func _check_actor(actor: BattleActorView, viewport_size: Vector2i) -> void:
	var rig := actor.rig
	_check(is_instance_valid(rig) and actor.fit_mobile_stage, "%s uses the selected native rig at %s" % [actor.definition_id, viewport_size])
	if not is_instance_valid(rig):
		return
	var art := Transform2D(0, rig.scale, 0, rig.position) * rig._rest_art_bounds
	var key := "%s %s" % [actor.definition_id, viewport_size]
	_actor_heights[key] = mini(roundi(art.size.y), int(_actor_heights.get(key, 1000)))
	_check(Rect2(Vector2.ZERO, actor.size).encloses(art) and art.size.y >= 29, "%s keeps the whole visible art in its battlefield slot at %s" % [actor.definition_id, viewport_size])


func _check_target(page: UiPage, uid: String, viewport_size: Vector2i) -> void:
	var control := page._buttons.get(uid) as Button
	_check(is_instance_valid(control) and control.size.y >= 44 and page.get_global_rect().encloses(control.get_global_rect()), "%s fits the window and has a 44-point target at %s" % [uid, viewport_size])


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures.append(description)


func _tap(control: Control) -> void:
	await _tap_point(control.get_global_rect().get_center())


func _tap_point(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		await process_frame
	await _settle()


func _settle() -> void:
	for index in 5:
		await process_frame
