class_name BattleStageEffects
extends RefCounted

## Events describe completed rules. This layer owns only poses and disposable ink.
var page: BattleScreen
var _previous: Dictionary = {}
var _lanes: Dictionary = {}
var _event_type := ""
var _event_index := -1
var _refined_transients: Dictionary = {}

func _init(screen: BattleScreen) -> void:
	page = screen

func remember() -> void:
	_previous.clear()
	_lanes.clear()
	for id in page._actors:
		var actor: BattleActorView = page._actors[id]
		if is_instance_valid(actor):
			_previous[id] = {"definition": actor.definition_id, "kind": actor.actor_kind, "phase": actor.phase_index, "center": page._stage_center(actor), "origin": _actor_point(actor, actor.action_anchor()), "impact": _actor_point(actor, actor.size * Vector2(.5,.6)), "size": actor.size}

func has_actor(id: String) -> bool:
	return is_instance_valid(page._actors.get(id)) or _previous.has(id)

func _actor_point(actor: Control, point: Vector2) -> Vector2:
	return page._stage.get_global_transform_with_canvas().affine_inverse() * (actor.get_global_transform_with_canvas() * point)

func source_actor(event: Dictionary) -> String:
	var source := str(event.get("source_id", ""))
	if has_actor(source):
		return source
	return str(page.view.get("effect_sources", {}).get(source, ""))

func anchor(id: String) -> Vector2:
	var actor: BattleActorView = page._actors.get(id)
	if is_instance_valid(actor):
		return _actor_point(actor, actor.action_anchor())
	return _previous.get(id, {}).get("origin", Vector2.ZERO)

func target_anchor(id: String) -> Vector2:
	var actor: BattleActorView = page._actors.get(id)
	if is_instance_valid(actor):
		return _actor_point(actor, actor.size * Vector2(.5,.6))
	return _previous.get(id, {}).get("impact", Vector2.ZERO)

func cue(id: String, kind: String) -> void:
	var actor := _visible_actor(id)
	if is_instance_valid(actor):
		page._presentation._tweens.append(actor.cue(kind,page.effect_speed()))

func present(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	var data: Dictionary = event.get("data", {})
	var targets: Array = event.get("target_ids", [])
	var source := source_actor(event)
	_event_type = kind
	_event_index = int(event.get("index", -1))
	if kind == "task_advanced":
		var old_id := str(data.get("old_task_id", event.get("source_id", "")))
		var next_id := str(data.get("new_task_id", ""))
		# The explicit old/new relationship preserves intermediate phase geometry
		# even when a multi-segment command has already completed the new phase.
		if not has_actor(next_id) and _previous.has(old_id):
			_previous[next_id] = _previous[old_id].duplicate(true)
			_previous[next_id].phase = int(_previous[old_id].phase) + 1
		_local(next_id, "phase", UiStyle.GOLD)
		_pilot_cue(next_id, "phase")
		_feedback(next_id, "进入下一阶段", UiStyle.GOLD)
		return
	if kind == "card_played":
		cue(source,"action")
		return
	for id in targets:
		_present_target(kind, data, source, str(id))

func _present_target(kind: String, data: Dictionary, source: String, target: String) -> void:
	if not has_actor(target):
		return
	match kind:
		"completion_applied", "pressure_applied":
			_impact(kind, data, source, target)
		"relax_changed", "focus_changed", "synergy_changed", "paper_changed":
			_resource(kind,data,source,target)
		"unit_healed", "vitality_changed":
			var delta := int(data.get("after",0))-int(data.get("before",0))
			if delta > 0:
				_local(target,"heal",Color("98d7b3"))
				_feedback(target,"精力 +%d" % delta,Color("b8ead1"))
			elif delta < 0 and kind == "vitality_changed":
				_local(target,"resource_spend" if data.get("reason","") == "payment" else "pressure_hit",Color("e0b784"))
				_feedback(target,"精力 −%d" % -delta,Color("f0c58c"))
		"shield_changed":
			var delta := int(data.get("after",0))-int(data.get("before",0))
			if delta != 0:
				_local(target,"guard_gain" if delta > 0 else ("guard_break" if int(data.get("after",0)) == 0 else "guard_absorb"),Color("91c7e8"))
				_feedback(target,"屏障 %s%d" % ["+" if delta > 0 else "−",absi(delta)],Color("b8d9ed"))
		"status_gained", "status_changed", "status_removed":
			_status(kind, data, source, target)
		"unit_summoned":
			_local(target,"partner",Color("99cbb2"))
			_feedback(target,"伙伴加入",UiStyle.GREEN.lightened(.35))
		"task_summoned":
			_local(target,"phase",UiStyle.GOLD)
			_feedback(target,"召唤入场",UiStyle.GOLD)
		"task_self_destructed":
			_local(target,"guard_break",Color("ec967e"))
			_feedback(target,"自爆退场",Color("ffc2ad"))
			_depart(target)
		"unit_departed", "task_completed":
			_depart(target)
		"coop_target_set":
			cue(source,"action")
			_trail(source,target,"link",UiStyle.GREEN)
		"task_transformed":
			_pilot_cue(target, "phase")
			_local(target,"phase",UiStyle.GOLD)
			_feedback(target,"形态转化",UiStyle.GOLD)
		"chapter_deployed", "chapter_ran", "chapter_returned", "chapter_slots_swapped", "paper_published", "v3_ability_registered":
			cue(target,"guard")
			_feedback(target,UiStyle.label(kind),UiStyle.GOLD)

func _impact(kind: String, data: Dictionary, source: String, target: String) -> void:
	var work := kind == "completion_applied"
	var loss := maxi(0,int(data.get("work_before" if work else "vitality_before",0))-int(data.get("work_after" if work else "vitality_after",0)))
	var absorbed := maxi(0,int(data.get("shield_before" if work else "relax_before",0))-int(data.get("shield_after" if work else "relax_after",0)))
	if loss == 0 and absorbed == 0:
		return
	var actor := _visible_actor(source)
	if is_instance_valid(actor) and is_instance_valid(actor.rig) and actor.rig.refined and page.animation_enabled:
		cue(source, "action")
		_restore_refined_target(target)
		var delay := actor.rig.seconds_to_contact()
		if delay > .005:
			var event_type := _event_type
			var event_index := _event_index
			var tween := page.create_tween()
			page._presentation._tweens.append(tween)
			tween.tween_interval(delay)
			tween.tween_callback(func():
				var previous_type := _event_type
				var previous_index := _event_index
				_event_type = event_type
				_event_index = event_index
				_impact_now(kind, data, source, target)
				_event_type = previous_type
				_event_index = previous_index)
			return
	_impact_now(kind, data, source, target)


func _impact_now(kind: String, data: Dictionary, source: String, target: String) -> void:
	var work := kind == "completion_applied"
	var loss := maxi(0,int(data.get("work_before" if work else "vitality_before",0))-int(data.get("work_after" if work else "vitality_after",0)))
	var absorbed := maxi(0,int(data.get("shield_before" if work else "relax_before",0))-int(data.get("shield_after" if work else "relax_after",0)))
	var color := UiStyle.GOLD if work else Color("ec967e")
	var direction := target_anchor(target)-anchor(source) if has_actor(source) else Vector2.RIGHT
	cue(source,"action")
	_trail(source,target,"work" if work else "pressure",color)
	if absorbed > 0:
		_local(target,"guard_absorb",Color("91c7e8"),direction)
		if int(data.get("shield_after" if work else "relax_after",0)) == 0:
			_local(target,"guard_break",Color("91c7e8"),direction,1.0,.18)
	if loss > 0:
		cue(target,"hit")
		_local(target,("work_heavy" if loss >= 10 else "work_light") if work else "pressure_hit",color,direction)

func _status(kind: String, data: Dictionary, source: String, target: String) -> void:
	var delta := int(data.get("after",0))-int(data.get("before",0))
	if kind != "status_removed" and delta == 0:
		return
	var glyph := "status_remove" if kind == "status_removed" else ("status_decay" if delta < 0 else "status_attach")
	_local(target,glyph,Color("adcad2"))
	if delta > 0 and kind != "status_removed":
		_trail(source,target,"status",Color("adcad2"))
	var status := UiStyle.label(str(data.get("status_definition_id", data.get("status_id", ""))))
	if not status.is_empty():
		_feedback(target,("解除 " if kind == "status_removed" else "")+status,Color("c1d0c7"))

func _resource(kind: String, data: Dictionary, source: String, target: String) -> void:
	var resource := str(data.get("resource",kind.trim_suffix("_changed")))
	var delta := int(data.get("delta",int(data.get("after",0))-int(data.get("before",0))))
	if delta == 0 or data.get("reason","") == "pressure_absorbed":
		return
	if resource == "relax" and delta > 0:
		_pilot_cue(target, "guard")
	var names := {"relax":"放松","focus":"专注","synergy":"协同","progress":"论文进度","citations":"引用","modifier":"修正","amplify":"增幅","open":"开题"}
	var glyph := str({"progress":"book","citations":"book","modifier":"book","amplify":"work","synergy":"link","open":"book"}.get(resource,resource))
	if delta > 0:
		_trail(source,target,glyph,UiStyle.GREEN)
	_local(target,"guard_gain" if resource == "relax" and delta > 0 else ("resource_gain" if delta > 0 else "resource_spend"),Color("91c7e8") if resource == "relax" and delta > 0 else (Color("d2c3f0") if delta > 0 else Color("e0b784")))
	_feedback(target,"%s %s%d" % [names.get(resource,resource),"+" if delta > 0 else "−",absi(delta)],Color("b8ead1") if delta > 0 else Color("f0c58c"))

func _feedback(id: String, text: String, color: Color) -> void:
	if not has_actor(id):
		return
	var lane := int(_lanes.get(id,0)) % 3
	_lanes[id] = lane+1
	page._float_event_text(text,target_anchor(id)+Vector2(0,-lane*27),color,1.1)

func _local(id: String, glyph: String, color: Color, direction: Vector2 = Vector2.RIGHT, intensity: float = 1.0, delay: float = 0.0) -> void:
	if not has_actor(id):
		return
	var actor: BattleActorView = page._actors.get(id)
	var actor_size: Vector2 = actor.size if is_instance_valid(actor) else _previous[id].size
	var extent := clampf(minf(actor_size.x,actor_size.y),88,144)
	var effect := BattleSemanticEffectView.new()
	effect.kind = glyph
	effect.ink = color
	effect.direction = direction
	effect.intensity = intensity
	effect.size = Vector2.ONE * extent
	effect.position = target_anchor(id)-effect.size*.5
	effect.z_index = 79
	effect.set_meta("battle_event_effect",true)
	effect.set_meta("effect_target",id)
	effect.set_meta("effect_event_type",_event_type)
	effect.set_meta("effect_event_index",_event_index)
	page._stage.add_child(effect)
	var tween := effect.create_tween()
	page._presentation._tweens.append(tween)
	if delay > 0:
		tween.tween_interval(delay/page.effect_speed())
	tween.tween_property(effect,"progress",1.0,1.0/page.effect_speed())
	tween.tween_callback(effect.queue_free)

func _trail(source: String, target: String, glyph: String, color: Color) -> void:
	# An absent origin never becomes a fictional player attack.
	if source.is_empty() or target.is_empty() or source == target:
		return
	if not has_actor(source) or not has_actor(target):
		return
	var trail := BattleImpactView.new()
	trail.origin = anchor(source)
	trail.destination = target_anchor(target)
	trail.glyph = glyph
	trail.ink = color
	trail.z_index = 80
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.set_meta("battle_event_effect",true)
	trail.set_meta("effect_source",source)
	trail.set_meta("effect_target",target)
	trail.set_meta("effect_event_type",_event_type)
	page._stage.add_child(trail)
	var tween := trail.create_tween()
	page._presentation._tweens.append(tween)
	tween.tween_property(trail,"progress",1.0,.32/page.effect_speed())
	tween.tween_property(trail,"modulate:a",0.0,.35/page.effect_speed())
	tween.tween_callback(trail.queue_free)

func _depart(id: String) -> void:
	var actor := _visible_actor(id)
	if not is_instance_valid(actor) and _previous.has(id):
		var old: Dictionary = _previous[id]
		actor = BattleActorView.new()
		actor.configure(old.definition,old.kind,old.phase)
		actor.size = old.size
		actor.position = old.center-actor.size*.5
		actor.set_meta("battle_event_effect",true)
		page._stage.add_child(actor)
	if not is_instance_valid(actor):
		return
	actor.set_motion(page.animation_enabled)
	actor._fit_rig()
	if is_instance_valid(actor.rig):
		page._presentation._tweens.append(actor.cue("depart", page.effect_speed()))
	var tween := actor.create_tween().set_parallel(true)
	page._presentation._tweens.append(tween)
	tween.tween_property(actor,"hit_strength",1.0,.3/page.effect_speed())
	if is_instance_valid(actor.rig) and actor.rig.refined and page.animation_enabled:
		var duration := actor.rig.action_length("depart") / page.effect_speed()
		tween.tween_property(actor,"modulate:a",0.0,duration * .4).set_delay(duration * .58)
	else:
		tween.tween_property(actor,"modulate:a",0.0,.8/page.effect_speed())


func _visible_actor(id: String) -> BattleActorView:
	var actor: BattleActorView = page._actors.get(id)
	if not is_instance_valid(actor):
		actor = _refined_transients.get(id)
	return actor if is_instance_valid(actor) else null


func impact_feedback_delay(event: Dictionary) -> float:
	var actor := _visible_actor(source_actor(event))
	if is_instance_valid(actor) and is_instance_valid(actor.rig) and actor.rig.refined and page.animation_enabled:
		return actor.rig.seconds_to_contact()
	return 0.0


func _restore_refined_target(id: String) -> void:
	if is_instance_valid(_visible_actor(id)) or not _previous.has(id):
		return
	var old: Dictionary = _previous[id]
	var file := BattleActorView.rig_resource_path(str(old.definition), str(old.kind))
	if file.is_empty():
		return
	var resource: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not resource is Dictionary or int(resource.get("version", 1)) < 2:
		return
	var actor := BattleActorView.new()
	actor.configure(old.definition, old.kind, old.phase)
	actor.size = old.size
	actor.position = old.center - actor.size * .5
	actor.set_meta("battle_event_effect", true)
	page._stage.add_child(actor)
	actor._fit_rig()
	actor.set_motion(page.animation_enabled)
	_refined_transients[id] = actor

func _pilot_cue(id: String, kind: String) -> void:
	var actor: BattleActorView = page._actors.get(id)
	if is_instance_valid(actor) and is_instance_valid(actor.rig):
		cue(id, kind)
