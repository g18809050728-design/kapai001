extends RefCounted

## Test-room UI suite: menu entry, home, battle HUD, result page, close.

var _failures: Array[String] = []
var _root: String = ""


func run() -> Array[String]:
	_root = "user://test-room-ui-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
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
		_check(shell.press("test:character:P02"), "character selection works")
		_check(shell.press("test:start"), "start submits the test configuration")
	_check(session.has_test_room(), "test context starts")
	_check(shell.page is BattleScreen, "test battle uses the battle screen")
	_check(shell._test_hud != null, "battle HUD exists")
	_check(shell.page.button_uids().has("battle:end_turn"), "battle controls are available")
	var hud: TestHud = shell._test_hud
	_check(hud.press("test:open_editor"), "editor opens from the HUD")
	var panel: TestEditorPanel = hud.editor
	_check(panel.is_open(), "editor panel is open")
	_check(bool(session.get_test_view().test.editing), "service enters editing mode")
	_check(panel.press("test:editor:tab:resources"), "editor switches to the resources tab")
	_check(not panel.press("test:editor:apply"), "apply is disabled without a draft")
	var focus_before := int(session.get_test_view().battle.player.focus)
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
	_check(int(view.test.revision) == 1, "patch increments revision")
	_check(panel.draft_count() == 0, "draft clears after apply")
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
	_check(shell.page is TestRoomPage, "result uses the test room page")
	if shell.page is TestRoomPage:
		_check((shell.page as TestRoomPage).screen == "test_room_result", "result screen")
		_check(shell.page.button_uids().has("test:result:continue"), "continue button exists")
		_check(shell.press("test:result:continue"), "continue clears the manual outcome")
	_check(shell.page is BattleScreen, "continue returns to the battle")
	shell.submit_action({"type": "test.close", "payload": {}})
	_check(not session.has_test_room(), "close clears the test context")
	_check(shell.press("menu:new"), "formal menu still works after test room")
	_check(shell.page is not TestRoomPage, "formal pages are restored")
	shell.queue_free()
	return _failures


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


