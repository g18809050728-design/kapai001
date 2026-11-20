extends SceneTree
## Native presentation checks. Launch with -- --relic-pilot and an isolated APPDATA.

const OUT := "res://artifacts/verification/relic-pilot-20261120/review/screens"

var _captures: Array[Dictionary] = []
var _failures: Array[String] = []
var _checks := 0
var _catalog := ContentDB.new("res://data/four_year")
var _store := SaveStore.new("user://relic_pilot/saves")
var _main: Node
var _shell: GameShell
var _session: GameSession


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var evidence := ProjectSettings.globalize_path("res://artifacts/verification/relic-pilot-20261120/isolation-").replace("\\", "/").to_lower()
	if not OS.get_cmdline_user_args().has("--relic-pilot") or not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(evidence):
		push_error("Use -- --relic-pilot and an APPDATA under artifacts/verification/relic-pilot-20261120/isolation-*")
		quit(1)
		return
	if not _catalog.load(RelicPilot.MANIFEST).ok:
		push_error("Could not load relic pilot catalog")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	_boot()
	_check(_session.is_relic_pilot(), "actual main scene recognizes --relic-pilot")
	_size(100)
	await _settle()
	await _capture("pilot-menu")
	_check(_shell.press("menu:new"), "main menu opens setup")
	_check(_shell.press("setup:start"), "setup opens real campaign")
	var opened := _session.get_view()
	_check(opened.run is Dictionary and opened.run.get("manifest_id") == RelicPilot.MANIFEST and opened.run.relics.is_empty(), "new campaign uses pilot manifest and starts unequipped")
	_shell.show_screen("menu")
	_check(_shell.press("menu:test"), "main menu opens test room")
	await _settle()
	var slots := _shell.page.find_children("PilotRelicSlot*", "OptionButton", true, false)
	if _check(slots.size() == 3, "pilot entry has three relic selectors"):
		var first := slots[0] as OptionButton
		_check(_choice(first, "RX-P01-01") > 0 and _choice(first, "RX-P02-01") == -1 and _choice(first, "RX-C03") == -1, "only active general and current owner relics are selectable")
		_select(first, "RX-C01")
		_select(slots[1] as OptionButton, "RX-C01")
		_check(first.selected == 0, "duplicate selector moves the item, not duplicates it")
		_select(first, "RX-C02")
		_select(slots[2] as OptionButton, "RX-P01-01")
		await _capture("test-room-equipped")
		_check(_shell.press("test:start"), "start experiment via the test room button")
		await _settle()
		var battle: Dictionary = _session.get_test_view().get("battle", {})
		_check(battle.get("relics", []) == ["RX-C02", "RX-C01", "RX-P01-01"] and int(battle.get("player", {}).get("relax", 0)) == 4, "actual battle uses selector order and applies the bell")
		var equipped := _button("toolbar:relic:1")
		_check(equipped != null and equipped.get_global_rect().position.y >= TestHud.bar_height(), "test controls do not cover actual equipment buttons")
		_check(_has_label("晨课铃触发 · 放松 +4 · 剩余 0 次"), "startup uses real trigger value and remaining count")
		await _capture("test-battle-relic-hud")
		_check(_shell.press("toolbar:relic:1"), "equipped HUD opens exact relic")
		await _settle()
		_check(_has_label("第 1 回合恢复自然专注后，获得 4 放松。"), "full equipped effect uses RX text")
		await _capture("battle-equipped-detail")
		_check(_shell.press("battle:close_panel"), "close battle reference without changing equipment")
		_check(_shell.press("battle:end_turn"), "actual end turn in test room")
		await _settle()
		_check(_has_label("定时插座触发 · 专注 +1 · 剩余 0 次"), "experiment command shows actual round-two outlet event")
		if _session.has_test_room():
			_session.close_test_room()
	var fixtures := _collect_fixtures()
	if _check(fixtures.has("offer") and fixtures.has("card_reward"), "capture fixtures from real generated rewards"):
		for dimensions in [Vector2i(1280, 800), Vector2i(960, 640)]:
			root.size = dimensions
			for text_scale in [100, 125, 150]:
				_size(text_scale)
				await _settle()
				await _offer(fixtures.offer, "%d-%d" % [dimensions.x, text_scale])
		await _skip_reward(fixtures.card_reward)
	_main.free()
	var report := {"checks": _checks, "failures": _failures, "captures": _captures,
		"scope": "original main, scripted battle settlements for real reward fixtures, actual controls, isolated user data"}
	var file := FileAccess.open(OUT.path_join("manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("RX_PILOT_UI=" + JSON.stringify({"checks":_checks,"failures":_failures,"captures":_captures.size()}))
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _collect_fixtures() -> Dictionary:
	var service := RunService.new(_catalog)
	var start := service.create(StartRunRequest.new("P04", &"normal", RelicPilot.MANIFEST, "42"))
	if not _check(start.ok, "fixed pilot route created"):
		return {}
	var run: RunState = start.data.state
	var rng: Dictionary = start.data.rng_states
	var equipment := TransactionResolver.new(_catalog)
	equipment.add_relic(run, "RX-C26", "", 0)
	equipment.add_relic(run, "RX-C28", "", 1)
	equipment.add_relic(run, "RX-P04-06", "", 2)
	var fixtures := {}
	for i in 80:
		var node := run.find_node(run.current_node_id)
		var pending: Dictionary = run.campaign.pending
		var reward: RewardOffer = run.pending_reward
		var command: GameAction
		var next: GameResult
		if pending.get("kind") == "relic":
			fixtures.offer = _snapshot(run, rng)
			break
		elif not pending.is_empty():
			command = GameAction.new(&"choose_campaign", {"offer_id":pending.offer_id,"option_id":"skip"})
		elif not run.active_battle_id.is_empty():
			next = service.settle_battle(run, {"battle_id":run.active_battle_id,"result":"won","remaining_vitality":20}, rng)
		elif node != null and node.status == "active":
			if reward != null and not reward.is_complete():
				if not fixtures.has("card_reward"):
					fixtures.card_reward = _snapshot(run, rng)
				command = GameAction.new(&"skip_reward", {"offer_id":reward.offer_id,"item_id":reward.items[0].item_id})
			elif node.kind == "event" and str(node.context.event.resolved_option_id).is_empty():
				command = GameAction.new(&"choose_event", {"event_instance_id":node.context.event.event_instance_id,"option_id":"leave"})
			elif node.kind == "rest" and not node.context.get("used", false):
				command = GameAction.new(&"take_rest", {"node_id":node.node_id,"option_id":"heal"})
			else:
				command = GameAction.new(&"leave_node", {"node_id":node.node_id})
		else:
			var reachable := run.reachable_node_ids()
			if reachable.is_empty():
				break
			command = GameAction.new(&"enter_node", {"node_id":reachable.front()})
		if command != null:
			next = service.apply(run, command, rng)
		if not _check(next != null and next.ok, "advance fixture step %d (%s): %s" % [i, command.type if command != null else "settle", next.error.to_dictionary() if next != null and next.error != null else ""]):
			break
		run = next.data.state
		rng = next.data.rng_states
	return fixtures


func _snapshot(run: RunState, rng: Dictionary) -> Dictionary:
	var state := SessionState.new()
	state.run = run
	state.random_snapshot = rng
	var encoded := SnapshotCodec.encode_session(state, _catalog.get_info())
	return encoded.data if _check(encoded.ok, "serialize generated fixture") else {}


func _boot() -> void:
	if is_instance_valid(_main):
		# Main connects a window signal; remove its stale callable between runs.
		for connection in root.close_requested.get_connections():
			if connection.callable.get_object() == _main:
				root.close_requested.disconnect(connection.callable)
		_main.free()
	_main = preload("res://src/app/main.tscn").instantiate()
	root.add_child(_main)
	_shell = _main.get_node("GameShell") as GameShell
	_session = _main.get_node("GameSession") as GameSession


func _restore(snapshot: Dictionary) -> bool:
	_boot()
	if not _check(not snapshot.is_empty() and _store.save("current_run", snapshot).ok, "write isolated UI fixture"):
		return false
	if not _check(_session.continue_run().ok, "continue real saved fixture via GameSession"):
		return false
	_shell.show_screen("")
	return true


func _offer(snapshot: Dictionary, suffix: String) -> void:
	if not _restore(snapshot):
		return
	await _settle()
	var view := _session.get_view()
	if not _check(view.screen == &"campaign" and view.run.campaign_offer.kind == "relic", "real campaign reward " + suffix):
		return
	var candidates: Array = view.run.campaign_offer.candidates
	var target := str(candidates[1])
	var card := _button("campaign:claim:" + target) as UiOfferCard
	if not _check(card != null, "role relic reward control " + suffix):
		return
	_check(UiStyle.texture(target) != null, "native texture loads " + target)
	_check(card.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(root.size))), "candidate in viewport " + suffix)
	await _capture("reward-" + suffix)
	card.grab_focus()
	await _settle()
	var text := str(view.run.campaign_offer.details[target].rx.text)
	_check(_has_label(text), "focus reveals complete relic rules " + suffix)
	_check(_shell.press("card:pin"), "keyboard preview can be pinned " + suffix)
	await _settle()
	var popup: Control = _shell.page._card_preview
	_check(is_instance_valid(popup) and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(popup.get_global_rect().grow(-1)), "full description popup fits %s (bounds %s)" % [suffix, popup.get_global_rect() if is_instance_valid(popup) else "missing"])
	await _capture("candidate-detail-" + suffix)
	_check(_shell.press("card:pin"), "pinned detail closes " + suffix)
	await _settle()
	_check(_shell.press("campaign:claim:" + target), "select without claim " + suffix)
	await _settle()
	_check(_button("campaign:confirm").disabled, "full slots require a real replacement " + suffix)
	var old := str(view.run.relics[2].relic_id)
	var replacing := _button("campaign:replace:" + old)
	if not _check(replacing != null and replacing.focus_mode != Control.FOCUS_NONE, "replacement reachable by focus " + suffix):
		return
	replacing.grab_focus()
	await _settle()
	_check(_shell.page._scroll.get_global_rect().encloses(replacing.get_global_rect().grow(-1)), "keyboard focus scrolls replacement into view " + suffix)
	_check(_shell.press("campaign:replace:" + old), "choose replacement " + suffix)
	await _settle()
	replacing = _button("campaign:replace:" + old)
	await _settle()
	var confirm := _button("campaign:confirm")
	_check(confirm != null and not confirm.disabled and confirm.size.y >= 44.0 and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(confirm.get_global_rect().grow(-1)), "confirmation enabled, visible, at least 44px " + suffix)
	_check(_has_label(str(view.run.relics[2].detail.rx.text)), "long equipped description present in replacement " + suffix)
	await _capture("replace-" + suffix)
	_check(_shell.press("campaign:inspect:" + old), "inspect old item without replacing " + suffix)
	await _settle()
	_check(_has_label(str(view.run.relics[2].detail.rx.text)), "long old effect readable in overlay " + suffix)
	await _capture("equipped-detail-" + suffix)
	_check(_shell.press("inspect:close") and _shell.press("selection:cancel"), "close inspection and cancel replacement " + suffix)
	var unchanged := _session.get_view()
	_check(unchanged.revision == view.revision and unchanged.run.relics == view.run.relics and unchanged.run.campaign_offer.candidates == candidates, "all preview and cancel steps leave offer and inventory frozen " + suffix)


func _skip_reward(snapshot: Dictionary) -> void:
	if not _restore(snapshot):
		return
	await _settle()
	var before := _session.get_view()
	var item: Dictionary = before.run.pending_reward.items[0]
	var prefix := "reward:%s:" % item.item_id
	_check(item.get("rx_skip_bonus") == 8 and _shell.press(prefix + "skip"), "card reward display uses actual +8 quote")
	await _settle()
	_check(_has_label("确认跳过这项奖励？ · 失物招领牌：+8 金钱"), "skip confirmation names relic and actual money")
	await _capture("skip-card-confirmation")
	_check(_shell.press(prefix + "skip_confirm"), "accept the explicit skip")
	await _settle()
	var after := _session.get_view()
	_check(int(after.run.money) == int(before.run.money) + 8 and after.run.campaign.rx_uses.get("RX-C28") == 1, "confirm skip credits and consumes one charge")


func _size(text_scale: int) -> void:
	_check(_session.update_settings({"autosave":false,"presentation":{"text_scale":text_scale,"reduced_motion":true,"animation_speed":0}}).ok, "isolated presentation setting %d" % text_scale)
	_shell._apply_presentation()
	_shell.refresh()


func _button(uid: String) -> Button:
	return _shell.page._buttons.get(uid) as Button


func _choice(button: OptionButton, id: String) -> int:
	for index in button.item_count:
		if button.get_item_metadata(index) == id:
			return index
	return -1


func _select(button: OptionButton, id: String) -> void:
	var index := _choice(button, id)
	if _check(index >= 0, "choose test relic " + id):
		button.select(index)
		button.item_selected.emit(index)


func _has_label(text: String) -> bool:
	return _shell.page.find_children("*", "Label", true, false).any(func(label): return label.is_visible_in_tree() and label.text == text)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if _check(image != null and image.save_png(OUT.path_join(label + ".png")) == OK, "capture " + label):
		_captures.append({"file":label + ".png","width":image.get_width(),"height":image.get_height(),"scale":roundi(UiStyle.text_scale * 100)})


func _check(result: bool, name: String) -> bool:
	_checks += 1
	if not result:
		_failures.append(name)
	return result
