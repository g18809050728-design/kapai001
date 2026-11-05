class_name BattleScreen
extends UiPage

signal result_presentation_finished

var preview_callback: Callable = Callable()
var animation_enabled: bool = true:
	set(value):
		animation_enabled = value
		if not value and _presentation != null:
			_finish_event_presentation()
var speed_scale: float = 1.0
const EFFECT_SPEED := 4.0

var _animator: BattleEventAnimator
var _feedback_text: String = ""
var _feedback_label: Label
var _panel_text: String = ""
var _panel_zone := ""
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
var _hover_panel: Control
var _hover_title: Label
var _hover_meta: Label
var _hover_body: Label
var _hint_label: Label
var _hovered_card: BattleCard
var _hover_target: Dictionary = {}
var _last_hover_uid: String = ""
var _detail_terms: Array[String] = []
var _inspect_open: bool = false
var _pointer_card: BattleCard
var _pointer_start := Vector2.ZERO
var _dragging: bool = false
var _drag_ghost: BattleCard
var _pointer_position := Vector2.ZERO
var _hover_pinned := false
var _compact_layout := false
var _battle_layout_size := Vector2.ZERO
var _battle_resize_pending := false
var _previous_card_centers: Dictionary = {}
var _previous_target_centers: Dictionary = {}
var _effect_zone_centers: Dictionary = {}
var _task_meters: Dictionary = {}
var _presentation: BattlePresentation
var _result_pending := false
var _result_events_done := false


func effect_speed() -> float:
	return maxf(speed_scale, 0.05) * EFFECT_SPEED


func _init() -> void:
	_animator = BattleEventAnimator.new()
	_animator.event_presented.connect(_on_event_presented)
	_animator.queue_finished.connect(_on_event_queue_finished)
	_presentation = BattlePresentation.new(self)


func _exit_tree() -> void:
	_presentation.finish()


func _finish_event_presentation() -> void:
	_presentation.finish()
	if _result_pending:
		_result_pending = false
		result_presentation_finished.emit()


func _on_event_queue_finished() -> void:
	if _result_pending:
		_result_events_done = true
	else:
		_finish_event_presentation()


func _process(delta: float) -> void:
	super._process(delta)
	_animator.advance(delta)
	if _result_pending:
		if _result_events_done and not _presentation.is_animating():
			_finish_event_presentation()
		return
	if not is_inside_tree():
		return
	_update_pointer(delta)


func render(data: Dictionary) -> void:
	_presentation.finish()
	var next_view := data.duplicate(true)
	var next_revision := int(next_view.get("revision", -1))
	var next_choice := _choice_dict(next_view.get("pending_choice"))
	var next_choice_id := str(next_choice.get("choice_id", ""))
	if next_choice_id != _choice_id_seen:
		_choice_selected_ids.clear()
	_choice_id_seen = next_choice_id
	if next_revision != _revision_seen and next_revision >= 0:
		_remember_effect_origins()
		_presentation.capture_hand(self)
		_hover_pinned = false
		_selected_card_id = ""
		_selected_unit_id = ""
		_target_ids.clear()
		_replace_unit_id = ""
		_active_preview = null
		_preview_draft = {}
		if _inspect_open:
			_panel_text = ""
			_detail_terms.clear()
			_inspect_open = false
	_revision_seen = next_revision
	_submitted_revision = -2
	view = next_view
	_render_battle()
	_presentation.release_unused.call_deferred()


func consume_events(events: Array, run_id: String, revision: int) -> void:
	_animator.animation_enabled = animation_enabled
	_animator.speed_scale = effect_speed()
	var snapshots: Dictionary = {}
	for entry in _array(view.get("event_log")):
		if str(entry.get("run_id", "")) == run_id and int(entry.get("revision", -1)) == revision:
			snapshots[int(entry.get("index", -1))] = entry
	var presented: Array = []
	for ordinal in events.size():
		var event: Variant = events[ordinal]
		var index: int = int(event.get("index", ordinal)) if event is Dictionary else event.index
		presented.append(snapshots.get(index, event))
	presented = _animator.unseen_events(presented, run_id, revision)
	_presentation.prepare(presented)
	_animator.play(presented, run_id, revision)


func present_result(events: Array, event_log: Array, run_id: String, revision: int) -> void:
	_finish_event_presentation()
	_remember_effect_origins()
	var departing: Array = []
	for raw in events:
		var event: Dictionary = _animator._event_dictionary(raw, 0)
		if str(event.type) in ["card_played", "card_resolved", "card_discarded", "card_exhausted"]:
			departing.append(_presentation.card_id(event))
	_presentation.capture_hand(self, departing)
	view.event_log = event_log.duplicate(true)
	_result_pending = true
	_result_events_done = false
	close_card_preview()
	if is_instance_valid(_hover_panel):
		_hover_panel.visible = false
	if is_instance_valid(_aim):
		_aim.visible = false
	_apply_lock_state()
	consume_events(events, run_id, revision)


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
	return _array(_dict(view.get("zones_public")).get("draw")).map(func(card): return card.card_id)


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
		"active_visual_effects": _active_visual_effect_count(),
		"queued_draws": _animator.pending_type_count("card_drawn"),
		"pending_hand_cards": _presentation.pending_ids(),
	}


func apply_gating(results: Dictionary) -> void:
	super.apply_gating(results)
	_apply_lock_state()
	_sync_card_visuals()


func action_draft(uid: String) -> Dictionary:
	if _result_pending:
		return {}
	var draft := super.action_draft(uid)
	if is_locked() and str(draft.get("type", "")) not in ["confirm_choice", "ui.new_run"]:
		return {}
	return draft


func _render_battle() -> void:
	var dimensions := size if size.x > 0 else (get_viewport_rect().size if is_inside_tree() else Vector2(1280, 800))
	_compact_layout = dimensions.x < 1100 or dimensions.y < 700 or UiStyle.text_scale > 1.0
	set_meta("compact_cards", _compact_layout)
	_battle_layout_size = size
	if _compact_layout:
		BattleCompactLayout.new().build(self)
	else:
		BattleLayout.new().build(self)


func _reset_stage() -> void:
	close_card_preview()
	_pointer_card = null
	_hovered_card = null
	_hover_target = {}
	_drag_ghost = null
	_dragging = false
	_hand_cards.clear()
	_target_frames.clear()
	_task_meters.clear()
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
	if size != _battle_layout_size and not _battle_resize_pending:
		_battle_resize_pending = true
		_rebuild_for_size.call_deferred()
	_stage.scale = Vector2.ONE
	_stage.position = Vector2.ZERO if _compact_layout else (size - Vector2(1280, 800)) * 0.5


func _rebuild_for_size() -> void:
	_battle_resize_pending = false
	if is_inside_tree() and size != _battle_layout_size:
		if _result_pending:
			_finish_event_presentation()
			return
		_presentation.finish()
		_render_battle()


func _input(event: InputEvent) -> void:
	if _result_pending or not is_visible_in_tree() or not is_instance_valid(_stage):
		return
	if is_instance_valid(_card_preview) and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_card_preview()
		get_viewport().set_input_as_handled()
		return
	if _preview_pinned:
		if event is InputEventMouseButton and not _card_preview.get_global_rect().has_point(get_global_mouse_position()):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_I and is_instance_valid(_preview_card):
		_show_card_preview(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse:
		_pointer_position = event.position
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not is_locked():
		match event.keycode:
			KEY_P:
				_hover_pinned = not _hover_pinned
			KEY_G, KEY_F1:
				_show_rules()
			KEY_D:
				_show_deck()
			KEY_L:
				_show_log()
			KEY_E:
				if _panel_text.is_empty():
					_emit_draft(_end_turn_draft().call())
			_:
				pass
		if event.keycode in [KEY_P, KEY_G, KEY_F1, KEY_D, KEY_L, KEY_E]:
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_I
		and not event.ctrl_pressed
		and not event.alt_pressed
		and not event.meta_pressed
	):
		if not is_locked():
			_toggle_detail()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_hover_pinned = false
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
		if _compact_layout and index < _array(view.get("hand")).size():
			var compact_card: Button = _buttons.get("card:" + str(view.hand[index].card_id))
			if compact_card != null and compact_card.disabled:
				_show_disabled_card_feedback(compact_card)
			else:
				press("card:" + str(view.hand[index].card_id))
			get_viewport().set_input_as_handled()
			return
		if index < _hand_cards.size():
			var card := _hand_cards[index]
			if card.disabled:
				_show_disabled_card_feedback(card)
			else:
				_on_card_pressed(str(card.card_data.get("card_id", "")))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _compact_layout:
				for entry in _array(view.get("hand")):
					var compact_card: Button = _buttons.get("card:" + str(entry.get("card_id", "")))
					if compact_card != null and compact_card.disabled and compact_card.is_visible_in_tree() and compact_card.get_global_rect().has_point(event.position) and compact_card.get_parent().get_parent().get_global_rect().has_point(event.position):
						_show_disabled_card_feedback(compact_card)
						get_viewport().set_input_as_handled()
						return
			var card := _card_at(event.position)
			if card != null:
				if card.disabled:
					_show_disabled_card_feedback(card)
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
	if is_instance_valid(_hovered_card) and not _presentation.is_pending(str(_hovered_card.card_data.get("card_id", ""))) and _hovered_card.contains_global(point):
		return _hovered_card
	for index in range(_hand_cards.size() - 1, -1, -1):
		if _presentation.is_pending(str(_hand_cards[index].card_data.get("card_id", ""))):
			continue
		if _hand_cards[index].contains_home(point):
			return _hand_cards[index]
	return null


func _update_pointer(delta: float) -> void:
	if not is_instance_valid(_stage):
		return
	if not is_locked() and _panel_text.is_empty():
		_hovered_card = null if _dragging else _card_at(_pointer_position)
		if not _hover_pinned:
			_hover_target = _hover_target_at(_pointer_position)
			if _hover_target.is_empty():
				var focus := get_viewport().gui_get_focus_owner()
				if focus is BattlePileButton and not focus.disabled:
					_hover_target = focus.hover_content()
	else:
		_hovered_card = null
		_hover_target = {}
	var hover_uid := str(_hover_target.get("uid", ""))
	if hover_uid != _last_hover_uid:
		_last_hover_uid = hover_uid
		if not hover_uid.is_empty() and audio != null:
			audio.play_ui("ui_hover")
	for card in _hand_cards:
		if card.get_meta("card_in_flight", false) or card.get_meta("draw_pending", false):
			continue
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
	if is_instance_valid(_hovered_card) and not _hover_pinned:
		_hover_target = _card_hover_target(_hovered_card)
	_update_hover_window()
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


func _update_hover_window() -> void:
	if not is_instance_valid(_hover_panel):
		return
	var show := not _hover_target.is_empty() and not is_locked() and _panel_text.is_empty()
	_hover_panel.visible = show
	if not show:
		return
	_hover_title.text = str(_hover_target.get("title", ""))
	_hover_meta.text = str(_hover_target.get("meta", ""))
	_hover_body.text = str(_hover_target.get("body", ""))
	_place_hover_panel()


func _place_hover_panel() -> void:
	var inverse := _stage.get_global_transform_with_canvas().affine_inverse()
	var local := inverse * _pointer_position
	var size := _hover_panel.size
	var canvas := _stage.size
	var top_margin := 12.0 if _compact_layout else 76.0
	var raw_rect: Variant = _hover_target.get("rect", Rect2())
	var target_rect: Rect2 = raw_rect if raw_rect is Rect2 else Rect2()
	var candidates: Array[Vector2] = []
	var protected_rects: Array[Rect2] = []
	var entry: Variant = _buttons.get(str(_hover_target.get("uid", "")))
	if entry is BattlePileButton:
		if is_instance_valid(_hint_label):
			protected_rects.append(_hint_label.get_global_rect())
		for uid in ["battle:end_turn", "battle:cancel"]:
			if _buttons.has(uid) and _buttons[uid].is_visible_in_tree():
				protected_rects.append(_button_rect(uid))
	if target_rect.size != Vector2.ZERO:
		var target_local := Rect2(inverse * target_rect.position, target_rect.size / _stage.scale)
		var target_end := target_local.position + target_local.size
		candidates.append(Vector2(target_local.position.x, target_local.position.y - size.y - 12))
		candidates.append(Vector2(target_local.position.x, target_end.y + 12))
		candidates.append(Vector2(target_local.position.x - size.x - 12, target_local.position.y))
		candidates.append(Vector2(target_end.x + 12, target_local.position.y))
	if not protected_rects.is_empty():
		var footer_top: Vector2 = inverse * protected_rects[0].position
		candidates.append(Vector2(local.x - size.x * 0.5, footer_top.y - size.y - 12))
		candidates.append(Vector2(12, footer_top.y - size.y - 12))
		candidates.append(Vector2(canvas.x - size.x - 12, footer_top.y - size.y - 12))
	candidates.append(local + Vector2(20, 20))
	candidates.append(local + Vector2(20, -size.y - 20))
	candidates.append(local + Vector2(-size.x - 20, 20))
	candidates.append(local + Vector2(-size.x - 20, -size.y - 20))
	candidates.append(Vector2(12, top_margin + 12))
	candidates.append(Vector2(canvas.x - size.x - 12, top_margin + 12))
	for candidate in candidates:
		var pos: Vector2 = candidate
		pos.x = clampf(pos.x, 12, maxf(12, canvas.x - size.x - 12))
		pos.y = clampf(pos.y, top_margin, maxf(top_margin, canvas.y - size.y - 12))
		_hover_panel.position = pos
		var panel_rect := _hover_panel.get_global_rect()
		var clear := target_rect.size == Vector2.ZERO or not panel_rect.intersects(target_rect)
		for protected_rect in protected_rects:
			clear = clear and not panel_rect.intersects(protected_rect)
		if clear:
			return
	_hover_panel.position = Vector2(
		clampf(local.x + 20, 12, maxf(12, canvas.x - size.x - 12)),
		clampf(local.y + 20, top_margin, maxf(top_margin, canvas.y - size.y - 12))
	)


func _hover_target_at(point: Vector2) -> Dictionary:
	if is_instance_valid(_hovered_card):
		return _card_hover_target(_hovered_card)
	for uid in _buttons:
		var key := str(uid)
		if _buttons[uid] is BattlePileButton and not _buttons[uid].disabled and _button_hit(key, point):
			return _buttons[uid].hover_content()
		if key.begins_with("task:") and _button_hit(key, point):
			return _task_hover_target(key.trim_prefix("task:"))
		if key.begins_with("unit:") and _button_hit(key, point):
			return _unit_hover_target(key.trim_prefix("unit:"))
	if _buttons.has("statuses:player") and _button_hit("statuses:player", point):
		return _status_hover_target()
	return {}


func _button_hit(uid: String, point: Vector2) -> bool:
	if not _buttons.has(uid):
		return false
	var button: Button = _buttons[uid]
	return (
		is_instance_valid(button) and button.visible and button.get_global_rect().has_point(point)
	)


func _button_rect(uid: String) -> Rect2:
	if not _buttons.has(uid):
		return Rect2()
	var button: Button = _buttons[uid]
	return button.get_global_rect() if is_instance_valid(button) else Rect2()


func _card_hover_target(card: BattleCard) -> Dictionary:
	var data: Dictionary = card.card_data
	var definition_id := str(data.get("definition_id", ""))
	var face := _dict(data.get("face", data.get("effective_card", {})))
	var card_type := str(face.get("type", face.get("card_type", "work")))
	var reason := str(card.get_meta("disabled_reason", ""))
	var summary := (
		"%s · %s · 专注 %s"
		% [UiStyle.label(definition_id), UiStyle.label(card_type), data.get("effective_cost", "—")]
	)
	var effect_text := UiContentText.card_summary(face)
	if effect_text.is_empty():
		effect_text = str(data.get("description", ""))
	if not effect_text.is_empty():
		summary += "\n" + _short_text(effect_text, 52)
	if not reason.is_empty():
		summary = "无法打出：" + reason
	var entry := _run_card_entry(str(data.get("card_id", "")), definition_id)
	var detail_data := _dict(entry.get("detail"))
	var body := (
		UiContentText.describe_card(detail_data)
		if not detail_data.is_empty()
		else UiContentText.describe_card(face)
	)
	var upgraded := _dict(entry.get("upgrade_detail"))
	if not upgraded.is_empty():
		body += "\n\n升级后：\n" + UiContentText.describe_card(upgraded)
	var terms := _card_terms(face, card_type)
	var meta := "%s · 专注 %s" % [UiStyle.label(card_type), data.get("effective_cost", "—")]
	if int(data.get("effective_vitality_cost", 0)) > 0:
		meta += " · 精力 %s" % data.get("effective_vitality_cost", 0)
	return {
		"uid": "card:" + str(data.get("card_id", "")),
		"title": UiStyle.label(definition_id),
		"meta": meta,
		"body": effect_text if reason.is_empty() else "无法打出：" + reason,
		"summary": summary,
		"detail": UiStyle.label(definition_id) + "\n" + body,
		"terms": terms,
		"rect": card.get_global_rect(),
	}


func _task_hover_target(task_id: String) -> Dictionary:
	var task := {}
	for value in _array(view.get("tasks")):
		if str(_dict(value).get("task_id", "")) == task_id:
			task = _dict(value)
			break
	if task.is_empty():
		return {}
	var phase_count := maxi(1, int(task.get("phase_count", 1)))
	var phase_index := maxi(1, int(task.get("phase_index", 1)))
	var intent := _intent_text(_dict(task.get("intent_snapshot")))
	var statuses := _statuses_for(task_id)
	var summary := (
		"%s · 第 %s/%s 阶段 · 剩余 %s/%s · 屏障 %s"
		% [
			UiStyle.label(str(task.get("definition_id", ""))),
			phase_index,
			phase_count,
			task.get("work_remaining", 0),
			task.get("work_max", 0),
			task.get("shield", 0)
		]
	)
	summary += "\n下回合：" + _short_text(intent, 46)
	var lines: Array[String] = [
		"任务：" + UiStyle.label(str(task.get("definition_id", ""))),
		(
			"阶段：第 %s/%s 阶段 · %s"
			% [phase_index, phase_count, UiStyle.label(str(task.get("phase_key", "")))]
		),
		"未完成量：%s/%s" % [task.get("work_remaining", 0), task.get("work_max", 0)],
		"屏障：%s" % task.get("shield", 0),
		"下回合意图：" + intent,
	]
	if not statuses.is_empty():
		lines.append("状态：" + _status_text(statuses))
	if not bool(task.get("victory_required", true)):
		lines.append("非胜利必需：该任务存活不阻止胜利。")
	var terms: Array[String] = ["pressure", "shield", "ddl"]
	for value in statuses:
		var key := str(_dict(value).get("status_id", ""))
		if not key.is_empty() and not terms.has(key):
			terms.append(key)
	return {
		"uid": "task:" + task_id,
		"title": UiStyle.label(str(task.get("definition_id", ""))),
		"meta":
		(
			"第 %s/%s 阶段 · 剩余 %s/%s"
			% [phase_index, phase_count, task.get("work_remaining", 0), task.get("work_max", 0)]
		),
		"body": "屏障 %s\n下回合：%s" % [task.get("shield", 0), _short_text(intent, 42)],
		"summary": summary,
		"detail": "\n".join(lines),
		"terms": terms,
		"rect": _button_rect("task:" + task_id),
	}


func _unit_hover_target(unit_id: String) -> Dictionary:
	var unit := {}
	for value in _array(view.get("units")):
		if str(_dict(value).get("unit_id", "")) == unit_id:
			unit = _dict(value)
			break
	if unit.is_empty():
		return {}
	var summary := (
		"%s · 精力 %s/%s · 协作 %s · 护卫 %s"
		% [
			UiStyle.label(str(unit.get("definition_id", ""))),
			unit.get("vitality", 0),
			unit.get("max_vitality", 0),
			unit.get("cooperation", 0),
			unit.get("guard", 0)
		]
	)
	var lines: Array[String] = [
		"单位：" + UiStyle.label(str(unit.get("definition_id", ""))),
		"精力：%s/%s" % [unit.get("vitality", 0), unit.get("max_vitality", 0)],
		"协作：%s" % unit.get("cooperation", 0),
		"放松：%s" % unit.get("relax", 0),
		"护卫：%s" % unit.get("guard", 0),
		"本轮已行动：%s" % unit.get("actions_taken", 0),
	]
	var terms: Array[String] = ["vitality", "guard"]
	return {
		"uid": "unit:" + unit_id,
		"title": UiStyle.label(str(unit.get("definition_id", ""))),
		"meta":
		(
			"精力 %s/%s · 协作 %s"
			% [unit.get("vitality", 0), unit.get("max_vitality", 0), unit.get("cooperation", 0)]
		),
		"body":
		(
			"放松 %s · 护卫 %s\n本轮已行动 %s"
			% [unit.get("relax", 0), unit.get("guard", 0), unit.get("actions_taken", 0)]
		),
		"summary": summary,
		"detail": "\n".join(lines),
		"terms": terms,
		"rect": _button_rect("unit:" + unit_id),
	}


func _status_hover_target() -> Dictionary:
	var player := _dict(view.get("player"))
	var statuses := _statuses_for(str(player.get("entity_id", "")))
	if statuses.is_empty():
		return {}
	var names: PackedStringArray = []
	var lines: Array[String] = ["我的状态"]
	var terms: Array[String] = []
	for value in statuses:
		var status := _dict(value)
		var key := str(status.get("status_id", ""))
		var stacks := int(status.get("stacks", 0))
		names.append("%s×%s" % [UiStyle.label(key), stacks])
		lines.append("\n%s\n当前层数：%s" % [UiGlossary.describe(key), stacks])
		if not key.is_empty() and not terms.has(key):
			terms.append(key)
	return {
		"uid": "statuses:player",
		"title": "我的状态",
		"meta": "、".join(names),
		"body": "共 %s 项状态；点击状态区或按 I 查看详情" % statuses.size(),
		"summary": "我的状态：" + "、".join(names),
		"detail": "\n".join(lines),
		"terms": terms,
		"rect": _button_rect("statuses:player"),
	}


func _statuses_for(target_id: String) -> Array:
	var result: Array = []
	for value in _array(view.get("statuses")):
		if str(_dict(value).get("target_id", "")) == target_id:
			result.append(value)
	return result


func _card_terms(face: Dictionary, card_type: String) -> Array[String]:
	var terms: Array[String] = []
	for key in UiGlossary.keys_for_effects(
		_array(face.get("effects")) + _array(face.get("pre_effects"))
	):
		terms.append(key)
	for key in UiGlossary.keys_for_types([card_type]):
		if not terms.has(key):
			terms.append(key)
	if bool(face.get("exhaust", false)) and not terms.has("exhaust"):
		terms.append("exhaust")
	if bool(face.get("retain", false)) and not terms.has("retain"):
		terms.append("retain")
	return terms


func _short_text(value: String, limit: int) -> String:
	var text := value.replace("\n", "；")
	if text.length() <= limit:
		return text
	return text.substr(0, limit) + "…"


func _run_card_entry(card_id: String, definition_id: String) -> Dictionary:
	for value in _array(view.get("cards")):
		var card := _dict(value)
		if str(card.get("card_id", "")) == card_id:
			return card
	for value in _array(view.get("cards")):
		var card := _dict(value)
		if str(card.get("definition_id", "")) == definition_id:
			return card
	return {}


func _target_for_uid(uid: String) -> Dictionary:
	if _buttons.get(uid) is BattlePileButton:
		return _buttons[uid].hover_content()
	if uid.begins_with("card:"):
		var card_id := uid.trim_prefix("card:")
		for card in _hand_cards:
			if str(card.card_data.get("card_id", "")) == card_id:
				return _card_hover_target(card)
		if _buttons.has(uid):
			var focused_card := _buttons[uid] as BattleCard
			if focused_card != null:
				return _card_hover_target(focused_card)
	if uid.begins_with("task:"):
		return _task_hover_target(uid.trim_prefix("task:"))
	if uid.begins_with("unit:"):
		return _unit_hover_target(uid.trim_prefix("unit:"))
	if uid == "statuses:player":
		return _status_hover_target()
	if uid == "battle:resources":
		var id := str(view.get("character_id", ""))
		var passive := str({"P01": "r3_p01_link_replay", "P02": "r3_p02_paper_record", "P03": "r3_p03_compound_reaction", "P04": "r3_p04_teamwork"}.get(id, ""))
		var text := UiContentText.describe_character_passive(passive)
		var info := _dict(view.get("character_info"))
		if id == "P01":
			text += "\n前牌类型：" + UiStyle.label(str(info.get("previous_type", "无"))) + "；策略→工作形成连携。"
		elif id == "P02":
			var paper := _dict(info.get("paper"))
			text += "\n进度 %s/10 · 引用 %s/5 · 修正 %s · 增幅 %s\n章节按1→2→3槽在准备阶段运行；新部署章节从下回合生效。" % [paper.get("progress", 0), paper.get("citations", 0), paper.get("modifier", 0), paper.get("amplify", 0)]
		elif id == "P04":
			text += "\n协同 %s/6；伙伴的正常合作在轮末执行，随后自身精力-1。" % info.get("synergy", 0)
		if info.has("passive_available"):
			text += "\n本回合被动机会：" + ("可用" if info.passive_available else "已使用")
		return {"uid": uid, "title": UiStyle.label(id) + " · 角色资源", "detail": text, "body": text, "terms": []}
	return {}


func _current_inspect_target() -> Dictionary:
	if not _hover_target.is_empty():
		return _hover_target
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BattleCard:
		return _card_hover_target(focus)
	if focus is Button and focus.has_meta("uid"):
		return _target_for_uid(str(focus.get_meta("uid")))
	if not _selected_card_id.is_empty():
		return _target_for_uid("card:" + _selected_card_id)
	return {}


func _add_pile_button(parent: Node, kind: String, callback: Callable, dark_background: bool = true) -> BattlePileButton:
	var counts := _dict(view.get("zone_counts"))
	var amount := int(counts.get(kind, _array(_dict(view.get("zones_public")).get(kind)).size()))
	if kind == "deck":
		amount = _array(view.get("cards")).size()
	elif kind == "log":
		amount = _array(view.get("event_log")).size()
	var button := BattlePileButton.new()
	button.set_meta("uid", "battle:" + kind)
	button.configure(kind, amount, dark_background)
	button.custom_minimum_size = Vector2(96, 64) * minf(UiStyle.text_scale, 1.2)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	_buttons["battle:" + kind] = button
	button.pressed.connect(func():
		if button.disabled or is_locked() or not _panel_text.is_empty():
			return
		if audio != null:
			audio.play_ui("detail_open")
		callback.call()
	)
	return button


func _toggle_detail() -> void:
	if _inspect_open:
		_close_panel()
		return
	if not _panel_text.is_empty():
		return
	_open_detail(_current_inspect_target())


func _open_detail_for_uid(uid: String) -> void:
	_open_detail(_target_for_uid(uid))


func _open_detail(target: Dictionary) -> void:
	if target.is_empty():
		return
	if audio != null:
		audio.play_ui("detail_open")
	_panel_zone = ""
	_panel_text = str(target.get("detail", "信息不可用"))
	_detail_terms.clear()
	_inspect_open = true
	for value in _array(target.get("terms")):
		_detail_terms.append(str(value))
	_render_from_local()


func _bind_term(term: String) -> Callable:
	return func(): _show_term(term)


func _show_term(term: String) -> void:
	if _panel_text.is_empty():
		return
	_panel_text += "\n\n" + UiGlossary.describe(term)
	_render_from_local()


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
		var frame: Control = _target_frames[uid]
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
	if is_locked() or _presentation.is_pending(card_id):
		return
	if audio != null:
		audio.play_ui("ui_click")
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
		return UiStyle.error_text(
			ApiError.new(
				StringName(str(value.get("code", "ERROR"))), str(value.get("message_key", ""))
			)
		)
	return str(value)


func _apply_lock_state() -> void:
	if _result_pending:
		for uid in button_uids():
			_buttons[uid].disabled = true
			_buttons[uid].focus_mode = Control.FOCUS_NONE
		return
	if not is_locked():
		if not _panel_text.is_empty():
			for uid in button_uids():
				if uid == "battle:close_panel" or str(uid).begins_with("pile:card:") or str(uid).begins_with("term:"):
					continue
				_buttons[uid].disabled = true
				_buttons[uid].focus_mode = Control.FOCUS_NONE
		return
	for uid in button_uids():
		if str(uid).begins_with("choice:"):
			continue
		_buttons[uid].disabled = true
		if _buttons[uid] is BattleCard:
			_buttons[uid].set_meta("disabled_reason", "请先完成当前选择")
			_buttons[uid].tooltip_text = ""
		else:
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
	if not _buttons.has(uid):
		return
	_buttons[uid].disabled = not enabled
	_buttons[uid].set_meta("disabled_reason", "" if enabled else reason)
	if _buttons[uid] is BattleCard:
		var card: BattleCard = _buttons[uid]
		card.set_meta("disabled_reason", "" if enabled else reason)
		card.tooltip_text = ""
	else:
		_buttons[uid].tooltip_text = "" if enabled else reason


func _render_from_local() -> void:
	var current := view.duplicate(true)
	render(current)


func _on_event_presented(event: Dictionary, text: String) -> void:
	_present_event_visual(event)
	if str(event.get("type", "")) == "card_drawn":
		var queued := _animator.pending_type_count("card_drawn")
		text += " · 正在抽牌 · 排队中：%d 张" % queued
	if audio != null:
		if str(event.get("type", "")) == "ddl_ticked":
			audio.play_deadline(int(_dict(event.get("data")).get("after", 0)))
		else:
			audio.play_event(str(event.get("type", "")))
	_feedback_text = text
	if is_instance_valid(_feedback_label):
		_feedback_label.text = text
		_feedback_label.visible = true


func _show_disabled_card_feedback(card: Button) -> void:
	_feedback_text = str(card.get_meta("disabled_reason", "无法打出"))
	if _feedback_text.is_empty():
		_feedback_text = "当前无法打出这张牌"
	if is_instance_valid(_feedback_label):
		_feedback_label.text = _feedback_text
		_feedback_label.visible = true


func _active_visual_effect_count() -> int:
	if not is_instance_valid(_stage):
		return 0
	var count := 0
	for child in _stage.get_children():
		if child.has_meta("battle_event_effect") and not child.is_queued_for_deletion():
			count += 1
	return count


func _clear_event_visuals() -> void:
	if not is_instance_valid(_stage):
		return
	for child in _stage.get_children():
		if child.has_meta("battle_event_effect"):
			_stage.remove_child(child)
			child.queue_free()


func _present_event_visual(event: Dictionary) -> void:
	if not animation_enabled or not is_instance_valid(_stage):
		return
	var kind := str(event.get("type", ""))
	var data := _dict(event.get("data"))
	match kind:
		"card_played":
			_presentation.show_played(event)
		"card_drawn":
			_presentation.draw(event)
		"card_discarded":
			_presentation.move_out(event, str(data.get("to_zone", "discard")))
		"card_exhausted":
			_presentation.move_out(event, "exhaust")
		"card_resolved":
			var destination := str(data.get("destination", "discard"))
			if destination in ["discard", "exhaust"]:
				_presentation.move_out(event, destination)
		"completion_applied":
			_show_completion_feedback(event, data)
		"pressure_applied":
			_show_pressure_feedback(event, data)


func _show_completion_feedback(event: Dictionary, data: Dictionary) -> void:
	var targets := _array(event.get("target_ids"))
	if targets.is_empty():
		return
	var target_id := "task:" + str(targets[0])
	var target: Control = _target_frames.get(target_id)
	var center: Vector2 = _stage_center(target) if is_instance_valid(target) else _previous_target_centers.get(target_id, _stage.size * Vector2(0.72, 0.35))
	var parts: Array[String] = []
	var work_lost := maxi(0, int(data.get("work_before", 0)) - int(data.get("work_after", 0)))
	var shield_lost := maxi(0, int(data.get("shield_before", 0)) - int(data.get("shield_after", 0)))
	if work_lost > 0:
		parts.append("完成量 −%d" % work_lost)
	if shield_lost > 0:
		parts.append("屏障 −%d" % shield_lost)
	if parts.is_empty():
		return
	_presentation.animate_meter(str(targets[0]), data)
	_float_event_text("  ·  ".join(parts), center, Color("ffe2a1"), 1.05)
	if is_instance_valid(target):
		var old_color: Color = target.modulate
		var flash := target.create_tween()
		_presentation._tweens.append(flash)
		flash.tween_property(target, "modulate", Color("ffe2a1"), 0.16 / effect_speed())
		flash.tween_property(target, "modulate", old_color, 0.74 / effect_speed())


func _show_pressure_feedback(event: Dictionary, data: Dictionary) -> void:
	var targets := _array(event.get("target_ids"))
	var target_id := str(targets[0]) if not targets.is_empty() else ""
	var control: Control = _target_frames.get("unit:" + target_id)
	if control == null:
		control = _buttons.get("battle:resources") if _compact_layout else null
	var center := _stage_center(control) if is_instance_valid(control) else _stage.size * Vector2(0.12, 0.40)
	var vitality_lost := maxi(0, int(data.get("vitality_before", 0)) - int(data.get("vitality_after", 0)))
	var relaxed := maxi(0, int(data.get("relax_before", 0)) - int(data.get("relax_after", 0)))
	var parts: Array[String] = []
	if vitality_lost > 0:
		parts.append("精力 −%d" % vitality_lost)
	if relaxed > 0:
		parts.append("放松抵消 %d" % relaxed)
	if not parts.is_empty():
		_float_event_text(" · ".join(parts), center, Color("ffb8a4"))


func _float_event_text(text: String, center: Vector2, color: Color, seconds: float = 0.4) -> void:
	var feedback := Label.new()
	feedback.text = text
	feedback.add_theme_font_size_override("font_size", 22)
	feedback.add_theme_color_override("font_color", color)
	feedback.add_theme_color_override("font_outline_color", Color("192f35"))
	feedback.add_theme_constant_override("outline_size", 5)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.size = Vector2(300, 38)
	feedback.position = center - Vector2(feedback.size.x * 0.5, 36)
	feedback.z_index = 181
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.set_meta("battle_event_effect", true)
	_stage.add_child(feedback)
	var tween := feedback.create_tween()
	_presentation._tweens.append(tween)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	var duration := seconds / effect_speed()
	tween.tween_property(feedback, "position", feedback.position - Vector2(0, 26), duration)
	tween.parallel().tween_property(feedback, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	tween.tween_callback(feedback.queue_free)


func _hand_card_control(card_id: String) -> Control:
	return _buttons.get("card:" + card_id)


func _remember_effect_origins() -> void:
	_previous_card_centers.clear()
	_previous_target_centers.clear()
	if not is_instance_valid(_stage):
		return
	for uid in _buttons:
		if str(uid).begins_with("card:"):
			_previous_card_centers[str(uid).trim_prefix("card:")] = _stage_center(_buttons[uid])
	for uid in _target_frames:
		_previous_target_centers[uid] = _stage_center(_target_frames[uid])
	for zone in ["draw", "discard", "exhaust"]:
		var control: Control = _buttons.get("battle:" + zone)
		if is_instance_valid(control):
			_effect_zone_centers[zone] = _stage_center(control)


func _zone_center(zone: String, fallback: Vector2) -> Vector2:
	var control: Variant = _buttons.get("battle:" + zone)
	if control is Control and is_instance_valid(control):
		return _stage_center(control)
	return _effect_zone_centers.get(zone, fallback)


func _stage_center(control: Control) -> Vector2:
	return _stage.get_global_transform_with_canvas().affine_inverse() * (control.get_global_transform_with_canvas() * (control.size * 0.5))


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
	_animator.speed_scale = effect_speed()
	_render_from_local()


func _show_draw() -> void:
	_show_zone("draw", "抽牌堆")


func _show_deck() -> void:
	if is_locked():
		return
	_detail_terms.clear()
	_panel_zone = ""
	_inspect_open = false
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
	_show_zone("discard", "弃牌堆")


func _show_exhaust() -> void:
	_show_zone("exhaust", "消耗堆")


func _show_zone(zone: String, title: String) -> void:
	if is_locked():
		return
	_detail_terms.clear()
	_inspect_open = false
	_panel_zone = zone
	_panel_text = _zone_details(zone, title)
	_render_from_local()


func populate_info(parent: Node, on_dark: bool = false) -> void:
	var ink := UiStyle.PAPER if on_dark else UiStyle.INK
	if _panel_zone.is_empty():
		add_text(parent, _panel_text, 18, ink)
		return
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	add_text(column, _panel_text.get_slice("\n", 0) + (" · 按卡牌整理，隐藏抽取顺序" if _panel_zone == "draw" else " · 点击 / 悬停查看卡文"), 17, ink)
	var cards := _array(_dict(view.get("zones_public")).get(_panel_zone))
	if cards.is_empty():
		add_text(column, "这里暂时没有卡牌。", 19, ink)
	var grid := GridContainer.new()
	grid.columns = 3 if size.x >= 750 and UiStyle.text_scale <= 1.25 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	column.add_child(grid)
	for card in cards:
		var detail := _dict(card.get("face", card.get("effective_card", {}))).duplicate(true)
		detail.cost = card.get("effective_cost", detail.get("cost", 0))
		detail.vitality_cost = card.get("effective_vitality_cost", detail.get("vitality_cost", 0))
		var button := add_card(grid, "pile:card:" + str(card.card_id), str(card.definition_id), detail, UiStyle.label(str(card.definition_id)), false, func(): pass)
		button.pressed.connect(func(): _preview_card = button; _show_card_preview(true))


func add_end_turn(parent: Node, bounds: Rect2 = Rect2()) -> Button:
	var button := BattleActionButton.new()
	button.configure("turn")
	button.set_meta("uid", "battle:end_turn")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(148 * UiStyle.text_scale, 54 * UiStyle.text_scale)
	parent.add_child(button)
	_buttons["battle:end_turn"] = button
	_drafts["battle:end_turn"] = _end_turn_draft()
	var source_run := str(view.get("run_id", ""))
	var source_revision := int(view.get("revision", -1))
	button.pressed.connect(func():
		if button.disabled or not _panel_text.is_empty():
			return
		var draft := action_draft("battle:end_turn")
		draft["source_run_id"] = source_run
		draft["source_revision"] = source_revision
		_emit_draft(draft))
	if bounds.has_area():
		button.custom_minimum_size = Vector2.ZERO
		button.position = bounds.position
		button.size = bounds.size
	return button


func _show_rules() -> void:
	_panel_zone = ""
	_detail_terms.clear()
	_inspect_open = false
	_panel_text = "把鼠标移到卡牌、任务、单位或状态上可看摘要；按 I 打开详情与词条，Esc 关闭。\n\n点击或拖拽整张卡牌出牌。数字 1—9 对应从左到右的手牌，与点击相同。需要目标的牌，选牌后点击高亮任务/伙伴，或直接拖到目标后松手。\n\n不需要目标的牌，可点击或按对应数字使用，也可拖出底部手牌区域后松手使用。拖回底部、右键或 Esc 可取消。\n\n点击伙伴，再点击任务可指定协作目标。需要换班时，选择高亮伙伴。结束回合前可选择本回合保留牌。\n\n牌组可查看本局全部卡牌与饰品。弃牌和消耗堆可查看公开牌效果，抽牌堆公开剩余卡牌，按卡牌整理，不显示实际抽取顺序。卡牌效果产生待选时，须先在中央选牌面板完成选择。"
	_panel_text += "\n\n快捷键：P 固定/解除悬停摘要，G 或 F1 打开本帮助，D 查看牌组，L 查看记录，E 结束回合。效果内待选时须先完成选择。固定摘要在新命令或 Esc 后解除。"
	_panel_text = "完成所有任务才是整场胜利；阶段完成后可能还有下一阶段。精力耗尽，或DDL到期仍有任务时失败。\n精力是本局生命资源；专注支付卡牌费用；放松抵挡压力。DDL表示剩余完整轮末次数，按轮末时序结算。\n\n" + _panel_text
	var v3 := _dict(view.get("v3"))
	if not v3.is_empty():
		var paper := _dict(v3.get("paper"))
		_panel_text += "\n\n人物资源：论文进度 %d/10，引用 %d/5，修正 %d，增幅 %d；协同 %d/6。" % [int(paper.get("progress", 0)), int(paper.get("citations", 0)), int(paper.get("modifier", 0)), int(paper.get("amplify", 0)), int(v3.get("synergy", 0))]
		for entry in _array(paper.get("chapters")):
			_panel_text += "\n章节：%s · %s" % [UiStyle.label(str(entry.get("definition_id", ""))), "下回合生效" if int(entry.get("deployed_round", 0)) >= int(view.get("round_index", 0)) else "已生效"]
		for ability in _array(v3.get("abilities")):
			_panel_text += "\n持续能力：%s · %s" % [UiStyle.label(str(ability.get("definition_id", ""))), "下回合生效" if int(ability.get("activate_round", 0)) > int(view.get("round_index", 0)) else "已生效"]
	_render_from_local()


func _show_log() -> void:
	_panel_zone = ""
	_detail_terms.clear()
	_inspect_open = false
	var lines: Array[String] = []
	for value in _array(view.get("event_log")):
		lines.append(_event_text(_dict(value)))
	_panel_text = "战斗记录\n\n" + ("\n".join(lines) if not lines.is_empty() else "暂无记录")
	_render_from_local()


func _close_panel() -> void:
	close_card_preview()
	_panel_zone = ""
	_panel_text = ""
	_detail_terms.clear()
	_inspect_open = false
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
	var face := _dict(preview.get("face", preview.get("effective_card", {})))
	if not face.is_empty():
		return UiContentText.card_summary(face)
	var definition_id := str(preview.get("definition_id", ""))
	return UiStyle.label(definition_id) if not definition_id.is_empty() else ""


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
