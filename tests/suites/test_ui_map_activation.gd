extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _stationary_samples: Array = []


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var previous_size := tree.root.size
	var previous_scale := UiStyle.text_scale
	for dimensions in [Vector2i(1280,800), Vector2i(960,600)]:
		for scale_value in [1.0, 1.25, 1.5]:
			for gap_frames in [0, 8]:
				await _stationary_double_click(dimensions, scale_value, gap_frames, false)
			await _stationary_double_click(dimensions, scale_value, 4, true)
			await _stationary_double_click(dimensions, scale_value, 8, false, false)
	UiStyle.text_scale = previous_scale
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
		_check(_helpers.fingerprint(session) == before, "switching back to another node only selects it")
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
	print("MAP_DOUBLE_CLICK=",JSON.stringify({"sizes":["1280x800","960x600","1920x1080"],"pointer_events":true,"stationary_samples":_stationary_samples,"failures":_failures}))
	return _failures


func _stationary_double_click(dimensions: Vector2i, scale_value: float, gap_frames: int, caption_target: bool, native_double: bool = true) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.size = dimensions
	UiStyle.text_scale = scale_value
	var session := GameSession.new(SaveStore.new("user://map-stationary-%d" % Time.get_ticks_usec()))
	_check(session.update_settings({"autosave":false,"presentation":{"reduced_motion":true,"animation_speed":0,"text_scale":roundi(scale_value*100)}}).ok,"stationary presentation settings accepted")
	_check(session.start_run(StartRunRequest.new("P03",&"normal","campus_four_year","42")).accepted,"start stationary production run")
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	await _frames()
	var page := shell.page as UiExperiencePage
	_check(is_equal_approx(UiStyle.text_scale, scale_value),"stationary test uses the actual requested text scale")
	var target := str(session.get_view().run.reachable_node_ids[0])
	var button: Button = page._buttons["node:"+target]
	page._scroll.ensure_control_visible(button)
	await _frames()
	var button_id := button.get_instance_id()
	var point: Vector2 = button.global_position + (button.call("label_rect").get_center() if caption_target else button.call("stamp_center"))
	var scroll_before := page._scroll.scroll_vertical
	var generation := page._render_generation
	var before := _helpers.fingerprint(session)
	var revision := int(session.get_view().revision)
	var submissions: Array = []
	var repeated: Array[bool] = [false]
	page.action_requested.connect(func(draft):
		submissions.append(draft.duplicate(true))
		if not repeated[0]:
			repeated[0] = true
			var repeat_event := InputEventMouseButton.new()
			repeat_event.button_index = MOUSE_BUTTON_LEFT
			repeat_event.pressed = true
			repeat_event.double_click = true
			page._map_node_input(repeat_event,target,generation))
	_send_click(point, false)
	var first_click_usec := Time.get_ticks_usec()
	if not native_double:
		await tree.create_timer(.8).timeout
	for frame in gap_frames:
		await tree.process_frame
	var current_button: Button = page._buttons["node:"+target]
	var current_point: Vector2 = current_button.global_position + (current_button.call("label_rect").get_center() if caption_target else current_button.call("stamp_center"))
	var same_control := current_button.get_instance_id() == button_id
	var label := "%s scale=%s gap=%d caption=%s double=%s" % [dimensions,scale_value,gap_frames,caption_target,native_double]
	_check(same_control and page._render_generation == generation,"single click keeps the actual node alive: "+label)
	_check(current_point.distance_to(point) < 1 and page._scroll.scroll_vertical == scroll_before,"single click keeps pointer target and scroll stationary: "+label)
	_check(_helpers.fingerprint(session) == before,"stationary first click is read only: "+label)
	if gap_frames > 0:
		_check(str(page._choices.get("map:node","")) == target and current_button.button_pressed,"first click selects and marks the original node: "+label)
		_check(page.action_draft("map:enter").payload.node_id == target,"confirmation draft follows in-place selection: "+label)
	# Keep the original coordinates. Do not scroll, look up a new target, or
	# preselect a node between the two halves of a player's double click.
	_send_click(point, native_double)
	await _frames()
	var entered := str(session.get_view().run.current_node_id) == target and session.get_view().screen == &"battle"
	_check(entered,"unselected node enters from double click at the original point: "+label)
	_check(int(session.get_view().revision) == revision+1 and submissions.size() == 1,"stationary double click commits once: "+label)
	_stationary_samples.append({"size":str(dimensions),"scale":scale_value,"gap_frames":gap_frames,"caption":caption_target,"double_flag":native_double,"elapsed_ms":(Time.get_ticks_usec()-first_click_usec)/1000.0,"same_control":same_control,"point_delta":current_point.distance_to(point),"scroll_delta":page._scroll.scroll_vertical-scroll_before if is_instance_valid(page) and is_instance_valid(page._scroll) else 0,"entered":entered,"submissions":submissions.size()})
	shell.free()
	await _frames()


func _send_click(point: Vector2, double_click: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		click.double_click = double_click and pressed
		Input.parse_input_event(click)


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
