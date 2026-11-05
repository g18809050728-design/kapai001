class_name BattleDamagePopupLayer
extends Control

const POPUP_SIZE := Vector2(100, 44)
const BASE_DELAY := 0.12
const BASE_DURATION := 0.7

var _pending: Array[Dictionary] = []
var _active: Array[Dictionary] = []
var _until_next := 0.0
var _moving := true
var _speed := 1.0
var _target_counts: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


func queue_events(events: Array, anchors: Dictionary, moving: bool, speed: float) -> int:
	var added := 0
	if _pending.is_empty() and _active.is_empty():
		_target_counts.clear()
	_moving = moving
	_speed = maxf(speed, 0.05)
	for raw in events:
		var event: Dictionary = raw if raw is Dictionary else (
			{"type": str(raw.type), "target_ids": raw.target_ids, "data": raw.data}
			if raw is RuleEvent else {}
		)
		if str(event.get("type", "")) != "completion_applied":
			continue
		var data: Dictionary = event.get("data", {})
		var loss := maxi(0, int(data.get("work_before", 0)) - int(data.get("work_after", 0)))
		if loss == 0:
			continue
		var targets: Array = event.get("target_ids", [])
		if targets.is_empty() or not anchors.has(str(targets[0])):
			continue
		var target_id := str(targets[0])
		var ordinal := int(_target_counts.get(target_id, 0))
		_target_counts[target_id] = ordinal + 1
		_pending.append({"text": "-%d" % loss, "anchor": anchors[target_id], "ordinal": ordinal})
		added += 1
	if _active.is_empty() and _until_next <= 0.0:
		_show_next()
	return added


func advance(delta: float) -> void:
	for index in range(_active.size() - 1, -1, -1):
		var item: Dictionary = _active[index]
		item.age += delta
		var label: Label = item.label
		if _moving:
			label.position = item.start_position + Vector2(0, -28 * minf(item.age / item.duration, 1.0))
		label.modulate.a = minf(1.0, (item.duration - item.age) / 0.18)
		if item.age >= item.duration:
			label.queue_free()
			_active.remove_at(index)
	if not _pending.is_empty():
		_until_next -= delta
		if _until_next <= 0.0:
			_show_next()


func active_popup_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _active:
		result.append({"text": item.label.text, "position": item.label.position})
	return result


func clear_popups() -> void:
	_pending.clear()
	_target_counts.clear()
	_until_next = 0.0
	for item in _active:
		item.label.queue_free()
	_active.clear()


func _show_next() -> void:
	if _pending.is_empty():
		return
	var item: Dictionary = _pending.pop_front()
	var label := Label.new()
	label.text = item.text
	label.size = POPUP_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("fff3d9"))
	label.add_theme_color_override("font_shadow_color", Color("7a3030"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	var local_anchor: Vector2 = get_global_transform().affine_inverse() * Vector2(item.anchor)
	var offset := Vector2((int(item.ordinal) % 3 - 1) * 30, -(int(item.ordinal) / 3) * 22)
	var position := local_anchor + offset - Vector2(POPUP_SIZE.x * 0.5, POPUP_SIZE.y)
	position.x = clampf(position.x, 0.0, maxf(0.0, size.x - POPUP_SIZE.x))
	position.y = clampf(position.y, 32.0, maxf(32.0, size.y - POPUP_SIZE.y - 32))
	label.position = position
	add_child(label)
	_active.append({"label": label, "start_position": position, "age": 0.0, "duration": (BASE_DURATION if _moving else 0.4) / _speed})
	_until_next = BASE_DELAY / _speed
