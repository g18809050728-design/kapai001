extends SceneTree

const OUT := "res://artifacts/verification/non-character-vfx-20261114/sampled-runtime-v3"
var _records: Array = []
var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for dimensions in [Vector2i(1280,800),Vector2i(960,600)]:
		root.size = dimensions
		var session := GameSession.new(SaveStore.new("user://semantic-capture-%d-%d" % [dimensions.x,Time.get_ticks_usec()]))
		session.update_settings({"autosave":false})
		if not session.start_run(StartRunRequest.new("P01",&"normal","campus_four_year","42")).accepted:
			_failures.append("production run failed")
			break
		var shell := _helpers.attach_shell(session) as GameShell
		shell.show_screen("")
		if not _helpers.enter_node(shell,str(session.get_view().run.reachable_node_ids[0])):
			_failures.append("production battle failed")
			break
		for frame in 5:
			await process_frame
		var page := shell.page as BattleScreen
		page._finish_event_presentation()
		var before := _helpers.fingerprint(session)
		var card_id := ""
		for card in page.view.hand:
			if str(card.definition_id) in ["R3-C-01","R3-P01-02"]:
				card_id = str(card.card_id)
				break
		await _reveal_actor(page,str(page.view.tasks[0].task_id))
		if card_id.is_empty() or not shell.press("card:"+card_id) or not shell.press("task:"+str(page.view.tasks[0].task_id)):
			_failures.append("actual work command failed at %d" % dimensions.x)
		else:
			page = shell.page as BattleScreen
			_records.append({"name":"production-work","width":dimensions.x,"kind":"actual normal GameShell command","input":{"card_id":card_id},"before_sha256":before.sha256_text(),"after_sha256":_helpers.fingerprint(session).sha256_text(),"event_log":page.view.event_log.duplicate(true)})
			await _frames(shell,"production-work",dimensions.x,16)
		page._finish_event_presentation()
		shell._damage_layer.clear_popups()
		var player := str(page.view.player.entity_id)
		var task := str(page.view.tasks[0].task_id)
		var scenarios := [
			["pressure-absorbed","pressure_applied",task,[player],{"vitality_before":70,"vitality_after":70,"relax_before":6,"relax_after":2}],
			["pressure-damage","pressure_applied",task,[player],{"vitality_before":70,"vitality_after":62}],
			["recovery","vitality_changed",player,[player],{"before":60,"after":65}],
			["focus-gain","focus_changed",player,[player],{"before":1,"after":3,"delta":2}],
			["focus-payment","focus_changed",player,[player],{"before":3,"after":1,"delta":-2}],
			["status-attach","status_gained",player,[task],{"before":0,"after":2,"status_definition_id":"erosion"}],
			["status-remove","status_removed","",[task],{"status_definition_id":"erosion"}],
			["next-phase","task_advanced",task,[task,"capture-next-phase"],{"old_task_id":task,"new_task_id":"capture-next-phase","phase_key":"capture"}]
		]
		var domain := _helpers.fingerprint(session)
		for scenario in scenarios:
			page._finish_event_presentation()
			await _reveal_actor(page,player if scenario[0] in ["pressure-absorbed","pressure-damage","recovery","focus-gain","focus-payment"] else task)
			page._stage_effects.remember()
			var event := {"index":0,"type":scenario[1],"source_id":scenario[2],"target_ids":scenario[3],"data":scenario[4]}
			page._present_event_visual(event)
			_records.append({"name":scenario[0],"width":dimensions.x,"kind":"controlled read-only visual event fixture; HUD remains production state","event":event})
			await _frames(shell,scenario[0],dimensions.x,8)
		if domain != _helpers.fingerprint(session):
			_failures.append("visual fixtures changed domain at %d" % dimensions.x)
		page._finish_event_presentation()
		shell.free()
		await process_frame
	var report := FileAccess.open(OUT.path_join("capture.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"records":_records,"failures":_failures,"motion":"controlled sampling of paused production Tweens via custom_step and actual event animator; base x4, user x1; not real-time performance or natural input latency"},"\t"))
	report.close()
	await create_timer(.15).timeout
	for failure in _failures:
		push_error(failure)
	print("RUNTIME_SEMANTIC_CAPTURE=", "passed" if _failures.is_empty() else "failed", " records=",_records.size())
	quit(0 if _failures.is_empty() else 1)


func _frames(shell: GameShell, name: String, width: int, count: int) -> void:
	var directory := OUT.path_join("%d/%s" % [width,name])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var started := Time.get_ticks_usec()
	var page := shell.page as BattleScreen
	page.set_process(false)
	shell._damage_layer.set_process(false)
	page._animator.queue_finished.disconnect(page._on_event_queue_finished)
	var step := .05 if count > 8 else .035
	for index in count:
		page._animator.advance(step)
		for tween in page._presentation._tweens.duplicate():
			if tween.is_valid():
				tween.pause()
				tween.custom_step(step)
		shell._damage_layer.advance(step)
		await process_frame
		await process_frame
		# A fully settled off-screen viewport may not emit another automatic draw.
		RenderingServer.force_draw(false)
		var path := directory.path_join("%02d.png" % index)
		if root.get_texture().get_image().save_png(path) != OK:
			_failures.append("frame save failed: "+path)
		var effects: Array = []
		if page != null:
			for node in page._stage.get_children():
				if node is BattleSemanticEffectView:
					effects.append({"kind":node.kind,"progress":node.progress,"target":node.get_meta("effect_target"),"center":str(node.position+node.size*.5)})
		_records.append({"file":path.trim_prefix(OUT+"/"),"scenario":name,"width":width,"frame":index,"simulated_elapsed_ms":(index+1)*step*1000.0,"wall_elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"effects":effects})
	page._animator.queue_finished.connect(page._on_event_queue_finished)
	page.set_process(true)
	shell._damage_layer.set_process(true)


func _reveal_actor(page: BattleScreen, id: String) -> void:
	var actor: Control = page._actors.get(id)
	if not is_instance_valid(actor):
		return
	var ancestor := actor.get_parent()
	while ancestor != null and ancestor != page:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(actor)
			break
		ancestor = ancestor.get_parent()
	for frame in 3:
		await process_frame
