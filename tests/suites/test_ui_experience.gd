extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	_card_semantics()
	await _reward_loop()
	await _campaign_loop()
	await _v04_event_loop()
	await _status_and_settings()
	await _submission_and_persistence()
	await _large_text_and_focus()
	print("FY_UX_CHECKS=", JSON.stringify({"failures": _failures, "scope": "AC-01 to AC-15 targeted UI integration; controlled checkpoints; no natural four-year playthrough"}))
	return _failures


func _v04_event_loop() -> void:
	var path := "user://fy-v04-event-%d" % Time.get_ticks_usec()
	var session := GameSession.new(SaveStore.new(path))
	session.update_settings({"autosave": false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "V04 UI production run starts")
	var state := session._state.run
	# Historical V04 UI fixture places the event directly after the starter.
	# Annual-map progression and saved paths have their own integration suite.
	state.campaign = CampaignService.initial()
	state.nodes = CampaignMap.build(state.run_id)
	var nodes: Array = state.nodes.filter(func(value): return value.kind == "event" and value.term == 1)
	_check(not nodes.is_empty(), "V04 UI has an event node")
	if nodes.is_empty():
		return
	var node: RunNodeState = nodes[0]
	var first: RunNodeState = state.nodes.filter(func(value): return value.term == 1 and value.layer == 1)[0]
	first.status = "completed"
	first.context["encounter_id"] = "N13"
	first.context["settled"] = true
	state.settled_battle_ids.append(first.node_id)
	state.node_path.append(first.node_id)
	node.status = "active"
	state.current_node_id = node.node_id
	state.seen_event_ids.append("V04")
	node.context["event"] = EventState.create({"event_instance_id": state.next_instance_id("event"), "node_id": node.node_id, "definition_id": "V04", "frozen_candidates": {"rest": {}, "upgrade_work": {}, "leave": {}}})
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	var event_options: Array = session.get_view().run.event.options
	var eligible: Array = event_options.filter(func(value): return value.option_id == "upgrade_work")[0].eligible_card_ids
	var before := _helpers.fingerprint(session)
	_check(shell.press("event:upgrade_work"), "V04 action can be previewed")
	await _frames()
	var text := _all_text(shell.page)
	_check(text.contains("自动升级 %d 张工作牌" % eligible.size()) and text.contains("升级后："), "V04 UI lists every upgrade and comparison")
	_check(shell.page.action_draft("event:confirm").payload.selection_ids.is_empty(), "V04 UI sends no card target")
	_check(_helpers.fingerprint(session) == before, "V04 preview does not change state or RNG")
	_check(shell.press("event:confirm"), "V04 confirms one command")
	var upgraded: Dictionary = session.get_view().run
	_check(upgraded.vitality == 66 and upgraded.cards.filter(func(value): return eligible.has(value.card_id) and value.upgrade_level == 1).size() == eligible.size(), "V04 upgrades all work instances for one cost")
	var saved := session.save_current()
	_check(saved.ok, "V04 result saves at stable boundary: " + str(saved.error.to_dictionary() if saved.error != null else null))
	if saved.ok:
		var restored := GameSession.new(SaveStore.new(path))
		var continued := restored.continue_run()
		_check(continued.ok, "V04 result resumes: " + str(continued.error.to_dictionary() if continued.error != null else null))
		if continued.ok:
			_check(restored.get_view().run.cards == upgraded.cards and restored.get_view().run.vitality == upgraded.vitality, "V04 save retains all upgrades")
		restored.free()
	shell.free()


func _card_semantics() -> void:
	var catalog := ContentDB.new("res://data/four_year")
	_check(catalog.load("campus_four_year").ok, "production card catalog loads")
	var service := RunService.new(catalog)
	var rules: Dictionary = catalog.get_definition("ruleset", "campus_rules").data if catalog.get_definition("ruleset", "campus_rules").ok else catalog.get_definition("ruleset", str(catalog.get_info().enabled.ruleset[0])).data
	var texts := {}
	for id in ["R3-P01-10", "R3-P02-10", "R3-P02-11", "R3-P01-06", "R3-P03-05", "R3-P04-01", "R3-P04-25", "R3-P04-30"]:
		texts[id] = UiContentText.describe_card(service._reward_candidate_view("card", id, rules))
		_check(not texts[id].contains("{"), "card text never displays internal dictionaries: " + id)
	_check(texts["R3-P01-10"].contains("放松 3") and texts["R3-P01-10"].contains("每回合两次"), "full continuous ability and limit")
	_check(texts["R3-P02-10"].contains("抽牌 1") and texts["R3-P02-10"].contains("放松 2"), "paper ability includes both effects")
	_check(texts["R3-P02-11"].contains("章节常驻") and texts["R3-P02-11"].contains("下回合生效"), "chapter resident timing")
	_check(texts["R3-P01-06"].contains("连携") and texts["R3-P01-06"].contains("抽牌 1"), "conditional combo draw")
	_check(texts["R3-P03-05"].contains("所选源任务") and texts["R3-P03-05"].contains("最多 3"), "readable dynamic status cap")
	_check(texts["R3-P04-01"].contains("正常合作"), "related partner behavior")
	_check(texts["R3-P04-25"].contains("放松 5") and texts["R3-P04-25"].contains("每消耗 1 协同额外 +3") and texts["R3-P04-25"].contains("焦虑"), "synergy details include nested scaling benefit and final cleanse")
	_check(texts["R3-P04-30"].contains("完成量 12") and texts["R3-P04-30"].contains("协同为 0 也执行后续"), "all-synergy card shows its base benefit even at zero synergy")


func _reward_loop() -> void:
	var shell := _helpers.start_fixture_shell("user://fy-ux-reward-%d" % Time.get_ticks_usec()) as GameShell
	_check(_helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])), "map select and enter")
	_check(_helpers.finish_battle(shell), "real fixture battle reaches reward")
	var session := shell.session
	if session.get_view().screen != &"reward":
		_check(false, "reward route")
		shell.free()
		return
	var item: Dictionary = session.get_view().run.pending_reward.items[0]
	var prefix := "reward:%s" % item.item_id
	var first := str(item.candidates[0])
	var before := _helpers.fingerprint(session) as String
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		(Engine.get_main_loop() as SceneTree).root.size = dimensions
		shell.refresh()
		await _frames()
		for candidate in item.candidates:
			var button: Button = shell.page._buttons[prefix + ":pick:" + str(candidate)]
			if not shell.page._scroll.get_global_rect().encloses(button.get_global_rect()):
				print("FY_UX_GEOMETRY ", dimensions, " scroll=", shell.page._scroll.get_global_rect(), " card=", button.get_global_rect(), " page=", shell.page.size)
			_check(shell.page._scroll.get_global_rect().encloses(button.get_global_rect()), "all three candidates completely visible at %s" % dimensions)
		_check(shell.page.get_global_rect().encloses(shell.page._buttons[prefix + ":claim"].get_global_rect()), "fixed confirmation visible at %s" % dimensions)
	var card: UiOfferCard = shell.page._buttons[prefix + ":pick:" + first]
	_mouse_move(card.get_global_rect().get_center())
	await (Engine.get_main_loop() as SceneTree).create_timer(0.3).timeout
	_check(is_instance_valid(shell.page._card_preview), "real pointer hover opens delayed card details")
	if is_instance_valid(shell.page._card_preview):
		var preview_rect := shell.page._card_preview.get_global_rect()
		_mouse_move(Vector2(preview_rect.position.x - 4, preview_rect.get_center().y))
		await (Engine.get_main_loop() as SceneTree).process_frame
		_mouse_move(preview_rect.get_center())
		await (Engine.get_main_loop() as SceneTree).create_timer(0.22).timeout
		_check(is_instance_valid(shell.page._card_preview) and shell.page._preview_card == card, "pointer crosses the gap and keeps the same details readable")
	_mouse_move(Vector2(2, 2))
	await (Engine.get_main_loop() as SceneTree).create_timer(0.22).timeout
	shell.page.close_card_preview()
	card.grab_focus()
	await _frames()
	_check(is_instance_valid(shell.page._card_preview), "keyboard focus opens full detail")
	var key := InputEventKey.new()
	key.keycode = KEY_I
	key.pressed = true
	(Engine.get_main_loop() as SceneTree).root.push_input(key, true)
	_check(shell.page._preview_pinned, "I fixes card details")
	shell.page.close_card_preview()
	_check(_helpers.fingerprint(session) == before, "viewing and pinning preserve full state/RNG/revision")
	_check(shell.press(prefix + ":pick:" + first), "card object preselects")
	_check(_helpers.fingerprint(session) == before, "preselection is read-only")
	_check(shell.press(prefix + ":skip"), "skip is a local confirmation state")
	_check(_helpers.fingerprint(session) == before, "skip preview is read-only")
	shell.press("selection:cancel")
	_check(shell.press(prefix + ":claim"), "confirmation adds selected card")
	_check(session.get_view().run.cards.size() == 13, "selected card joins the actual deck once")
	_check(shell.notice.contains(first) or shell.notice.contains(UiStyle.label(first)), "business result survives automatic map return")
	var claimed := _helpers.fingerprint(session) as String
	_check(not shell.press(prefix + ":claim"), "consumed reward has no active claim button")
	_check(_helpers.fingerprint(session) == claimed, "duplicate claim changes nothing")
	shell.free()


func _campaign_loop() -> void:
	var runner = load("res://tests/suites/test_four_year.gd").new()
	_failures.append_array(runner.run())
	for kind in ["grand", "relic_full", "direction", "destination", "service"]:
		var session := GameSession.new(SaveStore.new("user://fy-ux-%s-%d" % [kind, Time.get_ticks_usec()]))
		session.update_settings({"autosave": false})
		session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
		session._state.run = runner._checkpoints[kind].copy_for_write()
		session._state.random_snapshot = runner._rng.duplicate(true)
		var shell := _helpers.attach_shell(session) as GameShell
		shell.show_screen("")
		await _frames()
		var before := _helpers.fingerprint(session) as String
		if kind == "grand":
			for category in ["cards", "deck", "resources"]:
				_check(shell.page.get_global_rect().encloses(shell.page._buttons["campaign:category:" + category].get_global_rect()), "all reward categories on first screen")
			shell.press("campaign:category:deck")
			shell.press("campaign:mode:upgrade")
			var target: Dictionary = session.get_view().run.cards.filter(func(value): return value.upgrade_detail is Dictionary)[0]
			shell.press("campaign:upgrade:" + str(target.card_id))
			var text := _all_text(shell.page)
			_check(text.contains("当前：") and text.contains("升级后："), "selected instance compares both levels")
			_check(shell.page.action_draft("campaign:confirm").payload.candidate_id == target.card_id, "confirmation uses exact instance ID")
			shell.press("campaign:back")
			shell.press("campaign:category:resources")
		elif kind == "relic_full":
			var offer: Dictionary = session.get_view().run.campaign_offer
			shell.press("campaign:claim:" + str(offer.candidates[0]))
			var replacement: Dictionary = session.get_view().run.relics[0]
			shell.press("campaign:replace:" + str(replacement.relic_id))
			_check(shell.page.action_draft("campaign:confirm").payload.replace_relic_id == replacement.relic_id, "explicit replacement instance")
		elif kind in ["direction", "destination"]:
			shell.press("campaign:" + ("theory" if kind == "direction" else "job"))
			_check(_all_text(shell.page).contains("方向") if kind == "direction" else _all_text(shell.page).contains("毕设"), "known consequence displayed")
		else:
			shell.press("campaign:skip")
		_check(_helpers.fingerprint(session) == before, "all local campaign browsing preserves full state/RNG: " + kind)
		_check(shell.press("campaign:confirm"), "one final campaign confirmation: " + kind)
		_check(_helpers.fingerprint(session) != before, "only final confirmation mutates: " + kind)
		shell.free()


func _status_and_settings() -> void:
	var session := GameSession.new(SaveStore.new("user://fy-ux-settings-%d" % Time.get_ticks_usec()))
	_check(session.update_settings({"presentation": {"text_scale": 150, "reduced_motion": true, "animation_speed": 0}}).ok, "presentation settings accepted")
	_check(not session.update_settings({"presentation": {"text_scale": 1, "reduced_motion": true, "animation_speed": 0}}).ok, "invalid text scale rejected")
	var restored := GameSession.new(session._store)
	_check(restored.get_presentation_settings().text_scale == 150, "presentation settings survive restart")
	restored.free()
	session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": false, "animation_speed": 1}, "autosave": false})
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
	# Controlled production hand; the actual negative effects still run through GameSession.
	var battle := session._state.battle
	var target_id := str(battle.tasks[0].task_id)
	var card_id := str(battle.zones.hand[0])
	battle.card_by_id[card_id].definition_id = "R3-P03-21"
	battle.player.focus = 10
	shell.refresh()
	shell.press("card:" + card_id)
	shell.press("task:" + target_id)
	var text := _all_text(shell.page)
	_check(text.contains("虚弱") and text.contains("乏力"), "actual applied task statuses appear on battlefield")
	_check(not text.contains("协同"), "P03 receives its own summary")
	_check(shell.press("battle:resources"), "resource summary has a real detail target")
	_check((shell.page as BattleScreen)._panel_text.contains("复合反应"), "resource details describe current character")
	shell.free()
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	(Engine.get_main_loop() as SceneTree).root.size = Vector2i(1280, 800)


func _all_text(node: Node) -> String:
	var value: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		value += _all_text(child)
	return value


func _submission_and_persistence() -> void:
	var path := "user://fy-ux-submit-%d" % Time.get_ticks_usec()
	var animated := _helpers.start_fixture_shell(path) as GameShell
	_helpers.enter_node(animated, str(animated.session.get_view().run.reachable_node_ids[0]))
	_helpers.finish_battle(animated)
	_check(animated.session.save_current().ok, "reward boundary saves frozen offer")
	var instant := _helpers.attach_shell(_helpers.fixture_session(path)) as GameShell
	_check(instant.press("menu:continue"), "reward restores with frozen candidates")
	instant.session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}})
	instant._apply_presentation()
	var item: Dictionary = animated.session.get_view().run.pending_reward.items[0]
	var prefix := "reward:%s" % item.item_id
	var candidate := str(item.candidates[0])
	var old_draft := {}
	for shell in [animated, instant]:
		shell.press(prefix + ":pick:" + candidate)
		old_draft = shell.page.action_draft(prefix + ":claim")
		old_draft.source_run_id = shell.session.get_view().run_id
		old_draft.source_revision = shell.session.get_view().revision
		if shell == animated:
			shell.session.update_settings({"autosave": true})
			shell.session._store.debug_hooks = {"current_run": {"fail_write": true}}
		_check(shell.press(prefix + ":claim"), "confirmed reward submits once")
		if shell == animated:
			_check(shell.notice.contains("已加入牌组") and shell.notice.contains("保存失败"), "business success and failed persistence are both visible")
		var after := _helpers.fingerprint(shell.session) as String
		shell.submit_action(old_draft)
		_check(_helpers.fingerprint(shell.session) == after, "duplicate and obsolete drafts never replay reward")
		_check(shell.notice.contains("过期"), "stale request visibly requires re-selection")
		if shell == animated:
			# Restore the already accepted result feedback for the persistence retry assertion.
			_check(shell.session.get_view().run.cards.size() == 13, "failed autosave retains the granted card")
			shell.session._store.debug_hooks = {}
			shell.show_screen("settings")
			var before_save := _helpers.fingerprint(shell.session) as String
			_check(shell.press("settings:save"), "save retry uses the visible save action")
			_check(_helpers.fingerprint(shell.session) == before_save, "retry only persists, without replaying reward")
			shell.show_screen("")
	_check(_helpers.fingerprint(animated.session) == _helpers.fingerprint(instant.session), "reward animation and reduced motion produce identical complete state/RNG")
	var stable := _helpers.fingerprint(animated.session) as String
	await (Engine.get_main_loop() as SceneTree).create_timer(0.45).timeout
	_check(_helpers.fingerprint(animated.session) == stable, "result animation completion never invokes business")
	animated.free()
	instant.free()


func _large_text_and_focus() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var page := UiExperiencePage.new()
	page.screen = "reward"
	page.theme = UiStyle.make_theme()
	tree.root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var name := "用于验证长名称完整换行的校园协作与期末资料整理卡牌"
	var data := {"run_id": "layout", "revision": 0, "cards": [], "relics": [], "pending_reward": {"offer_id": "layout", "items": [{"item_id": "long", "kind": "card", "status": "pending", "candidates": [name], "candidate_details": {name: {"cost": 1, "type": "strategy", "effects": [{"op": "draw", "amount": 2}]}}, "skippable": true}]}}
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		await _frames()
		for scale in [1.0, 1.25, 1.5]:
			UiStyle.text_scale = scale
			page.render(data)
			await _frames()
			var card: UiOfferCard = page._buttons["reward:long:pick:" + name]
			_check(page.get_global_rect().encloses(page._buttons["reward:long:claim"].get_global_rect()), "long name/missing art keeps confirmation accessible at %s %s" % [dimensions, scale])
			for label in card._face.find_children("*", "Label", true, false):
				_check(card.get_global_rect().encloses(label.get_global_rect()), "missing art and long card text remain inside the card at %s %s" % [dimensions, scale])
			card.grab_focus()
			page._show_card_preview(true)
			await _frames()
			_check(page._card_preview.is_ancestor_of(tree.root.gui_get_focus_owner()), "pinned details own keyboard focus")
			_check(card.focus_mode == Control.FOCUS_NONE, "pinned details isolate background keyboard focus")
			page.close_card_preview()
			_check(tree.root.gui_get_focus_owner() == card and not is_instance_valid(page._card_preview), "closing detail restores original card without reopening the panel")
	page.free()
	UiStyle.text_scale = 1.0
	tree.root.size = Vector2i(1280, 800)


func _frames() -> void:
	for i in 5:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append("FY-UX: " + message)
