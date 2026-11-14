extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _capture_dir := ""


func run() -> Array[String]:
	_capture_dir = OS.get_environment("CAMPUS_UI_FLOW_CAPTURE_OUT")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_capture_dir))
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	await _setup_and_map()
	await _rooms()
	await _pending_home()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	var evidence := {"checks": _checks, "failures": _failures, "captures": _captures, "scope": "real GameSession commands from isolated controlled route checkpoints; no natural playthrough or balance acceptance"}
	if not _capture_dir.is_empty():
		var file := FileAccess.open(_capture_dir + "/checks.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence, "\t"))
	print("UI_FLOW_REVISION=", JSON.stringify(evidence))
	return _failures


func _setup_and_map() -> void:
	var session := _session()
	var shell: GameShell = _helpers.attach_shell(session)
	shell.press("menu:new")
	for dimensions in [Vector2i(1280,800), Vector2i(960,600)]:
		for scale in [100,125,150]:
			await _present(shell, dimensions, scale)
			var page := shell.page as UiExperiencePage
			for uid in ["setup:difficulty:relaxed", "setup:difficulty:normal", "setup:difficulty:hard", "setup:advanced", "setup:start", "setup:back"]:
				_check(page.get_global_rect().encloses(page._buttons[uid].get_global_rect()), "fixed creation controls fit %s/%d: %s" % [dimensions,scale,uid])
			_check(page._buttons["setup:start"].global_position.x > page._buttons["setup:back"].global_position.x, "primary creation action stays on the right")
			for difficulty in ["relaxed", "normal", "hard"]:
				_check(shell.press("setup:difficulty:" + difficulty), "difficulty can actually be selected")
				_check(shell.page.action_draft("setup:start").payload.difficulty == difficulty, "selection reaches the actual start request")
				_check((shell.page.find_child("DifficultyEffects",true,false) as Label).text == DifficultyRules.description(session.get_setup_options().data.difficulty_details[difficulty]), "difficulty explanation comes from production rules")
			await _capture("setup-%d-%d" % [dimensions.x,scale])
			shell.press("setup:advanced")
			await _frames()
			var input := shell.page.find_child("RunSeedInput",true,false) as LineEdit
			_check(input != null and shell.page.get_global_rect().encloses(input.get_global_rect()) and input.has_focus(), "seed editor is visible and receives focus")
			if input != null and (not input.has_focus() or not shell.page.get_global_rect().encloses(input.get_global_rect())):
				print("SEED_LAYOUT=", {"page":shell.page.get_global_rect(), "input":input.get_global_rect(), "focus":input.has_focus(), "generation":shell.page._render_generation})
			input.text = "9223372036854775807"
			input.text_changed.emit(input.text)
			await _capture("seed-%d-%d" % [dimensions.x,scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(not is_instance_valid(shell.page._inspector) and shell.page.action_draft("setup:start").payload.seed == "9223372036854775807", "Escape closes settings and preserves the exact integer draft")
			shell.press("setup:advanced")
			shell.press("setup:seed_random")
			await _frames()
			_check(is_instance_valid(shell.page._inspector) and shell.page.find_child("RunSeedInput",true,false) != null, "random seed keeps the independent settings dialog open")
			shell.press("inspect:close")
	shell.press("setup:difficulty:normal")
	_check(shell.press("setup:start"), "real creation enters the map")
	_check(_helpers.enter_node(shell,str(session.get_view().run.reachable_node_ids[0])), "real map enters battle")
	for dimensions in [Vector2i(1280,800), Vector2i(960,600)]:
		for scale in [100,125,150]:
			await _present(shell,dimensions,scale)
			var battle := shell.page as BattleScreen
			var before := _helpers.fingerprint(session)
			var hand := battle._buttons.keys().filter(func(uid): return str(uid).begins_with("card:"))
			var originals := {}
			for uid in hand:
				originals[uid] = battle._buttons[uid]
			var button: Button = battle._buttons["battle:map"]
			button.grab_focus()
			_check(shell.press("battle:map"), "top bar opens the complete map")
			await _frames()
			var overlay := battle._full_map
			_check(is_instance_valid(overlay) and overlay._route.nodes == battle.view.route_nodes and overlay._route.positions.size() == battle.view.route_nodes.size(), "overlay displays every frozen annual node")
			_check(overlay._route.detailed_overview and overlay.get_global_rect().encloses(overlay._route.get_global_rect()) and overlay.get_global_rect().encloses(overlay._close.get_global_rect()), "semantic complete map and close control fit the viewport")
			for point in overlay._route.positions.values():
				_check(Rect2(Vector2.ZERO,overlay._route.size).has_point(point), "complete map contains every node center")
			_check(not shell.press("battle:end_turn"), "map modal blocks background battle commands")
			var id := str(overlay._nodes[-1].node_id)
			overlay._inspect(id)
			_check(overlay._details.text.contains(str(overlay._nodes[-1].title)), "any node reveals its actual room title")
			await _capture("full-map-%d-%d" % [dimensions.x,scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(button.has_focus(), "closing map restores the exact previous control focus")
			for uid in hand:
				_check(battle._buttons[uid] == originals[uid], "map open and close retain original hand controls")
			_check(_helpers.fingerprint(session) == before, "map viewing preserves complete state, revision and RNG")
			_key(KEY_M)
			await _frames()
			_check(is_instance_valid(battle._full_map), "M opens map")
			_key(KEY_M)
			await _frames()
			_check(not is_instance_valid(battle._full_map), "M closes map")
			await _capture("toolbar-%d-%d" % [dimensions.x,scale])
	shell.free()


func _rooms() -> void:
	for subtype in ["C","I","L","LAB","T","ST","R","E"]:
		var shell := _controlled_room(subtype)
		if shell == null:
			continue
		var session := shell.session
		var before := _helpers.fingerprint(session)
		for dimensions in [Vector2i(1280,800),Vector2i(960,600)]:
			for scale in [100,125,150]:
				await _present(shell,dimensions,scale)
				var page := shell.page as UiExperiencePage
				_check(is_instance_valid(page._room_illustration) and page._room_illustration.artwork != null, "room has a real campus illustration: " + subtype)
				if not is_instance_valid(page._room_illustration):
					print("ROOM_RENDER=", {"subtype":subtype,"screen":page.screen,"last_error":shell.last_error.to_dictionary() if shell.last_error != null else {},"view":page.view.get("campaign_offer",{})})
					shell.free()
					return
				_check(page.get_global_rect().encloses(page._room_illustration.get_global_rect()), "room illustration fits: " + subtype)
				_check(not page._room_illustration.get_global_rect().intersects(page._scroll.get_global_rect()), "illustration leaves readable action space: " + subtype)
				page.press("flow:options")
				await _frames()
				for uid in ["flow:map","inspect:deck","inspect:relics",page.screen+":save",page.screen+":menu","flow:help"]:
					var button: Button = page._buttons[uid]
					if page._toolbar._panel.is_ancestor_of(button):
						button.grab_focus()
						await _frames()
						_check(page._toolbar._panel.get_global_rect().encloses(button.get_global_rect()), "menu keyboard focus scrolls actual action into view: " + uid)
					_check(button.icon != null and button.has_meta("nav_icon") and page.get_global_rect().encloses(button.get_global_rect()), "uniform toolbar fits: " + uid)
				page.press("flow:close_options")
				if (dimensions.x == 1280 and scale == 100) or (dimensions.x == 960 and scale == 150):
					await _capture("room-%s-%d-%d" % [subtype,dimensions.x,scale])
		var page := shell.page as UiExperiencePage
		_check(shell.press("flow:map"), "ordinary room has the shared complete map")
		await _frames()
		_check(page._full_map._nodes == page.view.nodes, "room map uses the current public annual nodes")
		_click(page.global_position + Vector2(5,5))
		await _frames()
		_check(not is_instance_valid(page._full_map), "clicking the shaded background closes map")
		_check(_helpers.fingerprint(session) == before, "room viewing and complete map remain read-only")
		if subtype in ["C","I","ST","R","E"]:
			var uid := str({"C":"campaign:money","I":"campaign:money","ST":"campaign:progress","R":"rest:option:heal","E":"event:option:leave"}[subtype])
			var button: Button = page._buttons[uid]
			var old_choice := str(session.get_view().run.campaign.get("pending",{}).get("offer_id",""))
			_check(not button.disabled and shell.press(uid), "simple action submits directly: " + subtype)
			var after := _helpers.fingerprint(session)
			_check(after != before, "direct action actually resolves: " + subtype)
			button.pressed.emit()
			_check(_helpers.fingerprint(session) == after, "repeated old-button signal cannot submit twice: " + subtype)
			if not old_choice.is_empty():
				_check(session._state.run.campaign.history.filter(func(item): return item.offer_id == old_choice).size() == 1, "activity is consumed exactly once")
		else:
			_check(shell.press("campaign:mode:upgrade"), "paid service opens card selection: " + subtype)
			var card: Dictionary = session.get_view().run.cards.filter(func(item): return item.upgrade_detail is Dictionary)[0]
			shell.press("campaign:upgrade:"+str(card.card_id))
			await _frames()
			_check(_helpers.fingerprint(session) == before, "paid service selection is read-only")
			_check(shell.page._buttons["campaign:confirm"].global_position.x > shell.page._buttons["selection:cancel"].global_position.x, "paid service confirm is to the right of cancel")
			await _capture("room-%s-confirm-960-150" % subtype)
			_check(shell.press("campaign:confirm"), "paid action has one final confirmation: " + subtype)
			_check(session._state.run.cards.filter(func(item): return item.card_id == card.card_id)[0].upgrade_level == 1, "confirmation upgrades the chosen instance")
		shell.free()


func _controlled_room(subtype: String) -> GameShell:
	var session := _session()
	session.start_run(StartRunRequest.new("P01",&"normal","campus_four_year","42"))
	var run := session._state.run
	run.campaign = CampaignService.initial()
	run.nodes = CampaignMap.build(run.run_id)
	run.money = 200
	run.vitality = 40
	var destination: RunNodeState
	for node in run.nodes:
		if str(CampaignMap.metadata(node.node_id).subtype) == subtype:
			destination = node
			break
	_check(destination != null, "controlled room exists: " + subtype)
	if destination == null:
		session.free()
		return null
	var path: Array = []
	for year in range(1,destination.term+1):
		var first: RunNodeState = run.nodes.filter(func(node): return node.term == year and node.layer == 1)[0]
		if year == destination.term:
			for entrance in run.nodes.filter(func(node): return node.term == year and node.layer == 1):
				var approach := _path_to(run,entrance.node_id,destination.node_id)
				if not approach.is_empty():
					path.append_array(approach)
					break
		else:
			var node := first
			while true:
				path.append(node.node_id)
				if node.next_ids.is_empty():
					break
				node = run.find_node(node.next_ids[0])
	path.erase(destination.node_id)
	for id in path:
		var node := run.find_node(id)
		node.status = "completed"
		if node.kind in ["normal","elite","boss"]:
			node.context = {"settled":true}
			run.settled_battle_ids.append(id)
		run.node_path.append(id)
		run.current_node_id = id
	run.term = destination.term
	if run.term > 1:
		run.campaign.direction = "theory"
	if run.term == 4:
		run.campaign.destination = "job"
	_check(run.validate().is_empty(), "controlled route checkpoint validates: " + subtype)
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	var entered: bool = _helpers.enter_node(shell,destination.node_id)
	_check(entered, "public node command enters the real room: " + subtype)
	if not entered:
		print("ROOM_ENTRY_ERROR=", {"subtype":subtype,"destination":destination.node_id,"reachable":run.reachable_node_ids(),"issues":run.validate(),"current":run.current_node_id,"last_error":shell.last_error.to_dictionary() if shell.last_error != null else {},"view":session.get_view().screen,"uids":shell.page.button_uids()})
	return shell


func _path_to(run: RunState, id: String, destination: String) -> Array:
	if id == destination:
		return [id]
	for next in run.find_node(id).next_ids:
		var path := _path_to(run,next,destination)
		if not path.is_empty():
			path.push_front(id)
			return path
	return []


func _pending_home() -> void:
	var session := _session()
	session.start_run(StartRunRequest.new("P01",&"normal","campus_mvp","0"))
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	_helpers.enter_node(shell,str(session.get_view().run.reachable_node_ids[0]))
	(shell.page as BattleScreen)._finish_event_presentation()
	var card: Dictionary = session.get_view().battle.hand.filter(func(item): return item.definition_id == "K03")[0]
	shell.press("card:"+str(card.card_id))
	var choice: Variant = session.get_view().pending_choice
	_check(choice != null, "real K03 opens a mandatory choice")
	if choice != null:
		var id := str(choice.candidates[0].id)
		shell.press("choice:"+id)
		var before := _helpers.fingerprint(session)
		_check(shell.page.button_text("choice:menu") == "返回主页" and not shell.page.button_uids().has("choice:new_run"), "mandatory choice offers homepage instead of a new run")
		await _capture("choice-home-960-150")
		_check(shell.press("choice:menu") and shell.press("menu:continue"), "homepage returns to the same pending action")
		_check(_helpers.fingerprint(session) == before and (shell.page as BattleScreen).selection_snapshot().choice_selected_ids == [id], "homepage preserves workspace, selected cards, revision and RNG")
		_check(not session.save_current().ok, "half-resolved card effects remain unsavable")
		_check(shell.press("choice:confirm") and session.get_view().pending_choice == null, "returning from homepage completes the original choice")
	shell.free()


func _session() -> GameSession:
	var session := GameSession.new(SaveStore.new("user://flow-revision-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave":false,"presentation":{"reduced_motion":true,"animation_speed":0}})
	return session


func _present(shell: GameShell, dimensions: Vector2i, scale: int) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = dimensions
	shell.session.update_settings({"presentation":{"text_scale":scale,"reduced_motion":true,"animation_speed":0}})
	shell._apply_presentation()
	shell.refresh()
	await _frames(8)


func _frames(count: int = 5) -> void:
	for frame in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	(Engine.get_main_loop() as SceneTree).root.push_input(event,true)


func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		(Engine.get_main_loop() as SceneTree).root.push_input(event,true)


func _capture(caption: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var tree := Engine.get_main_loop() as SceneTree
	var code := tree.root.get_texture().get_image().save_png(_capture_dir+"/"+caption+".png")
	_check(code == OK,"capture saves " + caption)
	_captures.append(caption)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("UI flow revision: " + message)
