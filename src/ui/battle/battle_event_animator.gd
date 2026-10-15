class_name BattleEventAnimator
extends RefCounted

signal event_presented(event: Dictionary, text: String)
signal queue_finished

var base_delay: float = 0.12
var speed_scale: float = 1.0
var animation_enabled: bool = true:
	set(value):
		animation_enabled = value
		if not value:
			_finish_immediately()
var last_event: Dictionary = {}
var _seen: Dictionary = {}
var _queue: Array[Dictionary] = []
var _remaining: float = 0.0


func play(events: Array, run_id: String, revision: int) -> void:
	var ordinal := 0
	for raw in events:
		var event := _event_dictionary(raw, ordinal)
		var key := "%s/%s/%s" % [run_id, revision, event.get("index", ordinal)]
		ordinal += 1
		if _seen.has(key):
			continue
		_seen[key] = true
		_queue.append({"event": event, "key": key})
	if _queue.is_empty():
		return
	if not animation_enabled:
		_finish_immediately()
	elif _remaining <= 0.0:
		_present_next()


func clear_pending() -> void:
	_queue.clear()
	_remaining = 0.0


func seen_snapshot() -> Array:
	return _seen.keys()


func advance(delta: float) -> void:
	if _queue.is_empty():
		return
	_remaining -= delta * maxf(speed_scale, 0.05)
	if _remaining <= 0.0:
		_present_next()


func pending_count() -> int:
	return _queue.size()


func _present_next() -> void:
	if _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_present(item.event)
	_remaining = maxf(base_delay, 0.0)
	if _queue.is_empty():
		queue_finished.emit()


func _finish_immediately() -> void:
	var had_pending := not _queue.is_empty()
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		_present(item.event)
	_remaining = 0.0
	if had_pending:
		queue_finished.emit()


func _present(event: Dictionary) -> void:
	last_event = event.duplicate(true)
	event_presented.emit(last_event.duplicate(true), _describe(event))


func _event_dictionary(raw: Variant, ordinal: int) -> Dictionary:
	if raw is Dictionary:
		var copied: Dictionary = raw.duplicate(true)
		if not copied.has("index"):
			copied.index = ordinal
		return copied
	if raw is RuleEvent:
		return {
			"index": raw.index,
			"type": String(raw.type),
			"source_id": raw.source_id,
			"target_ids": raw.target_ids.duplicate(),
			"data": raw.data.duplicate(true),
		}
	return {"index": ordinal, "type": "unknown", "source_id": "", "target_ids": [], "data": {}}


func _describe(event: Dictionary) -> String:
	var kind := str(event.get("type", "unknown"))
	var data: Dictionary = event.get("data", {}) if event.get("data", {}) is Dictionary else {}
	var source := str(event.get("source_label", event.get("source_id", "")))
	var targets: Array = event.get("target_labels", event.get("target_ids", []))
	var target_text := "、".join(
		PackedStringArray(targets.map(func(value): return UiStyle.label(str(value))))
	)
	var text := UiStyle.label(kind)
	if not source.is_empty():
		text += " · " + UiStyle.label(source)
	if not target_text.is_empty():
		text += " → " + target_text
	if not data.is_empty():
		var amount: Variant = data.get("amount", data.get("delta", data.get("result", "")))
		if not str(amount).is_empty():
			text += "（%s）" % str(amount)
	return text
