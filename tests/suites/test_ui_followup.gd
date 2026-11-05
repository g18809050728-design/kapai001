extends RefCounted

const OUT := "res://artifacts/verification/ui-followup-20261105/visual"
var capture_enabled := false
var _failures: Array[String] = []
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _runner = preload("res://tests/suites/test_four_year.gd").new()


func run() -> Array[String]:
	_failures.append_array(_runner.run())
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		await _reward_and_services(str(dimensions.x))
		await _production_shop(str(dimensions.x))
		await _production_reward(str(dimensions.x))
		await _campaign(str(dimensions.x))
		await _battle_and_map(str(dimensions.x))
	await _audio()
	var clean := _helpers.attach_shell(GameSession.new(SaveStore.new("user://followup-menu-%d" % Time.get_ticks_usec()))) as GameShell
	_check(clean.page.button_disabled("menu:continue") and not clean.press("menu:continue"), "no save: Continue is disabled")
	await _save("menu-no-save")
	clean.press("menu:new")
	clean.press("setup:start")
	_check(clean.session.get_view().screen == &"map" and not clean.page.button_uids().has("setup:restart_confirm"), "empty start creates directly")
	clean.free()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	if capture_enabled:
		var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_captures, "\t"))
	print("UI_FOLLOWUP=", JSON.stringify({"failures": _failures, "captures": _captures.size(), "scope": "real pointer + controlled production checkpoints, isolated data"}))
	return _failures


func _reward_and_services(suffix: String) -> void:
	var shell := _helpers.start_fixture_shell("user://followup-cards-%d" % Time.get_ticks_usec()) as GameShell
	_helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0]))
	_helpers.finish_battle(shell)
	await _frames()
	var item: Dictionary = shell.session.get_view().run.pending_reward.items[0]
	var prefix := "reward:%s" % item.item_id
	var fingerprint: String = _helpers.fingerprint(shell.session)
	for repetition in 3:
		for id in item.candidates:
			await _click_card(shell, prefix + ":pick:" + str(id))
			_check(shell.page._buttons[prefix + ":pick:" + str(id)].selected, "real pointer selects the intended reward card")
			for other in item.candidates:
				var card: UiOfferCard = shell.page._buttons[prefix + ":pick:" + str(other)]
				_check(card._face.size.y <= card.size.y + 1, "selected reward face stays inside its allocated height")
				_check(card.size.y < 350, "reward height stays stable over repeated real clicks")
	_check(_helpers.fingerprint(shell.session) == fingerprint, "real reward clicks are read-only")
	_check(is_instance_valid(shell.page._card_preview) and shell.page.get_global_rect().encloses(shell.page._card_preview.get_global_rect()), "reward popup stays within page after rebuilding")
	await _save("reward-selected-" + suffix)
	for scale in [1.25, 1.5]:
		UiStyle.text_scale = scale
		shell.page.refresh_local()
		await _frames()
		await _click_card(shell, prefix + ":pick:" + str(item.candidates[0]))
		var card: UiOfferCard = shell.page._buttons[prefix + ":pick:" + str(item.candidates[0])]
		_check(card._face.size.y <= card.size.y + 1, "large text focus never stretches a face")
		await _save("reward-text%d-" % roundi(scale * 100) + suffix)
	UiStyle.text_scale = 1.0
	shell.refresh()
	_skip_rewards(shell)
	for kind in ["event", "shop"]:
		var id := ""
		for node in shell.session.get_view().run.nodes:
			if node.kind == kind:
				id = str(node.node_id)
		_helpers.enter_node(shell, id)
		await _frames()
		fingerprint = _helpers.fingerprint(shell.session)
		if kind == "event":
			var options: Array = shell.session.get_view().run.event.options
			for option in options:
				if option.enabled and str(option.option_id) != "leave":
					shell.press("event:" + str(option.option_id))
					break
			_check(shell.page.button_uids().has("selection:cancel") and shell.page.button_uids().has("event:confirm"), "event preselection shows a reversible confirmation")
			await _save("event-selected-" + suffix)
			_check(_helpers.fingerprint(shell.session) == fingerprint, "event browsing is read-only")
			shell.press("selection:cancel")
			for option in options:
				_check(shell.page.button_uids().has("event:option:leave" if option.option_id == "leave" else "event:" + str(option.option_id)), "event return restores every candidate")
			shell.press("event:option:leave")
			shell.press("event:confirm")
		else:
			for stock in shell.session.get_view().run.shop.stocks:
				if stock.kind == "card":
					await _click_card(shell, "shop:pick:" + str(stock.stock_id))
					var card: UiOfferCard = shell.page._buttons["shop:pick:" + str(stock.stock_id)]
					_check(card._face.size.y <= card.size.y + 1, "shop selection never stretches card face")
					break
			_check(_helpers.fingerprint(shell.session) == fingerprint, "shop preselection is read-only")
			await _save("shop-selected-" + suffix)
			shell.press("shop:leave")
	shell.free()


func _production_shop(suffix: String) -> void:
	var session := _production_session()
	# Controlled checkpoint before the actual production shop, using real topology.
	var run := session._state.run
	var shop_id := ""
	for node in run.nodes:
		if node.term == 1 and node.layer <= 2 and node.node_id.ends_with("s0"):
			node.status = "completed"
			run.node_path.append(node.node_id)
			run.current_node_id = node.node_id
		if node.term == 1 and node.layer == 3 and node.kind == "shop":
			shop_id = node.node_id
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	var entered: bool = _helpers.enter_node(shell, shop_id)
	_check(entered, "controlled checkpoint enters real production shop")
	if not entered:
		shell.free()
		return
	await _frames()
	var fingerprint: String = _helpers.fingerprint(session)
	_check(UiStyle.texture("campus_meal") != null, "new meal illustration imports and loads")
	var meal := ""
	for stock in session.get_view().run.shop.stocks:
		if stock.kind == "meal":
			meal = str(stock.stock_id)
	_check(not meal.is_empty() and shell.press("shop:pick:" + meal), "meal is a real selectable stock")
	await _frames()
	_check(_helpers.fingerprint(session) == fingerprint, "meal preselection preserves frozen stock and state")
	shell.page._scroll.ensure_control_visible(shell.page._buttons["shop:pick:" + meal].get_parent().get_parent())
	await _frames()
	await _save("shop-meal-" + suffix)
	shell.press("shop:leave")
	# Layer 3 grants the scheduled relic before returning to the map.
	if session.get_view().screen == &"campaign":
		shell.press("campaign:skip")
		shell.press("campaign:confirm")
	await _frames(14)
	var page := shell.page as UiExperiencePage
	var reachable: Array = session.get_view().run.reachable_node_ids
	_check(not reachable.is_empty(), "shop and scheduled reward return to reachable map")
	if reachable.is_empty():
		shell.free()
		return
	var next: Button = page._buttons["node:" + str(reachable[0])]
	var scroll_rect := page._scroll.get_global_rect()
	_check(scroll_rect.encloses(next.get_global_rect()), "real shop return keeps next reachable layer visible")
	_check(absf(scroll_rect.get_center().y - next.get_global_rect().get_center().y) <= 2, "real shop return centers next layer after page resize")
	await _save("map-after-shop-" + suffix)
	shell.free()


func _production_reward(suffix: String) -> void:
	var session := _production_session()
	# Isolated display checkpoint: real card definitions, including the reported
	# continuous ability. Rule behavior is exercised by the P03 rule suite.
	var run := _runner._checkpoints["grand"].copy_for_write() as RunState
	var candidates := ["R3-P03-19", "R3-P03-10", "R3-P03-27"]
	run.campaign.pending = {}
	run.pending_reward = RewardOffer.new({"offer_id": "followup-real-cards", "source_node_id": run.current_node_id, "items": [{"item_id": "cards", "kind": "card", "status": "pending", "candidates": candidates, "skippable": true}], "meta": {"money": 15}})
	session._state.run = run
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	await _frames()
	var fingerprint: String = _helpers.fingerprint(session)
	for id in candidates:
		await _click_card(shell, "reward:cards:pick:" + id)
		_check(shell.page._buttons["reward:cards:pick:" + id].selected, "production card can be selected beside hover details")
	await _click_card(shell, "reward:cards:pick:" + candidates[0])
	await _save("reward-production-selected-" + suffix)
	shell.page._show_card_preview(true)
	await _save("burst-full-description-" + suffix)
	_check(_helpers.fingerprint(session) == fingerprint, "real card selection and burst inspection stay read-only")
	shell.free()


func _campaign(suffix: String) -> void:
	for kind in ["direction", "destination", "relic_full", "grand"]:
		var session := _production_session()
		session._state.run = _runner._checkpoints[kind].copy_for_write()
		session._state.random_snapshot = _runner._rng.duplicate(true)
		var shell := _helpers.attach_shell(session) as GameShell
		shell.show_screen("")
		await _frames()
		var fingerprint: String = _helpers.fingerprint(session)
		if kind in ["direction", "destination"]:
			shell.press("campaign:theory" if kind == "direction" else "campaign:job")
			for id in CampaignService.DIRECTIONS if kind == "direction" else CampaignService.DESTINATIONS:
				_check(shell.page.button_uids().has("campaign:" + id), "illustrated choice retains every alternative")
			await _frames()
			if kind == "direction":
				for id in CampaignService.DIRECTIONS:
					_check(shell.page._scroll.get_global_rect().encloses(shell.page._buttons["campaign:" + id].get_global_rect()), "all four direction choices fit the visible region")
			_check(shell.page.body.find_children("*", "TextureRect", true, false).size() == 4, "four illustrations fill direction/destination page")
		elif kind == "relic_full":
			var offer: Dictionary = session.get_view().run.campaign_offer
			shell.press("campaign:claim:" + str(offer.candidates[0]))
			for id in offer.candidates:
				_check(shell.page.button_uids().has("campaign:claim:" + str(id)), "relic selection retains every candidate")
		else:
			shell.press("campaign:category:deck")
			shell.press("campaign:mode:upgrade")
			var target: Dictionary = session.get_view().run.cards.filter(func(card): return card.get("upgrade_detail") is Dictionary)[0]
			shell.press("campaign:upgrade:" + str(target.card_id))
			for card in session.get_view().run.cards:
				_check(shell.page.button_uids().has("campaign:upgrade:" + str(card.card_id)), "upgrade preselection retains candidate grid")
		_check(_helpers.fingerprint(session) == fingerprint, "campaign preselection preserves state/RNG/revision")
		await _save(kind + "-selected-" + suffix)
		shell.free()


func _battle_and_map(suffix: String) -> void:
	var session := _production_session()
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	await _frames()
	var page := shell.page as UiExperiencePage
	var geometry := page.view.duplicate(true)
	var middle: Array = geometry.nodes.filter(func(node): return int(node.layer) == 6)
	geometry.current_node_id = geometry.nodes.filter(func(node): return int(node.layer) == 5)[0].node_id
	geometry.reachable_node_ids = middle.map(func(node): return node.node_id)
	geometry.revision += 1
	page.render(geometry)
	await _frames(14)
	var next: Button = page._buttons["node:" + str(middle[0].node_id)]
	_check(absf(next.get_global_rect().get_center().y - page._scroll.get_global_rect().get_center().y) <= 2, "next reachable layer centers after scroll restoration")
	var current: Button = page._buttons["node:" + str(geometry.current_node_id)]
	_check(current.get_meta("current_node", false) and current.get_theme_stylebox("normal").bg_color.get_luminance() < .4, "current map node has dark background")
	await _save("map-middle-" + suffix)
	page._scroll.scroll_vertical += 50
	var scroll := page._scroll.scroll_vertical
	page.press("node:" + str(middle[0].node_id))
	await _frames(12)
	_check(abs(page._scroll.scroll_vertical - scroll) <= 1, "local map preselection preserves manual scroll")
	shell.refresh()
	_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
	# Give all three zones visible members for the layout/inspection fixture.
	var state := session._state.battle
	state.zones.discard.append(state.zones.hand.pop_back())
	state.zones.exhaust.append(state.zones.hand.pop_back())
	shell.refresh()
	await _frames()
	var battle := shell.page as BattleScreen
	var fingerprint: String = _helpers.fingerprint(session)
	var original := battle.draw_pile_card_ids()
	_check(original.size() == int(battle.view.zone_counts.draw), "draw membership matches actual count")
	session._state.battle.zones.draw.reverse()
	_check(session.get_view().battle.zones_public.draw.map(func(card): return card.card_id) == original, "reversing secret draw order cannot change public view")
	session._state.battle.zones.draw.reverse()
	_check(_helpers.fingerprint(session) == fingerprint, "privacy check restores its controlled fixture exactly")
	if not battle._compact_layout:
		_check(battle._buttons["battle:log"].position.x < battle._buttons["battle:rules"].position.x, "record precedes rules after swap")
	_check(battle._buttons["battle:end_turn"] is BattleActionButton, "end turn uses matching paper control")
	await _save("battle-controls-" + suffix)
	for kind in ["draw", "discard", "exhaust"]:
		_check(shell.press("battle:" + kind), "pile opens: " + kind)
		await _frames()
		var count: int = battle.view.zone_counts[kind]
		var cards: Array = battle.button_uids().filter(func(uid): return str(uid).begins_with("pile:card:"))
		_check(cards.size() == count, "pile cards match public count: " + kind)
		_check(battle.button_disabled("battle:end_turn"), "pile modal locks background")
		if not cards.is_empty():
			await _click_card(shell, str(cards[0]))
			_check(is_instance_valid(battle._card_preview) and battle._preview_pinned, "pile card opens full pinned preview")
			await _save("pile-" + kind + "-preview-" + suffix)
			battle.close_card_preview()
		await _save("pile-" + kind + "-" + suffix)
		shell.press("battle:close_panel")
	_check(_helpers.fingerprint(session) == fingerprint, "all pile views preserve domain/RNG/revision")
	var detail: Dictionary = session._run_service._reward_candidate_view("card", "R3-P03-19", session._catalog.get_definition("ruleset", session._state.run.ruleset_id).data)
	var summary := UiContentText.card_summary(detail)
	_check(summary.contains("下回合") and summary.contains("3") and summary.contains("4") and summary.contains("每回合一次"), "burst card summary describes real activation and effect")
	shell.free()


func _audio() -> void:
	var audio := AudioManager.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(audio)
	_check(not audio.play_ui("ui_hover"), "hover stays quiet")
	_check(audio.play_sfx("card_play"), "primary card action remains audible")
	for id in ["card_draw", "card_discard", "chapter", "task_hit"]:
		_check(not audio.play_sfx(id), "cross-event burst is suppressed: " + id)
	_check(not audio.play_event("status_changed"), "minor status changes are silent")
	_check(audio.play_sfx("choice"), "important choice overrides minor burst")
	_check(audio._sfx_players.size() == 3, "bounded sound polyphony")
	await (Engine.get_main_loop() as SceneTree).create_timer(.2).timeout
	_check(not audio.play_sfx("card_play"), "important cue receives a quiet window")
	while Time.get_ticks_msec() - int(audio._last_group.get("important", 0)) < 260:
		await (Engine.get_main_loop() as SceneTree).process_frame
	_check(audio.play_sfx("card_play"), "normal feedback returns after cooldown")
	audio.free()


func _production_session() -> GameSession:
	var session := GameSession.new(SaveStore.new("user://followup-production-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	return session


func _skip_rewards(shell: GameShell) -> void:
	for index in 8:
		if shell.session.get_view().screen != &"reward":
			return
		for item in shell.session.get_view().run.pending_reward.items:
			if item.status == "pending":
				shell.press("reward:%s:skip" % item.item_id)
				shell.press("reward:%s:skip_confirm" % item.item_id)
				break


func _click_card(shell: GameShell, uid: String) -> void:
	var card: Button = shell.page._buttons[uid]
	var point := card.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	await _frames(2)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		Input.parse_input_event(click)
	await _frames(10)


func _frames(count: int = 8) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _save(label: String) -> void:
	if not capture_enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _frames()
	await RenderingServer.frame_post_draw
	var viewport := (Engine.get_main_loop() as SceneTree).root
	var result := viewport.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	_check(result == OK, "screenshot saved: " + label)
	_captures.append({"name": label, "width": viewport.size.x, "height": viewport.size.y, "save_error": result})


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append("UI followup: " + message)
