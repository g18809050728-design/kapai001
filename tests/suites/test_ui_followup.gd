extends RefCounted

const OUT := "res://artifacts/verification/card-dwell-20261106/visual"
var capture_enabled := false
var _failures: Array[String] = []
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _runner = preload("res://tests/suites/test_four_year.gd").new()


func run() -> Array[String]:
	capture_enabled = DisplayServer.get_name() != "headless" or OS.get_environment("BATTLE_CARD_COPY_CAPTURE") == "1"
	_failures.append_array(_runner.run())
	_card_copy_coverage()
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


func _card_copy_coverage() -> void:
	var file := FileAccess.open("res://data/four_year/definitions/cards.json", FileAccess.READ)
	_check(file != null, "current four-year card definitions are available for copy coverage")
	if file == null:
		return
	var definitions: Variant = JSON.parse_string(file.get_as_text())
	_check(definitions is Array and definitions.size() == 174, "copy coverage includes all 174 current card definitions")
	if not definitions is Array:
		return
	var tokens: Array[String] = []
	var upgraded_count := 0
	var exam_count := 0
	var surface_count := 0
	var session := _production_session()
	var card_rules := BattleCardRules.new(session._catalog)
	var evidence: Array = []
	for definition_value in definitions:
		_collect_copy_tokens(definition_value, tokens)
	for definition_value in definitions:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value.duplicate(true)
		if definition.has("ability"):
			for trigger in definition.ability.get("triggers", []):
				if trigger is Dictionary and trigger.has("on"):
					tokens.append(str(trigger.on))
		var surfaces: Array[Dictionary] = []
		var exam: Dictionary = definition.get("exam", {})
		var exam_options: Array = [""]
		if not exam.is_empty():
			exam_options.append(str(exam.get("condition", "")))
			exam_count += 1
		for exam_flag in exam_options:
			for level in [0, 1]:
				if level == 1 and definition.get("upgrade", {}).is_empty():
					continue
				var state := BattleState.new({
					"card_by_id": {"copy_test": {"definition_id": str(definition.id), "upgrade_level": level}},
					"exam_flags": [] if str(exam_flag).is_empty() else [str(exam_flag)]
				})
				var resolved := card_rules.resolve_face(state, "copy_test")
				_check(resolved.ok, "copy uses the runtime-resolved card face: " + str(definition.id))
				if not resolved.ok:
					continue
				surfaces.append(resolved.data)
				if level == 1 and str(exam_flag).is_empty():
					upgraded_count += 1
		for surface in surfaces:
			var explanation := UiContentText.describe_battle_card(surface)
			_check(not explanation.is_empty(), "card detail explanation is present: " + str(definition.get("id", "unknown")))
			_check(not explanation.contains("详细说明待补"), "card detail has no generic placeholder: " + str(definition.get("id", "unknown")))
			var raw_token := ""
			for token in tokens:
				if token.length() > 2 and explanation.contains(token):
					raw_token = token
					break
			_check(raw_token.is_empty(), "effect/condition identifiers stay out of player copy: " + str(definition.get("id", "unknown")) + " " + raw_token)
			evidence.append({"definition_id": str(definition.id), "upgrade_level": surface.get("upgrade_level", 0), "target": surface.get("target", ""), "effects": surface.get("effects", []), "explanation": explanation})
			surface_count += 1
	var output := "res://artifacts/verification/card-dwell-20261106"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var evidence_file := FileAccess.open(output.path_join("card-copy-coverage.json"), FileAccess.WRITE)
	evidence_file.store_string(JSON.stringify(evidence, "\t"))
	var combo: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P01-19")[0]
	var combo_text := UiContentText.describe_battle_card(combo)
	_check(combo_text.contains("上一张成功打出的牌是策略牌") and combo_text.contains("额外完成量 +5") and combo_text.contains("同一段完成量"), "conditional bonus explains trigger and additive same-hit result")
	var discard: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P01-35")[0]
	var discard_text := UiContentText.describe_battle_card(discard)
	_check(discard_text.find("1. ") < discard_text.find("2. ") and discard_text.find("2. ") < discard_text.find("3. ") and discard_text.contains("已经弃掉至少一张手牌"), "ordered discard and conditional draw are explained")
	var segmented: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P01-37")[0]
	var segmented_text := UiContentText.describe_battle_card(segmented)
	_check(segmented_text.contains("第2段：") and segmented_text.contains("不会转向其他任务") and not segmented_text.contains("第2阶段"), "separate completion hits are distinguished from task phases")
	var group: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-C-12")[0]
	_check(UiContentText.describe_battle_card(group).contains("对所有任务造成"), "group effects inherit the card target")
	var window: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P03-10")[0]
	var window_text := UiContentText.describe_battle_card(window)
	_check(window_text.contains("自然结算改为2次") and window_text.contains("随后减少1层") and not window_text.contains("尚未应用"), "erosion window copy reflects implemented automatic repeats")
	var window_summary := UiContentText.card_summary(window)
	_check(window_summary.contains("自然结算2次") and not window_summary.contains("尚未应用"), "erosion window short summary matches the implemented effect")
	var spending: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P04-25")[0]
	var spending_text := UiContentText.describe_battle_card(spending)
	_check(spending_text.contains("随后：") and spending_text.contains("每消耗1点协同") and spending_text.contains("最后："), "nested spending effects show order and variable rewards")
	_check(not spending_text.contains("消耗：这张牌"), "spending synergy does not imply exhausting the card")
	var first_work: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-C-06")[0]
	var first_work_text := UiContentText.describe_battle_card(first_work)
	_check(first_work_text.contains("本次工作牌的首段完成量增加2点") and not first_work_text.contains("下一张工作牌"), "first-work trigger boosts the resolving card")
	_check(first_work_text.contains("消耗：这张牌"), "exhausting a card retains its keyword explanation")
	var retrieved: Dictionary = definitions.filter(func(card): return str(card.get("id", "")) == "R3-P01-14")[0]
	_check(UiContentText.describe_battle_card(retrieved).contains("手牌满时也算"), "passive retrieval condition reflects the implemented full-hand counter")
	print("BATTLE_CARD_COPY_COVERAGE=", JSON.stringify({"definitions": definitions.size(), "upgraded": upgraded_count, "exam": exam_count, "surfaces": surface_count}))
	session.free()


func _collect_copy_tokens(value: Variant, tokens: Array[String]) -> void:
	if value is Dictionary:
		for key in value:
			if key in ["op", "kind"] and not str(value[key]).is_empty():
				tokens.append(str(value[key]))
			_collect_copy_tokens(value[key], tokens)
	elif value is Array:
		for item in value:
			_collect_copy_tokens(item, tokens)


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
	# This historical UI fixture targets the fixed map's layer-three shop.
	# Annual-map navigation is covered by test_ui_adaptive_maps.
	var run := session._state.run
	run.campaign = CampaignService.initial()
	run.nodes = CampaignMap.build(run.run_id)
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
	_check(current.get_meta("current_node", false) and current.get("map_status") == "当前" and current.tooltip_text.contains("当前"), "current map stamp identifies the actual position in state and description")
	_check(next.get("map_status") == "可入" and not next.get_meta("current_node", false), "next reachable stamp remains distinct from the current position")
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
	if not battle._hand_cards.is_empty():
		var example_card: BattleCard = battle._hand_cards[0]
		var hover := battle._card_hover_target(example_card)
		var face: Dictionary = example_card.card_data.get("face", {})
		face = face.duplicate(true)
		face["cost"] = example_card.card_data.get("effective_cost", face.get("cost", 0))
		face["vitality_cost"] = example_card.card_data.get("effective_vitality_cost", face.get("vitality_cost", 0))
		var expected_detail := UiContentText.describe_battle_card(face)
		_check(str(hover.get("detail", "")).ends_with(expected_detail) and not str(hover.get("detail", "")).contains("升级后："), "battle hover explains the actual active card face")
		battle._pin_card_detail(hover)
		await _frames()
		_check(battle._hover_body.text == str(hover.detail) and battle._hover_body.max_lines_visible == -1, "side panel shows the complete active-face explanation")
		_check(battle._hover_panel.mouse_filter == Control.MOUSE_FILTER_STOP and battle._hover_scroll.mouse_filter == Control.MOUSE_FILTER_STOP, "fixed explanation supports reading and scrolling")
		await _save("battle-card-hover-" + suffix)
		var inspect_event := InputEventKey.new()
		inspect_event.keycode = KEY_I
		inspect_event.pressed = true
		_check(not battle._pinned_card_detail.is_empty() and battle._panel_text.is_empty(), "I details remain beside the card without opening the global modal")
		_check(battle._hover_body.text.contains("名词解释：") or battle._hover_body.text.contains("打出后按顺序结算"), "fixed details include the expanded explanation")
		await _save("battle-card-copy-" + suffix)
		battle._input(inspect_event)
		_check(battle._pinned_card_detail.is_empty() and not battle._hover_panel.visible, "I cancels the fixed battle card details")
		battle._hover_pinned = false
		_check(_helpers.fingerprint(session) == fingerprint, "battle card inspection preserves domain/RNG/revision")
	elif not battle.view.hand.is_empty():
		var compact_id := "card:" + str(battle.view.hand[0].card_id)
		var compact_card := battle._buttons[compact_id] as UiOfferCard
		for entry in battle.view.hand.slice(0, 2):
			var neighbour := battle._buttons["card:" + str(entry.card_id)] as UiOfferCard
			var motion := InputEventMouseMotion.new()
			motion.position = neighbour.get_global_rect().get_center()
			motion.global_position = motion.position
			Input.parse_input_event(motion)
			await (Engine.get_main_loop() as SceneTree).create_timer(.35).timeout
			_check(not is_instance_valid(battle._card_preview), "compact pointer can cross adjacent cards without an automatic popup")
			_check(str(battle._hover_target.get("uid", "")) == str(neighbour.get_meta("uid")), "compact pointer changes the I inspection target")
		await _save("battle-card-hover-" + suffix)
		compact_card.grab_focus()
		await _frames()
		_check(not is_instance_valid(battle._card_preview), "compact focus does not automatically open a long introduction")
		_check(compact_card.inspection_hint == "停留查看 · I 固定 / 取消", "compact hint describes delayed inspection and toggle")
		battle._pointer_position = Vector2.ZERO
		battle._update_pointer(0.0)
		var inspect_event := InputEventKey.new()
		inspect_event.keycode = KEY_I
		inspect_event.pressed = true
		battle._input(inspect_event)
		await _frames()
		_check(not battle._pinned_card_detail.is_empty() and battle._hover_panel.visible, "compact card I fixes the side explanation")
		battle._hover_target = {"uid": "battle:log", "title": "记录", "body": "查看本场记录"}
		battle._update_hover_window()
		_check(battle._hover_panel.visible and battle._hover_title.text != "记录", "fixed card details cannot be replaced by background summaries")
		var text: String = battle._hover_body.text
		_check(text.contains("打出后按顺序结算") and text.contains("名词解释："), "compact preview displays the same plain explanation")
		await _save("battle-card-copy-" + suffix)
		battle.close_card_preview()
		_check(_helpers.fingerprint(session) == fingerprint, "compact card inspection preserves domain/RNG/revision")
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
			_check(not battle._pinned_card_detail.is_empty() and battle._hover_panel.visible, "pile card opens the single pinned side explanation")
			await _save("pile-" + kind + "-preview-" + suffix)
			battle.close_card_preview()
		await _save("pile-" + kind + "-" + suffix)
		shell.press("battle:close_panel")
	_check(_helpers.fingerprint(session) == fingerprint, "all pile views preserve domain/RNG/revision")
	var detail: Dictionary = session._run_service._reward_candidate_view("card", "R3-P03-19", session._catalog.get_definition("ruleset", session._state.run.ruleset_id).data)
	var summary := UiContentText.card_summary(detail)
	_check(summary.contains("下回合") and summary.contains("3") and summary.contains("4") and summary.contains("每回合一次"), "burst card summary describes real activation and effect")
	await _card_face_inspection(battle, session, suffix)
	_check(_helpers.fingerprint(session) == fingerprint, "upgraded/exam card inspection preserves domain/RNG/revision")
	shell.free()


func _card_face_inspection(battle: BattleScreen, session: GameSession, suffix: String) -> void:
	var original := battle.view.duplicate(true)
	var card_rules := BattleCardRules.new(session._catalog)
	for sample in [
		{"id": "R3-P03-19", "exam": "", "term": "每回合最多"},
		{"id": "R3-P04-01", "exam": "independent_answer", "term": "放松"}
	]:
		var state := BattleState.new({
			"card_by_id": {"copy_variant": {"definition_id": str(sample.id), "upgrade_level": 1}},
			"exam_flags": [] if str(sample.exam).is_empty() else [str(sample.exam)]
		})
		var resolved := card_rules.resolve_face(state, "copy_variant")
		_check(resolved.ok, "controlled upgraded/exam view resolves: " + str(sample.id))
		if not resolved.ok:
			continue
		var face: Dictionary = resolved.data
		var shown := original.duplicate(true)
		var card_data: Dictionary = shown.hand[0].duplicate(true)
		card_data["definition_id"] = str(sample.id)
		card_data["face"] = face
		card_data["effective_cost"] = 0
		shown["hand"] = [card_data]
		battle.render(shown)
		await _frames()
		var text := ""
		if not battle._hand_cards.is_empty():
			battle._pin_card_detail(battle._card_hover_target(battle._hand_cards[0]))
			await _frames()
			_check(battle._hover_body.text.contains(str(sample.term)), "upgraded/exam explanation uses the resolved face")
			await _save("card-variant-hover-" + str(sample.id) + "-" + suffix)
			text = battle._hover_body.text
		else:
			var button := battle._buttons["card:" + str(card_data.card_id)] as UiOfferCard
			button.grab_focus()
			await _frames()
			_check(not is_instance_valid(battle._card_preview), "upgraded/exam focus requires I to open details")
			battle._pin_card_detail(battle._offer_card_hover_target(button))
			battle._update_pointer(.016)
			_check(not battle._pinned_card_detail.is_empty() and battle._hover_panel.visible and not is_instance_valid(battle._card_preview), "compact active-face details use a single side panel")
			text = battle._hover_body.text
		_check(text.contains(str(sample.term)) and text.contains("专注 0"), "upgraded/exam detail uses the active effects and effective cost")
		if not str(sample.exam).is_empty():
			_check(not text.contains("召入伙伴") and not text.contains("正常合作"), "exam detail excludes ordinary partner effects")
		await _frames()
		await _save("card-variant-" + str(sample.id) + "-" + suffix)
		if str(sample.exam).is_empty():
			battle._hover_scroll.scroll_vertical = 10000
			await _frames()
			_check(battle._hover_scroll.scroll_vertical > 0, "fixed long upgraded details remain scrollable")
			await _save("card-variant-scrolled-" + str(sample.id) + "-" + suffix)
		battle._close_panel()
		battle._hover_pinned = false
	battle.render(original)


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
