extends SceneTree
## Play the shared native main scene; all storage must be redirected to this batch.

const EVIDENCE := "res://artifacts/verification/relic-removal-20261120/"
const OUT := EVIDENCE + "review/screens/"

var _catalog := ContentDB.new("res://data/four_year")
var _main: Node
var _shell: GameShell
var _session: GameSession
var _captures: Array[Dictionary] = []
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolation := ProjectSettings.globalize_path(EVIDENCE + "isolation-").replace("\\", "/").to_lower()
	if not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(isolation) or OS.get_cmdline_user_args().has("--relic-pilot"):
		push_error("Use ordinary main and APPDATA under relic-removal-20261120/isolation-*")
		quit(1)
		return
	if not _catalog.load(RelicPilot.ROSTER).ok:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,800)
	_boot()
	await _compendium()
	await _normal_entry()
	await _reward()
	_main.free()
	var summary := {"checks":_checks,"failures":_failures,"captures":_captures,"scope":"normal native main; real compendium, ordinary entry, staged reward route and actual claim, normal combat; isolated files"}
	var file := FileAccess.open(OUT + "manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"\t"))
	file.close()
	print("RELIC_ROSTER_UI=" + JSON.stringify(summary))
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _boot() -> void:
	if is_instance_valid(_main):
		# Destroy the old window handler before instantiating a new main.
		for connection in root.close_requested.get_connections():
			if connection.callable.get_object() == _main: root.close_requested.disconnect(connection.callable)
		_main.free()
	_main = preload("res://src/app/main.tscn").instantiate()
	root.add_child(_main)
	_shell = _main.get_node("GameShell") as GameShell
	_session = _main.get_node("GameSession") as GameSession


func _compendium() -> void:
	var start_revision := _session.get_view().revision
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size = dimensions
		for text_scale in [100,125,150]:
			_size(text_scale)
			_shell.show_screen("menu")
			await _settle()
			_check(_shell.press("menu:compendium"),"menu route opens actual compendium")
			_check(_shell.press("compendium:tab:relics"),"actual relic tab button")
			await _settle()
			var page := _shell.page as UiCompendiumPage
			if not _check(page != null,"installed page type"): return
			var suffix := "%d-%d" % [dimensions.x,text_scale]
			page.reset_filters()
			await _settle()
			_check(page.filtered_ids.size() == 104 and page.visible_ids.size() >= 8,"complete list available " + suffix)
			_check(_visible(page._tabs.relics) and _visible(page._search) and _visible(page._buttons["compendium:back"]),"tab/search/back fit " + suffix)
			for key in ["owner","rarity","year"]:
				_check(_visible(page._filters.get_node("CompendiumFilter_"+key)),"filter fits " + key + " " + suffix)
			if dimensions.x == 1280 and text_scale == 100:
				await _capture("gallery-all-1280-100")
				var originals := page.visible_ids.duplicate()
				_wheel(page._scroll)
				await _settle()
				_check(page.visible_ids.size() > originals.size() and page.visible_ids.slice(0,originals.size()) == originals,"scroll appends without replacing prefix")
				for index in 70:
					if page.visible_ids.size() == page.filtered_ids.size(): break
					_key(KEY_PAGEDOWN)
					await _settle(5)
				_check(page.visible_ids == page.filtered_ids,"continuous scroll visits all 104 entries")
				var ownership := page._filters.get_node("CompendiumFilter_owner") as OptionButton
				_check(ownership.item_count == 6 and page.filtered_ids.all(RelicPilot.is_rx), "only common and four character groups; no FY")
				page.search("FY_Y1_1")
				_check(page.filtered_ids.is_empty(), "retired relic cannot be found by ID")
				page.reset_filters()
				page.search("三色校准夹")
				_check(page.filtered_ids == ["RX-P03-11"],"search by displayed name")
				page.search("只进入对应角色")
				_check(page.filtered_ids.size() == 63,"search indexes actual source; one exam-only relic has a different source phrase")
				page.reset_filters()
			_select_filter(page,"owner","林序")
			_check(page.filtered_ids.size() == 16,"character has all sixteen " + suffix)
			_check(page._buttons["compendium:item:RX-P01-03"] != null and UiStyle.texture("RX-P01-03").resource_path.contains("/relic-roster-v2/"), "gallery uses installed V2 texture")
			await _capture("gallery-" + suffix)
			page.reset_filters()
			_select_filter(page,"rarity","金色")
			_select_filter(page,"year","大一")
			_check(page.filtered_ids.is_empty(),"year one has no gold after removal")
			page.reset_filters()
			page.search("RX-C39")
			await _settle()
			var uid := "compendium:item:RX-C39"
			_check(page.filtered_ids == ["RX-C39"] and page.press(uid),"search by ID and open item " + suffix)
			await _settle()
			var modal := page.detail
			if _check(is_instance_valid(modal) and modal._relic_art.texture == UiStyle.texture("RX-C39"),"installed detail uses shared equipment art " + suffix):
				_check(_has(modal,"金色") and not _has(modal,"gold"),"localized quality on relic detail " + suffix)
				_check(_has(modal,"这一段最多把精力扣到 1") and _has(modal,"大三") and _has(modal,"大四"),"complete effect and sources " + suffix)
				_check(page._buttons["compendium:back"].disabled and page._search.focus_mode == Control.FOCUS_NONE,"modal owns focus " + suffix)
				_check(_visible(modal._relic_art) and _visible(modal._buttons["compendium:detail:close"]) and _visible(modal._scroll),"art, text scroll and close fit " + suffix)
				await _capture("detail-" + suffix)
				_key(KEY_ESCAPE)
				await _settle()
				_check(not is_instance_valid(page.detail) and page._buttons[uid].has_focus(),"Esc restores exact gallery focus " + suffix)
				_check(page.press("compendium:back"),"back to main menu " + suffix)
				await _settle()
	_check(_session.get_view().revision == start_revision and _session.get_view().run == null,"encyclopedia never mutates gameplay or starts a run")


func _normal_entry() -> void:
	root.size = Vector2i(1280,800)
	_size(100)
	_shell.show_screen("menu")
	await _settle()
	_check(not _session.is_relic_pilot() and _shell.press("menu:new"),"normal startup enters setup")
	_check(_shell.press("setup:character:P01") and _shell.press("setup:start"),"normal character start")
	await _settle()
	var view := _session.get_view()
	_check(view.screen == &"map" and view.run.manifest_id == RelicPilot.ROSTER and view.run.relics.is_empty(),"normal run uses full manifest and an unequipped four-year map")
	await _capture("normal-map")
	var node_id := str(view.run.reachable_node_ids[0])
	var entered := _session.submit(CommandContext.new(str(view.run_id),view.revision),GameAction.new(&"enter_node",{"node_id":node_id}))
	_check(entered.accepted and entered.view.screen == &"battle","ordinary map goes to a real first battle")
	_shell.show_screen("")
	await _settle()
	_check(_shell.press("battle:end_turn"),"normal combat passes an actual end turn")
	await _settle()


func _reward() -> void:
	var fixture := _offer_fixture()
	if not _check(not fixture.is_empty(),"generated normal reward fixture"): return
	_boot()
	var store := SaveStore.new()
	_check(store.save("current_run",fixture).ok and _session.continue_run().ok,"normal continue validates actual frozen full pool")
	_shell.show_screen("")
	await _settle()
	var view := _session.get_view()
	var offer: Dictionary = view.run.campaign_offer
	var ordered: Array = offer.candidates
	_check(ordered.size() == 3 and ordered[0].begins_with("RX-C") and ordered[1].begins_with("RX-P04-"),"actual frozen general/character/mixed offer")
	await _capture("reward")
	var claim := str(ordered[1])
	_check(_shell.press("campaign:claim:" + claim),"selection previews one new character relic")
	await _settle()
	var old := str(view.run.relics[1].relic_id)
	_check(_shell.press("campaign:replace:" + old),"select replacement in full three slots")
	await _settle()
	await _capture("replace")
	_check(_shell.press("campaign:confirm"),"actual confirm equips chosen new item")
	await _settle()
	view = _session.get_view()
	_check(view.run.relics.size()==3 and view.run.relics.any(func(item): return item.definition_id == claim and item.slot == 1),"chosen relic fills exact slot; three slots retained")
	await _capture("equipped-map")
	var normal := ""
	for node in view.run.nodes:
		if node.kind == "normal" and node.node_id in view.run.reachable_node_ids:
			normal = node.node_id
			break
	if not _check(not normal.is_empty(),"normal battle reachable after claiming"): return
	_shell.submit_action({"type":"enter_node","payload":{"node_id":normal}})
	var entered := _session.get_view()
	_check(_shell.last_error == null and entered.screen == &"battle" and entered.battle.player.relax == 4,"normal battle uses actual equipped bell effect")
	await _settle()
	await _capture("equipped-battle")
	_key(KEY_L)
	await _settle()
	var log_search := _shell.page.find_child("LogSearch",true,false) as LineEdit
	if _check(log_search != null,"real battle log opens from L"):
		log_search.text = UiStyle.label("RX-C01")
		log_search.text_changed.emit(log_search.text)
		await _settle()
		_check(_has(_shell.page,"饰品触发 · " + log_search.text) and _has(_shell.page,"放松 0→4"),"equipped bell appears in the battle event log with actual resource change")
		await _capture("equipped-receipt")
		_key(KEY_ESCAPE)
		await _settle()
	_check(_shell.press("toolbar:relic:1"),"equipped HUD inspects new relic")
	await _settle()
	_check(_has(_shell.page,UiStyle.label(claim)),"equipment panel shows chosen relic title")
	await _capture("equipped-detail")


func _offer_fixture() -> Dictionary:
	var service := RunService.new(_catalog)
	var created := service.create(StartRunRequest.new("P04",&"normal",RelicPilot.ROSTER,"42"))
	if not created.ok: return {}
	var run: RunState = created.data.state
	var rng: Dictionary = created.data.rng_states
	for i in 3: service.transactions().add_relic(run,["RX-C01","RX-C28","RX-C04"][i],"",i)
	for index in range(60):
		var current := run.find_node(run.current_node_id)
		var pending: Dictionary = run.campaign.pending
		if pending.get("kind") == "relic":
			if current == null or not current.next_ids.any(func(id): return run.find_node(id).kind == "normal"):
				var skipped := service.apply(run,GameAction.new(&"choose_campaign",{"offer_id":pending.offer_id,"option_id":"skip"}),rng)
				if not skipped.ok: return {}
				run = skipped.data.state
				rng = skipped.data.rng_states
				continue
			var session := SessionState.new()
			session.run = run
			session.random_snapshot = rng
			var encoded := SnapshotCodec.encode_session(session,_catalog.get_info())
			return encoded.data if encoded.ok else {}
		var next: GameResult
		var cmd: GameAction
		if not pending.is_empty():
			cmd = GameAction.new(&"choose_campaign",{"offer_id":pending.offer_id,"option_id":"skip"})
		elif not run.active_battle_id.is_empty():
			next = service.settle_battle(run,{"battle_id":run.active_battle_id,"result":"won","remaining_vitality":55},rng)
		elif run.pending_reward != null and not run.pending_reward.is_complete():
			cmd = GameAction.new(&"skip_reward",{"offer_id":run.pending_reward.offer_id,"item_id":run.pending_reward.items[0].item_id})
		elif current != null and current.status == "active":
			if current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				cmd = GameAction.new(&"choose_event",{"event_instance_id":current.context.event.event_instance_id,"option_id":"leave"})
			elif current.kind == "rest" and not current.context.get("used",false):
				cmd = GameAction.new(&"take_rest",{"node_id":current.node_id,"option_id":"heal"})
			else:
				cmd = GameAction.new(&"leave_node",{"node_id":current.node_id})
		else:
			var ids := run.reachable_node_ids()
			if ids.is_empty(): return {}
			cmd = GameAction.new(&"enter_node",{"node_id":ids.front()})
		if cmd != null: next = service.apply(run,cmd,rng)
		if not _check(next != null and next.ok,"staged route step %d: %s" % [index, next.error.to_dictionary() if next != null and next.error != null else ""]): return {}
		run = next.data.state
		rng = next.data.rng_states
	return {}


func _select_filter(page: UiCompendiumPage, key: String, caption: String) -> void:
	var option := page._filters.get_node("CompendiumFilter_"+key) as OptionButton
	for index in option.item_count:
		if option.get_item_text(index).ends_with(" · " + caption):
			option.select(index)
			option.item_selected.emit(index)
			return
	_check(false,"missing visible filter: " + key + " / " + caption)


func _wheel(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.position = control.get_global_rect().get_center()
	event.factor = 10.0
	event.pressed = true
	root.push_input(event)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	root.push_input(event)


func _has(parent: Node, needle: String) -> bool:
	return parent.find_children("*","Label",true,false).any(func(node): return node.is_visible_in_tree() and node.text.contains(needle))


func _visible(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect().grow(-1))


func _size(percent: int) -> void:
	_check(_session.update_settings({"autosave":false,"presentation":{"text_scale":percent,"reduced_motion":true,"animation_speed":0}}).ok,"size setting %d" % percent)
	_shell._apply_presentation()
	_shell.refresh()


func _settle(frames: int = 7) -> void:
	for index in frames: await process_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _settle()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if _check(img != null and img.save_png(OUT + name + ".png") == OK,"write native screenshot " + name):
		_captures.append({"file":name + ".png","width":img.get_width(),"height":img.get_height(),"text_scale":roundi(UiStyle.text_scale*100)})


func _check(ok: bool, label: String) -> bool:
	_checks += 1
	if not ok: _failures.append(label)
	return ok
