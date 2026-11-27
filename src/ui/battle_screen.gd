class_name BattleScreen
extends UiPage

signal result_presentation_finished

var preview_callback: Callable = Callable()
var animation_enabled: bool = true:
	set(value):
		animation_enabled = value
		if not value and _presentation != null:
			_finish_event_presentation()
		for actor in _actors.values():
			if is_instance_valid(actor):
				actor.set_motion(value)
var speed_scale: float = 1.0
var use_shell_damage_popups := false
const EFFECT_SPEED := 4.0
const END_TURN_INTERVAL_MS := 600

var _animator: BattleEventAnimator
var _feedback_text: String = ""
var _feedback_label: Label
var _task_event_notices := PackedStringArray()
var _panel_text: String = ""
var _panel_zone := ""
var _full_map: UiRouteOverlay
var _toolbar: UiRunToolbar
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
var _end_turn_after_ms := 0
var _choice_status: Label
var _choice_scroll: ScrollContainer
var _choice_scroll_x := 0
var _choice_focus_uid := ""
var _stage: Control
var _hand_cards: Array[BattleCard] = []
var _target_frames: Dictionary = {}
var _actors: Dictionary = {}
var _pilot_actor_cache: Dictionary = {}
var _stage_effects: BattleStageEffects
var _aim: BattleAim
var _hover_panel: Control
var _hover_title: Label
var _hover_meta: Label
var _hover_body: Label
var _hover_scroll: ScrollContainer
var _hover_hint: Label
var _glossary_toggle: Button
var _glossary_box: PanelContainer
var _glossary_scroll: ScrollContainer
var _glossary_body: Label
var _glossary_open := false
var _glossary_uid := ""
var _hint_label: Label
var _hovered_card: BattleCard
var _hover_target: Dictionary = {}
var _last_hover_uid: String = ""
var _detail_terms: Array[String] = []
var _inspect_open: bool = false
var _pointer_card: BattleCard
var _pointer_start := Vector2.ZERO
var _touch_pointer := false
var _held_for := 0.0
var _dragging: bool = false
var _drag_ghost: BattleCard
var _pointer_position := Vector2.ZERO
var _hover_pinned := false
const CARD_DETAIL_DELAY := 0.7
var _card_hover_uid := ""
var _card_hover_elapsed := 0.0
var _pinned_card_detail: Dictionary = {}
var _compact_layout := false
var _short_web := false
var _battle_layout_size := Vector2.ZERO
var _battle_resize_pending := false
var _hand_top := 548.0
var _previous_card_centers: Dictionary = {}
var _previous_target_centers: Dictionary = {}
var _effect_zone_centers: Dictionary = {}
var _task_meters: Dictionary = {}
var _presentation: BattlePresentation
var _result_pending := false
var _result_events_done := false
var _detail_return_uid := ""
var _status_return_scroll := 0


func effect_speed() -> float:
	return maxf(speed_scale, 0.05) * EFFECT_SPEED


func has_refined_actors() -> bool:
	for actor in _actors.values():
		if is_instance_valid(actor) and is_instance_valid(actor.rig) and actor.rig.refined:
			return true
	return false


func _init() -> void:
	automatic_card_details = false
	_animator = BattleEventAnimator.new()
	_animator.event_presented.connect(_on_event_presented)
	_animator.queue_finished.connect(_on_event_queue_finished)
	_presentation = BattlePresentation.new(self)
	_stage_effects = BattleStageEffects.new(self)


func _exit_tree() -> void:
	_presentation.finish()
	_release_pilot_actor_cache()


func _finish_event_presentation() -> void:
	_result_events_done = false
	_presentation.finish()
	if _result_pending:
		_result_pending = false
		result_presentation_finished.emit()


func _on_event_queue_finished() -> void:
	_result_events_done = true
	if not _presentation.is_animating():
		_finish_event_presentation()


func _process(delta: float) -> void:
	_animator.advance(delta)
	if _result_events_done and not _presentation.is_animating():
		_result_events_done = false
		_finish_event_presentation()
	if _result_pending:
		if _result_events_done and not _presentation.is_animating():
			_finish_event_presentation()
		return
	if not is_inside_tree():
		return
	_refresh_end_turn()
	_update_pointer(delta)
	if _touch_pointer and is_instance_valid(_pointer_card) and not _dragging:
		_held_for += delta
		if _held_for >= 0.5 and not is_locked():
			var detail := _card_hover_target(_pointer_card)
			_pointer_card = null
			_open_detail(detail)


func render(data: Dictionary) -> void:
	if is_instance_valid(_reference):
		_reference.close()
	_presentation.finish()
	var next_view := data.duplicate(true)
	if next_view.get("battle_id") != view.get("battle_id") or next_view.get("run_id") != view.get("run_id"):
		_task_event_notices.clear()
		_end_turn_after_ms = 0
	var next_revision := int(next_view.get("revision", -1))
	var next_choice := _choice_dict(next_view.get("pending_choice"))
	var next_choice_id := str(next_choice.get("choice_id", ""))
	if next_choice_id != _choice_id_seen:
		_choice_selected_ids.clear()
		_choice_scroll = null
		_choice_scroll_x = 0
		_choice_focus_uid = ""
	_choice_id_seen = next_choice_id
	if next_revision != _revision_seen and next_revision >= 0:
		_remember_effect_origins()
		_presentation.capture_hand(self)
		_hover_pinned = false
		_glossary_open = false
		_glossary_uid = ""
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
	_result_events_done = false
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
	if not presented.is_empty():
		_task_event_notices.clear()
	_presentation.prepare(presented)
	_animator.play(presented, run_id, revision)


func damage_target_anchors() -> Dictionary:
	var anchors := {}
	for task in _array(view.get("tasks")):
		var id := str(task.get("task_id", ""))
		var uid := "task:" + id
		var target: Control = _target_frames.get(uid, _buttons.get(uid))
		if _stage_effects.has_actor(id):
			anchors[id] = _stage.get_global_transform_with_canvas() * _stage_effects.target_anchor(id)
		elif is_instance_valid(target):
			anchors[id] = target.get_global_rect().get_center()
	return anchors


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


func export_choice_selection() -> Dictionary:
	return {"run_id": view.get("run_id", ""), "revision": view.get("revision", -1), "choice_id": _choice_id_seen, "selected_ids": _choice_selected_ids.duplicate()}


func restore_choice_selection(saved: Dictionary) -> void:
	if saved.get("run_id") != view.get("run_id") or saved.get("revision") != view.get("revision") or saved.get("choice_id", "") != _choice_id_seen or _choice_id_seen.is_empty():
		return
	_choice_selected_ids.assign(saved.get("selected_ids", []))
	_render_from_local()


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
	_show_end_turn_lock()
	_sync_card_visuals()


func action_draft(uid: String) -> Dictionary:
	if _result_pending:
		return {}
	var draft := super.action_draft(uid)
	if is_locked() and str(draft.get("type", "")) not in ["confirm_choice", "ui.new_run", "ui.menu"]:
		return {}
	return draft


func _render_battle() -> void:
	_compact_layout = false
	_short_web = UiStyle.short_web(size)
	set_meta("compact_cards", false)
	_battle_layout_size = size
	BattleLayout.new().build(self)
	_release_pilot_actor_cache()


func _take_pilot_actor(id: String, definition: String, kind: String, phase: int) -> BattleActorView:
	var actor: BattleActorView = _pilot_actor_cache.get(id)
	_pilot_actor_cache.erase(id)
	if is_instance_valid(actor) and actor.definition_id == definition and actor.actor_kind == kind and actor.phase_index == phase:
		return actor
	if is_instance_valid(actor):
		actor.queue_free()
	return null


func _release_pilot_actor_cache() -> void:
	for actor in _pilot_actor_cache.values():
		if is_instance_valid(actor):
			actor.queue_free()
	_pilot_actor_cache.clear()


func _reset_stage() -> void:
	if is_instance_valid(_choice_scroll):
		_choice_scroll_x = _choice_scroll.scroll_horizontal
		var focused := get_viewport().gui_get_focus_owner()
		_choice_focus_uid = str(focused.get_meta("uid", "")) if is_instance_valid(focused) else ""
	_choice_scroll = null
	_choice_status = null
	if is_instance_valid(_toolbar):
		_toolbar.close_menu(false)
	_toolbar = null
	close_card_preview()
	_pointer_card = null
	_hovered_card = null
	_hover_target = {}
	_drag_ghost = null
	_dragging = false
	_hand_cards.clear()
	_target_frames.clear()
	# Keep the opt-in rig node and its loop clock across local UI rebuilds.
	for id in _actors:
		var actor: BattleActorView = _actors[id]
		if is_instance_valid(actor) and is_instance_valid(actor.rig):
			actor.get_parent().remove_child(actor)
			_pilot_actor_cache[id] = actor
	_actors.clear()
	_task_meters.clear()
	_buttons.clear()
	_drafts.clear()
	_last_action.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stage = Control.new()
	var aspect := size.x / maxf(size.y, 1.0)
	var height := clampf(1280.0 / maxf(aspect, 0.1), 560.0 if _short_web else 690.0, 800.0)
	_stage.size = Vector2(maxf(1280.0, aspect * height), height)
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
	var factor := minf(size.x / _stage.size.x, size.y / _stage.size.y)
	_stage.scale = Vector2.ONE*factor
	_stage.position = (size-_stage.size*factor)*.5


func _rebuild_for_size() -> void:
	_battle_resize_pending = false
	if is_inside_tree() and size != _battle_layout_size:
		if _result_pending:
			_finish_event_presentation()
			return
		_presentation.finish()
		_render_battle()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_reference) and _reference.visible:
		return
	if _result_pending or not is_visible_in_tree() or not is_instance_valid(_stage):
		return
	if is_instance_valid(_full_map) and _full_map.visible:
		return
	if event is InputEventScreenTouch and event.canceled:
		if _dragging:
			_render_from_local()
		_pointer_card = null
		return
	if is_instance_valid(_toolbar) and _toolbar.route_input(event):
		return
	if _block_repeated_turn_input(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_card_preview) and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_card_preview()
		get_viewport().set_input_as_handled()
		return
	if _preview_pinned:
		if event is InputEventMouseButton and not _card_preview.get_global_rect().has_point(get_global_mouse_position()):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse:
		_touch_pointer = event.device == InputEvent.DEVICE_ID_EMULATION
		_pointer_position = event.position
		_update_pointer(0.0)
		var detail_target := _pinned_card_detail if not _pinned_card_detail.is_empty() else _hover_target
		if _hover_panel.visible and _is_card_detail(detail_target) and _over_card_detail_panel(event.position):
			return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not is_locked():
		match event.keycode:
			KEY_F10:
				press("battle:options")
			KEY_P:
				if not _is_card_detail(_hover_target):
					_hover_pinned = not _hover_pinned
			KEY_G, KEY_F1:
				_show_rules()
			KEY_D:
				_show_deck()
			KEY_L:
				_show_log()
			KEY_M:
				_show_map()
			KEY_E:
				if _panel_text.is_empty():
					_emit_draft(_end_turn_draft().call())
			_:
				pass
		if event.keycode in [KEY_P, KEY_G, KEY_F1, KEY_D, KEY_L, KEY_E, KEY_M, KEY_F10]:
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
		if not is_locked() or _is_card_detail(_current_inspect_target()) or not _pinned_card_detail.is_empty():
			_toggle_detail()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _pinned_card_detail.is_empty():
			close_card_preview()
			get_viewport().set_input_as_handled()
			return
		_hover_pinned = false
		if is_locked():
			if not _choice_selected_ids.is_empty():
				_clear_choice_selection()
				get_viewport().set_input_as_handled()
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
				if card.disabled and not _touch_pointer:
					_show_disabled_card_feedback(card)
				else:
					_pointer_card = card
					_pointer_start = event.position
					_held_for = 0.0
				get_viewport().set_input_as_handled()
		elif is_instance_valid(_pointer_card):
			get_viewport().set_input_as_handled()
			var card_id := str(_pointer_card.card_data.get("card_id", ""))
			if _dragging:
				_finish_drag(event.position)
			else:
				var card := _pointer_card
				_pointer_card = null
				if card.disabled:
					_show_disabled_card_feedback(card)
				elif not _touch_pointer or event.position.distance_to(_pointer_start) < 14:
					_on_card_pressed(card_id)
	elif event is InputEventMouseMotion and is_instance_valid(_pointer_card):
		if not _dragging and event.position.distance_to(_pointer_start) > (14 if _touch_pointer else 10):
			if not _pointer_card.disabled:
				_begin_drag()
			else:
				_pointer_card = null
		if _dragging:
			_move_drag(event.position)
		get_viewport().set_input_as_handled()


func _card_at(point: Vector2) -> BattleCard:
	# Within the fan, stable home slots win over a raised card's expanded face.
	# Otherwise the current card traps the pointer while crossing its neighbour.
	for index in range(_hand_cards.size() - 1, -1, -1):
		if _presentation.is_pending(str(_hand_cards[index].card_data.get("card_id", ""))):
			continue
		if _hand_cards[index].contains_home(point):
			return _hand_cards[index]
	if is_instance_valid(_hovered_card) and not _presentation.is_pending(str(_hovered_card.card_data.get("card_id", ""))) and _hovered_card.contains_global(point):
		return _hovered_card
	return null


func _over_card_detail_panel(point: Vector2) -> bool:
	if not is_instance_valid(_hover_panel):
		return false
	var panel_rect := _hover_panel.get_global_rect()
	if panel_rect.has_point(point):
		return true
	var target := _pinned_card_detail if not _pinned_card_detail.is_empty() else _hover_target
	var raw_rect: Variant = target.get("rect", Rect2())
	if not raw_rect is Rect2:
		return false
	var card_rect: Rect2 = raw_rect
	var top := maxf(card_rect.position.y, panel_rect.position.y)
	var bottom := minf(card_rect.end.y, panel_rect.end.y)
	if bottom <= top:
		return false
	# Let the pointer cross the narrow gap into the side panel without the
	# hover target disappearing before it can reach the dropdown.
	if card_rect.end.x <= panel_rect.position.x:
		return (
			point.x >= card_rect.end.x
			and point.x <= panel_rect.position.x
			and point.y >= top
			and point.y <= bottom
		)
	if panel_rect.end.x <= card_rect.position.x:
		return (
			point.x >= panel_rect.end.x
			and point.x <= card_rect.position.x
			and point.y >= top
			and point.y <= bottom
		)
	return false


func _update_pointer(delta: float) -> void:
	if is_instance_valid(_toolbar) and _toolbar.is_menu_open():
		_hover_target = {}
		if is_instance_valid(_hover_panel):
			_hover_panel.hide()
		return
	if not is_instance_valid(_stage):
		return
	var pinned_target := _pinned_card_detail if not _pinned_card_detail.is_empty() else _hover_target
	var reading_pinned := not _pinned_card_detail.is_empty() and _hover_panel.visible and _hover_panel.get_global_rect().has_point(_pointer_position)
	var reading_card_panel := (
		_hover_panel.visible
		and _is_card_detail(pinned_target)
		and _over_card_detail_panel(_pointer_position)
	)
	var reading_detail := reading_pinned or reading_card_panel
	if not is_locked() and _panel_text.is_empty() and not is_instance_valid(_card_preview):
		_hovered_card = null if _touch_pointer or _dragging or reading_detail else _card_at(_pointer_position)
		if not _hover_pinned:
			if not reading_detail:
				_hover_target = {} if _touch_pointer or _dragging else _hover_target_at(_pointer_position)
			if _hover_target.is_empty() and not reading_detail:
				var focus := get_viewport().gui_get_focus_owner()
				if focus is BattlePileButton and not focus.disabled:
					_hover_target = focus.hover_content()
				elif focus is BattleStatusSlot and not focus.disabled:
					_hover_target = _buff_hover_target(str(focus.get_meta("uid", "")))
				elif focus is Button and not focus.disabled and str(focus.get_meta("uid", "")).begins_with("detail:task:"):
					_hover_target = _target_for_uid(str(focus.get_meta("uid")))
	else:
		_hovered_card = null
		_hover_target = {} if reading_detail or _dragging else _hover_card_at(_pointer_position)
	var hover_uid := str(_hover_target.get("uid", ""))
	if hover_uid != _last_hover_uid:
		_last_hover_uid = hover_uid
		if not hover_uid.is_empty() and audio != null:
			audio.play_ui("ui_hover")
	for card in _hand_cards:
		if card.get_meta("card_in_flight", false) or card.get_meta("draw_pending", false):
			continue
		var raised := card == _hovered_card or card.selected
		var destination := card.home_position + (Vector2(0, -34 if _stage.size.y < 800.0 else -60) if raised else Vector2.ZERO)
		card.position = card.position.lerp(destination, minf(1, delta * 18))
		card.rotation = lerp_angle(
			card.rotation, 0.0 if raised else card.home_rotation, minf(1, delta * 18)
		)
		card.scale = card.scale.lerp(Vector2.ONE * card.home_scale * (1.16 if raised else 1.0), minf(1, delta * 18))
		card.z_index = 60 if raised else card.home_order
		card.highlighted = raised
		card.queue_redraw()
	if is_instance_valid(_hovered_card) and not _hover_pinned:
		_hover_target = _card_hover_target(_hovered_card)
	var card_uid := str(_hover_target.get("uid", "")) if _is_card_detail(_hover_target) else ""
	if card_uid != _card_hover_uid:
		_card_hover_uid = card_uid
		_card_hover_elapsed = 0.0
	if not card_uid.is_empty():
		_card_hover_elapsed += delta
	_update_hover_window()
	if is_instance_valid(_aim):
		_aim.visible = (
			not _selected_card_id.is_empty() and not is_locked() and _panel_text.is_empty()
		)
		if _aim.visible:
			_aim.origin = Vector2(_stage.size.x * 0.5, _hand_top + 26)
			_aim.destination = (
				_stage.get_global_transform_with_canvas().affine_inverse() * _pointer_position
			)
			_aim.valid_target = not _target_at(_pointer_position).is_empty()
			_aim.queue_redraw()


func _update_hover_window() -> void:
	if not is_instance_valid(_hover_panel):
		return
	var pinned := not _pinned_card_detail.is_empty()
	var target := _pinned_card_detail if pinned else _hover_target
	var card_detail := _is_card_detail(target)
	var show := not target.is_empty() and not _result_pending and not is_instance_valid(_card_preview)
	if card_detail:
		show = show and (pinned or _card_hover_elapsed >= CARD_DETAIL_DELAY)
	else:
		show = show and not is_locked() and _panel_text.is_empty()
	_hover_panel.visible = show
	if not show:
		_glossary_open = false
		_glossary_uid = ""
		return
	_hover_title.text = str(target.get("title", ""))
	_hover_meta.text = str(target.get("meta", ""))
	var factor := UiStyle.text_scale
	var width := minf((380.0 if card_detail else 360.0) * minf(factor, 1.2), _stage.size.x - 24)
	var height := minf(440.0 * factor, _stage.size.y - 100) if card_detail else 168.0 * factor
	if _compact_layout and not card_detail and is_instance_valid(header):
		# Large text still needs a summary above the protected hand/action zones.
		# Full content remains in I details, with the existing scrolling behavior.
		height = minf(height,maxf(150,header.size.y-24))
	_hover_panel.size = Vector2(width, height)
	_hover_panel.z_index = 350 if card_detail else 120
	# Card details now own a clickable dropdown, so the unfixed window also
	# keeps pointer input while it is open. Summaries still pass events through.
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_STOP if card_detail else Control.MOUSE_FILTER_IGNORE
	_hover_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if card_detail else Control.MOUSE_FILTER_IGNORE
	_hover_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if card_detail else ScrollContainer.SCROLL_MODE_DISABLED
	_hover_body.max_lines_visible = -1 if card_detail else 4
	if card_detail:
		_place_card_detail(target)
	else:
		_place_hover_panel()
	width = _hover_panel.size.x
	_hover_title.size.x = width - 32 * factor
	_hover_meta.size.x = width - 32 * factor
	var text := str(target.get("detail" if card_detail else "body", ""))
	if _hover_body.text != text:
		_hover_scroll.scroll_vertical = 0
		_hover_body.text = text
	if card_detail:
		var glossary_uid := str(target.get("uid", ""))
		if glossary_uid != _glossary_uid:
			_glossary_uid = glossary_uid
			_glossary_open = false
		_glossary_body.text = str(target.get("glossary", ""))
		if _glossary_scroll.scroll_vertical != 0 and not _glossary_open:
			_glossary_scroll.scroll_vertical = 0
	else:
		_glossary_uid = ""
		_glossary_open = false
		_glossary_body.text = ""
	_layout_hover_sections(width, height, factor, card_detail)
	var has_glossary := card_detail and not _glossary_body.text.strip_edges().is_empty()
	var glossary_action := "收起" if _glossary_open else "展开"
	if card_detail:
		if pinned:
			_hover_hint.text = (
				"点名词解释%s · I 取消固定" % glossary_action
				if has_glossary
				else "已固定 · 滚轮阅读 · I 取消固定"
			)
		else:
			_hover_hint.text = (
				"点名词解释%s · I 固定介绍" % glossary_action
				if has_glossary
				else "移开收起 · I 固定介绍"
			)
	else:
		_hover_hint.text = "I 查看详情"


func _layout_hover_sections(width: float, height: float, factor: float, card_detail: bool) -> void:
	var content_left := 16.0 * factor
	var content_width := width - 32.0 * factor
	var content_top := 62.0 * factor
	var hint_top := height - 22.0 * factor
	_hover_hint.position = Vector2(content_left, hint_top)
	_hover_hint.size.x = content_width
	var toggle_height := maxf(32.0, 32.0 * factor)
	var toggle_top := hint_top - toggle_height - 4.0 * factor
	var body_bottom := hint_top - 8.0 * factor
	var has_glossary := card_detail and not _glossary_body.text.strip_edges().is_empty()
	if has_glossary:
		_glossary_toggle.visible = true
		_glossary_toggle.position = Vector2(content_left, toggle_top)
		_glossary_toggle.size = Vector2(content_width, toggle_height)
		_glossary_toggle.text = ("▾  名词解释" if _glossary_open else "▸  名词解释")
		body_bottom = toggle_top - 8.0 * factor
		if _glossary_open:
			var available := maxf(0.0, toggle_top - 8.0 * factor - content_top)
			var glossary_height := minf(150.0 * factor, maxf(64.0 * factor, available * 0.45))
			glossary_height = minf(glossary_height, maxf(0.0, available - 72.0 * factor))
			_glossary_box.visible = glossary_height > 0
			if _glossary_box.visible:
				_glossary_box.position = Vector2(content_left, toggle_top - glossary_height - 6.0 * factor)
				_glossary_box.size = Vector2(content_width, glossary_height)
				body_bottom = _glossary_box.position.y - 8.0 * factor
		else:
			_glossary_box.visible = false
	else:
		_glossary_toggle.visible = false
		_glossary_box.visible = false
	_hover_scroll.position = Vector2(content_left, content_top)
	_hover_scroll.size = Vector2(content_width, maxf(40.0 * factor, body_bottom - content_top))
	_hover_body.custom_minimum_size.x = _hover_scroll.size.x - 16


func _toggle_glossary() -> void:
	if _glossary_body.text.strip_edges().is_empty():
		return
	_glossary_open = not _glossary_open
	if _glossary_open:
		_glossary_scroll.scroll_vertical = 0
	_update_hover_window()


func _is_card_detail(target: Dictionary) -> bool:
	return bool(target.get("card_detail", false))


func _place_card_detail(target: Dictionary) -> void:
	var inverse := _stage.get_global_transform_with_canvas().affine_inverse()
	var bounds: Rect2 = inverse * target.get("rect", Rect2())
	var gap := 14.0 / maxf(.1,_stage.scale.x)
	var left_space := bounds.position.x - gap - 12
	var right_space := _stage.size.x - bounds.end.x - gap - 12
	var use_right := right_space >= left_space
	var width := minf(_hover_panel.size.x, maxf(left_space, right_space))
	if width < 160:
		_hover_panel.visible = false
		return
	_hover_panel.size.x = width
	var x := bounds.end.x + gap if use_right else bounds.position.x - gap - width
	var top := 12.0 if _compact_layout else 76.0
	var y := clampf(bounds.position.y, top, maxf(top, _stage.size.y - _hover_panel.size.y - 12))
	_hover_panel.position = Vector2(x, y)


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
	if is_instance_valid(_hint_label):
		protected_rects.append(_hint_label.get_global_rect())
	for uid in ["battle:end_turn", "battle:cancel"]:
		if _buttons.has(uid) and _buttons[uid].is_visible_in_tree():
			protected_rects.append(_button_rect(uid))
	for uid in _buttons:
		var card := _buttons[uid] as Control
		if not str(uid).begins_with("card:") or not card.is_visible_in_tree():
			continue
		var bounds: Rect2 = card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
		var ancestor := card.get_parent()
		while ancestor is Control:
			if ancestor.clip_contents:
				bounds = bounds.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		if bounds.has_area():
			protected_rects.append(bounds.grow(16))
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
	if is_instance_valid(_hint_label):
		var hint_end := (inverse * _hint_label.get_global_rect()).end.y + 12
		candidates.append(Vector2(12,hint_end))
		candidates.append(Vector2(canvas.x-size.x-12,hint_end))
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
	# A missing summary is preferable to covering a card or an action. I remains available.
	_hover_panel.visible = false


func _hover_target_at(point: Vector2) -> Dictionary:
	var card_target := _hover_card_at(point)
	if not card_target.is_empty():
		return card_target
	for uid in _buttons:
		if _buttons[uid] is BattleStatusSlot and _button_hit(str(uid), point):
			var slot: BattleStatusSlot = _buttons[uid]
			var scroll: ScrollContainer = slot.get_meta("status_scroll")
			if scroll.get_global_rect().has_point(point):
				return _buff_hover_target(str(uid))
	for uid in _buttons:
		var key := str(uid)
		if _buttons[uid] is BattlePileButton and not _buttons[uid].disabled and _button_hit(key, point):
			return _buttons[uid].hover_content()
		if key.begins_with("detail:task:") and _button_hit(key, point):
			return _target_for_uid(key)
		if key.begins_with("task:") and _button_hit(key, point):
			return _task_hover_target(key.trim_prefix("task:"))
		if key.begins_with("unit:") and _button_hit(key, point):
			return _unit_hover_target(key.trim_prefix("unit:"))
	return {}


func _hover_card_at(point: Vector2) -> Dictionary:
	if not is_locked() and _panel_text.is_empty() and is_instance_valid(_hovered_card):
		return _card_hover_target(_hovered_card)
	for uid in _buttons:
		var key := str(uid)
		var control := _buttons[uid] as Control
		if not (control is UiOfferCard or control is BattleCard):
			continue
		if is_locked() and not key.begins_with("choice:"):
			continue
		if not _panel_text.is_empty() and not key.begins_with("pile:card:"):
			continue
		if not control.is_visible_in_tree() or control.get_meta("draw_pending", false) or control.get_meta("card_in_flight", false):
			continue
		if _visible_card_rect(control).has_point(point):
			return _offer_card_hover_target(control) if control is UiOfferCard else _card_hover_target(control)
	return {}


func _visible_card_rect(control: Control) -> Rect2:
	var bounds: Rect2 = control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	var ancestor := control.get_parent()
	while ancestor is Control:
		if ancestor.clip_contents:
			bounds = bounds.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return bounds


func _offer_card_hover_target(card: UiOfferCard) -> Dictionary:
	var detail := _battle_card_detail(card.detail)
	return {
		"uid": str(card.get_meta("uid", "")), "card_detail": true,
		"title": UiStyle.label(card.definition_id),
		"meta": "%s · 专注 %s" % [UiStyle.label(str(detail.get("type", ""))), detail.get("cost", 0)],
		"body": UiContentText.card_summary(detail),
		"detail": UiStyle.label(card.definition_id) + "\n" + UiContentText.describe_battle_card(detail),
		"glossary": UiContentText.describe_battle_card_glossary(detail),
		"terms": [], "rect": _visible_card_rect(card),
	}


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
	var detail_data := _battle_card_detail(face)
	detail_data["cost"] = data.get("effective_cost", detail_data.get("cost", 0))
	detail_data["vitality_cost"] = data.get("effective_vitality_cost", detail_data.get("vitality_cost", 0))
	var body := UiContentText.describe_battle_card(detail_data)
	var terms := _card_terms(face, card_type)
	var meta := "%s · 专注 %s" % [UiStyle.label(card_type), data.get("effective_cost", "—")]
	if int(data.get("effective_vitality_cost", 0)) > 0:
		meta += " · 精力 %s" % data.get("effective_vitality_cost", 0)
	return {
		"uid": "card:" + str(data.get("card_id", "")),
		"card_detail": true,
		"title": UiStyle.label(definition_id),
		"meta": meta,
		"body": effect_text if reason.is_empty() else "无法打出：" + reason,
		"summary": summary,
		"detail": UiStyle.label(definition_id) + "\n" + body,
		"glossary": UiContentText.describe_battle_card_glossary(detail_data),
		"terms": terms,
		"rect": _visible_card_rect(card),
	}


func _show_card_preview(pinned: bool) -> void:
	if pinned and is_instance_valid(_preview_card):
		_pin_card_detail(_offer_card_hover_target(_preview_card))


func close_card_preview() -> void:
	super.close_card_preview()
	_pinned_card_detail = {}
	_card_hover_uid = ""
	_card_hover_elapsed = 0.0
	_glossary_open = false
	_glossary_uid = ""
	if is_instance_valid(_hover_panel):
		_hover_panel.visible = false


func _pin_card_detail(target: Dictionary) -> void:
	if not _is_card_detail(target):
		return
	_pinned_card_detail = target.duplicate(true)
	_hover_pinned = false
	_update_hover_window()


func _card_preview_text(detail: Dictionary) -> String:
	if detail.has("campaign") or detail.has("hooks"):
		return super._card_preview_text(detail)
	return UiContentText.describe_battle_card(_battle_card_detail(detail))


func _card_preview_keyword_help(_detail: Dictionary) -> String:
	return ""


func _battle_card_detail(face: Dictionary) -> Dictionary:
	var detail := face.duplicate(true)
	# Only enrich references used by the active face; never replace its effects or costs.
	for effect in _array(face.get("effects")) + _array(face.get("pre_effects")):
		for pair in [["unit", "related_units"], ["scene", "related_scenes"]]:
			var reference := str(_dict(effect).get(pair[0], ""))
			if reference.is_empty():
				continue
			for card in _array(view.get("cards")):
				for source in [_dict(card).get("detail"), _dict(card).get("upgrade_detail")]:
					var metadata := _dict(source)
					if str(metadata.get("id", "")) != str(face.get("id", "")):
						continue
					var related := _dict(metadata.get(pair[1]))
					if related.has(reference):
						if not detail.has(pair[1]):
							detail[pair[1]] = {}
						detail[pair[1]][reference] = related[reference].duplicate(true)
	return detail


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
	var intent := _dict(task.get("intent_snapshot"))
	var phase := _dict(task.get("intent_phase"))
	var intent_summary := _task_intent_text(task)
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
	summary += "\n结束回合后：" + intent_summary
	var phase_name := str(phase.get("name_key", ""))
	var task_name := UiStyle.label(str(task.get("definition_id", "")))
	var lines: Array[String] = [
		"%s · 第 %s/%s 阶段%s" % [task_name, phase_index, phase_count, " · " + UiStyle.label(phase_name) if not phase_name.is_empty() else ""],
		"未完成量 %s/%s · 屏障 %s" % [task.get("work_remaining", 0), task.get("work_max", 0), task.get("shield", 0)],
	]
	var action_name := str(intent.get("text_key", ""))
	var timing := "\n结束回合后"
	if not action_name.is_empty() and not task.get("intent_waiting", false):
		timing += " · " + UiStyle.label(action_name)
	lines.append(timing)
	lines.append(TaskIntentText.describe(intent, task, _dict(view.get("status_rules"))))
	if not statuses.is_empty():
		lines.append("\n当前状态：" + _status_text(statuses))
	var traits := _dict(task.get("traits")).duplicate()
	traits.taunt = task.get("taunting", false)
	var trait_lines := TaskIntentText.traits(traits)
	if not trait_lines.is_empty():
		lines.append("\n特殊机制")
		lines.append_array(trait_lines)
	var intents := _array(phase.get("intents"))
	if intents.size() > 1:
		lines.append("\n本阶段意图顺序（基础效果）")
		lines.append(TaskIntentText.sequence_rule(phase))
		for index in intents.size():
			var marker := "（当前）" if index == int(task.get("intent_cursor", 0)) else ""
			lines.append("%d. %s%s" % [index + 1, TaskIntentText.summary(intents[index], {}, 3), marker])
	var terms: Array[String] = ["pressure", "shield", "ddl"]
	var predicted_status := str(_dict(intent.get("gain_status")).get("status", ""))
	if UiGlossary.ENTRIES.has(predicted_status):
		terms.append(predicted_status)
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
		"body": "屏障 %s\n结束回合后：%s" % [task.get("shield", 0), intent_summary],
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


func _buff_hover_target(uid: String) -> Dictionary:
	var slot: BattleStatusSlot = _buttons.get(uid)
	if not is_instance_valid(slot):
		return {}
	var entry := slot.entry
	var title := str(entry.title)
	var count := str(entry.get("count", ""))
	var meta := "负面状态" if entry.get("negative", false) else "增益 / 持续效果"
	if entry.has("mechanic"):
		meta = "特殊机制 · " + str(entry.mechanic)
	elif not count.is_empty():
		meta += " · " + ("下回合生效" if count == "待" else "当前 %s" % count)
	return {"uid":uid, "title":title, "meta":meta, "body":str(entry.body), "detail":title + "\n" + meta + "\n\n" + str(entry.body), "terms":[], "rect":slot.get_global_rect().intersection((slot.get_meta("status_scroll") as Control).get_global_rect())}


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
	if uid.begins_with("buff:"):
		return _buff_hover_target(uid)
	if _buttons.get(uid) is UiOfferCard:
		return _offer_card_hover_target(_buttons[uid])
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
	if uid.begins_with("detail:task:"):
		var target := _task_hover_target(uid.trim_prefix("detail:task:"))
		if not target.is_empty():
			target.uid = uid
			target.rect = _button_rect(uid)
		return target
	if uid.begins_with("unit:"):
		return _unit_hover_target(uid.trim_prefix("unit:"))
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
	if focus is UiOfferCard:
		return _offer_card_hover_target(focus)
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
	if not _pinned_card_detail.is_empty():
		close_card_preview()
		return
	var target := _current_inspect_target()
	if _is_card_detail(target):
		_pin_card_detail(target)
		return
	if _inspect_open:
		_close_panel()
		return
	if not _panel_text.is_empty():
		return
	var uid := str(target.get("uid", ""))
	if uid.begins_with("buff:") or uid.begins_with("detail:task:"):
		_open_detail_for_uid(uid)
	else:
		_open_detail(target)


func _open_detail_for_uid(uid: String) -> void:
	if uid.begins_with("buff:") and _buttons.has(uid):
		_detail_return_uid = uid
		_status_return_scroll = (_buttons[uid].get_meta("status_scroll") as ScrollContainer).scroll_horizontal
	elif uid.begins_with("detail:task:") and _buttons.has(uid):
		_detail_return_uid = uid
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
	if target.is_empty() and not Rect2(0, 66, _stage.size.x, _hand_top - 66).has_point(local):
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
		if frame is BattleActorView:
			frame.set_targeted(active)
			continue
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
	elif _touch_pointer:
		_open_detail_for_uid("task:" + task_id)


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
	var ending_turn: bool = draft.get("type") == "end_turn"
	if ending_turn and _end_turn_blocked():
		return
	var quote: Variant = _preview(draft)
	if not _preview_can_submit(quote):
		_feedback_text = _preview_error(quote)
		_render_from_local()
		return
	_feedback_text = ""
	_last_action = draft.duplicate(true)
	_submitted_revision = int(view.get("revision", -1))
	if ending_turn:
		_end_turn_after_ms = Time.get_ticks_msec() + END_TURN_INTERVAL_MS
		_show_end_turn_lock()
	action_requested.emit(draft.duplicate(true))


func _end_turn_blocked() -> bool:
	return _end_turn_after_ms > 0 and (
		Time.get_ticks_msec() < _end_turn_after_ms or _animator.is_playing() or _presentation.is_animating()
	)


func _block_repeated_turn_input(event: InputEvent) -> bool:
	var button := _buttons.get("battle:end_turn") as Button
	if button == null or is_locked() or not _panel_text.is_empty():
		return false
	var repeat := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		repeat = _button_hit("battle:end_turn", event.position) and (event.double_click or _end_turn_blocked())
	elif event is InputEventKey and event.pressed and _end_turn_blocked():
		repeat = (event.keycode == KEY_E and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed) or (button.has_focus() and event.is_action_pressed(&"ui_accept", true))
	if repeat and _end_turn_after_ms > 0:
		_end_turn_after_ms = Time.get_ticks_msec() + END_TURN_INTERVAL_MS
		_show_end_turn_lock()
	return repeat


func _show_end_turn_lock() -> void:
	if not _end_turn_blocked() or not _buttons.has("battle:end_turn"):
		return
	var button: Button = _buttons["battle:end_turn"]
	button.disabled = true
	var caption := "回合结算中" if _animator.is_playing() or _presentation.is_animating() else "请稍候"
	if button.text != caption:
		button.text = caption
	button.tooltip_text = "本次结束回合已提交"


func _refresh_end_turn() -> void:
	if _end_turn_after_ms == 0 or is_locked() or not _panel_text.is_empty() or not _buttons.has("battle:end_turn"):
		return
	if (is_instance_valid(_full_map) and _full_map.visible) or (is_instance_valid(_toolbar) and _toolbar.is_menu_open()):
		return
	if _end_turn_blocked():
		_show_end_turn_lock()
		return
	_end_turn_after_ms = 0
	_buttons["battle:end_turn"].text = "结束回合"
	var quote: Variant = _preview(action_draft("battle:end_turn"))
	_set_enabled("battle:end_turn", _preview_can_submit(quote), _preview_error(quote))


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
	elif max_count == 1:
		_choice_selected_ids.assign([id])
	elif _choice_selected_ids.size() < max_count:
		_choice_selected_ids.append(id)
	else:
		_sync_choice_controls(true)
		return
	_sync_choice_controls()
	local_selection_changed.emit(selection_snapshot())


func _clear_choice_selection() -> void:
	_choice_selected_ids.clear()
	_sync_choice_controls()
	local_selection_changed.emit(selection_snapshot())


func _sync_choice_arrows(bar: HScrollBar, previous: Button, next: Button) -> void:
	if not is_instance_valid(bar) or not is_instance_valid(previous) or not is_instance_valid(next):
		return
	previous.disabled = bar.value <= 0
	next.disabled = bar.value + bar.page >= bar.max_value - 1


func _choice_labels(kind: String) -> Array:
	return {
		"discard": ["从手牌弃牌", "确认弃牌", "跳过弃牌"],
		"recall": ["从弃牌堆取回", "取回所选牌", "不取回"],
		"retrieve_strategy": ["取回上一张策略", "取回此牌", "不取回"],
		"retain": ["保留到下一轮", "保留所选牌", "不保留"],
		"exhaust": ["选择耗尽的牌", "确认耗尽", "跳过耗尽"],
		"remove_status": ["选择要解除的状态", "解除所选状态", "跳过解除"],
		"purify": ["选择要净化的状态", "净化所选状态", "跳过净化"],
		"chapter_replace": ["选择要撤下的章节", "确认撤下", "跳过撤下"],
		"change_topic": ["选择要重置的已用牌名", "重置牌名并抽牌", "仅抽牌"],
	}.get(kind, ["完成卡牌效果", "确认选择", "跳过本次"])


func _sync_choice_controls(at_limit: bool = false) -> void:
	if not is_locked():
		return
	var choice := _choice_dict(view.get("pending_choice"))
	var count := _choice_selected_ids.size()
	var minimum := int(choice.get("min_count", 0))
	var maximum := int(choice.get("max_count", 0))
	var kind := str(choice.get("kind", ""))
	if is_instance_valid(_choice_status):
		var unit: String = {"change_topic": "个", "remove_status": "项", "purify": "项", "chapter_replace": "项"}.get(kind, "张")
		var required := "须选 %d" % minimum if minimum == maximum else ("最多选 %d" % maximum if minimum == 0 else "可选 %d 至 %d" % [minimum, maximum])
		var tip := " · 还需选 %d %s" % [minimum - count, unit] if count < minimum else ""
		if at_limit:
			tip = " · 已选满，可点已选项取消"
		elif kind == "retrieve_strategy":
			tip = " · 本轮取回机会已触发"
		_choice_status.text = "%s %s · 已选 %d %s%s" % [required, unit, count, unit, tip]
	for value in _array(choice.get("candidates")):
		var uid := "choice:" + str(value.get("id", value.get("candidate_id", "")))
		var button: Button = _buttons.get(uid)
		var selected := _choice_selected_ids.has(uid.trim_prefix("choice:"))
		if button is BattleCard or button is UiOfferCard:
			button.selected = selected
			button.accessibility_description = "已选" if selected else "可选"
			button.queue_redraw()
			var marker := button.get_meta("choice_marker", null) as Label
			if is_instance_valid(marker):
				marker.text = "✓ 已选" if selected else ""
		elif is_instance_valid(button):
			button.text = ("✓ " if selected else "") + button.text.trim_prefix("✓ ")
			UiStyle.button_skin(button, "selected" if selected else "secondary", true)
	if _buttons.has("choice:clear"):
		_buttons["choice:clear"].disabled = count == 0
	if _buttons.has("choice:confirm"):
		var labels := _choice_labels(kind)
		_buttons["choice:confirm"].text = labels[2] if count == 0 and minimum == 0 else labels[1]
		_apply_preview_gating()
		_apply_lock_state()


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
	_show_end_turn_lock()
	var selection_field := _selection_kind()
	var candidates := _selection_candidate_ids(selection_field)
	for value in _array(view.get("tasks")):
		var task := _dict(value)
		var id := str(task.get("task_id", ""))
		var allowed := UiStyle.web_touch
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
		_buttons[uid].tooltip_text = str(_buttons[uid].get_meta("navigation_hint", "")) if enabled else reason


func _render_from_local() -> void:
	var current := view.duplicate(true)
	render(current)


func _on_event_presented(event: Dictionary, text: String) -> void:
	_present_event_visual(event)
	var notice := _task_event_notice(event)
	if not notice.is_empty() and not _task_event_notices.has(notice):
		_task_event_notices.append(notice)
	if str(event.get("type", "")) == "relic_triggered":
		var data := _dict(event.get("data"))
		var id := str(data.get("relic_id", ""))
		if RelicPilot.is_rx(id):
			if is_instance_valid(_toolbar) and animation_enabled:
				_toolbar.flash_relic(id)
			text = _rx_trigger_text(id, data)
	if str(event.get("type", "")) == "card_drawn":
		var queued := _animator.pending_type_count("card_drawn")
		text += " · 正在抽牌 · 排队中：%d 张" % queued
	if audio != null:
		if str(event.get("type", "")) == "ddl_ticked":
			audio.play_deadline(int(_dict(event.get("data")).get("after", 0)))
		else:
			audio.play_event(str(event.get("type", "")))
	_feedback_text = text
	_update_feedback_label()


func _visible_feedback() -> String:
	return _feedback_text if _task_event_notices.is_empty() else "  ·  ".join(_task_event_notices)


func _update_feedback_label() -> void:
	if is_instance_valid(_feedback_label):
		_feedback_label.text = _visible_feedback()
		_feedback_label.visible = not _feedback_label.text.is_empty()


func _task_event_notice(event: Dictionary) -> String:
	var data := _dict(event.get("data"))
	match str(event.get("type", "")):
		"task_summoned":
			var text := "召唤 " + UiStyle.label(str(data.get("definition_id", "")))
			for task in _array(view.get("tasks")):
				if task.get("task_id", "") in _array(event.get("target_ids")) and task.get("taunting", false):
					return text + "（嘲讽）"
			return text
		"task_transformed":
			return "%s 转化为 %s" % [
				UiStyle.label(str(data.get("from_definition_id", ""))),
				UiStyle.label(str(data.get("to_definition_id", "")))
			]
		"task_self_destructed":
			return UiStyle.label(str(data.get("definition_id", ""))) + " 自爆退场"
	return ""


func _show_disabled_card_feedback(card: Button) -> void:
	_task_event_notices.clear()
	_feedback_text = str(card.get_meta("disabled_reason", "无法打出"))
	if _feedback_text.is_empty():
		_feedback_text = "当前无法打出这张牌"
	_update_feedback_label()


func _active_visual_effect_count() -> int:
	if not is_instance_valid(_stage):
		return 0
	var count := 0
	for child in _stage.get_children():
		if child.has_meta("battle_event_effect") and not child.is_queued_for_deletion():
			count += 1
	return count


func _clear_event_visuals() -> void:
	for actor in _actors.values():
		if is_instance_valid(actor):
			actor.reset_pose()
	if not is_instance_valid(_stage):
		return
	for child in _stage.get_children():
		if child.has_meta("battle_event_effect"):
			_stage.remove_child(child)
			child.queue_free()


func _rx_trigger_text(id: String, data: Dictionary) -> String:
	var resource := str(data.get("resource",""))
	if not resource.is_empty():
		return "%s触发 · %s %d · 剩余 %d 次" % [UiStyle.label(id),resource,int(data.get("amount",0)),int(data.get("remaining",0))]
	resource = "放松"
	match str(data.get("at", "")):
		"natural_focus":
			resource = "放松" if id == "RX-C01" else "专注"
		"base_draw", "strategy_without_work":
			resource = "张牌入手"
		"alarm_draw", "next_card_resolved", "partner_switched_draw":
			resource = "抽牌"
		"work_primary_segment", "paper_publish", "natural_induced":
			resource = "完成量"
		"paper_open":
			resource = "论文修正"
		"direct_erosion":
			resource = "侵蚀"
		"extra_cooperation":
			resource = "伙伴精力"
	return "%s触发 · %s +%d · 剩余 %d 次" % [UiStyle.label(id), resource, int(data.get("amount", 0)), int(data.get("remaining", 0))]


func _present_event_visual(event: Dictionary) -> void:
	if not animation_enabled or not is_instance_valid(_stage):
		return
	var kind := str(event.get("type", ""))
	var data := _dict(event.get("data"))
	_stage_effects.present(event)
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
			_schedule_impact_feedback(event, data, true)
		"pressure_applied":
			_schedule_impact_feedback(event, data, false)


func _schedule_impact_feedback(event: Dictionary, data: Dictionary, completion: bool) -> void:
	var callback := _show_completion_feedback.bind(event, data) if completion else _show_pressure_feedback.bind(event, data)
	var delay := _stage_effects.impact_feedback_delay(event)
	if delay <= .005:
		callback.call()
		return
	var tween := create_tween()
	_presentation._tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_callback(callback)


func _show_completion_feedback(event: Dictionary, data: Dictionary) -> void:
	var targets := _array(event.get("target_ids"))
	if targets.is_empty():
		return
	var target_id := "task:" + str(targets[0])
	var target: Control = _target_frames.get(target_id)
	if not _stage_effects.has_actor(str(targets[0])):
		return
	var center := _stage_effects.target_anchor(str(targets[0]))
	var parts: Array[String] = []
	var work_lost := maxi(0, int(data.get("work_before", 0)) - int(data.get("work_after", 0)))
	var shield_lost := maxi(0, int(data.get("shield_before", 0)) - int(data.get("shield_after", 0)))
	if work_lost > 0 and not use_shell_damage_popups:
		parts.append("完成量 −%d" % work_lost)
	if shield_lost > 0:
		parts.append("屏障 −%d" % shield_lost)
	if work_lost == 0 and shield_lost == 0:
		return
	_presentation.animate_meter(str(targets[0]), data)
	if not parts.is_empty():
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
	if not _stage_effects.has_actor(target_id):
		return
	var center := _stage_effects.target_anchor(target_id)
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
	feedback.size = Vector2(minf(300,maxf(40,_stage.size.x-16)), 38)
	feedback.position = center - Vector2(feedback.size.x * 0.5, 36)
	feedback.position.x = clampf(feedback.position.x,8,maxf(8,_stage.size.x-feedback.size.x-8))
	feedback.position.y = clampf(feedback.position.y,34,maxf(34,_stage.size.y-feedback.size.y-8))
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
	_stage_effects.remember()
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
	if is_instance_valid(_toolbar):
		_toolbar.refresh_presentation()


func _cycle_speed() -> void:
	if is_locked():
		return
	speed_scale = 1.0 if speed_scale >= 2.0 else (2.0 if speed_scale >= 1.5 else 1.5)
	_animator.speed_scale = effect_speed()
	if is_instance_valid(_toolbar):
		_toolbar.refresh_presentation()


func _show_draw() -> void:
	_show_zone("draw", "抽牌堆")


func _show_map() -> void:
	if is_locked():
		return
	if is_instance_valid(_full_map) and not _full_map.is_queued_for_deletion():
		_full_map.close()
		return
	close_card_preview()
	_full_map = UiRouteOverlay.new()
	add_child(_full_map)
	_full_map.configure(_array(view.get("route_nodes")),str(view.get("route_current","")),_array(view.get("route_reachable")),str(view.get("year_label","")))
	_toolbar.mark_active("map", true)
	_buttons["battle:close_panel"] = _full_map._close
	_full_map.closed.connect(func():
		_buttons.erase("battle:close_panel")
		if is_instance_valid(_toolbar):
			_toolbar.mark_active("map", false))


func _show_deck() -> void:
	if is_locked():
		return
	_detail_terms.clear()
	_panel_zone = "deck"
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
					UiContentText.describe_battle_card(_dict(card.get("detail")))
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
	if _panel_zone == "route":
		var map_column := VBoxContainer.new()
		map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(map_column)
		add_text(map_column,_panel_text,18,ink)
		var route := UiRouteCanvas.new()
		route.overview = true
		route.overview_height = 260
		route.configure(_array(view.get("route_nodes")),[],str(view.get("route_current","")))
		route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map_column.add_child(route)
		route.arrange.call_deferred()
		return
	if _panel_zone.is_empty():
		add_text(parent, _panel_text, 18, ink)
		return
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	add_text(column, _panel_text.get_slice("\n", 0) + (" · 按卡牌整理，隐藏抽取顺序" if _panel_zone == "draw" else " · 点击 / 悬停查看卡文"), 17, ink)
	var cards := _array(view.get("cards")) if _panel_zone == "deck" else _array(_dict(view.get("zones_public")).get(_panel_zone))
	if cards.is_empty():
		add_text(column, "这里暂时没有卡牌。", 19, ink)
	var grid := GridContainer.new()
	grid.columns = 4 if UiStyle.text_scale <= 1.0 else (3 if UiStyle.text_scale <= 1.25 else 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	column.add_child(grid)
	for card in cards:
		var detail := _dict(card.get("face", card.get("effective_card", card.get("detail",{})))).duplicate(true)
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
	_open_reference("rules")


func _show_log() -> void:
	_open_reference("log")


func _show_relics() -> void:
	_open_reference("relics")


func _open_reference(kind: String, relic_id: String = "") -> void:
	if is_locked() or _result_pending:
		return
	if is_instance_valid(_toolbar):
		_toolbar.close_menu()
	_panel_text = str({"rules": "规则帮助", "log": "战斗记录", "relics": "携带饰品", "info": "冒险信息"}.get(kind, "冒险信息"))
	var overlay := open_reference(kind, relic_id)
	_buttons["battle:close_panel"] = overlay._close
	if is_instance_valid(_toolbar):
		_toolbar.mark_active("relics", kind == "relics")
	overlay.closed.connect(func():
		_panel_text = ""
		_buttons.erase("battle:close_panel")
		if is_instance_valid(_toolbar): _toolbar.mark_active("relics", false))


func _close_panel() -> void:
	if is_instance_valid(_reference):
		_reference.close()
		return
	close_card_preview()
	_panel_zone = ""
	_panel_text = ""
	_detail_terms.clear()
	_inspect_open = false
	_render_from_local()
	if not _detail_return_uid.is_empty():
		_restore_detail_focus.call_deferred()


func _restore_detail_focus() -> void:
	var slot: Button = _buttons.get(_detail_return_uid)
	_detail_return_uid = ""
	if is_instance_valid(slot):
		slot.grab_focus()
		if slot is BattleStatusSlot:
			(slot.get_meta("status_scroll") as ScrollContainer).set_deferred("scroll_horizontal", _status_return_scroll)


func _battle_subtitle() -> String:
	var encounter := str(view.get("encounter_id", ""))
	return UiStyle.label(encounter) if not encounter.is_empty() else "公开任务与行动"


func tutorial_anchor(key: String) -> Rect2:
	match key:
		"battle_intents":
			var intent_rect := Rect2()
			for node in find_children("TaskIntent_*", "Label", true, false):
				if node is Control and node.is_visible_in_tree():
					intent_rect = _merge_rect(intent_rect, (node as Control).get_global_rect())
			var turn := find_child("TurnDdlValue", true, false)
			if turn is Control and turn.is_visible_in_tree():
				intent_rect = _merge_rect(intent_rect, (turn as Control).get_global_rect())
			return intent_rect
		"battle_tasks":
			var rect := Rect2()
			for prefix in ["TaskIntent_", "TaskWorkValue_", "TaskTitle_"]:
				for node in find_children(prefix + "*", "Label", true, false):
					if node is Control and node.is_visible_in_tree():
						rect = _merge_rect(rect, (node as Control).get_global_rect())
			var ddl := find_child("TurnDdlValue", true, false)
			if ddl is Control and ddl.is_visible_in_tree():
				rect = _merge_rect(rect, (ddl as Control).get_global_rect())
			return rect
		"battle_focus":
			var focus := find_child("FocusDevice", true, false)
			if focus is Control:
				return (focus as Control).get_global_rect()
		"battle_end_turn":
			var end_turn: Variant = _buttons.get("battle:end_turn")
			if end_turn is Control:
				return (end_turn as Control).get_global_rect()
		"battle_piles":
			var rect := Rect2()
			for uid in ["battle:draw", "battle:discard", "battle:exhaust"]:
				var pile: Variant = _buttons.get(uid)
				if pile is Control:
					rect = _merge_rect(rect, (pile as Control).get_global_rect())
			return rect
		"battle_player":
			var rect := Rect2()
			for node_name in ["PlayerVitalityValue", "PlayerRelaxValue"]:
				var value := find_child(node_name, true, false)
				if value is Control:
					rect = _merge_rect(rect, (value as Control).get_global_rect())
			return rect
	return Rect2()


func _merge_rect(current: Rect2, addition: Rect2) -> Rect2:
	return addition if not current.has_area() else current.merge(addition)


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


func _task_intent_text(task: Dictionary) -> String:
	return TaskIntentText.summary(_dict(task.get("intent_snapshot")), task)


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
		var detail := _dict(card.get("face", card.get("effective_card", card.get("detail",{})))).duplicate(true)
		detail.cost = card.get("effective_cost", detail.get("cost", 0))
		detail.vitality_cost = card.get("effective_vitality_cost", detail.get("vitality_cost", 0))
		lines.append(
			(
				"%s\n%s"
				% [
					UiStyle.label(str(card.get("definition_id", ""))),
					UiContentText.describe_battle_card(detail)
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
		if str(data.get("result", "")) == "won":
			return "战斗胜利"
		var defeat_reasons := {
			"deadline_expired": "DDL 已到期，仍有未完成任务",
			"vitality_depleted": "精力耗尽",
			"battle_lost": "战斗失败",
		}
		return "战斗失败 · " + str(defeat_reasons.get(str(data.get("reason", "")), "战斗结束"))
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
