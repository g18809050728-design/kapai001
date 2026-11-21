extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _requests: Array[bool] = []


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var root := "user://web-permissions-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var previous_path := TextOverrides.current_path()
	TextOverrides.use_path(root + "/text_overrides.json")
	var session := GameSession.new(SaveStore.new(root + "/saves"))
	session.test_service().store = TestStore.new(root + "/test")
	var shell := GameShell.new()
	shell.session = session
	tree.root.add_child(shell)
	shell.web_play_requested.connect(func(developer_tools: bool): _requests.append(developer_tools))
	_expect_tools(shell, true, "native development")
	_check(shell.press("menu:text_editor"), "native text editor entry exists")
	_check(shell.page is UiTextEditorPage, "native text editor opens without web authentication")
	shell.show_screen("menu")
	for state in ["checking", "login", "unavailable", "guest", "bundle_unavailable"]:
		shell.set_web_account_state(state, true, "", "", "admin")
		_expect_tools(shell, false, state)
		_check_denied(shell, state)
	shell.set_web_account_state("ready", true, "player", "", "player")
	_expect_tools(shell, false, "ordinary account")
	_check_denied(shell, "ordinary account")
	shell.set_web_account_state("ready", true, "administrator", "", "admin")
	_expect_tools(shell, true, "administrator")
	for entry in ["menu:test", "menu:text_editor"]:
		_requests.clear()
		_check(shell.press(entry), "administrator can request " + entry)
		_check(_requests == [true], "developer entry requires an administrator session recheck")
		_check(shell._ui_screen == "menu", "developer entry waits for the session response")
		shell.resolve_web_play(false)
		_check(shell._ui_screen == "menu", "failed session confirmation refuses developer entry")
		_check(shell.press(entry), "administrator can retry after failed confirmation")
		shell.resolve_web_play(true)
		_check(shell.page is TestRoomPage if entry == "menu:test" else shell.page is UiTextEditorPage, "confirmed administrator opens " + entry)
		shell.show_screen("menu")
	_requests.clear()
	_check(shell.press("menu:new"), "normal play remains available to administrators")
	_check(_requests == [false], "normal play uses the ordinary session check")
	shell.resolve_web_play(false)
	shell.set_web_account_state("ready", true, "former administrator", "", "player")
	_expect_tools(shell, false, "role revoked")
	_check_denied(shell, "role revoked")
	shell.set_web_account_state("ready", true, "administrator", "", "admin")
	shell.set_web_account_state("login", true, "", "")
	_expect_tools(shell, false, "logout")
	_check_denied(shell, "logout")
	_check(not session.has_test_room() and session.get_view().run_id == null, "permission checks do not create formal or test runs")
	shell.queue_free()
	await tree.process_frame
	TextOverrides.use_path(previous_path)
	print("WEB_ACCOUNT_PERMISSIONS=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures


func _expect_tools(shell: GameShell, expected: bool, label: String) -> void:
	for uid in ["menu:test", "menu:text_editor"]:
		_check(shell.page.button_uids().has(uid) == expected, label + ": " + uid)


func _check_denied(shell: GameShell, label: String) -> void:
	for action in ["ui.test_room", "ui.text_editor", "test.start"]:
		shell.submit_action({"type": action, "payload": {}})
		_check(shell._ui_screen == "menu" and not shell.session.has_test_room(), label + ": rejects direct " + action)
	_check(shell._web_play_draft.is_empty(), label + ": no pending developer action")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
