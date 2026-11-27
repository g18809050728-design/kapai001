extends RefCounted

## First-run tutorial checks: the overlay appears on a fresh run, explains the
## real resources in order, anchors to the map and battle controls, survives a
## resize, can be skipped, and never leaks into a later run by itself.

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _tree: SceneTree
var _previous_path := ""
var _override_path := ""


func run() -> Array[String]:
	_tree = Engine.get_main_loop() as SceneTree
	var old_size := _tree.root.size
	_previous_path = TextOverrides.current_path()
	_override_path = "user://tutorial-text-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path))
	TextOverrides.use_path(_override_path)
	UiStyle.text_scale = 1.0
	UiStyle.web_touch = false
	_tree.root.size = Vector2i(1280, 800)
	await _test_intro_then_battle()
	await _test_skip_all()
	await _test_replay_from_menu()
	await _test_external_action_dismisses()
	await _test_activation_scope()
	_tree.root.size = old_size
	UiStyle.text_scale = 1.0
	TextOverrides.use_path(_previous_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path))
	return _failures


func _start(path: String, online: bool = true) -> GameShell:
	var shell := _helpers.attach_shell(_helpers.fixture_session(path)) as GameShell
	shell.web_first_play_tutorial = online
	shell.session.update_settings({"autosave": false})
	_check(shell.press("menu:new"), "menu opens new-run setup")
	_check(shell.press("setup:character:test_P01"), "fixture character is available")
	_check(shell.press("setup:start"), "setup starts the fixture run")
	return shell


func _test_intro_then_battle() -> void:
	var shell := _start("user://tutorial-intro-%d" % Time.get_ticks_usec())
	_check(shell.tutorial_visible(), "a new run opens the tutorial immediately")
	var state := shell.tutorial_state()
	_check(int(state.get("step", 0)) == 1 and int(state.get("count", 0)) == 3, "intro starts at step 1 / 3")
	_check(str(state.get("mode", "")) == "intro", "first layer is the intro")
	_check(shell._tutorial._body_label.text.is_empty() and not shell._tutorial._body_label.visible, "bundled empty intro body stays hidden on first play")
	var text := _text_of(shell._tutorial)
	for required in ["基础数值", "精力", "金钱", "DDL", "失败"]:
		_check(text.contains(required), "intro 1 explains " + required)
	_check(shell._tutorial.mouse_filter == Control.MOUSE_FILTER_STOP, "tutorial blocks pointer input to the page")
	_check(shell._tutorial.get_global_rect().size == Vector2(_tree.root.size), "tutorial covers the viewport")
	var map_point: Rect2 = shell.page.tutorial_anchor("map_node")
	if map_point.has_area():
		var revision_before := shell.session.get_view().revision
		_mouse_click(map_point.get_center())
		await _frames(3)
		_check(
			shell.tutorial_visible() and shell.session.get_view().revision == revision_before,
			"real pointer on the page stays blocked while the tutorial is open"
		)
	_key(KEY_M)
	await _frames(3)
	_check(
		shell.tutorial_visible() and not shell.page._map_overview,
		"page keyboard shortcuts stay blocked while the tutorial is open"
	)
	_tree.root.size = Vector2i(960, 600)
	await _frames(6)
	var panel_rect := shell._tutorial._panel.get_global_rect()
	_check(
		Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(panel_rect),
		"tutorial panel fits the compact viewport"
	)
	_tree.root.size = Vector2i(1280, 800)
	await _frames(6)

	await _frames(8)
	_check(shell.press("tutorial:next"), "next advances the intro")
	state = shell.tutorial_state()
	_check(int(state.get("step", 0)) == 2, "intro step 2 is active")
	_check(str(state.get("title", "")).contains("地图"), "map step explains the route")
	await _frames(8)
	var highlight: Rect2 = shell._tutorial.highlight_rect()
	_check(highlight.has_area(), "map step highlights a real reachable node")
	_check(
		shell._tutorial.get_global_rect().encloses(highlight),
		"map highlight stays inside the tutorial viewport"
	)
	_check(shell.press("tutorial:prev"), "previous returns to step 1")
	_check(int(shell.tutorial_state().get("step", 0)) == 1, "previous restores step 1")
	_check(shell.press("tutorial:next") and shell.press("tutorial:next"), "advance to the battle preparation step")
	text = _text_of(shell._tutorial)
	for required in ["5 张", "3 点专注", "上限 10", "1—9", "结束回合"]:
		_check(text.contains(required), "battle preparation explains " + required)
	_check(shell.press("tutorial:next"), "last intro page finishes the tutorial")
	_check(not shell.tutorial_visible(), "intro closes after its last page")
	_check(shell._tutorial_intro_done, "intro completion is remembered")

	var reachable: Array = shell.session.get_view().run.reachable_node_ids
	_check(not reachable.is_empty(), "fixture run has a reachable battle")
	_check(_helpers.enter_node(shell, str(reachable[0])), "first node opens the real battle")
	await _frames(10)
	_check(shell.tutorial_visible(), "the first battle continues the tutorial on the real UI")
	state = shell.tutorial_state()
	_check(str(state.get("mode", "")) == "battle" and int(state.get("step", 0)) == 1, "battle tutorial starts at step 1 / 3")
	_check(shell.page is BattleScreen, "battle page stays rendered under the tutorial")
	await _frames(8)
	highlight = shell._tutorial.highlight_rect()
	_check(highlight.has_area(), "battle step 1 highlights task intent and values")
	var text_1 := _text_of(shell._tutorial)
	for required in ["意图", "屏障", "完成量", "DDL", "精力"]:
		_check(text_1.contains(required), "battle step 1 explains " + required)

	_check(shell.press("tutorial:next"), "next advances the battle tutorial")
	await _frames(8)
	state = shell.tutorial_state()
	_check(int(state.get("step", 0)) == 2 and str(state.get("title", "")).contains("专注"), "battle step 2 explains focus")
	highlight = shell._tutorial.highlight_rect()
	_check(highlight.has_area(), "focus step highlights the focus device")
	var focus_device: Variant = shell._tutorial._buttons.get("tutorial:next")
	var focus_owner := _tree.root.gui_get_focus_owner()
	_check(
		is_instance_valid(focus_device)
		and is_instance_valid(focus_owner)
		and shell._tutorial.is_ancestor_of(focus_owner),
		"tutorial keeps keyboard focus on its own controls"
	)

	_check(shell.press("tutorial:next"), "next advances to card play")
	state = shell.tutorial_state()
	_check(int(state.get("step", 0)) == 3 and str(state.get("title", "")).contains("结束回合"), "battle step 3 explains playing cards and ending the turn")
	await _frames(8)
	highlight = shell._tutorial.highlight_rect()
	_check(highlight.has_area(), "end-turn step highlights the real end-turn button")
	_check(shell.press("tutorial:next"), "last battle page closes the tutorial")
	_check(not shell.tutorial_visible(), "battle tutorial closes after its last page")
	_check(shell._tutorial_battle_done, "battle tutorial completion is remembered")
	_check(shell.page.button_uids().has("battle:end_turn"), "battle controls remain available after the tutorial")

	var revision := shell.session.get_view().revision
	_check(shell.press("battle:end_turn"), "end turn works after the tutorial")
	_check(shell.session.get_view().revision > revision, "the battle accepts a real command after teaching")
	shell.free()


func _test_skip_all() -> void:
	var shell := _start("user://tutorial-skip-%d" % Time.get_ticks_usec())
	_check(shell.tutorial_visible(), "skip test starts with the tutorial")
	_check(shell.press("tutorial:skip"), "skip button is reachable")
	_check(not shell.tutorial_visible(), "skip closes the overlay")
	_check(shell._tutorial_intro_done and shell._tutorial_battle_done, "skip suppresses the later battle lesson")
	var reachable: Array = shell.session.get_view().run.reachable_node_ids
	_check(_helpers.enter_node(shell, str(reachable[0])), "skip test still enters a battle")
	await _frames(10)
	_check(not shell.tutorial_visible(), "skipped tutorial does not reopen in battle")
	shell.free()


func _test_replay_from_menu() -> void:
	var shell := _start("user://tutorial-replay-%d" % Time.get_ticks_usec())
	_check(shell.press("tutorial:skip"), "replay test skips the first lesson")
	_check(shell.press("map:menu"), "map returns to the menu")
	_check(shell.press("menu:tutorial"), "menu exposes the tutorial again")
	await _frames(2)
	_check(shell.tutorial_visible(), "menu tutorial opens a replay")
	var state := shell.tutorial_state()
	_check(bool(state.get("replay", false)), "replay is marked read-only for progress")
	_check(str(state.get("mode", "")) == "intro", "replay starts from the intro")
	for _index in 3:
		shell.press("tutorial:next")
	_check(not shell.tutorial_visible(), "replay can be finished")
	_check(shell._tutorial_intro_done and shell._tutorial_battle_done, "replay does not change tutorial progress")
	shell.free()


func _test_external_action_dismisses() -> void:
	var shell := _start("user://tutorial-external-%d" % Time.get_ticks_usec())
	_check(shell.tutorial_visible(), "external-action test starts with the tutorial")
	var reachable: Array = shell.session.get_view().run.reachable_node_ids
	var node_id := str(reachable[0])
	_check(shell.press("node:" + node_id), "programmatic node press still reaches the page")
	_check(not shell.tutorial_visible(), "an external page action dismisses the tutorial")
	_check(shell.press("map:enter"), "the map enters the selected node")
	await _frames(10)
	_check(not shell.tutorial_visible(), "dismissed tutorial does not reopen in battle")
	shell.free()


func _test_activation_scope() -> void:
	var local := _start("user://tutorial-local-%d" % Time.get_ticks_usec(), false)
	_check(not local.tutorial_visible(), "local play does not auto-open the lesson")
	_check(local.session.get_profile().tutorial_flags.is_empty(), "local play does not claim the online tutorial")
	local.queue_free()
	await _frames(1)
	var path := "user://tutorial-once-%d" % Time.get_ticks_usec()
	var first := _start(path)
	_check(first.tutorial_visible(), "online first play opens the lesson")
	_check(bool(first.session.get_profile().tutorial_flags.get(GameSession.FIRST_PLAY_TUTORIAL)), "first play persists the existing profile flag even without autosave")
	first.queue_free()
	await _frames(1)
	var returning := _start(path)
	_check(not returning.tutorial_visible(), "a new shell and unsaved previous run still do not replay the lesson")
	returning.queue_free()
	await _frames(1)
	var old_path := "user://tutorial-old-save-%d" % Time.get_ticks_usec()
	var existing := _start(old_path, false)
	_check(existing.session.save_current().ok, "existing run fixture has a real save")
	_check(not existing.session.qualifies_for_first_play_tutorial(), "an active existing run is not first play")
	var stored := _helpers.fixture_session(old_path) as GameSession
	_check(not stored.qualifies_for_first_play_tutorial(), "a returning player with a save but without a tutorial flag is not first play")
	stored.free()
	existing.queue_free()
	await _frames(1)


func _text_of(node: Node) -> String:
	var text := ""
	if node == null:
		return text
	for label in node.find_children("*", "Label", true, false):
		text += str(label.text) + "\n"
	return text


func _frames(count: int) -> void:
	for _index in count:
		await _tree.process_frame


func _mouse_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	_tree.root.push_input(event, true)
	event = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	_tree.root.push_input(event, true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_tree.root.push_input(event, true)
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	_tree.root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("tutorial: " + message)
