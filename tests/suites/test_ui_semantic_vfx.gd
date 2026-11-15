extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _records: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _ordinal := 900


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var original_size := tree.root.size
	var session := GameSession.new(SaveStore.new("user://semantic-vfx-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave":false})
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted,"production run starts in isolated user data")
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	_check(_helpers.enter_node(shell,str(session.get_view().run.reachable_node_ids[0])),"production battle entered through normal command")
	await _frames(3)
	for dimensions in [Vector2i(1280,800),Vector2i(960,600)]:
		tree.root.size = dimensions
		shell.refresh()
		await _frames(4)
		var page := shell.page as BattleScreen
		page._finish_event_presentation()
		var before: String = _helpers.fingerprint(session)
		await _matrix(page,str(dimensions.x))
		_check(before == _helpers.fingerprint(session),"all effect fixtures preserve domain/revision/RNG at %d" % dimensions.x)
	await _published_command_modes(shell)
	shell.free()
	tree.root.size = original_size
	await _frames(2)
	print("SEMANTIC_VFX_EVIDENCE=",JSON.stringify({"checks":_checks,"fixtures":_records,"failures":_failures,"scope":"controlled visual event matrix plus real published command replay; no human signoff"}))
	return _failures


func _matrix(page: BattleScreen, label: String) -> void:
	var player := str(page.view.player.entity_id)
	var task := str(page.view.tasks[0].task_id)
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":20,"shield_before":0,"shield_after":0},player,[],label+" zero work")
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":16},player,["work_light"],label+" light work")
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":7},player,["work_heavy"],label+" heavy work")
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":20,"shield_before":8,"shield_after":3},player,["guard_absorb"],label+" shield only")
	await _frames(2)
	_check(is_zero_approx((page._actors[task] as BattleActorView).hit_strength),"shield-only work never cues body damage at "+label)
	_check(is_zero_approx((page._actors[task] as BattleActorView).guard_strength),"local shield never adds the oversized legacy body shield at "+label)
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":20,"shield_before":5,"shield_after":0},player,["guard_absorb","guard_break"],label+" broken shield without work loss")
	await _expect(page,"pressure_applied",[player],{"vitality_before":70,"vitality_after":70,"relax_before":6,"relax_after":2},task,["guard_absorb"],label+" pressure absorbed")
	_check(_labels(page).contains("放松抵消 4") and not _labels(page).contains("精力 −"),"absorbed pressure reports only actual absorption at "+label)
	var emitted: Array = []
	var observe_trail := func(node: Node):
		if node is BattleImpactView:
			emitted.append({"trail": node, "source": page._stage_effects.anchor(task), "target": page._stage_effects.target_anchor(player)})
	page._stage.child_entered_tree.connect(observe_trail)
	await _expect(page,"pressure_applied",[player],{"vitality_before":70,"vitality_after":66},task,["pressure_hit"],label+" pressure damage")
	page._stage.child_entered_tree.disconnect(observe_trail)
	var trails := _trails(page)
	_check(trails.size() == 1 and emitted.size() == 1 and trails[0] == emitted[0].trail and trails[0].origin.is_equal_approx(emitted[0].source) and trails[0].destination.is_equal_approx(emitted[0].target),"pressure trail uses actual task origin at emission and player impact at "+label)
	await _expect(page,"vitality_changed",[player],{"before":66,"after":70},player,["heal"],label+" heal")
	await _expect(page,"vitality_changed",[player],{"before":70,"after":70},player,[],label+" capped heal")
	await _expect(page,"focus_changed",[player],{"before":1,"after":3,"delta":2},player,["resource_gain"],label+" focus gained")
	await _expect(page,"focus_changed",[player],{"before":3,"after":1,"delta":-2},player,["resource_spend"],label+" focus paid")
	_check(_trails(page).is_empty(),"self payment cannot invent an attack trail at "+label)
	await _expect(page,"relax_changed",[player],{"before":0,"after":6,"delta":6},player,["guard_gain"],label+" guard gained")
	await _expect(page,"relax_changed",[player],{"before":6,"after":2,"delta":-4,"reason":"pressure_absorbed"},task,[],label+" no duplicate absorption")
	await _expect(page,"status_gained",[task],{"before":0,"after":2,"status_definition_id":"erosion"},player,["status_attach"],label+" status attached")
	await _expect(page,"status_changed",[task],{"before":2,"after":1,"status_definition_id":"erosion"},"",["status_decay"],label+" status decayed")
	await _expect(page,"status_removed",[task],{"status_definition_id":"erosion"},"",["status_remove"],label+" status removed")
	await _expect(page,"status_gained",[task],{"before":2,"after":2,"status_definition_id":"erosion"},player,[],label+" zero status gain")
	await _expect(page,"status_gained",[player,task],{"before":0,"after":1,"status_definition_id":"weakness"},"",["status_attach","status_attach"],label+" multi-target order")
	var ordered := _locals(page)
	_check(ordered.size() == 2 and ordered[0].get_meta("effect_target") == player and ordered[1].get_meta("effect_target") == task,"all targets keep published order at "+label)
	await _expect(page,"completion_applied",[task],{"work_before":20,"work_after":18},"unknown-source",["work_light"],label+" unknown origin")
	_check(_trails(page).is_empty(),"unknown source shows local result without fictional player trail at "+label)
	await _expect(page,"pressure_applied",["missing-target"],{"vitality_before":70,"vitality_after":60},task,[],label+" unknown target")
	_check(_labels(page).is_empty(),"unknown target never falls back to player at "+label)
	page._stage_effects.remember()
	await _expect(page,"task_advanced",[task,"fixture-next-phase"],{"old_task_id":task,"new_task_id":"fixture-next-phase"},task,["phase"],label+" explicit next phase")
	var phase_effects := _locals(page)
	_check(not phase_effects.is_empty() and phase_effects[0].get_meta("effect_target") == "fixture-next-phase","stage effect belongs to new task ID at "+label)
	await _expect(page,"task_transformed",[task],{},task,["phase"],label+" transformed task")
	page._presentation.finish()
	var base := page.view.duplicate(true)
	var unit_view := base.duplicate(true)
	unit_view.units.append({"unit_id":"visual-unit","definition_id":"U01","vitality":2,"cooperation":1,"relax":0,"guard":false})
	page.render(unit_view)
	await _frames(3)
	await _expect(page,"unit_healed",["visual-unit"],{"before":2,"after":4},player,["heal"],label+" unit recovery display fixture")
	page.render(base)
	await _frames(3)
	var anchors := page.damage_target_anchors()
	_check(anchors.has(task) and Vector2(anchors[task]).is_equal_approx(page._stage.get_global_transform_with_canvas()*page._stage_effects.target_anchor(task)),"damage number shares local impact point at "+label)
	await _lifecycle(page,player,task,label)
	page._presentation.finish()
	_check(_locals(page).is_empty() and _trails(page).is_empty() and not page._presentation.is_animating(),"cleanup removes effects and active tweens at "+label)


func _lifecycle(page: BattleScreen, player: String, task: String, label: String) -> void:
	page._presentation.finish()
	_ordinal += 1
	var event := {"index":0,"type":"focus_changed","source_id":player,"target_ids":[player],"data":{"before":1,"after":2,"delta":1}}
	page.consume_events([event],"semantic-dedup-"+label,_ordinal)
	var count := _locals(page).size()
	page.consume_events([event],"semantic-dedup-"+label,_ordinal)
	_check(count == 1 and _locals(page).size() == count,"same run/revision/event consumes exactly once at "+label)
	page._presentation.finish()
	var completed: Array = []
	var callback := func(): completed.append(true)
	page.result_presentation_finished.connect(callback)
	_ordinal += 1
	page.present_result([{"index":0,"type":"task_transformed","source_id":task,"target_ids":[task],"data":{}}],[],"semantic-terminal-"+label,_ordinal)
	page._animator.advance(.06)
	_check(completed.is_empty() and page._result_pending and page._presentation.is_animating(),"terminal waits for actual phase tween after event queue ends at "+label)
	var phase_seconds := .4
	var actor: BattleActorView = page._actors.get(task)
	if is_instance_valid(actor) and is_instance_valid(actor.rig):
		phase_seconds = maxf(phase_seconds, actor.rig.action_length("phase") / page.effect_speed())
	var deadline := Time.get_ticks_msec() + int((phase_seconds + .6) * 1000)
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	await _frames(2)
	_check(completed.size() == 1 and not page._result_pending,"terminal signals once after phase tween finishes at "+label)
	page.result_presentation_finished.disconnect(callback)
	await _expect(page,"vitality_changed",[player],{"before":60,"after":65},player,["heal"],label+" before disable")
	page.animation_enabled = false
	_check(_locals(page).is_empty() and not page._presentation.is_animating(),"disabling motion cancels live effects at "+label)
	page._present_event_visual(event)
	_check(_locals(page).is_empty(),"reduced-motion path creates no transient at "+label)
	page.animation_enabled = true


func _published_command_modes(shell: GameShell) -> void:
	var page := shell.page as BattleScreen
	page._finish_event_presentation()
	var session := shell.session
	var current := session.get_view()
	var card_id := ""
	for card in current.battle.hand:
		if str(card.definition_id) in ["R3-C-01","R3-P01-02"]:
			card_id = str(card.card_id)
			break
	_check(not card_id.is_empty(),"real production work card available")
	if card_id.is_empty():
		return
	var result := session.submit(CommandContext.new(str(current.run_id),current.revision),GameAction.new(&"play_card",{"card_instance_id":card_id,"target_ids":[str(current.battle.tasks[0].task_id)],"replace_unit_id":null}))
	_check(result.accepted,"real work command accepted")
	if not result.accepted:
		return
	var published: String = _helpers.fingerprint(session)
	var found_work := false
	for event in result.events:
		if str(event.type) == "completion_applied":
			found_work = true
	_check(found_work,"production command actually publishes completion event")
	for mode in ["normal","double","reduced"]:
		shell.refresh()
		await _frames(3)
		page = shell.page as BattleScreen
		page._finish_event_presentation()
		page.speed_scale = 2.0 if mode == "double" else 1.0
		page.animation_enabled = mode != "reduced"
		# A separate presentation stream replays one already-published command.
		page.consume_events(result.events,"published-mode-"+mode,result.revision)
		# Headless frame rates vary; finite presentation completion is a time bound.
		var replay_deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < replay_deadline:
			if page._animator.pending_count() == 0 and not page._presentation.is_animating():
				break
			await _frames(1)
		_check(published == _helpers.fingerprint(session),"published domain/revision/RNG unchanged after "+mode)
		_check(page._animator.pending_count() == 0 and not page._presentation.is_animating(),"real event replay settles at "+mode)
		page._finish_event_presentation()


func _expect(page: BattleScreen, kind: String, targets: Array, data: Dictionary, source: String, expected: Array, name: String) -> void:
	page._presentation.finish()
	_ordinal += 1
	var event := {"index":_ordinal,"type":kind,"source_id":source,"target_ids":targets,"data":data}
	page._present_event_visual(event)
	if kind in ["completion_applied", "pressure_applied"] and not expected.is_empty():
		var delay := page._stage_effects.impact_feedback_delay(event)
		if delay > .005:
			_check(_locals(page).is_empty(), name + " waits for the authored contact")
			await (Engine.get_main_loop() as SceneTree).create_timer(delay + .02).timeout
	var actual: Array = _locals(page).map(func(effect): return effect.kind)
	_check(actual == expected,name+" -> "+str(expected)+" got "+str(actual))
	for effect in _locals(page):
		_check(effect.mouse_filter == Control.MOUSE_FILTER_IGNORE and effect.focus_mode == Control.FOCUS_NONE,name+" never captures input")
	for node in page._stage.get_children():
		if node is Label and node.has_meta("battle_event_effect"):
			_check(Rect2(Vector2.ZERO,page._stage.size).encloses(Rect2(node.position,node.size)),name+" feedback stays within stage")
	_records.append({"name":name,"input":event,"expected":expected,"actual":actual})


func _locals(page: BattleScreen) -> Array:
	return page._stage.get_children().filter(func(node): return node is BattleSemanticEffectView)


func _trails(page: BattleScreen) -> Array:
	return page._stage.get_children().filter(func(node): return node is BattleImpactView)


func _labels(page: BattleScreen) -> String:
	var values := PackedStringArray()
	for node in page._stage.get_children():
		if node is Label and node.has_meta("battle_event_effect"):
			values.append(node.text)
	return " | ".join(values)


func _frames(count: int) -> void:
	for frame in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("Semantic VFX: "+message)
