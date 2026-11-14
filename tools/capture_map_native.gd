extends SceneTree

var out_path := "res://artifacts/verification/map-card-feedback-20261114/native"
var shell: GameShell
var session: GameSession
var target := ""
var sequence := -1
var before := ""
var initial_revision := 0
var submissions: Array = []
var recorder: PointerRecorder


class PointerRecorder extends Node:
	var events: Array = []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			events.append({"button":event.button_index,"pressed":event.pressed,"double_click":event.double_click,"position":[event.position.x,event.position.y],"time_usec":Time.get_ticks_usec()})


func _initialize() -> void:
	if not OS.get_environment("MAP_NATIVE_OUT").is_empty():
		out_path = OS.get_environment("MAP_NATIVE_OUT")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path))
	DisplayServer.window_set_title("Campus map native double-click verification")
	recorder = PointerRecorder.new()
	root.add_child(recorder)
	while true:
		var request_path := out_path.path_join("request.json")
		if FileAccess.file_exists(request_path):
			var request = JSON.parse_string(FileAccess.get_file_as_string(request_path))
			if request is Dictionary and int(request.get("sequence",-1)) != sequence:
				sequence = int(request.sequence)
				if request.get("action","") == "quit":
					quit(0)
					return
				await _reset(request)
		_write_state()
		await create_timer(.04).timeout


func _reset(request: Dictionary) -> void:
	if is_instance_valid(shell):
		shell.free()
	root.size = Vector2i(int(request.get("width",1280)),int(request.get("height",800)))
	root.position = Vector2i(60,60)
	session = GameSession.new(SaveStore.new("user://native-map-%d" % Time.get_ticks_usec()))
	var settings := session.update_settings({"autosave":false,"presentation":{"reduced_motion":true,"animation_speed":0,"text_scale":int(request.get("text_scale",100))}})
	if not settings.ok or not session.start_run(StartRunRequest.new("P03",&"normal","campus_four_year","42")).accepted:
		push_error("Native map fixture failed")
		quit(1)
		return
	shell = GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	for frame in 15:
		await process_frame
	target = str(session.get_view().run.reachable_node_ids[0])
	var button: Button = shell.page._buttons["node:"+target]
	shell.page._scroll.ensure_control_visible(button)
	for frame in 8:
		await process_frame
	before = load("res://tests/suites/test_ui_shell_pages.gd").new().fingerprint(session)
	initial_revision = int(session.get_view().revision)
	submissions.clear()
	recorder.events.clear()
	shell.page.action_requested.connect(func(draft): submissions.append(draft.duplicate(true)))
	shell.set_meta("native_request",request)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path.path_join("map-before-%d.png" % sequence))


func _write_state() -> void:
	if not is_instance_valid(shell):
		return
	var current := session.get_view()
	var state := {"sequence":sequence,"target":target,"screen":str(current.screen),"current_node_id":str(current.run.current_node_id),"revision_delta":int(current.revision)-initial_revision,"submissions":submissions,"events":recorder.events,"size":[root.size.x,root.size.y],"text_scale":UiStyle.text_scale}
	if shell.page is UiExperiencePage and (shell.page as UiExperiencePage).screen == "map":
		var page := shell.page as UiExperiencePage
		var point := func(button: Button):
			var stamp: Vector2 = button.global_position+button.call("stamp_center")
			var caption: Vector2 = button.global_position+button.call("label_rect").get_center()
			return {"stamp":[stamp.x,stamp.y],"caption":[caption.x,caption.y],"instance":button.get_instance_id()}
		state["point"] = point.call(page._buttons["node:"+target])
		state["selected"] = str(page._choices.get("map:node",""))
		state["scroll"] = page._scroll.scroll_vertical
		state["enter_enabled"] = not page.button_disabled("map:enter")
		var enter_center: Vector2 = page._buttons["map:enter"].get_global_rect().get_center()
		state["enter_point"] = [enter_center.x,enter_center.y]
		state["fingerprint_unchanged"] = load("res://tests/suites/test_ui_shell_pages.gd").new().fingerprint(session) == before
		var unavailable := ""
		for node in current.run.nodes:
			if int(node.layer) == 2 and not current.run.reachable_node_ids.has(str(node.node_id)):
				unavailable = str(node.node_id)
				break
		if not unavailable.is_empty():
			state["unavailable"] = {"id":unavailable,"point":point.call(page._buttons["node:"+unavailable])}
	var file := FileAccess.open(out_path.path_join("state.tmp"),FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(out_path.path_join("state.tmp")),ProjectSettings.globalize_path(out_path.path_join("state.json")))
