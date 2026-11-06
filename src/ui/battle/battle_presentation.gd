class_name BattlePresentation
extends RefCounted

# Presentation staging never writes to the session or rules.
var page: Control
var _saved: Dictionary = {}
var _departing: Dictionary = {}
var _departed: Dictionary = {}
var _pending: Dictionary = {}
var _flights: Dictionary = {}
var _tweens: Array[Tween] = []


func _init(screen: Control) -> void:
	page = screen


func capture_hand(source: Control, card_ids: Variant = null) -> void:
	for uid in source._buttons:
		if not str(uid).begins_with("card:"):
			continue
		if card_ids is Array and not str(uid).trim_prefix("card:") in card_ids:
			continue
		var card: Control = source._buttons[uid]
		var pose := {"center": source._stage_center(card), "size": card.size, "scale": card.scale, "rotation": card.rotation}
		card.get_parent().remove_child(card)
		_saved[str(uid).trim_prefix("card:")] = {"card": card, "pose": pose}


func release_unused() -> void:
	for entry in _saved.values():
		if is_instance_valid(entry.card):
			entry.card.queue_free()
	_saved.clear()


func prepare(events: Array) -> void:
	if events.is_empty():
		return
	if not page.animation_enabled:
		release_unused()
		return
	var staged_tasks := {}
	for event in events:
		var kind := str(event.get("type", ""))
		var id := card_id(event)
		if kind == "card_drawn":
			_pending[id] = int(_pending.get(id, 0)) + 1
		elif kind in ["card_played", "card_discarded", "card_exhausted", "card_resolved"] and _saved.has(id):
			var entry: Dictionary = _saved[id]
			_saved.erase(id)
			var card: Control = entry.card
			page._stage.add_child(card)
			card.pivot_offset = card.size * 0.5
			card.position = entry.pose.center - card.size * 0.5
			card.scale = entry.pose.scale
			card.rotation = entry.pose.rotation
			card.z_index = 175
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.focus_mode = Control.FOCUS_NONE
			card.set_meta("battle_event_effect", true)
			card.set_meta("event_card_id", id)
			_departing[id] = card
		if kind == "completion_applied":
			var targets: Array = event.get("target_ids", [])
			if not targets.is_empty() and not staged_tasks.has(str(targets[0])):
				var task_id := str(targets[0])
				staged_tasks[task_id] = true
				var data: Dictionary = event.get("data", {})
				set_meter(task_id, float(data.get("work_before", 0)), int(data.get("shield_before", 0)))
	for id in _pending:
		var card: Control = page._hand_card_control(id)
		if is_instance_valid(card):
			card.modulate.a = 0.0
			card.set_meta("draw_pending", true)
			card.set_meta("draw_mouse", card.mouse_filter)
			card.set_meta("draw_focus", card.focus_mode)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.focus_mode = Control.FOCUS_NONE
	release_unused()


func is_pending(id: String) -> bool:
	return _pending.has(id)


func pending_ids() -> Array:
	return _pending.keys()


func card_id(event: Dictionary) -> String:
	var targets: Array = event.get("target_ids", [])
	if str(event.get("type", "")) in ["card_drawn", "card_discarded", "card_exhausted"] and not targets.is_empty():
		return str(targets[0])
	return str(event.get("source_id", ""))


func show_played(event: Dictionary) -> void:
	var card: Control = _departing.get(card_id(event))
	if is_instance_valid(card):
		var tween := card.create_tween()
		_tweens.append(tween)
		tween.tween_property(card, "modulate", Color("ffe2a1"), 0.10 / page.effect_speed())
		tween.tween_property(card, "modulate", Color.WHITE, 0.12 / page.effect_speed())


func draw(event: Dictionary) -> void:
	# Container geometry settles before rendering this frame.
	_begin_draw.call_deferred(event)


func _begin_draw(event: Dictionary) -> void:
	var id := card_id(event)
	if not _pending.has(id) or not is_instance_valid(page._stage):
		return
	# A slow frame may consume the next event interval before the Tween gets
	# its frame. Land the preceding card before showing the next one.
	for previous_id in _flights.keys():
		_land(previous_id)
	_departed.erase(id)
	var card: Control = page._hand_card_control(id) if int(_pending[id]) == 1 else null
	var transient := not is_instance_valid(card)
	if transient:
		card = _new_card(event)
		if card == null:
			_pending.erase(id)
			return
		page._stage.add_child(card)
		card.position = page._stage.size * Vector2(0.5, 0.78) - card.size * 0.5
	var parent := card.get_parent()
	var index := card.get_index()
	var destination: Vector2 = page._stage_center(card)
	var home := {"parent": parent, "index": index, "position": card.position, "size": card.size, "rotation": card.rotation, "scale": card.scale, "pivot": card.pivot_offset, "z": card.z_index, "mouse": card.mouse_filter, "focus": card.focus_mode, "transient": transient}
	home.mouse = card.get_meta("draw_mouse", home.mouse)
	home.focus = card.get_meta("draw_focus", home.focus)
	if parent is Container:
		var placeholder := Control.new()
		placeholder.custom_minimum_size = card.size
		placeholder.size_flags_horizontal = card.size_flags_horizontal
		placeholder.size_flags_vertical = card.size_flags_vertical
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(placeholder)
		parent.move_child(placeholder, index)
		home.placeholder = placeholder
		card.reparent(page._stage)
	_flights[id] = {"card": card, "home": home}
	card.pivot_offset = card.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	card.modulate = Color.WHITE
	card.z_index = 180
	card.set_meta("card_in_flight", true)
	card.set_meta("event_card_id", id)
	card.set_meta("battle_event_effect", true)
	var start: Vector2 = page._zone_center("draw", page._stage.size * Vector2(0.08, 0.88))
	card.position = start - card.size * 0.5
	card.scale = Vector2.ONE * 0.82
	card.rotation = -0.12
	card.set_meta("motion_from", start)
	card.set_meta("motion_to", destination)
	var tween := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)
	var duration: float = 0.50 / page.effect_speed()
	_flights[id].tween = tween
	tween.tween_property(card, "position", destination - card.size * 0.5, duration)
	tween.tween_property(card, "scale", home.scale, duration)
	tween.tween_property(card, "rotation", home.rotation, duration)
	tween.chain().tween_callback(_land.bind(id))


func _land(id: String) -> void:
	if not _flights.has(id):
		return
	var entry: Dictionary = _flights[id]
	_flights.erase(id)
	var card: Control = entry.card
	var home: Dictionary = entry.home
	if entry.has("tween") and entry.tween.is_valid():
		entry.tween.kill()
	if not is_instance_valid(card):
		return
	if is_instance_valid(home.get("placeholder")):
		var placeholder: Control = home.placeholder
		placeholder.get_parent().remove_child(placeholder)
		placeholder.queue_free()
		card.reparent(home.parent)
		home.parent.move_child(card, mini(int(home.index), home.parent.get_child_count() - 1))
	card.position = home.position
	card.size = home.size
	card.rotation = home.rotation
	card.scale = home.scale
	card.pivot_offset = home.pivot
	card.z_index = home.z
	card.mouse_filter = home.mouse
	card.focus_mode = home.focus
	card.remove_meta("card_in_flight")
	card.remove_meta("battle_event_effect")
	card.remove_meta("draw_pending")
	card.remove_meta("draw_mouse")
	card.remove_meta("draw_focus")
	_pending[id] = int(_pending.get(id, 1)) - 1
	if int(_pending[id]) <= 0:
		_pending.erase(id)
	if _pending.is_empty():
		page._feedback_text = "抽牌完成"
		if is_instance_valid(page._feedback_label):
			page._feedback_label.text = page._feedback_text
	if home.transient:
		_departing[id] = card
		card.set_meta("battle_event_effect", true)


func move_out(event: Dictionary, destination: String) -> void:
	var id := card_id(event)
	if _departed.has(id):
		return
	_departed[id] = true
	var card: Control = _departing.get(id)
	_departing.erase(id)
	if not is_instance_valid(card):
		card = _new_card(event)
		if card == null:
			return
		page._stage.add_child(card)
		card.position = page._previous_card_centers.get(id, page._stage.size * Vector2(0.5, 0.76)) - card.size * 0.5
	card.pivot_offset = card.size * 0.5
	card.set_meta("battle_event_effect", true)
	card.set_meta("event_card_id", id)
	card.set_meta("card_in_flight", true)
	card.set_meta("motion_from", page._stage_center(card))
	card.set_meta("motion_to", page._zone_center(destination, page._stage.size * Vector2(0.95, 0.88)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 180
	var tween := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tweens.append(tween)
	var duration: float = 0.46 / page.effect_speed()
	tween.tween_property(card, "position", card.get_meta("motion_to") - card.size * 0.5, duration)
	tween.tween_property(card, "scale", Vector2.ONE * 0.20, duration)
	tween.tween_property(card, "rotation", 0.18, duration)
	tween.chain().tween_callback(card.queue_free)


func _new_card(event: Dictionary) -> BattleCard:
	var id := card_id(event)
	var definition := str(event.get("data", {}).get("definition_id", ""))
	var data: Dictionary = page._run_card_entry(id, definition)
	if data.is_empty():
		return null
	var card := BattleCard.new()
	card.configure(data)
	return card


func animate_meter(id: String, data: Dictionary) -> void:
	set_meter(id, float(data.get("work_before", 0)), int(data.get("shield_before", 0)))
	var tween: Tween = page._stage.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)
	tween.tween_method(func(value: float): set_meter(id, value, int(data.get("shield_after", 0))), float(data.get("work_before", 0)), float(data.get("work_after", 0)), 0.90 / page.effect_speed())


func set_meter(id: String, remaining: float, shield: int) -> void:
	var meter: Dictionary = page._task_meters.get(id, {})
	if meter.is_empty():
		return
	var maximum: int = meter.maximum
	var fill: Control = meter.fill
	if fill is ProgressBar:
		fill.value = remaining
	else:
		fill.size.x = float(meter.width) * clampf(remaining / maxi(1, maximum), 0, 1)
	meter.label.text = "剩余 %s/%s · 屏障 %s" % [ceili(remaining), maximum, shield]
	meter.label.set_meta("displayed_work", remaining)


func is_animating() -> bool:
	for tween in _tweens:
		if tween.is_valid() and tween.is_running():
			return true
	return false


func finish() -> void:
	page._animator.clear_pending()
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for id in _flights.keys():
		_land(id)
	for id in _pending:
		var card: Control = page._hand_card_control(id)
		if is_instance_valid(card):
			card.modulate.a = 1.0
			card.mouse_filter = card.get_meta("draw_mouse", card.mouse_filter)
			card.focus_mode = card.get_meta("draw_focus", card.focus_mode)
			card.remove_meta("draw_pending")
			card.remove_meta("draw_mouse")
			card.remove_meta("draw_focus")
	_pending.clear()
	for card in _departing.values():
		if is_instance_valid(card):
			card.queue_free()
	_departing.clear()
	_departed.clear()
	release_unused()
	page._clear_event_visuals()
	for task in page.view.get("tasks", []):
		set_meter(str(task.task_id), float(task.work_remaining), int(task.shield))
