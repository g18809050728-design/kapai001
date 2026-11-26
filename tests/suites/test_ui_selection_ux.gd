extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _capture_dir := ""


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	var old_scale := UiStyle.text_scale
	var old_motion := UiStyle.reduced_motion
	_capture_dir = OS.get_environment("KAPAI_SELECTION_CAPTURES")
	tree.root.size = Vector2i(1280, 800)
	await _test_turn()
	tree.root.size = Vector2i(960, 600)
	await _test_card_choices()
	await _test_relic_offer()
	tree.root.size = old_size
	UiStyle.text_scale = old_scale
	UiStyle.reduced_motion = old_motion
	print("SELECTION_UX_CHECKS=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures


func _shell(tag: String, scale: int) -> GameShell:
	var session := GameSession.new(SaveStore.new("user://selection-%s-%d" % [tag, Time.get_ticks_usec()]))
	session.update_settings({"autosave": false, "presentation": {"reduced_motion": true, "animation_speed": 0, "text_scale": scale}})
	return _helpers.attach_shell(session)


func _test_turn() -> void:
	var shell := _shell("end", 100)
	var started := shell.session.start_test_room({"encounter_id": "N01", "character_id": "P01", "seed": "42"})
	_check(started.accepted, "start a production encounter for the burst test")
	if not started.accepted:
		shell.free()
		return
	shell.refresh()
	await _frames()
	var page := shell.page as BattleScreen
	page.animation_enabled = false
	var before := shell.session.get_test_view()
	var initial_round := int(before.battle.round_index)
	var point := page._button_rect("battle:end_turn").get_center()
	_click(shell.get_viewport(), point)
	_check(int(shell.session.get_test_view().battle.round_index) == initial_round + 1, "actual first pointer click submits exactly one turn")
	_check(page.button_disabled("battle:end_turn"), "new revision keeps the end-turn control locked")
	_key(shell.get_viewport(), KEY_E)
	for index in 6:
		_click(shell.get_viewport(), point, index == 0, index % 2 == 1)
	var after := shell.session.get_test_view()
	_check(int(after.battle.round_index) == initial_round + 1 and int(after.test.revision) == int(before.test.revision) + 1, "mouse double-click, repeated touch and E cannot submit the next turn")
	page.animation_enabled = true
	# Keep an actual presentation queue open past the input interval.
	page.consume_events([{"type": "phase_changed", "data": {"phase": "enemy_pressure"}}, {"type": "phase_changed", "data": {"phase": "draw"}}], "guard-presentation-fixture", 1)
	page._animator.speed_scale = 0.05
	await _capture("turn-resolving")
	await shell.get_tree().create_timer((BattleScreen.END_TURN_INTERVAL_MS + 100) / 1000.0).timeout
	_check(page.button_disabled("battle:end_turn") and page._buttons["battle:end_turn"].text == "回合结算中", "presentation keeps the gate closed after the input interval")
	page.animation_enabled = false
	await _frames()
	_check(not page.button_disabled("battle:end_turn"), "turn control becomes available after the input settles")
	_key(shell.get_viewport(), KEY_E)
	_check(int(shell.session.get_test_view().battle.round_index) == initial_round + 2, "subsequent deliberate E still works")
	shell.free()


func _test_card_choices() -> void:
	var shell := _shell("cards", 150)
	var deck: Array[String] = ["R3-P01-16"]
	for _index in 10:
		deck.append("R3-P01-11")
	deck.append_array(["R3-P01-01", "R3-P01-01", "R3-P01-01"])
	var started := shell.session.start_test_room({"encounter_id": "N01", "character_id": "P01", "seed": "42", "cards": deck})
	_check(started.accepted, "start real card choice test room")
	if not started.accepted:
		shell.free()
		return
	var state := shell.session.test_service().state.battle
	# Arrange existing instances into a long discard pile for the real retrieve effect.
	var recall_id := ""
	var discard_id := ""
	for id in state.card_by_id:
		var definition := str(state.card_by_id[id].definition_id)
		if definition == "R3-P01-16":
			recall_id = str(id)
		elif definition == "R3-P01-01" and discard_id.is_empty():
			discard_id = str(id)
		for zone in ["draw", "discard", "hand"]:
			state.zones[zone].erase(id)
		state.zones["discard" if definition == "R3-P01-11" else "draw"].append(id)
	for id in [recall_id, discard_id]:
		state.zones.discard.erase(id)
		state.zones.draw.erase(id)
		state.zones.hand.append(id)
	shell.refresh()
	var page := shell.page as BattleScreen
	page.animation_enabled = false
	await _frames()
	_check(shell.press("card:" + recall_id), "play the real recall card")
	var choice: Variant = shell.session.get_test_view().pending_choice
	_check(choice is Dictionary and choice.kind == "recall", "recall opens a choice with a real action")
	if choice is Dictionary and choice.kind == "recall":
		var candidates: Array = choice.candidates
		_check(candidates.size() == 10, "all ten eligible discard instances are listed")
		await _frames()
		var scroll := page._choice_scroll
		_check(shell.press("choice:scroll:next") and scroll.scroll_horizontal > 0, "arrow browses more cards")
		scroll.scroll_horizontal = roundi(scroll.get_h_scroll_bar().max_value)
		var scroll_before := scroll.scroll_horizontal
		var first := str(candidates.back().id)
		var second := str(candidates[candidates.size() - 2].id)
		var widget: BattleCard = page._buttons["choice:" + first]
		var before := shell.session.test_service().state.state_hash()
		_check(shell.press("choice:" + first) and widget.selected and widget.get_meta("choice_marker").text == "✓ 已选", "select and label a card at the far end")
		_check(shell.press("choice:" + second) and page._choice_selected_ids == [second] and not widget.selected, "new single choice replaces the previous selection")
		_check(widget == page._buttons["choice:" + first] and scroll == page._choice_scroll and scroll.scroll_horizontal == scroll_before, "selection preserves card widgets and strip position")
		_check(shell.press("choice:clear") and page._choice_selected_ids.is_empty(), "clear selection is reversible")
		_check(shell.press("choice:" + second), "choose the final recall target")
		_check(shell.session.test_service().state.state_hash() == before, "selection and browsing preserve the pending state and RNG")
		await _capture("recall-long")
		await _check_footer_sizes(shell, "choice:confirm")
		_check(shell.press("choice:confirm") and shell.session.get_test_view().pending_choice == null, "confirm resolves the exact chosen card")
		_check(shell.session.test_service().state.battle.zones.hand.has(second), "selected card returns to hand")
	_check(shell.press("card:" + discard_id), "play the real draw/discard card")
	var discard: Variant = shell.session.get_test_view().pending_choice
	_check(discard is Dictionary and discard.kind == "discard", "discard opens its own choice")
	if discard is Dictionary and discard.kind == "discard":
		_check(page.button_disabled("choice:confirm") and page._choice_status.text.contains("还需选"), "mandatory discard shows the missing quantity")
		var selected := str(discard.candidates[0].id)
		_check(shell.press("choice:" + selected) and page._buttons["choice:confirm"].text == "确认弃牌", "selected discard has an explicit confirm action")
		await _capture("discard-selected")
		_check(shell.press("choice:confirm") and shell.session.test_service().state.battle.zones.discard.has(selected), "confirmation discards the exact card")
	shell.free()


func _test_relic_offer() -> void:
	var runner = preload("res://tests/suites/test_four_year.gd").new()
	_check(runner.run().is_empty(), "build an actual full-slot campaign checkpoint")
	var shell := _shell("relic", 150)
	var session := shell.session
	var started := session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "start production run for relic UI")
	if not started.accepted:
		shell.free()
		return
	session._state.run = runner.active_checkpoint("relic_full", session._catalog)
	session._state.random_snapshot = runner._rng.duplicate(true)
	shell.show_screen("")
	await _frames()
	var offer: Dictionary = session.get_view().run.campaign_offer
	var slots: Array = session.get_view().run.relics
	var before: String = _helpers.fingerprint(session)
	var first := str(offer.candidates[0])
	var second := str(offer.candidates[1])
	var replacement := str(slots[0].relic_id)
	var replace_uid := "campaign:replace:" + replacement
	_check(shell.press("campaign:claim:" + first) and shell.page.button_disabled("campaign:confirm"), "full slots require an explicit replacement")
	await _frames()
	var page := shell.page as UiExperiencePage
	_check(page.footer.is_ancestor_of(page._buttons[replace_uid]) and page.get_global_rect().encloses(page._buttons[replace_uid].get_global_rect()), "replacement controls stay visible with the confirmation")
	_check(shell.press(replace_uid) and not page.button_disabled("campaign:confirm"), "replacement enables final action")
	_check(shell.press("campaign:claim:" + second) and page.button_disabled("campaign:confirm"), "switching candidate clears the previous replacement")
	_check(shell.press("campaign:skip") and not page.button_disabled("campaign:confirm") and page.action_draft("campaign:confirm").payload.candidate_id == "", "skip works after selecting a candidate")
	_check(shell.press("selection:cancel") and page.button_disabled("campaign:confirm"), "return restores the candidate and still needs a slot")
	_check(shell.press("campaign:convert:" + second) and page._buttons["campaign:confirm"].text == "确认折算", "conversion describes its actual final action")
	_check(shell.press("selection:cancel") and shell.press(replace_uid), "return from conversion and confirm a new swap")
	_check(_helpers.fingerprint(session) == before, "relic comparison, skip preview and conversion preview remain read-only")
	await _frames()
	var comparison := page.find_child("RelicComparison", true, false) as Control
	var effects := comparison.find_children("RelicEffect", "Label", true, false) if is_instance_valid(comparison) else []
	_check(effects.size() == 2 and effects.all(func(effect): return page._scroll.get_global_rect().intersection(effect.get_global_rect()).size.y >= 20), "both actual effect descriptions start in view at large text")
	await _capture("relic-replacement")
	await _check_footer_sizes(shell, "campaign:confirm", replace_uid)
	_check(shell.press("campaign:confirm"), "commit one replacement")
	var equipped: Array = session.get_view().run.relics
	_check(equipped.size() == slots.size() and equipped.any(func(relic): return relic.definition_id == second) and not equipped.any(func(relic): return relic.relic_id == replacement), "actual campaign replaces only the selected slot")
	shell.free()
	_test_regular_relic_reward(runner)


func _test_regular_relic_reward(runner: RefCounted) -> void:
	var shell := _shell("reward", 100)
	var session := shell.session
	if not session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42")).accepted:
		_check(false, "start a regular reward fixture")
		shell.free()
		return
	var run: RunState = runner.active_checkpoint("grand", session._catalog)
	run.campaign.pending = {}
	run.relics.clear()
	var transactions := TransactionResolver.new(session._catalog)
	for slot in 3:
		transactions.add_relic(run, ["RX-C01", "RX-C02", "RX-C04"][slot], "", slot)
	run.pending_reward = RewardOffer.new({
		"offer_id": "selection-regular-relic", "source_node_id": run.current_node_id,
		"items": [{"item_id": "relic", "kind": "relic", "status": "pending", "candidates": ["RX-C05", "RX-C06"], "skippable": true}],
	})
	session._state.run = run
	session._state.random_snapshot = runner._rng.duplicate(true)
	shell.show_screen("")
	var target := str(session.get_view().run.relics[0].relic_id)
	var before: String = _helpers.fingerprint(session)
	_check(shell.press("reward:relic:pick:RX-C05") and shell.page.button_disabled("reward:relic:claim"), "ordinary reward preselect requires a slot")
	_check(shell.press("reward:relic:replace:" + target) and _helpers.fingerprint(session) == before, "ordinary reward slot choice is read-only")
	_check(shell.press("reward:relic:claim") and session.get_view().run.relics.any(func(relic): return relic.definition_id == "RX-C05"), "ordinary reward confirmation executes the replacement")
	shell.free()


func _check_footer_sizes(shell: GameShell, confirm: String, secondary: String = "") -> void:
	var tree := shell.get_tree()
	for viewport in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = viewport
		for scale in [100, 125, 150]:
			shell.session.update_settings({"presentation": {"text_scale": scale}})
			shell._apply_presentation()
			shell.refresh()
			await _frames()
			var page := shell.page
			var caption := "%s %s / %d%%" % [confirm, viewport, scale]
			var button: Button = page._buttons.get(confirm)
			_check(is_instance_valid(button) and page.get_global_rect().encloses(button.get_global_rect()), caption + " confirm is fully visible")
			if not secondary.is_empty():
				var slot: Button = page._buttons.get(secondary)
				_check(is_instance_valid(slot) and page.get_global_rect().encloses(slot.get_global_rect()), caption + " replacement is fully visible")


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	await _frames()
	await RenderingServer.frame_post_draw
	var capture := tree.root.get_texture().get_image()
	_check(capture != null and capture.save_png(_capture_dir.path_join(name + ".png")) == OK, "capture " + name)


func _click(viewport: Viewport, point: Vector2, twice: bool = false, touch: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.double_click = twice and down
		event.device = InputEvent.DEVICE_ID_EMULATION if touch else 0
		viewport.push_input(event, true)


func _key(viewport: Viewport, code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		viewport.push_input(event, true)


func _frames() -> void:
	for _i in 5:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append("selection UX: " + message)
