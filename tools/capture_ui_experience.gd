extends SceneTree

const OUT := "res://artifacts/verification/ui-experience-20261104/visual"
var shell: GameShell
var _screens: Array = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
		shell.show_screen("")
		await _save("map" + suffix)
		shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
		shell.press("map:enter")
		await _save("battle" + suffix)
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
		await _services(suffix)
	shell.free()
	var file := FileAccess.open(OUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_screens, "\t"))
	file.close()
	print("UI_EXPERIENCE_CAPTURE=passed count=", _screens.size())
	quit(0)


func _services(suffix: String) -> void:
	var saved := shell
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
			shell.press("event:confirm")
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


func _save(label: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT.path_join(label + ".png"))
	_screens.append({"name": label, "size": [root.size.x, root.size.y], "save_error": code})
	if code != OK:
		push_error("capture failed: " + label)
