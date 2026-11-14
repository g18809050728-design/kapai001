extends SceneTree

const OUT := "res://artifacts/verification/sts2-ui-rebuild-20261114/screens-responsive"
var output_path := OUT
var shell: GameShell
var _screens: Array = []


class CategorySample extends Control:
	var category := "attack"
	var cost := "1"
	var pixels := 40.0

	func _draw() -> void:
		var center := Vector2.ONE * pixels * .5
		var radius := 18.0 * pixels / 42.0
		CardFaceView.paint_category_badge(self, category, center, radius)
		CardFaceView.paint_category_cost(self, get_theme_font("font"), category, cost, center, radius)


func _initialize() -> void:
	if not OS.get_environment("CAMPUS_UI_CAPTURE_OUT").is_empty():
		output_path = OS.get_environment("CAMPUS_UI_CAPTURE_OUT")
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	await _card_categories()
	await _category_icons()
	var runner = load("res://tests/suites/test_four_year.gd").new()
	var failures: Array[String] = runner.run()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	var session := GameSession.new(SaveStore.new("user://ui-experience-capture-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	shell = GameShell.new()
	shell.session = session
	root.add_child(shell)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		var suffix := "-%d" % dimensions.x
		session.restart_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"), true)
		shell.show_screen("menu")
		await _save("menu" + suffix)
		shell.show_screen("")
		await _save("map" + suffix)
		shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
		await _save("map-selected" + suffix)
		for scale in [125, 150]:
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			shell._apply_presentation()
			shell.refresh()
			await _save("map-text%d" % scale + suffix)
			var forecast_scroll := shell.page.find_child("RouteForecast", true, false) as ScrollContainer
			forecast_scroll.scroll_vertical = 100000
			await _save("map-scrolled-text%d" % scale + suffix)
		session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": false, "animation_speed": 1}})
		shell._apply_presentation()
		shell.refresh()
		shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
		shell.press("map:enter")
		await _save("battle" + suffix)
		shell.press("battle:map")
		await _save("battle-map" + suffix)
		shell.press("battle:close_panel")
		shell.press("battle:deck")
		await _save("battle-deck" + suffix)
		shell.press("battle:close_panel")
		for scale in [125, 150]:
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			shell._apply_presentation()
			shell.refresh()
			await _save("battle-text%d" % scale + suffix)
		session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": false, "animation_speed": 1}})
		shell._apply_presentation()
		session._state.battle = null
		for kind in ["grand", "relic_full", "direction", "destination", "service"]:
			session._state.run = runner._checkpoints[kind].copy_for_write()
			session._state.random_snapshot = runner._rng.duplicate(true)
			shell.show_screen("")
			await _save(kind + suffix)
			if kind == "grand":
				shell.press("campaign:category:cards")
				await _save("grand-cards" + suffix)
				var id := str(session.get_view().run.campaign_offer.candidates[0])
				shell.press("campaign:claim:" + id)
				await _save("grand-selected" + suffix)
				shell.press("campaign:back")
				shell.press("campaign:category:deck")
				shell.press("campaign:mode:upgrade")
				await _save("upgrade-grid" + suffix)
				var target: Dictionary = session.get_view().run.cards.filter(func(card): return card.get("upgrade_detail") is Dictionary)[0]
				shell.press("campaign:upgrade:" + str(target.card_id))
				await _save("upgrade-comparison" + suffix)
			elif kind == "relic_full":
				shell.press("campaign:claim:" + str(session.get_view().run.campaign_offer.candidates[0]))
				shell.press("campaign:replace:" + str(session.get_view().run.relics[0].relic_id))
				await _save("relic-comparison" + suffix)
		var run := runner._checkpoints["grand"].copy_for_write() as RunState
		var candidates: Array = run.campaign.pending.candidates.duplicate()
		run.campaign.pending = {}
		run.pending_reward = RewardOffer.new({"offer_id": "capture-reward", "source_node_id": run.current_node_id, "items": [{"item_id": "cards", "kind": "card", "status": "pending", "candidates": candidates, "skippable": true}], "meta": {"money": 15}})
		session._state.run = run
		shell.show_screen("")
		await _save("reward" + suffix)
		var card: UiOfferCard = shell.page._buttons["reward:cards:pick:" + str(candidates[0])]
		card.grab_focus()
		await _save("reward-preview" + suffix)
		shell.press("reward:cards:pick:" + str(candidates[0]))
		for frame in 5:
			await process_frame
		shell.page.close_card_preview()
		await _save("reward-selected" + suffix)
		for scale in [125, 150]:
			session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			shell._apply_presentation()
			shell.refresh()
			await _save("reward-text%d" % scale + suffix)
			shell.show_screen("setup")
			await _save("setup-text%d" % scale + suffix)
			shell.show_screen("")
		session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": false, "animation_speed": 1}})
		shell._apply_presentation()
		shell.show_screen("setup")
		await _save("setup" + suffix)
		shell.show_screen("settings")
		await _save("settings" + suffix)
		shell.hide()
		var summary_page := UiExperiencePage.new()
		summary_page.screen = "summary"
		summary_page.theme = UiStyle.make_theme()
		root.add_child(summary_page)
		summary_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var summary_run := runner._checkpoints["summary"].copy_for_write() as RunState
		var summary_data: Dictionary = runner._service.make_view(summary_run)
		summary_data.terminal_summary = runner._service._finalize(summary_run,"won","four_years_completed",str(summary_run.campaign.destination)).to_dictionary()
		summary_page.render(summary_data)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var summary_error := root.get_texture().get_image().save_png(output_path.path_join("summary"+suffix+".png"))
		_screens.append({"name":"summary"+suffix,"size":[root.size.x,root.size.y],"save_error":summary_error,"controlled_summary":true})
		summary_page.free()
		shell.show()
		await _services(suffix)
		await _production_rooms(suffix)
	shell.free()
	var file := FileAccess.open(output_path.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_screens, "\t"))
	file.close()
	print("UI_EXPERIENCE_CAPTURE=passed count=", _screens.size())
	quit(0)


func _card_categories() -> void:
	root.size = Vector2i(1280, 800)
	var stage := Control.new()
	stage.theme = UiStyle.make_theme()
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var catalog := ContentDB.new("res://data/four_year")
	catalog.load("campus_four_year")
	var title := Label.new()
	title.text = "类型图形费用角标 · 共享卡框与正文层次"
	title.position = Vector2(40, 18)
	title.add_theme_font_size_override("font_size", 24)
	stage.add_child(title)
	var ids := ["R3-C-01", "R3-C-02", "R3-C-03", "R3-C-08", "R3-C-06", "R3-P04-01"]
	for index in ids.size():
		var detail: Dictionary = catalog.get_definition("card", ids[index]).data
		var face := CardFaceView.new()
		var model := CardDisplayModel.from_card(detail)
		face.configure(model)
		face.position = Vector2(42 + index * 200, 68)
		face.size = Vector2(168, 244)
		stage.add_child(face)
		var offer := UiOfferCard.new()
		offer.configure(ids[index], detail, "奖励 / 商店同源卡面", false, false, true)
		offer.position = Vector2(42 + index * 200, 356)
		stage.add_child(offer)
		offer.size = offer.custom_minimum_size
		offer._fit_contents()
		var label := Label.new()
		label.text = "%s · 专注%s" % [model.category_name, model.cost]
		label.position = Vector2(42 + index * 200, 318)
		label.add_theme_font_size_override("font_size", 17)
		stage.add_child(label)
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_path.path_join("card-categories-1280.png"))
	stage.free()


func _category_icons() -> void:
	root.size = Vector2i(1280, 480)
	var stage := Control.new()
	stage.theme = UiStyle.make_theme()
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("f4efe3")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(background)
	var categories := ["attack", "defense", "utility", "field", "ability", "burden"]
	for index in categories.size():
		var category: String = categories[index]
		var label := Label.new()
		label.text = CardDisplayModel.CATEGORY_NAMES[category]
		label.position = Vector2(40 + index * 205, 22)
		stage.add_child(label)
		for row in 3:
			var pixels: float = [40.0, 32.0, 24.0][row]
			var caption := Label.new()
			caption.text = "%d px · 费用0 / 1 / 2 / 3" % pixels
			caption.position = Vector2(40 + index * 205, 64 + row * 122)
			caption.add_theme_font_size_override("font_size", 13)
			stage.add_child(caption)
			for fee in 4:
				var sample := CategorySample.new()
				sample.category = category
				sample.cost = str(fee)
				sample.pixels = pixels
				sample.position = Vector2(40 + index * 205 + fee * 44, 96 + row * 122)
				sample.size = Vector2.ONE * pixels
				stage.add_child(sample)
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_path.path_join("category-icons.png"))
	stage.free()


func _services(suffix: String) -> void:
	var saved := shell
	saved.hide()
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	shell = helpers.start_fixture_shell("user://ux-services-%d" % Time.get_ticks_usec())
	for kind in ["normal", "event", "shop", "elite", "rest"]:
		var target := ""
		for node in shell.session.get_view().run.nodes:
			if node.kind == kind:
				target = str(node.node_id)
				break
		helpers.enter_node(shell, target)
		if kind in ["normal", "elite"]:
			helpers.finish_battle(shell)
			for i in 8:
				if shell.session.get_view().screen != &"reward":
					break
				for item in shell.session.get_view().run.pending_reward.items:
					if item.status == "pending":
						shell.press("reward:%s:skip" % item.item_id)
						shell.press("reward:%s:skip_confirm" % item.item_id)
						break
		elif kind == "event":
			await _save("event" + suffix)
			for option in shell.session.get_view().run.event.options:
				if option.enabled and option.effects.any(func(effect): return effect.op == "upgrade_card"):
					shell.press("event:" + str(option.option_id))
					await _save("event-targets" + suffix)
					shell.press("selection:cancel")
					break
			shell.press("event:option:leave")
		elif kind == "shop":
			await _save("shop" + suffix)
			shell.press("shop:removal")
			var card: Dictionary = shell.session.get_view().run.cards[0]
			shell.press("shop:remove:" + str(card.card_id))
			await _save("shop-removal" + suffix)
			shell.press("shop:leave")
		else:
			await _save("rest" + suffix)
			shell.press("rest:option:upgrade")
			var card: Dictionary = shell.session.get_view().run.cards.filter(func(value): return value.get("upgrade_detail") is Dictionary)[0]
			shell.press("rest:upgrade:" + str(card.card_id))
			await _save("rest-comparison" + suffix)
	shell.free()
	shell = saved
	saved.show()


func _production_rooms(suffix: String) -> void:
	var saved := shell
	saved.hide()
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	for kind in ["shop","event","rest"]:
		var session := GameSession.new(SaveStore.new("user://sts2-rooms-%s-%d" % [kind,Time.get_ticks_usec()]))
		session.update_settings({"autosave":false,"presentation":{"animation_speed":0}})
		session.start_run(StartRunRequest.new("P03",&"normal","campus_four_year","42"))
		var run := session._state.run
		run.campaign = CampaignService.initial()
		run.nodes = CampaignMap.build(run.run_id)
		var destination := ""
		var destination_layer := 0
		for node in run.nodes:
			if node.term == 1 and node.kind == kind and destination.is_empty():
				destination = node.node_id
				destination_layer = node.layer
		for node in run.nodes:
			if node.term == 1 and node.layer < destination_layer and node.node_id.ends_with("s0"):
				node.status = "completed"
				run.node_path.append(node.node_id)
				run.current_node_id = node.node_id
		shell = helpers.attach_shell(session)
		shell.show_screen("")
		if not helpers.enter_node(shell,destination):
			push_error("production room could not be entered: "+kind)
			quit(1)
			return
		await _save("production-"+kind+suffix)
		if kind == "shop":
			shell.press("inspect:deck")
			await _save("production-deck"+suffix)
			shell.press("inspect:close")
			var meal := ""
			for stock in session.get_view().run.shop.stocks:
				if stock.kind == "meal":
					meal = stock.stock_id
			shell.press("shop:pick:"+meal)
			await _save("production-shop-selected"+suffix)
			for scale in [125, 150]:
				session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
				shell._apply_presentation()
				shell.refresh()
				await _save("production-shop-text%d" % scale+suffix)
				var meal_button: Button = shell.page._buttons["shop:pick:"+meal]
				shell.page._scroll.ensure_control_visible(meal_button.get_parent().get_parent().get_parent() as Control)
				await _save("production-shop-scrolled-text%d" % scale+suffix)
		shell.free()
	shell = saved
	saved.show()


func _save(label: String) -> void:
	# Initial draws are sequential; wait for the actual cards to land.
	if shell.page is BattleScreen:
		for frame in 240:
			var battle := shell.page as BattleScreen
			if battle._animator.pending_count() == 0 and not battle._presentation.is_animating():
				break
			await create_timer(.025).timeout
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(output_path.path_join(label + ".png"))
	_screens.append({"name": label, "size": [root.size.x, root.size.y], "save_error": code})
	if code != OK:
		push_error("capture failed: " + label)
