extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	await _map_and_battle()
	await _reward()
	await _shop()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	print("UI_USABILITY=", JSON.stringify({"checks": _checks, "sizes": ["1280x800", "960x600"], "text_scales": [100, 125, 150], "failures": _failures}))
	return _failures


func _map_and_battle() -> void:
	var session := GameSession.new(SaveStore.new("user://ui-usability-map-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false, "presentation": {"animation_speed": 0, "reduced_motion": true}})
	_check(session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42")).accepted, "production map starts")
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	var run: Dictionary = session.get_view().run
	var id := str(run.reachable_node_ids[0])
	var before := _helpers.fingerprint(session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale_value in [100, 125, 150]:
			await _present(shell, dimensions, scale_value)
			var page := shell.page as UiExperiencePage
			var button: Button = page._buttons["node:" + id]
			var rect := button.get_global_rect()
			var scroll_before := page._scroll.scroll_vertical
			_check(shell.press("node:" + id), "map node can be selected")
			await _frames()
			_check(page._buttons["node:" + id] == button and button.get_global_rect() == rect and page._scroll.scroll_vertical == scroll_before, "preview retains map control, coordinates and scroll")
			var title := page.find_child("PreviewNodeTitle", true, false) as Label
			var status := page.find_child("PreviewNodeStatus", true, false) as Label
			var forecast := page.find_child("RouteForecast", true, false) as ScrollContainer
			var full := page.find_child("ForecastFullText", true, false) as Label
			_check(page._map_preview.get_global_rect().encloses(title.get_global_rect()) and page._map_preview.get_global_rect().encloses(status.get_global_rect()), "node identity and status fit the fixed preview")
			_check(status.text.contains("✓") and status.text.contains("可进入"), "selection and reachability have explicit symbols and text")
			_check(forecast.size.y >= 90, "long forecast has usable reading space")
			_check(full.text == UiExperiencePage.MapForecast.describe(run.nodes, id).text, "forecast retains exact public bounds, caveats and layer details")
			var title_rect := title.get_global_rect()
			forecast.scroll_vertical = 10000
			await _frames()
			_check(title.get_global_rect() == title_rect and status.is_visible_in_tree(), "scrolling the full forecast never moves node identity")
			_check(forecast.get_global_rect().end.y <= page._buttons["map:enter"].global_position.y, "forecast leaves fixed confirmation available")
			var unavailable: String = str(run.nodes.filter(func(node): return not run.reachable_node_ids.has(node.node_id))[0].node_id)
			page.press("node:" + unavailable)
			await _frames()
			_check(page.button_disabled("map:enter") and (page.find_child("PreviewNodeStatus", true, false) as Label).text.contains("不能进入"), "unreachable preview cannot be mistaken for an entry")
			_check(_helpers.fingerprint(session) == before, "map selection and scrolling preserve state, RNG and revision")
	shell.press("node:" + id)
	_check(shell.press("map:enter"), "original confirmation enters the real battle")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale_value in [100, 125, 150]:
			await _present(shell, dimensions, scale_value)
			var battle := shell.page as BattleScreen
			var vitality := battle.find_child("PlayerVitalityValue", true, false) as Label
			_check(vitality.text == "%s / %s" % [battle.view.player.vitality, battle.view.max_vitality], "readable vitality uses actual domain values")
			_check(vitality.get_theme_font_size("font_size") * battle._stage.scale.x >= 13.5, "vitality remains readable in the small viewport")
			for meter in battle._task_meters.values():
				_check(battle.get_global_rect().encloses(meter.label.get_global_rect()) and meter.label.text.contains("屏障"), "work and shield remain visible by their target")
	shell.free()


func _reward() -> void:
	var shell: GameShell = _helpers.start_fixture_shell("user://ui-usability-reward-%d" % Time.get_ticks_usec())
	_check(_helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])) and _helpers.finish_battle(shell), "rule commands produce an actual reward")
	var item: Dictionary = shell.session.get_view().run.pending_reward.items[0]
	var prefix := "reward:%s" % item.item_id
	var before := _helpers.fingerprint(shell.session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale_value in [100, 125, 150]:
			await _present(shell, dimensions, scale_value)
			for id in item.candidates:
				var card: UiOfferCard = shell.page._buttons[prefix + ":pick:" + str(id)]
				_check(shell.page._scroll.get_global_rect().encloses(card.get_global_rect()), "all reward choices and captions fit without scrolling")
			var first: UiOfferCard = shell.page._buttons[prefix + ":pick:" + str(item.candidates[0])]
			var rect := first.get_global_rect()
			first.grab_focus()
			await _frames()
			_check(first._highlighted and first.get_global_rect() == rect, "keyboard focus visibly marks the card without moving its hit area")
			shell.page.close_card_preview()
			_check(shell.press(prefix + ":pick:" + str(item.candidates[0])), "reward can be preselected")
			await _frames()
			var selected: UiOfferCard = shell.page._buttons[prefix + ":pick:" + str(item.candidates[0])]
			_check(selected.selected and selected._caption.text.begins_with("✓"), "chosen reward retains a visible non-color mark")
			var confirm: Button = shell.page._buttons[prefix + ":claim"]
			_check(not confirm.disabled and shell.page.get_global_rect().encloses(confirm.get_global_rect()), "selected reward has an enabled and visible confirmation")
			_check(_helpers.fingerprint(shell.session) == before, "inspection and preselection never claim the reward")
	shell.free()


func _shop() -> void:
	var session := GameSession.new(SaveStore.new("user://ui-usability-shop-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false, "presentation": {"animation_speed": 0, "reduced_motion": true}})
	_check(session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42")).accepted, "production shop fixture starts")
	# Controlled route checkpoint; entry and stock creation still use public commands.
	var run := session._state.run
	run.campaign = CampaignService.initial()
	RunRelicRoster.upgrade_base_campaign(run)
	run.nodes = CampaignMap.build(run.run_id)
	var destination: RunNodeState = run.nodes.filter(func(node): return node.term == 1 and node.kind == "shop")[0]
	for node in run.nodes:
		if node.term == 1 and node.layer < destination.layer and node.node_id.ends_with("s0"):
			node.status = "completed"
			run.node_path.append(node.node_id)
			run.current_node_id = node.node_id
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	_check(_helpers.enter_node(shell, destination.node_id), "real command freezes shop inventory")
	var before := _helpers.fingerprint(session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale_value in [100, 125, 150]:
			await _present(shell, dimensions, scale_value)
			for stock in session.get_view().run.shop.stocks:
				var price := shell.page.find_child("StockPrice_" + str(stock.stock_id).validate_node_name(), true, false) as Label
				_check(price.text.begins_with(str(stock.price) + " 金钱") and price.text.contains("可购买" if int(stock.price) <= int(session.get_view().run.money) and not stock.sold else ("已售罄" if stock.sold else "金钱不足")), "price and availability match the frozen stock")
				shell.page._scroll.ensure_control_visible(price)
				await _frames()
				_check(shell.page._scroll.get_global_rect().encloses(price.get_global_rect()), "each price remains fully reachable by scrolling")
			var meal: Dictionary = session.get_view().run.shop.stocks.filter(func(stock): return stock.kind == "meal")[0]
			shell.press("shop:pick:" + str(meal.stock_id))
			await _frames()
			_check(shell.page.get_global_rect().encloses(shell.page._buttons["shop:confirm"].get_global_rect()), "shop confirmation remains visible with a selected meal")
			_check(_helpers.fingerprint(session) == before, "shop layout and selection never buy or reroll stock")
	shell.free()


func _present(shell: GameShell, dimensions: Vector2i, scale_value: int) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = dimensions
	shell.session.update_settings({"presentation": {"text_scale": scale_value, "animation_speed": 0, "reduced_motion": true}})
	shell._apply_presentation()
	shell.refresh()
	await _frames(10)


func _frames(count: int = 5) -> void:
	for frame in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("UI usability: " + message)
