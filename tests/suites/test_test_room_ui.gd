extends RefCounted

## Test-room UI suite: menu entry, home, battle HUD, result page, close.

var _failures: Array[String] = []
var _root: String = ""


func run() -> Array[String]:
	_root = "user://test-room-ui-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	_check_home_map_selection()
	_check_fixed_start_node()
	_check_snapshot_deletion()
	_check_legacy_result()
	_check_default_battle_costs()
	_check_default_battle_costs(true)
	_check_default_end_turn()
	_check_campus_editor()
	_check_map_controls()
	_check_map_abandon()
	_check_free_map_navigation()
	_check_same_room_map_jump()
	var session := GameSession.new(SaveStore.new(_root + "/saves"))
	session.test_service().store = TestStore.new(_root + "/room")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(not session.has_test_room(), "no test context before entry")
	_check(shell.press("menu:test"), "menu exposes the test room entry")
	_check(shell.page is TestRoomPage, "menu entry opens the test room page")
	if shell.page is TestRoomPage:
		_check((shell.page as TestRoomPage).screen == "test_room_home", "home screen")
		_check(shell.page.button_uids().has("test:start"), "start button exists")
		_check(shell.page.button_uids().has("test:back"), "back button exists")
		var picker := shell.page.find_child("TestStartNode", true, false) as Button
		var location := shell.page.find_child("TestStartLocation", true, false) as Label
		_check(picker != null and not picker is OptionButton and location != null and location.text.contains("从本学年地图开始"), "home exposes the campus flow with visual node selection")
		_check(shell.page.find_child("TestStartSeed", true, false) is LineEdit
			and not shell.page.find_children("*", "LineEdit", true, false).any(func(input): return input.placeholder_text.begins_with("遭遇 ID")),
			"home has a seed input and no standalone encounter input")
		_check(shell.press("test:character:P02"), "character selection works")
		_check(shell.press("test:start"), "start submits the test configuration")
	_check(session.has_test_room(), "test context starts")
	_check(shell.page is UiExperiencePage and shell.page.screen == "map", "default start opens the campus map")
	_check(_enter_map_battle(shell), "default map enters a reachable battle")
	_check(shell.page is BattleScreen, "test battle uses the battle screen")
	_check(shell._test_hud != null, "battle HUD exists")
	_check(shell.page.button_uids().has("battle:end_turn"), "battle controls are available")
	var hud: TestHud = shell._test_hud
	for index in 3:
		_check(shell._test_hud.press("test:save"), "HUD consecutive snapshot save %d" % index)
	_check(session.list_test_files("snapshot").size() == 1, "HUD saves reuse one snapshot")
	var snapshot_id := str(session.list_test_files("snapshot")[0].id)
	_check(hud.press("test:open_editor"), "editor opens from the HUD")
	var panel: TestEditorPanel = hud.editor
	_check(panel.is_open(), "editor panel is open")
	_check(bool(session.get_test_view().test.editing), "service enters editing mode")
	_check(panel.press("test:editor:tab:resources"), "editor switches to the resources tab")
	_check(not panel.press("test:editor:apply"), "apply is disabled without a draft")
	var focus_before := int(session.get_test_view().battle.player.focus)
	var revision_before := int(session.get_test_view().test.revision)
	_check(panel.press("test:editor:field:player.focus:plus"), "editor creates a draft change")
	_check(panel.draft_count() == 1, "draft holds exactly one change")
	_check(panel.press("test:editor:discard"), "discard asks for confirmation")
	_check(panel.draft_count() == 1, "discard confirmation keeps the draft")
	_check(panel.press("test:editor:discard:cancel"), "discard confirmation can cancel")
	_check(panel.press("test:editor:close"), "close asks for confirmation with a draft")
	_check(panel.is_open(), "editor stays open until the close confirmation resolves")
	_check(panel.press("test:editor:close:cancel"), "close confirmation can cancel")
	_check(panel.press("test:editor:apply"), "apply submits the draft")
	var view := session.get_test_view()
	_check(int(view.battle.player.focus) == focus_before + 1, "draft change applies")
	_check(int(view.test.revision) == revision_before + 1, "patch increments revision")
	_check(panel.draft_count() == 0, "draft clears after apply")
	_check(panel.press("test:editor:tab:history"), "open snapshot editor controls")
	_check(panel.press("test:editor:save_snapshot"), "save snapshot from editor")
	_check(session.list_test_files("snapshot").size() == 1
		and str(session.list_test_files("snapshot")[0].id) == snapshot_id,
		"editor and HUD share the current snapshot")
	_check(panel.press("test:editor:close"), "editor closes from its own button")
	_check(not panel.is_open(), "editor panel is closed")
	_check(not bool(session.get_test_view().test.editing), "service leaves editing mode")
	shell.submit_action({"type": "test.undo", "payload": {}})
	view = session.get_test_view()
	_check(int(view.battle.player.focus) == focus_before, "undo reverts the applied change")
	_check(int(view.test.branch_id) == 1, "undo branches the context")
	var context := {
		"test_id": str(view.test.test_id),
		"branch_id": int(view.test.branch_id),
		"expected_revision": int(view.test.revision),
	}
	var won := session.set_test_outcome(context, "won")
	_check(won.accepted, "manual outcome can be set through the session")
	shell.refresh()
	_check(shell.page is UiExperiencePage and shell.page.screen in ["reward", "map"],
		"new experiments settle into normal campus rewards/map")
	shell.submit_action({"type": "test.save_and_exit", "payload": {}})
	_check(session.list_test_files("snapshot").size() == 1, "save and exit updates the current snapshot")
	_check(not session.has_test_room(), "close clears the test context")
	_check(shell.press("menu:new"), "formal menu still works after test room")
	_check(shell.page is not TestRoomPage, "formal pages are restored")
	shell.queue_free()
	return _failures


func _check_home_map_selection() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/home-map-saves"))
	session.test_service().store = TestStore.new(_root + "/home-map-room")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test"), "open setup for visual start selection")
	_check(shell.press("test:start:open_map"), "setup opens the same visual map picker as the editor")
	var picker: Variant = shell.page.get("map_picker")
	if picker == null or not picker.visible:
		_check(false, "setup visual map is visible before creating an experiment")
		shell.queue_free()
		return
	_check(not session.has_test_room(), "browsing the setup map does not start an experiment")
	_check(not shell.press("test:start"), "setup map blocks background start")
	var target: Dictionary = session.get_test_node_options("42").filter(func(node): return node.year == 4 and node.kind == "shop")[0]
	_check(picker.press("test:map:year:4") and picker.press("test:map:node:" + str(target.key)), "setup map previews a year four shop")
	_check(picker.visible and str(shell.page.get("_node_key")).is_empty(), "first click only previews the setup target")
	_check(picker.press("test:map:cancel"), "setup map can cancel")
	_check(str(shell.page.get("_node_key")).is_empty() and int(shell.page.get("_year")) == 1 and not session.has_test_room(), "cancel preserves setup and does not create an experiment")
	_check(shell.press("test:start:open_map"), "setup map can reopen")
	picker.press("test:map:year:4")
	picker.press("test:map:node:" + str(target.key))
	_check(picker.press("test:map:enter"), "setup map confirms the starting node")
	_check(not picker.visible and str(shell.page.get("_node_key")) == str(target.key) and int(shell.page.get("_year")) == 4, "confirmation updates setup year and selected node")
	_check(not session.has_test_room(), "confirming setup selection waits for start")
	_check(shell.press("test:start:open_map") and picker._year == 4 and picker._selected == target.key, "reopening locates the saved setup selection")
	picker.press("test:map:cancel")
	_check(str(shell.page.get("_node_key")) == str(target.key), "cancel keeps an already selected start node")
	var years := shell.page.find_child("TestStartYear", true, false) as OptionButton
	years.select(1)
	years.item_selected.emit(1)
	_check(str(shell.page.get("_node_key")).is_empty() and int(shell.page.get("_year")) == 2, "changing setup year clears the previous target")
	_select_home_node(shell, target)
	var seed := shell.page.find_child("TestStartSeed", true, false) as LineEdit
	seed.text = "43"
	seed.text_changed.emit("43")
	_check(str(shell.page.get("_node_key")).is_empty(), "changing seed clears a stale setup node")
	seed.text = "42"
	seed.text_changed.emit("42")
	shell.press("test:start:open_map")
	picker.press("test:map:node:" + str(target.key))
	_check(picker.press("test:map:node:" + str(target.key)), "second activation confirms setup selection")
	_check(not picker.visible and str(shell.page.get("_node_key")) == str(target.key), "second activation selects once and closes the setup map")
	_check(shell.press("test:start:map_default") and str(shell.page.get("_node_key")).is_empty(), "setup can return to starting at the year map")
	_check(shell.press("test:start") and session.get_test_view().run.term == 4 and session.get_test_view().run.current_node_id.is_empty(), "cleared selection starts at the chosen year map")
	shell.queue_free()


func _select_home_node(shell: GameShell, node: Dictionary) -> bool:
	_check(shell.press("test:start:open_map"), "setup opens visual node selection")
	var picker: Variant = shell.page.get("map_picker")
	if picker == null:
		_check(false, "setup has a visual map picker")
		return false
	_check(picker.press("test:map:year:%d" % int(node.year)), "setup map selects target year")
	_check(picker.press("test:map:node:" + str(node.key)), "setup map previews target node")
	_check(picker.press("test:map:enter"), "setup map confirms target node")
	return str(shell.page.get("_node_key")) == str(node.key)


func _check_fixed_start_node() -> void:
	for kind in ["normal", "shop"]:
		var session := GameSession.new(SaveStore.new(_root + "/fixed-start-" + kind))
		var shell := GameShell.new()
		shell.session = session
		(Engine.get_main_loop() as SceneTree).root.add_child(shell)
		_check(shell.press("menu:test"), "open fixed start setup " + kind)
		var nodes := session.get_test_node_options("42")
		var target: Dictionary = nodes.filter(func(node): return node.year == 4 and node.kind == kind)[0]
		_select_home_node(shell, target)
		_check(shell.press("test:start"), "start locates the chosen node " + kind)
		var picker: Variant = shell._test_hud.editor.map_picker
		_check(picker.visible and picker._selected == target.key, "confirmation map locates the original target " + kind)
		var state_hash := session.test_service().state.state_hash()
		for node in nodes.filter(func(entry): return entry.year == 4 and entry.key != target.key):
			_check(not picker.press("test:map:node:" + str(node.key)), "start confirmation blocks another node " + str(node.key))
		var other: Dictionary = nodes.filter(func(node): return node.year == 4 and node.key != target.key)[0]
		picker._overview.node_inspected.emit(str(other.key))
		_check(picker._selected == target.key, "overview cannot replace the original start " + kind)
		_check(picker.press("test:map:year:1"), "fixed start may browse another year " + kind)
		for node in nodes.filter(func(entry): return entry.year == 1):
			_check(not picker.press("test:map:node:" + str(node.key)), "start confirmation blocks cross-year node " + str(node.key))
		_check(not picker.press("test:map:enter"), "another year cannot confirm a different start " + kind)
		_check(session.test_service().state.state_hash() == state_hash, "blocked selections preserve experiment and RNG " + kind)
		_check(picker.press("test:map:current") and picker._year == 4 and picker._selected == target.key, "locate returns to the chosen start " + kind)
		var revision: int = session.get_test_view().test.revision
		_check(picker.press("test:map:enter"), "only the chosen start can confirm " + kind)
		var view := session.get_test_view()
		_check(str(view.run.current_node_id).ends_with("|" + str(target.key)) and int(view.test.revision) == revision + 1,
			"confirmation enters the original target once " + kind)
		_check(not picker.press("test:map:enter"), "closed start confirmation cannot enter twice " + kind)
		shell._test_hud.open_editor()
		var editor := shell._test_hud.editor
		_check(editor.press("test:editor:tab:nodes"), "explicit editor keeps free navigation " + kind)
		picker = editor.map_picker
		_check(picker.press("test:map:node:" + str(other.key)) and picker._selected == other.key,
			"start restriction does not leak into the editor " + kind)
		_check(picker.press("test:map:enter") and str(session.get_test_view().run.current_node_id).ends_with("|" + str(other.key)),
			"explicit editor still enters another node " + kind)
		shell.queue_free()


func _check_free_map_navigation() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/free-map-saves"))
	session.test_service().store = TestStore.new(_root + "/free-map-room")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test") and shell.press("test:start"), "free map starts at the campus map")
	shell._test_hud.open_editor()
	var editor := shell._test_hud.editor
	_check(editor.press("test:editor:tab:resources") and editor.press("test:editor:field:player.focus:plus"), "draft exists before opening map")
	var state_hash := session.test_service().state.state_hash()
	_check(editor.press("test:editor:tab:nodes"), "nodes tab opens visual navigation")
	var picker: Variant = editor.get("map_picker")
	_check(picker != null and picker.visible, "visual map is visible")
	if picker == null:
		shell.queue_free()
		return
	var view := session.get_test_view()
	var target: Dictionary = {}
	for year in range(1, 5):
		_check(picker.press("test:map:year:%d" % year), "browse year %d" % year)
		for node in view.nodes.filter(func(entry): return entry.year == year):
			_check(node.has("column") and node.has("next_ids") and node.has("status"), "map exposes real topology " + str(node.key))
			_check(picker.press("test:map:node:" + str(node.key)), "arbitrary node can preview " + str(node.key))
			_check(session.test_service().state.state_hash() == state_hash, "preview preserves state/RNG " + str(node.key))
			if year == 4 and node.kind == "normal":
				target = node
	_check(picker.press("test:map:cancel"), "cancel visual navigation")
	_check(not picker.visible and editor.is_open() and editor.draft_count() == 1, "cancel preserves the editor and existing draft")
	_check(session.test_service().state.state_hash() == state_hash, "cancel leaves the experiment unchanged")
	_check(editor.press("test:editor:open_map"), "map can reopen from the nodes tab")
	_check(picker.press("test:map:year:4") and picker.press("test:map:node:" + str(target.key)), "select a later unreachable battle")
	var focus_before := int(view.battle.player.focus)
	var revision_before := int(view.test.revision)
	_check(picker.press("test:map:enter"), "confirm applies draft and enters target")
	view = session.get_test_view()
	_check(shell.page is BattleScreen and view.run.term == 4 and str(view.run.current_node_id).ends_with("|" + str(target.key)), "free map jumps to the selected location")
	_check(int(view.test.revision) == revision_before + 1 and not view.test.editing, "one confirmation produces one revision and unlocks the room")
	_check(not picker.press("test:map:enter") and int(session.get_test_view().test.revision) == revision_before + 1, "a repeated confirmation cannot submit twice")
	_check(session.step_test_history(shell._test_context(), "undo").accepted, "jump and merged draft can undo together")
	view = session.get_test_view()
	_check(view.run.term == 1 and view.run.current_node_id.is_empty() and int(view.battle.player.focus) == focus_before, "undo restores the map and prior resource value")
	shell.refresh()
	shell._test_hud.open_editor()
	editor = shell._test_hud.editor
	editor._set_draft("invalid", {"op": "set_player_field", "field": "unknown", "value": 1})
	state_hash = session.test_service().state.state_hash()
	editor.press("test:editor:tab:nodes")
	picker = editor.map_picker
	picker.press("test:map:year:4")
	picker.press("test:map:node:" + str(target.key))
	_check(picker.press("test:map:enter"), "failed jump attempt is submitted through normal patch validation")
	_check(editor.draft_count() == 2 and editor.status_text().contains("失败") and not picker.visible, "failed patch preserves resource and node drafts in editor")
	_check(session.test_service().state.state_hash() == state_hash, "failed jump leaves state and RNG unchanged")
	shell.queue_free()


func _check_same_room_map_jump() -> void:
	for kind in ["normal", "shop"]:
		var session := GameSession.new(SaveStore.new(_root + "/same-room-" + kind))
		var nodes := session.get_test_node_options("42")
		var initial: Dictionary = nodes.filter(func(node): return node.year == 1 and node.kind == kind)[0]
		_check(session.start_test_room({"character_id": "P01", "seed": "42", "node_key": initial.key}).accepted, "start same-type jump " + kind)
		var shell := GameShell.new()
		shell.session = session
		(Engine.get_main_loop() as SceneTree).root.add_child(shell)
		for year in [2, 4]:
			shell._test_hud.open_editor()
			var editor := shell._test_hud.editor
			editor.press("test:editor:tab:nodes")
			var picker: Variant = editor.map_picker
			var target: Dictionary = nodes.filter(func(node): return node.year == year and node.kind == kind)[0]
			picker.press("test:map:year:%d" % year)
			picker.press("test:map:node:" + str(target.key))
			_check(picker.press("test:map:enter"), "confirm same-type jump " + kind)
			var view := session.get_test_view()
			_check(int(view.run.term) == year and not view.test.editing and not shell._test_hud.is_editor_open(), "same-type jump closes editor " + kind)
			_check(shell.page.is_processing_input(), "same-type room accepts input " + kind)
		shell.queue_free()


func _enter_map_battle(shell: GameShell) -> bool:
	var view := shell.session.get_test_view()
	if view.get("run", {}).get("screen") != "map" or view.run.reachable_node_ids.is_empty():
		return false
	var node_id := str(view.run.reachable_node_ids[0])
	return shell.press("node:" + node_id) and shell.press("map:enter") and shell.page is BattleScreen


func _check_legacy_result() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/legacy-saves"))
	session.test_service().store = TestStore.new(_root + "/legacy-room")
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"legacy standalone fixture starts")
	var saved := session.save_test_snapshot("旧单场实验")
	_check(saved.ok, "legacy snapshot is saved")
	session.close_test_room()
	if not saved.ok:
		session.free()
		return
	var before := FileAccess.get_sha256(str(saved.data.path))
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test") and shell.press("test:load_snapshot:" + str(saved.data.id)),
		"old standalone snapshot loads through the unified home")
	_check(shell.page is BattleScreen and session.get_test_view().run.is_empty(), "legacy battle is restored as saved")
	_check(FileAccess.get_sha256(str(saved.data.path)) == before, "legacy load does not rewrite the file")
	_check(session.set_test_outcome(shell._test_context(), "won").accepted, "legacy result can be set")
	shell.refresh()
	_check(shell.page is TestRoomPage and shell.page.screen == "test_room_result", "legacy result screen stays supported")
	_check(shell.press("test:result:continue") and shell.page is BattleScreen, "legacy continue editing works")
	_check(shell._test_hud.press("test:save") and session.list_test_files("snapshot").size() == 1,
		"legacy save updates the same file")
	session.close_test_room()
	shell.queue_free()


func _check_snapshot_deletion() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/delete-saves"))
	var store := TestStore.new(_root + "/delete-room")
	session.test_service().store = store
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"create isolated experiment for snapshot UI")
	var first := session.save_test_snapshot("待删除的测试快照")
	session.close_test_room()
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"create a separate experiment for the retained snapshot")
	var second := session.save_test_snapshot("保留的测试快照")
	var preset := session.save_test_preset("保留的预设")
	var record := session.save_test_record("保留的记录")
	session.close_test_room()
	var first_id := str(first.data.id)
	var second_id := str(second.data.id)
	var second_hash := FileAccess.get_sha256(str(second.data.path))
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test"), "open snapshot management")
	_check(shell.press("test:character:P02"), "choose character before deletion")
	var delete_uid := "test:delete_snapshot:" + first_id
	_check(shell.page.button_uids().has(delete_uid), "each snapshot has a delete button")
	if not shell.page.button_uids().has(delete_uid):
		shell.queue_free()
		return
	_check(shell.press(delete_uid), "request selected snapshot deletion")
	_check(FileAccess.file_exists(str(first.data.path)), "request alone preserves snapshot")
	_check(not shell.press("test:start") and not shell.press("test:load_snapshot:" + second_id),
		"confirmation isolates underlying actions")
	_check(shell.page._buttons.has("test:delete_snapshot:cancel"), "confirmation offers cancel")
	_check(shell.press("test:delete_snapshot:cancel"), "cancel deletion")
	_check(FileAccess.file_exists(str(first.data.path)), "cancel preserves snapshot")
	_check((shell.page as TestRoomPage)._character_id == "P02", "cancel preserves setup configuration")
	_check(shell.press(delete_uid) and shell.press("test:delete_snapshot:confirm"), "confirm snapshot deletion")
	_check(not FileAccess.file_exists(str(first.data.path)), "confirmation deletes the selected file")
	_check(not shell.page.button_uids().has(delete_uid), "successful deletion refreshes list")
	_check(shell.last_error == null and shell.notice.contains("已删除"), "success has clear feedback")
	_check(shell._ui_feedback.visible and shell._ui_feedback.text.contains("已删除"), "success feedback is visible on screen")
	_check(FileAccess.get_sha256(str(second.data.path)) == second_hash, "other snapshot bytes are unchanged")
	_check(FileAccess.file_exists(str(preset.data.path)) and FileAccess.file_exists(str(record.data.path)),
		"deletion preserves presets and records")
	# A stale list must report the missing file rather than show a success toast.
	_check(shell.press("test:delete_snapshot:" + second_id), "open second snapshot confirmation")
	_check(store.remove("snapshot", second_id).ok, "simulate file removed while confirmation is open")
	_check(shell.press("test:delete_snapshot:confirm"), "confirm stale snapshot")
	_check(shell.last_error != null and shell.last_error.code == GameConstants.ERROR_SAVE_NOT_FOUND,
		"stale confirmation reports missing snapshot")
	_check(shell.notice.contains("不存在") and not shell.notice.contains("已删除"), "missing feedback is understandable")
	# Replace a listed file with a directory to exercise a real filesystem failure.
	var failure_file := store.save("snapshot", "blocked", "删除失败用例", {})
	shell.refresh()
	_check(shell.press("test:delete_snapshot:blocked"), "confirm an existing snapshot before IO failure")
	DirAccess.remove_absolute(str(failure_file.data.path))
	DirAccess.make_dir_recursive_absolute(str(failure_file.data.path))
	_check(shell.press("test:delete_snapshot:confirm"), "submit deletion with filesystem obstruction")
	_check(shell.last_error != null and shell.last_error.code == GameConstants.ERROR_TEST_IO_ERROR,
		"UI reports actual filesystem deletion failure")
	_check(shell.notice.contains("删除失败"), "IO failure has explicit Chinese feedback")
	_check(shell._ui_feedback.visible and shell._ui_feedback.text.contains("删除失败"), "failure feedback is visible on screen")
	_check(not session.has_test_room(), "snapshot management never starts an experiment")
	# Remaining valid snapshots still use the original load path.
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"create remaining loadable snapshot")
	var remaining := session.save_test_snapshot("仍可载入")
	session.close_test_room()
	shell.refresh()
	_check(shell.press("test:load_snapshot:" + str(remaining.data.id)) and session.has_test_room(),
		"remaining snapshot still loads through the real UI")
	session.close_test_room()
	shell.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)




func _check_campus_editor() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/campus-saves"))
	session.test_service().store = TestStore.new(_root + "/campus-room")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test"), "open the test setup from main menu")
	var target_shop: Dictionary = session.get_test_node_options("42").filter(func(node): return node.year == 4 and node.kind == "shop")[0]
	if not _select_home_node(shell, target_shop):
		shell.queue_free()
		return
	_check(shell.press("test:start"), "locate year four shop from setup")
	_check(shell.page is UiExperiencePage and shell.page.screen == "map", "selected start previews its map before entering")
	if not (shell.page is UiExperiencePage and shell.page.screen == "map"):
		shell.queue_free()
		return
	var picker: Variant = shell._test_hud.editor.get("map_picker")
	_check(picker != null and picker.visible, "selected start opens the visual node picker")
	if picker == null:
		shell.queue_free()
		return
	_check(picker.press("test:map:enter"), "confirm located shop on the map")
	_check(shell.page is UiExperiencePage and shell.page.screen == "shop", "the real shop page is rendered")
	for index in 3:
		_check(shell._test_hud.press("test:save"), "campus HUD consecutive save %d" % index)
	_check(session.list_test_files("snapshot").size() == 1, "campus HUD saves reuse one snapshot")
	_check(shell.page.button_uids().any(func(uid): return str(uid).begins_with("shop:")), "shop actions are interactive")
	if shell._test_hud == null:
		shell.queue_free()
		return
	var hud: TestHud = shell._test_hud
	_check(hud.press("test:open_editor"), "campus HUD opens the test editor")
	var panel: TestEditorPanel = hud.editor
	_check(panel.press("test:editor:tab:nodes"), "nodes tab is available")
	picker = panel.get("map_picker")
	_check(picker != null and picker.visible, "nodes tab opens the map picker")
	if picker == null:
		shell.queue_free()
		return
	_check(picker.press("test:map:year:1"), "map switches to year one")
	var target: Dictionary = session.get_test_view().nodes.filter(func(node): return node.year == 1 and node.kind == "normal")[0]
	_check(picker.press("test:map:node:" + str(target.key)), "map node previews the jump")
	_check(picker.press("test:map:enter"), "map confirms the jump")
	_check(shell.page is BattleScreen and session.get_test_view().run.term == 1, "jump renders the selected year's battle")
	_check(not session.get_test_view().test.editing, "new room is immediately interactive")
	_check(shell._test_hud.press("test:open_editor"), "battle editor can open after jumping")
	panel = shell._test_hud.editor
	_check(panel.press("test:editor:tab:character") and panel.press("test:editor:character:P04"), "P04 is selected through the editor")
	_check(panel.press("test:editor:apply") and session.get_test_view().battle.character_info.character_id == "P04", "new character is active in battle")
	_check(session.test_service().state.run.cards.any(func(card): return card.definition_id == "R3-P04-01")
		and not session.test_service().state.battle.card_by_id.values().any(func(card): return str(card.definition_id).begins_with("R3-P01-")),
		"editor default switch replaces old exclusive hand and permanent deck")
	var mixed_before := session.test_service().state.core_snapshot()
	_check(panel.press("test:editor:character:keep_deck") and panel.press("test:editor:character:P03")
		and panel.press("test:editor:apply"), "editor explicitly keeps a mixed deck when checked")
	_check(session.test_service().state.battle.zones == mixed_before.battle.zones
		and session.test_service().state.run.cards == mixed_before.run.cards,
		"mixed mode preserves current hand and permanent deck")
	_check(panel.press("test:editor:character:keep_deck") and panel.press("test:editor:character:P04")
		and panel.press("test:editor:apply"), "unchecking mixed mode restores synchronized replacement")
	_check(panel.press("test:editor:tab:cards"), "open the hand editor")
	var hand: Array = session.get_test_view().battle.hand
	if hand.size() >= 2:
		var first := str(hand[0].card_id)
		var second := str(hand[1].card_id)
		_check(panel.press("test:editor:order:%s:later" % first), "hand order is edited through the card row")
		_check(panel.press("test:editor:apply"), "hand order draft applies")
		_check(session.get_test_view().battle.hand[0].card_id == second, "display and battle hand order changed")
		var raw := panel.find_child("RawCardId", true, false) as LineEdit
		if raw != null:
			raw.text = "R3-P02-18"
			_check(panel.press("test:editor:rawcard:hand") and panel.press("test:editor:apply"), "any catalog card can be added to the hand")
			_check(session.get_test_view().battle.hand.any(func(card): return card.definition_id == "R3-P02-18"), "added card appears in actual hand")
		_check(panel.press("test:editor:card:%s:discard" % second) and panel.press("test:editor:apply"), "hand card moves directly to discard")
		_check(session.get_test_view().battle.zones_public.discard.any(func(card): return card.card_id == second), "moved card is in discard")
	_check(panel.press("test:editor:tab:enemies"), "open enemy editor")
	var enemy_search := panel.button_uids().filter(func(uid): return str(uid).begins_with("test:editor:encounter:N02:"))
	if enemy_search.is_empty():
		panel.set_search("N02")
		enemy_search = panel.button_uids().filter(func(uid): return str(uid).begins_with("test:editor:encounter:N02:"))
	_check(not enemy_search.is_empty(), "enemy N02 is selectable")
	if not enemy_search.is_empty():
		_check(panel.press(enemy_search[0]) and panel.press("test:editor:apply"), "enemy replacement is submitted")
		_check(session.get_test_view().battle.tasks.size() == 1 and session.get_test_view().battle.tasks[0].definition_id == "N02", "real task roster is replaced")
	_check(panel.press("test:editor:tab:statuses"), "open status editor")
	var status_buttons := panel.button_uids().filter(func(uid): return str(uid).begins_with("test:editor:addstatus:"))
	_check(not status_buttons.is_empty(), "status selector is populated")
	if not status_buttons.is_empty():
		var status_count: int = session.test_service().state.battle.statuses.size()
		_check(panel.press(status_buttons[0]) and panel.press("test:editor:apply"), "status is submitted")
		_check(session.test_service().state.battle.statuses.size() > status_count, "status is applied to actual battle state")
	session.close_test_room()
	shell.queue_free()


func _check_default_battle_costs(reload_snapshot: bool = false) -> void:
	var session := GameSession.new(SaveStore.new(_root + "/default-cost-saves"))
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	var opened := shell.press("menu:test") and shell.press("test:start") and _enter_map_battle(shell)
	_check(opened, "default campus map enters its reachable opening battle")
	if opened and reload_snapshot:
		shell._handle_test_command("test.save_and_exit", {})
		_check(not session.has_test_room(), "save opening battle and return to menu")
		var snapshots := session.list_test_files("snapshot")
		_check(not snapshots.is_empty(), "saved opening battle is listed")
		if not snapshots.is_empty():
			var snapshot_id := str(snapshots[0].id)
			var stored := session.test_service().store.load_file("snapshot", snapshot_id)
			var hash_before := FileAccess.get_sha256(str(stored.data.path))
			shell._handle_test_command("test.load_snapshot", {"id": snapshot_id})
			opened = session.has_test_room() and shell.page is BattleScreen
			_check(opened, "reload saved opening battle through UI")
			_check(FileAccess.get_sha256(str(stored.data.path)) == hash_before, "loading preserves existing snapshot bytes")
	if opened:
		var view := session.get_test_view()
		var card_id := ""
		for entry in view.battle.hand:
			if entry.definition_id == "R3-C-02": # Stretch, a 1-focus card in the default opening hand.
				card_id = str(entry.card_id)
				break
		_check(not card_id.is_empty(), "default opening hand contains Stretch")
		if not card_id.is_empty():
			var card := (shell.page as BattleScreen)._hand_card_control(card_id) as BattleCard
			var shown := int(CardDisplayModel.from_card(card.card_data).cost) if card != null else -1
			_check(shown == 1, "Stretch shows 1 focus, got %d" % shown)
			var focus_before := int(view.battle.player.focus)
			_check(shell.press("card:" + card_id), "Stretch can be played from the hand")
			var after := session.get_test_view()
			var focus_after := int(after.battle.player.focus)
			_check(int(after.test.revision) == int(view.test.revision) + 1, "Stretch is submitted once")
			_check(focus_after == focus_before - 1, "Stretch pays 1 focus, got %d -> %d" % [focus_before, focus_after])
			print("Default test battle: R3-C-02, shown cost %d, focus %d -> %d" % [shown, focus_before, focus_after])
		session.close_test_room()
	shell.queue_free()


func _check_default_end_turn() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/default-turn-saves"))
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	var opened := shell.press("menu:test") and shell.press("test:start") and _enter_map_battle(shell)
	_check(opened, "untouched test-room setup opens the map then its first battle")
	if opened:
		var before := session.get_test_view()
		var active_switches: Array = before.switches.keys().filter(func(key): return before.switches[key])
		_check(active_switches.is_empty(), "default test battle has no debug overrides: %s" % [active_switches])
		_check(before.battle.hand.size() == 5, "the default encounter starts with five cards")
		var service := session.test_service()
		var formal := BattleEngine.new(service.base_catalog).apply(
			service.state.battle, ActionDraft.new(&"end_turn", {}), service.state.rng
		)
		_check(shell.press("battle:end_turn"), "end play from the opening hand")
		var after := session.get_test_view()
		_check(formal.ok, "the formal engine can resolve the same turn")
		if formal.ok:
			var expected: BattleStep = formal.data
			_check(service.state.battle.to_dictionary() == expected.state.to_dictionary(),
				"the default test turn matches formal combat state")
			_check(service.state.rng == expected.rng_state, "the default test turn matches formal RNG")
		var discard: Array = after.battle.zones_public.discard.map(func(card): return card.card_id)
		var discarded: Array = before.battle.hand.filter(func(card): return discard.has(card.card_id))
		_check(int(after.battle.round_index) == 2, "end play advances one turn")
		_check(discarded.size() == 5, "end play discards all five unplayed cards, got %d" % discarded.size())
		_check(after.battle.hand.size() == 5, "the next round has five cards, got %d" % after.battle.hand.size())
		print("Default test room round %s -> %s, hand %d -> %d, old cards discarded %d, active switches %s" % [
			before.battle.round_index, after.battle.round_index, before.battle.hand.size(),
			after.battle.hand.size(), discarded.size(), active_switches,
		])
		session.close_test_room()
	shell.queue_free()


func _check_map_abandon() -> void:
	var save_root := _root + "/abandon-saves"
	var session := GameSession.new(SaveStore.new(save_root))
	session.test_service().store = TestStore.new(_root + "/abandon-room")
	_check(session.update_settings({"autosave": false}).ok, "abandon fixture disables autosave")
	_check(session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42")).accepted,
		"abandon fixture starts a formal run")
	_check(session.save_current().ok, "abandon fixture saves the formal run")
	var formal := session.get_view()
	var formal_run: Dictionary = formal.run.duplicate(true)
	var completed_run_ids: Array = session.get_profile().completed_run_ids.duplicate()
	var save_hash := FileAccess.get_sha256(save_root + "/current_run.json")
	var profile_hash := FileAccess.get_sha256(save_root + "/profile.json")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test") and shell.press("test:start"), "abandon starts from the test campus map")
	var saved := session.save_test_snapshot("放弃前快照")
	_check(saved.ok, "save a snapshot before abandoning")
	var snapshot_path := str(saved.data.path)
	var snapshot_hash := FileAccess.get_sha256(snapshot_path)
	var state_hash := session.test_service().state.state_hash()
	_check(not shell._test_preview({"type": "abandon_run", "payload": {}}).can_submit,
		"test abandon requires explicit confirmation")
	shell.submit_action({"type": "abandon_run", "payload": {}})
	_check(session.has_test_room() and session.test_service().state.state_hash() == state_hash,
		"unconfirmed abandon leaves the experiment unchanged")
	_check(shell.press("map:abandon"), "test map opens abandon confirmation")
	_check(session.has_test_room() and session.test_service().state.state_hash() == state_hash,
		"opening confirmation preserves the experiment and RNG")
	_check(shell.page.button_uids().has("map:abandon_confirm"), "test map exposes the confirmation button")
	_check(shell.press("map:abandon"), "test map can cancel abandon confirmation")
	_check(not shell.page.button_uids().has("map:abandon_confirm")
		and session.test_service().state.state_hash() == state_hash, "cancel keeps the experiment unchanged")
	_check(shell.press("map:abandon"), "test map reopens abandon confirmation")
	_check(shell.press("map:abandon_confirm"), "test map confirmation is enabled and submits")
	_check(not session.has_test_room() and shell._test_hud == null and shell.page.screen == "menu",
		"confirmed abandon closes the test context and HUD and returns to the menu")
	_check(session.get_view().run_id == formal.run_id and session.get_view().revision == formal.revision
		and session.get_view().run == formal_run and session.get_view().terminal_summary == null,
		"test abandon preserves the active formal run")
	_check(session.get_profile().completed_run_ids == completed_run_ids
		and FileAccess.get_sha256(save_root + "/current_run.json") == save_hash
		and FileAccess.get_sha256(save_root + "/profile.json") == profile_hash,
		"test abandon preserves profile and formal save bytes")
	_check(session.list_test_files("snapshot").size() == 1
		and FileAccess.get_sha256(snapshot_path) == snapshot_hash, "test abandon keeps saved snapshots")
	# Clean up a failed exit so normal-run coverage can report independently.
	if session.has_test_room():
		var cleanup_hash := session.test_service().state.state_hash()
		shell.submit_action({"type": "test.close", "payload": {}})
		_confirm_test_discard(shell, cleanup_hash)
	_check(shell.press("menu:test") and shell.press("test:start"), "test room can start again after abandoning")
	var exit_hash := session.test_service().state.state_hash()
	_check(shell._test_hud.press("test:close"), "the existing HUD exit still works")
	_confirm_test_discard(shell, exit_hash)
	_check(shell.press("menu:continue") and shell.page.screen == "map", "continue restores the formal map")
	_check(shell.press("map:abandon") and session.get_view().terminal_summary == null,
		"normal map abandon still asks for confirmation")
	_check(shell.press("map:abandon_confirm") and session.get_view().terminal_summary is Dictionary,
		"normal map confirmed abandon still settles the formal run")
	if session.get_view().terminal_summary is Dictionary:
		_check(session.get_view().terminal_summary.result == "abandoned", "normal abandon retains its outcome")
	shell.queue_free()


func _check_map_controls() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/route-saves"))
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	_check(shell.press("menu:test"), "open the test setup for the route flow")
	var target: Dictionary = session.get_test_node_options("42").filter(func(node): return node.year == 1 and node.kind == "normal")[0]
	if not _select_home_node(shell, target):
		shell.queue_free()
		return
	_check(shell.press("test:start") and shell.page is UiExperiencePage and shell.page.screen == "map", "selected battle first opens its map")
	var picker: Variant = shell._test_hud.editor.get("map_picker")
	if picker != null:
		_check(picker.press("test:map:enter"), "selected map battle is confirmed through the map")
	if not (shell.page is BattleScreen):
		_check(false, "map confirmation enters the selected battle")
		shell.queue_free()
		return
	var won := session.set_test_outcome(shell._test_context(), "won")
	_check(won.accepted, "winning the map battle leaves a reward to resolve")
	shell.refresh()
	var view := session.get_test_view()
	if view.run.screen == "reward":
		for item in view.run.pending_reward.items:
			if item.status != "pending":
				continue
			var prefix := "reward:%s" % item.item_id
			_check(shell.press(prefix + ":skip"), "reward UI opens skip confirmation")
			_check(shell.press(prefix + ":skip_confirm"), "reward UI confirms the skip")
	view = session.get_test_view()
	_check(view.run.screen == "map" and not view.run.reachable_node_ids.is_empty(),
		"reward UI automatically completes the current node and refreshes the map")
	if not view.run.reachable_node_ids.is_empty():
		var next := str(view.run.reachable_node_ids[0])
		_check(shell.press("node:" + next), "next node can be selected on the map")
		_check(shell.press("map:enter"), "the normal map confirmation enters the node")
		_check(session.get_test_view().run.current_node_id == next, "route follows the selected connection")
	var exit_hash := session.test_service().state.state_hash()
	shell.submit_action({"type": "test.close", "payload": {}})
	_confirm_test_discard(shell, exit_hash)
	shell.queue_free()


func _confirm_test_discard(shell: GameShell, previous_hash: String) -> void:
	_check(shell.session.has_test_room() and is_instance_valid(shell._test_exit_dialog),
		"ordinary test exit asks for explicit save/discard/cancel")
	if not shell.session.has_test_room() or not is_instance_valid(shell._test_exit_dialog):
		return
	_check(shell.session.test_service().state.state_hash() == previous_hash,
		"opening exit confirmation preserves the experiment")
	shell._test_exit_dialog.custom_action.emit(&"discard")
	_check(not shell.session.has_test_room() and shell._test_hud == null and shell.page.screen == "menu",
		"explicit discard closes the experiment and returns to menu")
