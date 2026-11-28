extends SceneTree

const ShellFixtures = preload("res://tests/suites/test_ui_shell_pages.gd")
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	UiStyle.web_touch = true
	node_added.connect(MobileScroll.prepare_node)
	root.size = Vector2i(568, 320)
	var session := GameSession.new(SaveStore.new("user://collections-records-%s" % Time.get_ticks_usec()))
	var shell := ShellFixtures.new().attach_shell(session)
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "production run starts")
	shell.show_screen("")
	await _settle()
	for dimensions in [Vector2i(568, 320), Vector2i(844, 390)]:
		root.size = dimensions
		for percent in [100, 125, 150]:
			session.update_settings({"presentation": {"text_scale": percent}})
			shell._apply_presentation()
			shell.refresh()
			await _settle()
			await _verify_collections(shell.page as UiExperiencePage)
	var run := session.get_view()
	var route_id := str(run.run.reachable_node_ids[0])
	var entered := session.submit(CommandContext.new(str(run.run_id), run.revision), GameAction.new(&"enter_node", {"node_id": route_id}))
	_check(entered.accepted and entered.view.battle is Dictionary, "route opens a real battle")
	for _turn in 12:
		run = session.get_view()
		if run.battle == null:
			break
		var action := session.submit(CommandContext.new(str(run.run_id), run.revision), GameAction.new(&"end_turn", {}))
		if not action.accepted:
			_check(false, "battle end turn is accepted")
			break
	var archive := session.get_game_records()
	_check(archive.ok and archive.data.size() == 1, "terminal battle archives one native match")
	if archive.ok and archive.data.size() == 1 and archive.data[0].has("detail"):
		var record: Dictionary = archive.data[0]
		_check(record.result == "lost" and record.detail.cards.size() == 12, "settlement saves the real card instances and loss")
		_check(record.detail.route.size() == 1 and record.detail.route[0].status == "battle_lost", "entered node and exact battle result are archived")
		_check(record.detail.vitality == 0 and record.detail.money == 60 and record.detail.settled_battles == 1 and record.detail.completed_nodes == 0, "actual defeat records zero vitality and one settled battle without clearing the node")
		shell.show_screen("records")
		await _settle()
		await _verify_record(shell)
		UiStyle.web_touch = false
		root.size = Vector2i(1280, 800)
		shell.refresh()
		await _settle()
		await _verify_record(shell)
		var reopened := GameSession.new(session._store)
		_check(reopened.get_game_records().data[0].detail == record.detail, "details survive reloading the local archive")
		reopened.free()
	else:
		_check(false, "native match contains saved detail")
	shell.queue_free()
	await _settle()
	_verify_restart()
	print("COLLECTIONS_RECORDS=", JSON.stringify({"checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _verify_collections(page: UiExperiencePage) -> void:
	_check(page.press("inspect:deck"), "map opens deck")
	await _settle()
	var inspector := page._inspector
	var grid := inspector.find_child("CollectionGrid", true, false) as GridContainer
	var scroll := grid.get_parent() as ScrollContainer
	var first := grid.get_child(0) as UiOfferCard
	var bounds := scroll.get_global_rect()
	_check(first._face.size.y > 170 and bounds.encloses(first._face.get_global_rect()), "complete first card in deck at %s / %s" % [page.size, UiStyle.text_scale])
	var close := page._buttons["inspect:close"] as Button
	_check(page.get_global_rect().encloses(close.get_global_rect()) and close.size.y >= 44, "deck close fits")
	_check(inspector.find_child("CollectionSort", true, false) != null and inspector.find_child("CollectionSearch", true, false) != null, "deck retains search and sorting")
	# Simulate short drags inside the original card and a drag back to its start.
	await _drag_card(first, Vector2(0, -14), false)
	_check(not is_instance_valid(page._card_preview), "short drag beginning on the card never opens it")
	await _drag_card(first, Vector2(16, 0), true)
	_check(not is_instance_valid(page._card_preview), "drag returning to the original point never opens the card")
	await _tap(first)
	_check(is_instance_valid(page._card_preview) and page.get_global_rect().encloses(page._card_preview.get_global_rect()), "card opens a contained pinned detail")
	if is_instance_valid(page._card_preview):
		await _tap(page._buttons["card:pin"])
	_check(not is_instance_valid(page._card_preview) and is_instance_valid(page._inspector), "detail close returns to deck")
	await _tap(close)
	_check(not is_instance_valid(page._inspector), "deck close returns to map")
	_check(page.press("inspect:relics"), "map opens reference")
	await _settle()
	var reference := page._reference
	for key in ["relics", "rules", "log", "info"]:
		await _tap(reference._tabs[key])
		_check(reference.section == key and reference._body.size.y > 205, "reference reading area is usable in " + key)
		_check(page.get_global_rect().encloses(reference._close.get_global_rect()), "reference close is in bounds")
		if key == "relics":
			var third: Control = reference.find_child("RelicSlot2", true, false)
			_check(third.get_parent().get_parent().get_global_rect().encloses(third.get_global_rect()), "all three slots visible")
	await _tap(reference._close)
	_check(not is_instance_valid(page._reference), "closing reference returns to map")


func _verify_restart() -> void:
	var store := SaveStore.new("user://collections-restart-%s" % Time.get_ticks_usec())
	var session := GameSession.new(store)
	var request := StartRunRequest.new("P01", &"normal", "campus_four_year", "41")
	_check(session.start_run(request).accepted, "restart fixture starts")
	var old := str(session.get_view().run_id)
	var view := session.get_view()
	var route_id := str(view.run.reachable_node_ids[0])
	_check(session.submit(CommandContext.new(old, view.revision), GameAction.new(&"enter_node", {"node_id": route_id})).accepted, "old run enters a battle")
	# A battle applies pressure to its own player state before run settlement.
	session._state.battle.player.vitality = 47
	session._state.battle.player.max_vitality = 61
	var before := ShellFixtures.new().fingerprint(session)
	_check(not session.restart_run(request).accepted and session.get_game_records().data.is_empty(), "confirmation is required and does not create a record")
	store.debug_hooks = {"current_run": {"fail_rename": true}}
	_check(not session.restart_run(request, true).accepted, "replacement write failure is reported")
	_check(ShellFixtures.new().fingerprint(session) == before and session.get_game_records().data.is_empty(), "failed replacement preserves battle and never publishes abandonment")
	store.debug_hooks = {"records": {"fail_write": true}}
	_check(session.restart_run(request, true).accepted and session.get_view().run_id != old, "saved replacement can proceed with an interrupted record write")
	_check(not session.get_game_records().ok, "a failed record write remains pending")
	var replacement := str(session.get_view().run_id)
	session.free()
	store.debug_hooks = {}
	session = GameSession.new(store)
	var rows: Array = session.get_game_records().data
	_check(rows.size() == 1 and rows[0].run_id == old and rows[0].result == "abandoned" and rows[0].reason == "replaced_by_new_run", "fresh session publishes the exact old run once")
	if rows.size() == 1:
		_check(rows[0].detail.cards.size() == 12 and rows[0].detail.route.size() == 1 and rows[0].detail.route[0].status == "stopped", "replacement captures actual deck and current unfinished battle")
		_check(rows[0].detail.vitality == 47 and rows[0].detail.max_vitality == 61 and rows[0].detail.money == 60, "replacement records live battle vitality and actual run money")
		_check(rows[0].detail.completed_nodes == 0 and rows[0].detail.settled_battles == 0, "unfinished battle is not counted as settled")
	_check(session.get_game_records().data == rows, "recovery retry is idempotent")
	_check(session.restart_run(request, true).accepted, "unloaded disk run can be replaced")
	rows = session.get_game_records().data
	_check(rows.size() == 2 and rows.any(func(row): return row.run_id == replacement and row.detail.route.is_empty()), "replacing unopened disk save archives its correct start state")
	session.free()


func _drag_card(card: Control, movement: Vector2, return_to_origin: bool) -> void:
	var point := card.get_global_rect().get_center()
	_push_mouse(point, true)
	var drag := InputEventMouseMotion.new()
	drag.position = point + movement
	drag.global_position = drag.position
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag)
	_push_mouse(point if return_to_origin else drag.position, false)
	await _settle()


func _push_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event)


func _verify_record(shell: GameShell) -> void:
	var page := shell.page
	_check(page._buttons.has("records:open:0"), "record list displays clickable match")
	_verify_record_label(page, "失败  ›")
	_verify_record_label(page, "第 1 学年")
	_verify_record_label(page, "剩余精力")
	_verify_record_label(page, "金币")
	await _tap(page._buttons["records:open:0"])
	_check(page._buttons.has("records:tab:route"), "detail opens at route")
	for key in ["cards", "relics", "route"]:
		await _tap(page._buttons["records:tab:" + key])
		_check(page._scroll.size.y > 110, "record tab has reading space for " + key)
		_verify_record_label(page, "0 / 72")
		_verify_record_label(page, "已结算战斗")
		match key:
			"cards": _verify_record_label(page, "写作业")
			"relics": _verify_record_label(page, "结算时未携带饰品。")
			"route": _verify_record_label(page, "战斗失败")
	await _tap(page._buttons["records:back"])
	_check(page._buttons.has("records:open:0"), "returns to matches")


func _verify_record_label(page: Control, caption: String) -> void:
	var matches := page.find_children("*", "Label", true, false).filter(func(label): return label.text == caption)
	_check(not matches.is_empty() and matches[0].size.x > 32 and matches[0].size.y > 10, "readable record label " + caption)


func _tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		_push_mouse(point, pressed)
		await process_frame
	await _settle()


func _settle() -> void:
	for _frame in 4:
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
