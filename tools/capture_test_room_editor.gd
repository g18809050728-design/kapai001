extends SceneTree

const OUT := "res://artifacts/verification/test-room-ui-20261111"
var shell: GameShell


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var session := GameSession.new(
		SaveStore.new("user://test-room-ui-capture-%d" % Time.get_ticks_usec())
	)
	session.update_settings({"autosave": false})
	session.test_service().store = TestStore.new(
		"user://test-room-ui-capture-store-%d" % Time.get_ticks_usec()
	)
	var started := session.start_test_room(
		{"character_id": "P02", "encounter_id": "N01", "seed": "42"}
	)
	if not started.accepted:
		push_error("test room failed to start")
		quit(1)
		return
	session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{"op": "set_player_field", "field": "focus", "value": 4},
				{"op": "add_card", "definition_id": "R3-P02-18", "zone": "hand", "count": 1},
				{"op": "add_status", "status_id": "inspiration", "target_id": _player_id(session), "stacks": 2},
			]
		}
	)
	shell = GameShell.new()
	shell.session = session
	root.add_child(shell)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		await _frames(3)
		shell.refresh()
		var suffix := "-%d" % dimensions.x
		await _save("battle" + suffix)
		shell._test_hud.open_editor()
		await _frames(2)
		shell._test_hud.editor.press("test:editor:tab:resources")
		await _save("editor-resources" + suffix)
		if dimensions.x == 1280:
			shell._test_hud.editor.press("test:editor:field:player.focus:plus")
			await _save("editor-draft-1280")
			shell._test_hud.editor.press("test:editor:close")
			await _save("editor-close-confirm-1280")
			shell._test_hud.editor.press("test:editor:close:cancel")
			shell._test_hud.editor.press("test:editor:discard")
			await _frames(2)
			shell._test_hud.editor.press("test:editor:discard:confirm")
			await _frames(2)
			shell._test_hud.editor.clear_feedback()
			await _frames(2)
		shell._test_hud.editor.press("test:editor:tab:cards")
		await _save("editor-cards" + suffix)
		shell._test_hud.editor.press("test:editor:tab:enemies")
		await _save("editor-enemies" + suffix)
		shell._test_hud.editor.press("test:editor:tab:time")
		await _save("editor-time" + suffix)
		shell._test_hud.editor.press("test:editor:tab:enemies")
		await _frames(2)
		var tasks: Array = session.get_test_view().battle.tasks
		if not tasks.is_empty():
			shell._test_hud.editor.press("test:editor:task:%s:detail" % str(tasks[0].task_id))
			await _save("editor-task-detail" + suffix)
		shell._test_hud.editor.press("test:editor:tab:rules")
		await _save("editor-rules" + suffix)
		shell._test_hud.editor.press("test:editor:free:jump")
		await _save("editor-custom-definition" + suffix)
		shell._test_hud.editor.press("test:editor:tab:cards")
		await _frames(2)
		shell._test_hud.editor.press("test:editor:zone:chapter")
		await _save("editor-cards-chapter" + suffix)
		shell._test_hud.editor.press("test:editor:close")
		await _frames(2)
	session.update_settings(
		{"presentation": {"text_scale": 150, "reduced_motion": true, "animation_speed": 0}}
	)
	shell._apply_presentation()
	root.size = Vector2i(1280, 800)
	await _frames(3)
	shell.refresh()
	shell._test_hud.open_editor()
	await _frames(2)
	shell._test_hud.editor.press("test:editor:tab:resources")
	await _save("editor-resources-1280-text150")
	shell._test_hud.editor.press("test:editor:close")
	await _frames(2)
	await create_timer(0.2).timeout
	quit(0)


func _context(session: GameSession) -> Dictionary:
	var view := session.get_test_view()
	var test_state: Dictionary = view.get("test", {})
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _player_id(session: GameSession) -> String:
	return str(session.get_test_view().get("battle", {}).get("player", {}).get("entity_id", ""))


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _save(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT.path_join(label + ".png"))
	if code != OK:
		push_error("capture failed: " + label)
