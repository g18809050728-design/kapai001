class_name BattleStageEffects
extends RefCounted

## Events describe completed rules. This layer owns only poses and disposable ink.
var page: BattleScreen
var _previous: Dictionary = {}
var _lanes: Dictionary = {}

func _init(screen: BattleScreen) -> void:
	page = screen

func remember() -> void:
	_previous.clear()
	_lanes.clear()
	for id in page._actors:
		var actor: BattleActorView = page._actors[id]
		if is_instance_valid(actor):
			_previous[id] = {"definition": actor.definition_id, "kind": actor.actor_kind, "phase": actor.phase_index, "center": page._stage_center(actor), "size": actor.size}

func source_actor(event: Dictionary) -> String:
	var source := str(event.get("source_id", ""))
	if page._actors.has(source):
		return source
	return str(page.view.get("effect_sources", {}).get(source, ""))

func anchor(id: String) -> Vector2:
	var actor: BattleActorView = page._actors.get(id)
	if is_instance_valid(actor):
		return page._stage.get_global_transform_with_canvas().affine_inverse() * (actor.get_global_transform_with_canvas() * actor.action_anchor())
	return _previous.get(id, {}).get("center", page._stage.size * Vector2(.18,.4))

func cue(id: String, kind: String) -> void:
	var actor: BattleActorView = page._actors.get(id)
	if is_instance_valid(actor):
		page._presentation._tweens.append(actor.cue(kind,page.effect_speed()))

func present(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	var data: Dictionary = event.get("data", {})
	var targets: Array = event.get("target_ids", [])
	var source := source_actor(event)
	var target := str(targets[0]) if not targets.is_empty() else ""
	match kind:
		"card_played":
			cue(source,"action")
		"completion_applied", "pressure_applied":
			cue(source,"action")
			cue(target,"hit")
			_trail(source,target,"work" if kind == "completion_applied" else "pressure",UiStyle.GOLD if kind == "completion_applied" else UiStyle.RED)
		"relax_changed", "focus_changed", "synergy_changed", "paper_changed":
			_resource(event,data,source,target)
		"status_gained", "status_changed", "status_removed":
			cue(target,"guard")
			_trail(source,target,"status",UiStyle.GREEN)
			var status := UiStyle.label(str(data.get("status_definition_id", data.get("status_id", ""))))
			if not status.is_empty():
				_feedback(target,("解除 " if kind == "status_removed" else "")+status,Color("c1d0c7"))
		"unit_summoned":
			cue(target,"guard")
			_feedback(target,"伙伴加入",UiStyle.GREEN.lightened(.35))
		"unit_departed", "task_completed":
			_depart(target)
		"coop_target_set":
			cue(source,"action")
			_trail(source,target,"link",UiStyle.GREEN)
		"chapter_deployed", "chapter_ran", "chapter_returned", "chapter_slots_swapped", "paper_published", "v3_ability_registered", "task_transformed":
			var player := str(page.view.get("player",{}).get("entity_id",""))
			cue(target if not target.is_empty() else player,"guard")
			_feedback(target if not target.is_empty() else player,UiStyle.label(kind),UiStyle.GOLD)

func _resource(event: Dictionary, data: Dictionary, source: String, target: String) -> void:
	var resource := str(data.get("resource",str(event.type).trim_suffix("_changed")))
	var delta := int(data.get("delta",int(data.get("after",0))-int(data.get("before",0))))
	if delta == 0:
		return
	cue(target,"guard" if resource == "relax" and delta > 0 else "action")
	if data.get("reason","") == "pressure_absorbed":
		return # pressure_applied already shows the absorbed value.
	var names := {"relax":"放松","focus":"专注","synergy":"协同","progress":"论文进度","citations":"引用","modifier":"修正","amplify":"增幅","open":"开题"}
	var glyph := str({"progress":"book","citations":"book","modifier":"book","amplify":"work","synergy":"link","open":"book"}.get(resource,resource))
	if delta > 0:
		_trail(source,target,glyph,UiStyle.GREEN)
	_feedback(target,"%s %s%d" % [names.get(resource,resource),"+" if delta > 0 else "−",absi(delta)],Color("b8ead1") if delta > 0 else Color("f0c58c"))

func _feedback(id: String, text: String, color: Color) -> void:
	var lane := int(_lanes.get(id,0)) % 3
	_lanes[id] = lane+1
	page._float_event_text(text,anchor(id)+Vector2(0,-lane*27),color,1.1)

func _trail(source: String, target: String, glyph: String, color: Color) -> void:
	# An absent origin never becomes a fictional player attack.
	if source.is_empty() or target.is_empty() or source == target:
		return
	if not page._actors.has(source) and not _previous.has(source):
		return
	if not page._actors.has(target) and not _previous.has(target):
		return
	var trail := BattleImpactView.new()
	trail.origin = anchor(source)
	trail.destination = anchor(target)
	trail.glyph = glyph
	trail.ink = color
	trail.z_index = 80
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.set_meta("battle_event_effect",true)
	page._stage.add_child(trail)
	var tween := trail.create_tween()
	page._presentation._tweens.append(tween)
	tween.tween_property(trail,"progress",1.0,.32/page.effect_speed())
	tween.tween_property(trail,"modulate:a",0.0,.35/page.effect_speed())
	tween.tween_callback(trail.queue_free)

func _depart(id: String) -> void:
	var actor: BattleActorView = page._actors.get(id)
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
	var tween := actor.create_tween().set_parallel(true)
	page._presentation._tweens.append(tween)
	tween.tween_property(actor,"hit_strength",1.0,.3/page.effect_speed())
	tween.tween_property(actor,"modulate:a",0.0,.8/page.effect_speed())
