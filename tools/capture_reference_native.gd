extends SceneTree

var shell: GameShell
var session: GameSession
var sequence := -1
var out_path := ""
var before := ""
var events: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()

class PointerRecorder extends Node:
	var events: Array = []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			events.append({"button": event.button_index, "pressed": event.pressed, "double_click": event.double_click, "position": [event.position.x, event.position.y]})


func _initialize() -> void:
	out_path = OS.get_environment("REFERENCE_NATIVE_OUT")
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_title("Campus reference native verification")
	var recorder := PointerRecorder.new()
	root.add_child(recorder)
	events = recorder.events
	while true:
		var path := out_path.path_join("request.json")
		if FileAccess.file_exists(path):
			var request = JSON.parse_string(FileAccess.get_file_as_string(path))
			if request is Dictionary and int(request.sequence) != sequence:
				sequence = int(request.sequence)
				if request.get("action", "") == "quit":
					quit(0); return
				await _reset(request)
		if is_instance_valid(shell): _write()
		await create_timer(.05).timeout


func _reset(request: Dictionary) -> void:
	if is_instance_valid(shell): shell.free()
	root.size = Vector2i(int(request.width), int(request.height))
	root.position = Vector2i(60, 60)
	session = GameSession.new(SaveStore.new("user://native-reference-%d" % sequence))
	session.update_settings({"autosave": false, "presentation": {"text_scale": request.scale, "reduced_motion": true, "animation_speed": 0}})
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	var run: RunState = session._state.run
	var order := run.next_instance_seq
	var id := run.next_instance_id("relic")
	run.relics.assign([{"relic_id": id, "definition_id": "FY_Y1_3", "slot": 2, "acquired_order": order}])
	shell = _helpers.attach_shell(session)
	shell.show_screen("")
	if request.get("battle", false):
		_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
	else:
		shell.page.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
	for frame in 12: await process_frame
	before = _helpers.fingerprint(session)
	events.clear()


func _write() -> void:
	var page := shell.page
	var toolbar: UiRunToolbar = page.get("_toolbar")
	var reference: UiReferenceOverlay = page._reference
	var points := {}
	for uid in page._buttons:
		var button: Button = page._buttons[uid]
		if not is_instance_valid(button): continue
		points[uid] = _point(button)
		if button.has_node("MenuCaption"):
			points[uid + ":caption"] = _point(button.get_node("MenuCaption"))
	if is_instance_valid(reference):
		points["reference:close"] = _point(reference._close)
		for key in reference._tabs:
			points["reference:" + str(key)] = _point(reference._tabs[key])
		if reference.section == "log":
			points["reference:search"] = _point(reference._search)
	var state := {"sequence": sequence, "ready": true, "points": points,
		"screen": "battle" if page is BattleScreen else page.screen,
		"menu": is_instance_valid(toolbar) and toolbar.is_menu_open(),
		"reference": reference.section if is_instance_valid(reference) else "",
		"search_text": reference._search.text if is_instance_valid(reference) and reference.section == "log" else "",
		"selected_relic": reference.selected_relic if is_instance_valid(reference) else "",
		"unchanged": _helpers.fingerprint(session) == before,
		"feedback": shell._ui_feedback.visible, "events": events}
	state["mouse"] = [root.get_mouse_position().x, root.get_mouse_position().y]
	if root.has_method("gui_get_hovered_control"):
		var hovered: Control = root.call("gui_get_hovered_control")
		state["hovered"] = str(hovered.get_path()) if is_instance_valid(hovered) else ""
	var file := FileAccess.open(out_path.path_join("state.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(state))


func _point(control: Control) -> Dictionary:
	var bounds := control.get_global_rect()
	return {"x": bounds.get_center().x, "y": bounds.get_center().y, "width": bounds.size.x, "height": bounds.size.y, "disabled": control.disabled if control is BaseButton else false}
