extends RefCounted

class QuitCaptureShell:
	extends GameShell
	var exits: Array[bool] = []
	func _finish_quit(save: bool) -> void:
		if not save or _handle_save(session.save_current()):
			exits.append(save)

var _failures: Array[String] = []
var _checks := 0
var _sections: Array[String] = []

func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var helpers = load("res://tests/suites/test_ui_shell_pages.gd").new()
	var root := "user://account-navigation-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var session: GameSession = helpers.fixture_session(root)
	var shell := QuitCaptureShell.new()
	shell.session = session
	tree.root.add_child(shell)
	shell.web_section_requested.connect(func(section: String): _sections.append(section))
	for state in ["guest", "ready"]:
		shell.set_web_account_state(state, true, "测试玩家", "", "player")
		_check(shell.page._buttons.has("menu:identity"), "identity has a separate control")
		_check(not shell.page._buttons.has("menu:account"), "account removed from main options")
		_check(shell.page._buttons.has("menu:quit"), "quit game is a main option")
		_check(not shell.page._buttons.has("menu:admin"), "no management entry for " + state)
		_check(shell.press("menu:records") and shell.page.view.records.is_empty(), "history starts without device records for " + state)
		_check(shell.press("records:back"), "records return to menu")
		shell.submit_action({"type": "ui.web_stats"})
		_check(_sections.is_empty(), "ordinary identities cannot request statistics")
		shell.press("menu:settings")
		_check(shell.page._buttons.has("settings:cloud") == (state == "ready"), "cloud saves live in settings for signed in accounts")
		shell.press("settings:back")
	shell.set_web_account_state("ready", true, "管理员", "", "admin")
	_check(shell.press("menu:admin") and _sections == ["stats"], "administrator has a direct statistics entry")
	_sections.clear()
	_check(not session.has_unsaved_progress(), "empty session is clean")
	shell.press("menu:quit")
	_check(shell.exits == [false], "clean exit is immediate")
	shell.exits.clear()
	var started := session.start_run(StartRunRequest.new("test_P01", &"normal", "test_run_g4", "42"))
	_check(started.accepted, "real fixture run starts")
	_check(not session.has_unsaved_progress(), "saved run is clean")
	session.update_settings({"autosave": false})
	var view := session.get_view()
	var node_id := str(view.run.nodes[0].node_id)
	var action := session.submit(CommandContext.new(str(view.run_id), view.revision), GameAction.new(&"enter_node", {"node_id": node_id}))
	_check(action.accepted and session.has_unsaved_progress(), "unsaved gameplay is detected")
	shell.show_screen("menu")
	var before := helpers.fingerprint(session) as String
	shell.press("menu:quit")
	_check(is_instance_valid(shell._quit_dialog) and shell.exits.is_empty(), "dirty exit asks once")
	shell._quit_dialog.canceled.emit()
	_check(helpers.fingerprint(session) == before and session.has_unsaved_progress(), "cancel preserves gameplay and disk difference")
	await tree.process_frame
	session._store.debug_hooks = {"current_run": {"fail_write": true}}
	shell.press("menu:quit")
	shell._quit_dialog.confirmed.emit()
	_check(shell.exits.is_empty() and session.get_view().run_id != null, "save failure prevents exit")
	await tree.process_frame
	session._store.debug_hooks = {}
	_check(session.save_current().ok and not session.has_unsaved_progress(), "manual save clears dirty state")
	var summary := RunSummary.new({"run_id": "history-fixture", "result": "won", "reason": "completed", "character_id": "P01", "manifest_id": "test_run_g4", "term": 4})
	var merged := ProfileMerge.merge(ProfileMerge.default_profile(), summary)
	var encoded := SnapshotCodec.encode_document("profile", merged.data)
	_check(session._store.save("profile", encoded.data).ok, "isolated completed record saved")
	before = helpers.fingerprint(session)
	for state in ["ready", "guest"]:
		shell.set_web_account_state(state, true, "玩家", "", "player")
		shell.show_screen("menu")
		_check(shell.press("menu:records") and shell.page.view.records.is_empty(), "device records never leak to " + state)
	shell.set_web_account_state("", false, "", "")
	shell.show_screen("menu")
	_check(shell.press("menu:records") and shell.page.view.records.size() == 1, "legacy device summaries remain available locally")
	_check(helpers.fingerprint(session) == before, "records do not alter gameplay or random state")
	var rows := session.get_game_records()
	rows.data[0].reason = "changed outside session"
	_check(session.get_game_records().data[0].reason == "completed", "records are copies")
	shell.set_web_account_state("ready", true, "玩家", "", "player")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [1.0, 1.25, 1.5]:
			UiStyle.text_scale = scale
			shell.show_screen("menu")
			for _frame in 3:
				await tree.process_frame
			var rect: Rect2 = shell.page._buttons["menu:identity"].get_global_rect()
			_check(rect.position.x > dimensions.x * .5 and rect.end.x <= dimensions.x and rect.size.y >= 44, "identity remains at upper right with usable target")
	UiStyle.text_scale = 1.0
	tree.root.size = Vector2i(1280, 800)
	shell.queue_free()
	await tree.process_frame
	print("UI_ACCOUNT_NAVIGATION=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
