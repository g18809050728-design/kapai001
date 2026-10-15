class_name BattleScreen
extends UiPage

var preview_callback: Callable = Callable()
var animation_enabled: bool = true
var speed_scale: float = 1.0

var _animator: BattleEventAnimator
var _feedback_text: String = ""
var _feedback_label: Label
var _panel_text: String = ""
var _selected_card_id: String = ""
var _selected_unit_id: String = ""
var _target_ids: Array[String] = []
var _replace_unit_id: String = ""
var _choice_selected_ids: Array[String] = []
var _retained_card_ids: Array[String] = []
var _active_preview: Variant = null
var _preview_draft: Dictionary = {}
var _revision_seen: int = -1
var _choice_id_seen: String = ""
var _submitted_revision: int = -2
var _stage: Control
var _hand_cards: Array[BattleCard] = []
var _target_frames: Dictionary = {}
var _aim: BattleAim
var _tip_label: Label
var _hint_label: Label
var _hovered_card: BattleCard
var _pointer_card: BattleCard
var _pointer_start := Vector2.ZERO
var _dragging: bool = false
var _drag_ghost: BattleCard
var _pointer_position := Vector2.ZERO


func _init() -> void:
	_animator = BattleEventAnimator.new()
	_animator.event_presented.connect(_on_event_presented)


func _process(delta: float) -> void:
	_animator.advance(delta)
	_update_pointer(delta)


func render(data: Dictionary) -> void:
	var next_view := data.duplicate(true)
	var next_revision := int(next_view.get("revision", -1))
	var next_choice := _choice_dict(next_view.get("pending_choice"))
	var next_choice_id := str(next_choice.get("choice_id", ""))
	if next_choice_id != _choice_id_seen:
		_choice_selected_ids.clear()
	_choice_id_seen = next_choice_id
	if next_revision != _revision_seen and next_revision >= 0:
		_selected_card_id = ""
		_selected_unit_id = ""
		_target_ids.clear()
		_replace_unit_id = ""
		_active_preview = null
		_preview_draft = {}
	_revision_seen = next_revision
	_submitted_revision = -2
	view = next_view
	_render_battle()


func consume_events(events: Array, run_id: String, revision: int) -> void:
	_animator.animation_enabled = animation_enabled
	_animator.speed_scale = speed_scale
	var snapshots: Dictionary = {}
	for entry in _array(view.get("event_log")):
		if str(entry.get("run_id", "")) == run_id and int(entry.get("revision", -1)) == revision:
			snapshots[int(entry.get("index", -1))] = entry
	var presented: Array = []
	for ordinal in events.size():
		var event: Variant = events[ordinal]
		var index: int = int(event.get("index", ordinal)) if event is Dictionary else event.index
		presented.append(snapshots.get(index, event))
	_animator.play(presented, run_id, revision)


func is_locked() -> bool:
	return not _choice_dict(view.get("pending_choice")).is_empty()


func lock_snapshot() -> Dictionary:
	return {
		"pending": is_locked(),
		"hand": _locked("card:"),
		"tasks": _locked("task:"),
		"units": _locked("unit:"),
		"end_turn": button_disabled("battle:end_turn"),
		"decks":
		(
			button_disabled("battle:deck")
			or button_disabled("battle:draw")
			or button_disabled("battle:discard")
			or button_disabled("battle:exhaust")
		),
		"rules": button_disabled("battle:rules"),
		"animation": button_disabled("battle:animation"),
		"cancel": button_disabled("battle:cancel"),
		"save": button_disabled("battle:save"),
		"menu": button_disabled("battle:menu"),
	}


func draw_pile_card_ids() -> Array:
	return []


func selection_snapshot() -> Dictionary:
	return {
		"card_id": _selected_card_id,
		"unit_id": _selected_unit_id,
		"target_ids": _target_ids.duplicate(),
		"replace_unit_id": _replace_unit_id,
		"choice_selected_ids": _choice_selected_ids.duplicate(),
		"retained_card_ids": _retained_card_ids.duplicate(),
	}


func display_snapshot() -> Dictionary:
	return {
		"zone_counts": _dict(view.get("zone_counts")),
		"zones_public": _dict(view.get("zones_public")),
		"event_log": _array(view.get("event_log")).duplicate(true),
		"feedback": _feedback_text,
		"panel": _panel_text,
		"seen_events": _animator.seen_snapshot(),
	}


func apply_gating(results: Dictionary) -> void:
	super.apply_gating(results)
	_apply_lock_state()
	_sync_card_visuals()


func action_draft(uid: String) -> Dictionary:
	var draft := super.action_draft(uid)
	if is_locked() and str(draft.get("type", "")) not in ["confirm_choice", "ui.new_run"]:
		return {}
	return draft


func _render_battle() -> void:
	BattleLayout.new().build(self)


func _reset_stage() -> void:
	_pointer_card = null
	_hovered_card = null
	_drag_ghost = null
	_dragging = false
	_hand_cards.clear()
	_target_frames.clear()
	_buttons.clear()
	_drafts.clear()
	_last_action.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stage = Control.new()
	_stage.size = Vector2(1280, 800)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	if not resized.is_connected(_fit_stage):
		resized.connect(_fit_stage)


func _fit_stage() -> void:
	if not is_instance_valid(_stage):
		return
	var factor := minf(size.x / 1280.0, size.y / 800.0)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (size - Vector2(1280, 800) * factor) * 0.5


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_stage):
		return
	if event is InputEventMouse:
		_pointer_position = event.position
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_locked():
			return
		if not _panel_text.is_empty():
			_close_panel()
		else:
			_cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if not is_locked() and _panel_text.is_empty():
			_cancel_selection()
			get_viewport().set_input_as_handled()
		return
	if is_locked() or not _panel_text.is_empty():
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and not event.ctrl_pressed
		and not event.alt_pressed
		and not event.meta_pressed
		and event.keycode >= KEY_1
		and event.keycode <= KEY_9
	):
		var index := int(event.keycode) - int(KEY_1)
		if index < _hand_cards.size():
			var card := _hand_cards[index]
			if card.disabled:
				_feedback_text = card.tooltip_text
				_feedback_label.text = _feedback_text
				_feedback_label.visible = true
			else:
				_on_card_pressed(str(card.card_data.get("card_id", "")))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card := _card_at(event.position)
			if card != null:
				if card.disabled:
					_tip_label.text = card.tooltip_text
				else:
					_pointer_card = card
					_pointer_start = event.position
				get_viewport().set_input_as_handled()
		elif is_instance_valid(_pointer_card):
			get_viewport().set_input_as_handled()
			var card_id := str(_pointer_card.card_data.get("card_id", ""))
			if _dragging:
				_finish_drag(event.position)
			else:
				_pointer_card = null
				_on_card_pressed(card_id)
	elif event is InputEventMouseMotion and is_instance_valid(_pointer_card):
		if not _dragging and event.position.distance_to(_pointer_start) > 10:
			_begin_drag()
		if _dragging:
			_move_drag(event.position)
		get_viewport().set_input_as_handled()


func _card_at(point: Vector2) -> BattleCard:
	if is_instance_valid(_hovered_card) and _hovered_card.contains_global(point):
		return _hovered_card
	for index in range(_hand_cards.size() - 1, -1, -1):
		if _hand_cards[index].contains_home(point):
			return _hand_cards[index]
	return null


func _update_pointer(delta: float) -> void:
	if not is_instance_valid(_stage):
		return
	if not _dragging and not is_locked() and _panel_text.is_empty():
		_hovered_card = _card_at(_pointer_position)
	else:
		_hovered_card = null
	if is_instance_valid(_tip_label) and not is_instance_valid(_pointer_card):
		_tip_label.text = _hovered_card.tooltip_text if is_instance_valid(_hovered_card) else ""
	for card in _hand_cards:
		var raised := card == _hovered_card or card.selected
		var destination := card.home_position + (Vector2(0, -60) if raised else Vector2.ZERO)
		card.position = card.position.lerp(destination, minf(1, delta * 18))
		card.rotation = lerp_angle(
			card.rotation, 0.0 if raised else card.home_rotation, minf(1, delta * 18)
		)
		card.scale = card.scale.lerp(Vector2.ONE * (1.16 if raised else 1.0), minf(1, delta * 18))
		card.z_index = 60 if raised else card.home_order
		card.highlighted = raised
		card.queue_redraw()
	if is_instance_valid(_aim):
		_aim.visible = (
			not _selected_card_id.is_empty() and not is_locked() and _panel_text.is_empty()
		)
		if _aim.visible:
			_aim.origin = Vector2(640, 573)
			_aim.destination = (
				_stage.get_global_transform_with_canvas().affine_inverse() * _pointer_position
			)
			_aim.valid_target = not _target_at(_pointer_position).is_empty()
			_aim.queue_redraw()


func _begin_drag() -> void:
	_dragging = true
	_selected_card_id = str(_pointer_card.card_data.get("card_id", ""))
	_selected_unit_id = ""
	_target_ids.clear()
	_replace_unit_id = ""
	_preview_draft = {
		"type": "play_card",
		"payload":
		{"card_instance_id": _selected_card_id, "target_ids": [], "replace_unit_id": null}
	}
	_active_preview = _preview(_preview_draft)
	_drag_ghost = BattleCard.new()
	_drag_ghost.configure(_pointer_card.card_data, true)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 90
	_drag_ghost.scale = Vector2.ONE * 0.85
	_stage.add_child(_drag_ghost)
	_pointer_card.modulate.a = 0.3
	_apply_preview_gating()
	_sync_card_visuals()
	_hint_label.text = "松手出牌 · 拖回手牌区域或右键取消"
	_move_drag(_pointer_position)


func _move_drag(point: Vector2) -> void:
	if is_instance_valid(_drag_ghost):
		var local := _stage.get_global_transform_with_canvas().affine_inverse() * point
		_drag_ghost.position = local - Vector2(84, 170)
		_drag_ghost.modulate.a = 0.9


func _target_at(point: Vector2) -> String:
	for uid in _target_frames:
		var button: Button = _buttons[uid]
		if not button.disabled and button.get_global_rect().has_point(point):
			return str(uid)
	return ""


func _finish_drag(point: Vector2) -> void:
	var local := _stage.get_global_transform_with_canvas().affine_inverse() * point
	var target := _target_at(point)
	_pointer_card = null
	_dragging = false
	if is_instance_valid(_drag_ghost):
		_stage.remove_child(_drag_ghost)
		_drag_ghost.queue_free()
	_drag_ghost = null
	if local.y >= 540 or not Rect2(0, 66, 1280, 474).has_point(local):
		_cancel_selection()
		return
	if target.begins_with("task:"):
		_on_task_pressed(target.trim_prefix("task:"))
	elif target.begins_with("unit:"):
		_on_unit_pressed(target.trim_prefix("unit:"))
	elif _preview_can_submit(_active_preview) and _required(_active_preview).is_empty():
		_emit_draft(_preview_draft)
	else:
		_cancel_selection()


func _sync_card_visuals() -> void:
	for card in _hand_cards:
		card.selected = str(card.card_data.get("card_id", "")) == _selected_card_id
		card.queue_redraw()
	for uid in _target_frames:
		var frame: Panel = _target_frames[uid]
		var active: bool = (
			not _buttons[uid].disabled
			and (not _selected_card_id.is_empty() or not _selected_unit_id.is_empty())
		)
		var style := UiStyle.box(Color("eee7d7"))
		style.border_color = Color("f3d38a") if active else Color("b5ab8b")
		style.set_border_width_all(4 if active else 2)
		if active:
			style.shadow_color = Color(0.95, 0.81, 0.42, 0.4)
			style.shadow_size = 12
		frame.add_theme_stylebox_override("panel", style)


func _on_card_pressed(card_id: String) -> void:
	if is_locked():
		return
	_selected_card_id = card_id
	_selected_unit_id = ""
	_target_ids.clear()
	_replace_unit_id = ""
	_preview_draft = {
		"type": "play_card",
		"payload": {"card_instance_id": card_id, "target_ids": [], "replace_unit_id": null}
	}
	_active_preview = _preview(_preview_draft)
	if _preview_can_submit(_active_preview) and _required(_active_preview).is_empty():
		_emit_draft(_preview_draft)
		return
	_feedback_text = _preview_error(_active_preview)
	_render_from_local()


func _on_task_pressed(task_id: String) -> void:
	if is_locked():
		return
	if not _selected_card_id.is_empty():
		_target_ids = [task_id]
		_preview_draft.payload.target_ids = _target_ids.duplicate()
		_try_complete_preview()
	elif not _selected_unit_id.is_empty():
		_emit_draft(
			{
				"type": "set_ally_target",
				"payload": {"unit_instance_id": _selected_unit_id, "task_instance_id": task_id}
			}
		)


func _on_unit_pressed(unit_id: String) -> void:
	if is_locked():
		return
	if not _selected_card_id.is_empty():
		if _selection_kind() == "replace_unit_id":
			_replace_unit_id = unit_id
			_preview_draft.payload.replace_unit_id = unit_id
		else:
			_target_ids = [unit_id]
			_preview_draft.payload.target_ids = _target_ids.duplicate()
		_try_complete_preview()
	else:
		_selected_unit_id = unit_id
		_selected_card_id = ""
		_render_from_local()


func _try_complete_preview() -> void:
	_active_preview = _preview(_preview_draft)
	if _preview_can_submit(_active_preview) and _required(_active_preview).is_empty():
		_emit_draft(_preview_draft)
	else:
		_feedback_text = _preview_error(_active_preview)
		_render_from_local()


func _emit_draft(draft: Dictionary) -> void:
	if is_locked() and str(draft.get("type", "")) != "confirm_choice":
		return
	if _submitted_revision == int(view.get("revision", -1)):
		return
	var quote: Variant = _preview(draft)
	if not _preview_can_submit(quote):
		_feedback_text = _preview_error(quote)
		_render_from_local()
		return
	_feedback_text = ""
	_last_action = draft.duplicate(true)
	_submitted_revision = int(view.get("revision", -1))
	action_requested.emit(draft.duplicate(true))


func _cancel_selection() -> void:
	if is_locked():
		return
	_selected_card_id = ""
	_selected_unit_id = ""
	_target_ids.clear()
	_replace_unit_id = ""
	_active_preview = null
	_preview_draft = {}
	_feedback_text = ""
	_render_from_local()
	local_selection_changed.emit(selection_snapshot())


func _on_choice_pressed(id: String) -> void:
	if not is_locked():
		return
	var choice := _choice_dict(view.get("pending_choice"))
	var max_count := int(choice.get("max_count", 0))
	if _choice_selected_ids.has(id):
		_choice_selected_ids.erase(id)
	elif _choice_selected_ids.size() < max_count:
		_choice_selected_ids.append(id)
	_render_from_local()
	local_selection_changed.emit(selection_snapshot())


func _choice_draft() -> Callable:
	return func() -> Dictionary:
		var choice := _choice_dict(view.get("pending_choice"))
		return {
			"type": "confirm_choice",
			"payload":
			{
				"choice_id": str(choice.get("choice_id", "")),
				"selected_ids": _choice_selected_ids.duplicate()
			}
		}


func _end_turn_draft() -> Callable:
	return func() -> Dictionary:
		if is_locked():
			return {}
		return {
			"type": "end_turn", "payload": {"retained_card_ids": _retained_card_ids.duplicate()}
		}


func _preview(draft: Dictionary) -> Variant:
	if not preview_callback.is_valid():
		return null
	return preview_callback.call(draft.duplicate(true))


func _preview_can_submit(value: Variant) -> bool:
	if value is ActionPreview:
		return value.can_submit
	if value is Dictionary:
		return bool(value.get("can_submit", false))
	return false


func _required(value: Variant) -> Array:
	if value is ActionPreview:
		return value.required_selections
	if value is Dictionary:
		return _array(value.get("required_selections"))
	return []


func _preview_error(value: Variant) -> String:
	if value is ActionPreview and not value.blocking_errors.is_empty():
		return _error_text(value.blocking_errors[0])
	if value is Dictionary:
		var errors := _array(value.get("blocking_errors"))
		if not errors.is_empty():
			return _error_text(errors[0])
	return "请选择可用目标后继续。"


func _error_text(value: Variant) -> String:
	if value is ApiError:
		return UiStyle.error_text(value)
	if value is Dictionary:
		return "%s · %s" % [value.get("code", "ERROR"), value.get("message_key", "操作不可用")]
	return str(value)


func _apply_lock_state() -> void:
	if not is_locked():
		return
	for uid in button_uids():
		if str(uid).begins_with("choice:"):
			continue
		_buttons[uid].disabled = true
		_buttons[uid].tooltip_text = "请先完成当前选择"
	# Candidate buttons remain enabled; only the quantity gate disables confirm.
	var choice := _choice_dict(view.get("pending_choice"))
	if _buttons.has("choice:confirm"):
		var valid := (
			_choice_selected_ids.size() >= int(choice.get("min_count", 0))
			and _choice_selected_ids.size() <= int(choice.get("max_count", 0))
		)
		if not valid:
			_buttons["choice:confirm"].disabled = true


func _apply_preview_gating() -> void:
	if is_locked():
		var confirm_quote: Variant = _preview(action_draft("choice:confirm"))
		_set_enabled(
			"choice:confirm", _preview_can_submit(confirm_quote), _preview_error(confirm_quote)
		)
		return
	for value in _array(view.get("hand")):
		var card := _dict(value)
		var id := str(card.get("card_id", ""))
		var quote: Variant = _preview(
			{
				"type": "play_card",
				"payload": {"card_instance_id": id, "target_ids": [], "replace_unit_id": null}
			}
		)
		_set_enabled("card:" + id, _may_select(quote), _preview_error(quote))
	var end_quote: Variant = _preview(action_draft("battle:end_turn"))
	_set_enabled("battle:end_turn", _preview_can_submit(end_quote), _preview_error(end_quote))
	var selection_field := _selection_kind()
	var candidates := _selection_candidate_ids(selection_field)
	for value in _array(view.get("tasks")):
		var task := _dict(value)
		var id := str(task.get("task_id", ""))
		var allowed := false
		var reason := "请先选择需要目标的卡牌或协作单位"
		if not _selected_card_id.is_empty():
			allowed = selection_field == "target_ids" and candidates.has(id)
		elif not _selected_unit_id.is_empty():
			var quote: Variant = _preview(
				{
					"type": "set_ally_target",
					"payload": {"unit_instance_id": _selected_unit_id, "task_instance_id": id}
				}
			)
			allowed = _preview_can_submit(quote)
			reason = _preview_error(quote)
		_set_enabled("task:" + id, allowed, reason)
	for value in _array(view.get("units")):
		var unit := _dict(value)
		var id := str(unit.get("unit_id", ""))
		var allowed := false
		var reason := "当前不能选择此单位"
		if not _selected_card_id.is_empty():
			allowed = selection_field in ["target_ids", "replace_unit_id"] and candidates.has(id)
		else:
			# This button only selects a unit locally; task buttons preview
			# complete commands before enabling rule submission.
			allowed = true
			reason = "点击后选择要协作的任务"
		_set_enabled("unit:" + id, allowed, reason)
	_set_enabled("battle:save", bool(view.get("can_save", true)), "请先完成当前选择")


func _selection_kind() -> String:
	for value in _required(_active_preview):
		var selection := _dict(value)
		var field := str(selection.get("field", ""))
		if field in ["target_ids", "replace_unit_id"]:
			return field
	return ""


func _selection_candidate_ids(field: String) -> Array[String]:
	var result: Array[String] = []
	for value in _required(_active_preview):
		var selection := _dict(value)
		if str(selection.get("field", "")) != field:
			continue
		for candidate_value in _array(selection.get("candidates")):
			result.append(str(_dict(candidate_value).get("id", "")))
	return result


func _may_select(quote: Variant) -> bool:
	if _preview_can_submit(quote):
		return true
	if _required(quote).is_empty():
		return false
	var errors: Array = []
	if quote is ActionPreview:
		errors = quote.blocking_errors
	elif quote is Dictionary:
		errors = _array(quote.get("blocking_errors"))
	for error in errors:
		var code := String(error.code) if error is ApiError else str(_dict(error).get("code", ""))
		if code != "INVALID_TARGET":
			return false
	return true


func _set_enabled(uid: String, enabled: bool, reason: String) -> void:
	if _buttons.has(uid):
		_buttons[uid].disabled = not enabled
		_buttons[uid].tooltip_text = "" if enabled else reason
		if _buttons[uid] is BattleCard:
			var card: BattleCard = _buttons[uid]
			var face := _dict(card.card_data.get("face", card.card_data.get("effective_card", {})))
			card.tooltip_text = (
				("" if enabled else reason + "  ·  ")
				+ UiStyle.describe_effects(_array(face.get("effects")))
				+ (
					"  ·  专注 %s / 精力 %s（主动支付，绕过放松）"
					% [
						card.card_data.get("effective_cost", 0),
						card.card_data.get("effective_vitality_cost", 0)
					]
				)
			)


func _render_from_local() -> void:
	var current := view.duplicate(true)
	render(current)


func _on_event_presented(_event: Dictionary, text: String) -> void:
	_feedback_text = text
	if is_instance_valid(_feedback_label):
		_feedback_label.text = text
		_feedback_label.visible = true


func _toggle_animation() -> void:
	if is_locked():
		return
	animation_enabled = not animation_enabled
	_animator.animation_enabled = animation_enabled
	_render_from_local()


func _cycle_speed() -> void:
	if is_locked():
		return
	speed_scale = 1.0 if speed_scale >= 2.0 else (2.0 if speed_scale >= 1.5 else 1.5)
	_animator.speed_scale = speed_scale
	_render_from_local()


func _show_draw() -> void:
	_panel_text = "抽牌堆只公开数量：%s 张。" % _dict(view.get("zone_counts")).get("draw", 0)
	_render_from_local()


func _show_deck() -> void:
	if is_locked():
		return
	var cards := _array(view.get("cards")).duplicate(true)
	cards.sort_custom(
		func(a, b):
			return (
				"%s|%s" % [a.get("definition_id", ""), a.get("card_id", "")]
				< "%s|%s" % [b.get("definition_id", ""), b.get("card_id", "")]
			)
	)
	var lines: Array[String] = ["本局牌组 · %s 张" % cards.size(), "按卡牌整理；费用与效果为牌组基础值。"]
	for value in cards:
		var card := _dict(value)
		lines.append(
			(
				"%s%s\n%s"
				% [
					UiStyle.label(str(card.get("definition_id", ""))),
					" +%s" % card.upgrade_level if int(card.get("upgrade_level", 0)) > 0 else "",
					UiContentText.describe_card(_dict(card.get("detail")))
				]
			)
		)
	lines.append("携带饰品 · %s 件" % _array(view.get("relics")).size())
	for value in _array(view.get("relics")):
		var relic := _dict(value)
		lines.append(
			(
				"%s\n%s"
				% [
					UiStyle.label(str(relic.get("definition_id", ""))),
					UiContentText.describe_relic(_dict(relic.get("detail")))
				]
			)
		)
	_panel_text = "\n\n".join(lines)
	_render_from_local()


func _show_discard() -> void:
	_panel_text = _zone_details("discard", "弃牌堆")
	_render_from_local()


func _show_exhaust() -> void:
	_panel_text = _zone_details("exhaust", "消耗堆")
	_render_from_local()


func _show_rules() -> void:
	_panel_text = "点击或拖拽整张卡牌出牌。数字 1—9 对应从左到右的手牌，与点击相同。需要目标的牌，选牌后点击高亮任务/伙伴，或直接拖到目标后松手。\n\n不需要目标的牌，可点击或按对应数字使用，也可拖出底部手牌区域后松手使用。拖回底部、右键或 Esc 可取消。\n\n点击伙伴，再点击任务可指定协作目标。需要换班时，选择高亮伙伴。结束回合前可选择本回合保留牌。\n\n牌组可查看本局全部卡牌与饰品。弃牌和消耗堆可查看公开牌效果，抽牌堆仅公开数量。卡牌效果产生待选时，须先在中央选牌面板完成选择。"
	_render_from_local()


func _show_log() -> void:
	var lines: Array[String] = []
	for value in _array(view.get("event_log")):
		lines.append(_event_text(_dict(value)))
	_panel_text = "战斗记录\n\n" + ("\n".join(lines) if not lines.is_empty() else "暂无记录")
	_render_from_local()


func _close_panel() -> void:
	_panel_text = ""
	_render_from_local()


func _battle_subtitle() -> String:
	var encounter := str(view.get("encounter_id", ""))
	return UiStyle.label(encounter) if not encounter.is_empty() else "公开任务与行动"


func _locked(prefix: String) -> bool:
	for uid in button_uids():
		if str(uid).begins_with(prefix):
			return button_disabled(uid)
	return is_locked()


func _bind_card(id: String) -> Callable:
	return func() -> void: _on_card_pressed(id)


func _bind_task(id: String) -> Callable:
	return func() -> void: _on_task_pressed(id)


func _bind_unit(id: String) -> Callable:
	return func() -> void: _on_unit_pressed(id)


func _bind_choice(id: String) -> Callable:
	return func() -> void: _on_choice_pressed(id)


func _bind_retention(id: String, maximum: int) -> Callable:
	return func() -> void:
		if _retained_card_ids.has(id):
			_retained_card_ids.erase(id)
		elif _retained_card_ids.size() < maximum:
			_retained_card_ids.append(id)
		_render_from_local()
		local_selection_changed.emit(selection_snapshot())


func _choice_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	if value is ChoiceRequest:
		var candidates: Array = []
		for option in value.candidates:
			candidates.append(
				{
					"id": option.id,
					"label_key": option.label_key,
					"preview": option.preview.duplicate(true)
				}
			)
		return {
			"choice_id": value.choice_id,
			"kind": String(value.kind),
			"candidates": candidates,
			"min_count": value.min_count,
			"max_count": value.max_count,
			"prompt_key": value.prompt_key
		}
	return {}


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _card_definition(card_id: String) -> String:
	for card_value in _array(view.get("hand")):
		var card := _dict(card_value)
		if str(card.get("card_id", "")) == card_id:
			return str(card.get("definition_id", card_id))
	return card_id


func _unit_definition(unit_id: String) -> String:
	for unit_value in _array(view.get("units")):
		var unit := _dict(unit_value)
		if str(unit.get("unit_id", "")) == unit_id:
			return str(unit.get("definition_id", unit_id))
	return unit_id


func _intent_text(intent: Dictionary) -> String:
	var parts: Array[String] = []
	if int(intent.get("pressure", 0)) != 0:
		parts.append("压力 %s" % intent.get("pressure"))
	if int(intent.get("shield", 0)) != 0:
		parts.append("屏障 %s" % intent.get("shield"))
	if not str(intent.get("text_key", "")).is_empty():
		parts.append(UiStyle.label(str(intent.get("text_key"))))
	return "、".join(parts) if not parts.is_empty() else "待揭示"


func _status_text(statuses: Array) -> String:
	var parts: Array[String] = []
	for value in statuses:
		var status := _dict(value)
		parts.append(
			(
				"%s×%s"
				% [
					UiStyle.label(str(status.get("status_id", status.get("definition_id", "")))),
					status.get("stacks", 0)
				]
			)
		)
	return "、".join(parts)


func _zone_details(zone: String, title: String) -> String:
	var cards := _array(_dict(view.get("zones_public")).get(zone))
	var lines: Array[String] = ["%s · %s 张" % [title, cards.size()]]
	for value in cards:
		var card := _dict(value)
		var detail := _dict(card.get("face", card.get("effective_card", {}))).duplicate(true)
		detail.cost = card.get("effective_cost", detail.get("cost", 0))
		detail.vitality_cost = card.get("effective_vitality_cost", detail.get("vitality_cost", 0))
		lines.append(
			(
				"%s\n%s"
				% [
					UiStyle.label(str(card.get("definition_id", ""))),
					UiContentText.describe_card(detail)
				]
			)
		)
	if cards.is_empty():
		lines.append("暂无公开卡牌")
	return "\n\n".join(lines)


func _choice_preview_text(preview: Dictionary) -> String:
	if preview.is_empty():
		return ""
	return "、".join(
		PackedStringArray(preview.keys().map(func(key): return "%s:%s" % [key, preview[key]]))
	)


func _event_text(event: Dictionary) -> String:
	var type := str(event.get("type", "事件"))
	var data := _dict(event.get("data"))
	if type == "task_advanced":
		return "本阶段已完成，进入下一阶段 · " + UiStyle.label(str(data.get("phase_key", "")))
	if type == "task_completed":
		return "任务全部阶段已完成"
	if type == "battle_finished":
		return "战斗胜利" if str(data.get("result", "")) == "won" else "战斗结束"
	var source := str(event.get("source_label", event.get("source_id", "")))
	var suffix := ""
	if data.has("amount"):
		suffix = " · %s" % data.amount
	return (
		"%s%s%s"
		% [
			UiStyle.label(type),
			" · " + UiStyle.label(source) if not source.is_empty() else "",
			suffix
		]
	)
