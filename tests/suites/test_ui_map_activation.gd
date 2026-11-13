extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var previous_size := tree.root.size
	for dimensions in [Vector2i(1280,800),Vector2i(960,600),Vector2i(1920,1080)]:
		tree.root.size = dimensions
		var session := GameSession.new(SaveStore.new("user://map-double-click-%d" % Time.get_ticks_usec()))
		session.update_settings({"autosave":false,"presentation":{"reduced_motion":true,"animation_speed":0}})
		_check(session.start_run(StartRunRequest.new("P03",&"normal","campus_four_year","42")).accepted,"start production run")
		var shell: GameShell = _helpers.attach_shell(session)
		shell.show_screen("")
		await _frames()
		var reachable: Array = session.get_view().run.reachable_node_ids
		var target := str(reachable[0])
		var before := _helpers.fingerprint(session)
		await _click_node(shell,target,false)
		_check(_helpers.fingerprint(session) == before,"single click only previews at %s" % dimensions)
		_check(str((shell.page as UiExperiencePage)._choices.get("map:node","")) == target,"single click selects stable node ID")
		var old_generation := shell.page._render_generation
		shell.page.refresh_local()
		var double_event := InputEventMouseButton.new()
		double_event.button_index = MOUSE_BUTTON_LEFT
		double_event.pressed = true
		double_event.double_click = true
		(shell.page as UiExperiencePage)._map_node_input(double_event,target,old_generation)
		_check(_helpers.fingerprint(session) == before,"old render callback cannot enter")
		var unavailable := ""
		for node in session.get_view().run.nodes:
			if not reachable.has(str(node.node_id)):
				unavailable = str(node.node_id)
				break
		await _click_node(shell,unavailable,false)
		await _click_node(shell,unavailable,true)
		_check(_helpers.fingerprint(session) == before and session.get_view().screen == &"map","double clicking future node cannot enter at %s" % dimensions)
		# A full double click has two releases, including a release after the
		# scene changes. Neither release may submit a second game command.
		await _click_node(shell,target,false)
		var revision := int(session.get_view().revision)
		var submissions: Array = []
		shell.page.action_requested.connect(func(draft): submissions.append(draft.duplicate(true)))
		await _click_node(shell,target,true)
		_check(str(session.get_view().run.current_node_id) == target,"double click enters selected node at %s" % dimensions)
		_check(session.get_view().screen == &"battle","double click opens the real encounter")
		_check(int(session.get_view().revision) == revision+1,"double click commits exactly one revision")
		_check(submissions.size() == 1 and submissions[0].type == "enter_node" and submissions[0].payload.node_id == target,"double click reuses one normal enter command")
		shell.free()
		await _frames()
	tree.root.size = previous_size
	print("MAP_DOUBLE_CLICK=",JSON.stringify({"sizes":["1280x800","960x600","1920x1080"],"real_pointer":true,"failures":_failures}))
	return _failures


func _click_node(shell: GameShell, id: String, double_click: bool) -> void:
	var node: Button = shell.page._buttons["node:"+id]
	shell.page._scroll.ensure_control_visible(node)
	await _frames()
	node = shell.page._buttons["node:"+id]
	var point: Vector2 = node.get_global_rect().position + node.call("stamp_center")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.double_click = double_click and pressed
		Input.parse_input_event(click)
	await _frames()


func _frames() -> void:
	for frame in 8:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
