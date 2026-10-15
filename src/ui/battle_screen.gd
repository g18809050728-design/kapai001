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


func _init() -> void:
	_animator = BattleEventAnimator.new()
	_animator.event_presented.connect(_on_event_presented)


func _process(delta: float) -> void:
	_animator.advance(delta)


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
	reset_page("", "", true)
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
			button_disabled("battle:draw")
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


func action_draft(uid: String) -> Dictionary:
	var draft := super.action_draft(uid)
	if is_locked() and str(draft.get("type", "")) != "confirm_choice":
		return {}
	return draft


func _render_battle() -> void:
	_render_status_bar()
	_render_notice()
	_render_controls(body)
	var main_row := add_row(body)
	var left := _scroll_column(main_row, 1.1)
	_render_tasks(left)
	_render_units(left)
	var right := _scroll_column(main_row, 1.0)
	_render_choice(right)
	_render_selection(right)
	_render_retention(right)
	_render_player(right)
	_render_scene(right)
	_render_hand(body)
	_render_zones_and_log(body)
	_apply_preview_gating()
	_apply_lock_state()


func _render_status_bar() -> void:
	var player := _dict(view.get("player"))
	add_text(
		body,
		(
			"%s · 第 %s 回合 · %s　｜　专注 %s　精力 %s　DDL %s"
			% [
				_battle_subtitle(),
				view.get("round_index", 0),
				UiStyle.label(str(view.get("phase", ""))),
				player.get("focus", 0),
				player.get("vitality", 0),
				view.get("ddl", 0)
			]
		),
		20,
		UiStyle.INK
	)


func _scroll_column(parent: Node, stretch: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = stretch
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	return column


func _compact_panel(parent: Node) -> VBoxContainer:
	var column := add_panel(parent)
	column.add_theme_constant_override("separation", 4)
	var style := UiStyle.box(Color("f3f2e7"))
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	column.get_parent().add_theme_stylebox_override("panel", style)
	return column


func _render_notice() -> void:
	_feedback_label = add_text(
		body, _feedback_text, 18, UiStyle.RED if not _feedback_text.is_empty() else UiStyle.MUTED
	)
	_feedback_label.visible = not _feedback_text.is_empty()


func _render_tasks(parent: Node) -> void:
	add_text(parent, "当前任务", 20)
	var tasks := _array(view.get("tasks"))
	if tasks.is_empty():
		add_text(parent, "暂无公开任务。", 17, UiStyle.MUTED)
	for task_value in tasks:
		var task: Dictionary = _dict(task_value)
		var task_id := str(task.get("task_id", task.get("definition_id", "")))
		var panel := _compact_panel(parent)
		var row := add_row(panel)
		var art := add_art(row, str(task.get("definition_id", "")), Vector2(72, 68))
		art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		add_text(details, UiStyle.label(str(task.get("definition_id", task_id))), 18)
		add_text(
			details,
			(
				"阶段 %s · 剩余 %s/%s · 屏障 %s"
				% [
					UiStyle.label(str(task.get("phase_key", ""))),
					task.get("work_remaining", 0),
					task.get("work_max", 0),
					task.get("shield", 0)
				]
			),
			16,
			UiStyle.MUTED
		)
		var intent := _dict(task.get("intent_snapshot"))
		if not intent.is_empty():
			add_text(details, "公开意图：" + _intent_text(intent), 16, UiStyle.GOLD)
		var button := add_button(panel, "task:" + task_id, "选择任务", {}, _bind_task(task_id))
		button.tooltip_text = "点击后补足当前卡牌目标" if not _selected_card_id.is_empty() else "选择合作目标"


func _render_units(parent: Node) -> void:
	var units := _array(view.get("units"))
	if units.is_empty():
		add_text(parent, "协作单位：暂无", 16, UiStyle.MUTED)
		return
	add_text(parent, "协作单位", 20)
	for unit_value in units:
		var unit: Dictionary = _dict(unit_value)
		var unit_id := str(unit.get("unit_id", unit.get("definition_id", "")))
		var panel := _compact_panel(parent)
		add_art(panel, str(unit.get("definition_id", "")), Vector2(64, 48))
		add_text(panel, UiStyle.label(str(unit.get("definition_id", unit_id))), 19)
		add_text(
			panel,
			(
				"精力 %s · 协作 %s · 放松 %s · 护卫 %s"
				% [
					unit.get("vitality", 0),
					unit.get("cooperation", 0),
					unit.get("relax", 0),
					unit.get("guard", 0)
				]
			),
			16,
			UiStyle.MUTED
		)
		add_button(panel, "unit:" + unit_id, "选择单位", {}, _bind_unit(unit_id))


func _render_player(parent: Node) -> void:
	add_text(parent, "我的状态", 22)
	var player := _dict(view.get("player"))
	add_text(
		parent,
		(
			"专注 %s · 精力 %s · 放松 %s"
			% [player.get("focus", 0), player.get("vitality", 0), player.get("relax", 0)]
		),
		17
	)
	var statuses := _array(view.get("statuses"))
	if not statuses.is_empty():
		add_text(parent, "状态：" + _status_text(statuses), 16, UiStyle.MUTED)


func _render_scene(parent: Node) -> void:
	var scene := _dict(view.get("scene"))
	if scene.is_empty():
		return
	add_text(parent, "当前场景", 21)
	add_art(parent, str(scene.get("definition_id", "")), Vector2(160, 90))
	add_text(parent, UiStyle.label(str(scene.get("definition_id", ""))), 18)


func _render_choice(parent: Node) -> void:
	var choice := _choice_dict(view.get("pending_choice"))
	if choice.is_empty():
		return
	add_text(parent, "效果内选择", 22, UiStyle.GOLD)
	var choice_names := {
		"discard": "请选择要弃置的卡牌", "recall": "请选择要回忆的卡牌", "retain": "请选择要保留的卡牌", "purify": "请选择要净化的状态"
	}
	add_text(parent, str(choice_names.get(str(choice.get("kind", "")), "请选择候选")), 17)
	var candidates := _array(choice.get("candidates"))
	for option_value in candidates:
		var option := _dict(option_value)
		var id := str(option.get("id", option.get("candidate_id", "")))
		var selected := _choice_selected_ids.has(id)
		var option_preview := _dict(option.get("preview"))
		var definition_id := str(option_preview.get("definition_id", ""))
		var option_label := UiStyle.label(
			definition_id if not definition_id.is_empty() else str(option.get("label_key", id))
		)
		var button := add_button(
			parent,
			"choice:" + id,
			("● " if selected else "○ ") + option_label,
			{},
			_bind_choice(id)
		)
		button.tooltip_text = _choice_preview_text(_dict(option.get("preview")))
	var confirm := add_button(parent, "choice:confirm", "确认选择", _choice_draft())
	confirm.disabled = (
		_choice_selected_ids.size() < int(choice.get("min_count", 0))
		or _choice_selected_ids.size() > int(choice.get("max_count", 0))
	)
	if confirm.disabled:
		confirm.tooltip_text = (
			"请选择 %s-%s 项" % [choice.get("min_count", 0), choice.get("max_count", 0)]
		)


func _render_selection(parent: Node) -> void:
	if _selected_card_id.is_empty() and _selected_unit_id.is_empty():
		return
	add_text(parent, "当前预选", 21, UiStyle.GOLD)
	if not _selected_card_id.is_empty():
		add_text(parent, UiStyle.label(_card_definition(_selected_card_id)) + " · 等待目标", 17)
	if not _selected_unit_id.is_empty():
		add_text(parent, "单位：" + UiStyle.label(_unit_definition(_selected_unit_id)), 17)
	for selection_value in _required(_active_preview):
		var selection := _dict(selection_value)
		if str(selection.get("field", "")) == "replace_unit_id":
			add_text(parent, "单位槽已满，请选择换班对象：", 17)
			for candidate_value in _array(selection.get("candidates")):
				var candidate := _dict(candidate_value)
				var id := str(candidate.get("id", ""))
				add_button(
					parent,
					"replace:" + id,
					UiStyle.label(str(candidate.get("label_key", id))),
					{},
					_bind_unit(id)
				)


func _render_retention(parent: Node) -> void:
	if is_locked():
		return
	var quote: Variant = _preview({"type": "end_turn", "payload": {"retained_card_ids": []}})
	for selection_value in _required(quote):
		var selection := _dict(selection_value)
		if str(selection.get("field", "")) != "retained_card_ids":
			continue
		add_text(parent, "本回合普通保留（最多 %s 张）" % selection.get("max_count", 0), 18)
		for candidate_value in _array(selection.get("candidates")):
			var candidate := _dict(candidate_value)
			var id := str(candidate.get("id", ""))
			add_button(
				parent,
				"retain:" + id,
				(
					("● " if _retained_card_ids.has(id) else "○ ")
					+ UiStyle.label(str(candidate.get("label_key", id)))
				),
				{},
				_bind_retention(id, int(selection.get("max_count", 0)))
			)


func _render_controls(parent: Node) -> void:
	var row := add_row(parent)
	var end_button := add_button(row, "battle:end_turn", "结束回合", _end_turn_draft())
	end_button.tooltip_text = "结束本回合"
	add_button(row, "battle:draw", "抽牌堆", {}, Callable(self, "_show_draw"))
	add_button(row, "battle:discard", "弃牌堆", {}, Callable(self, "_show_discard"))
	add_button(row, "battle:exhaust", "消耗堆", {}, Callable(self, "_show_exhaust"))
	var row2 := add_row(parent)
	add_button(row2, "battle:rules", "规则说明", {}, Callable(self, "_show_rules"))
	var animation := add_button(
		row2,
		"battle:animation",
		"动画：" + ("开" if animation_enabled else "关"),
		{},
		Callable(self, "_toggle_animation")
	)
	animation.tooltip_text = "切换事件提示动画"
	add_button(row2, "battle:speed", "速度 ×%s" % speed_scale, {}, Callable(self, "_cycle_speed"))
	add_button(row2, "battle:save", "保存", {"type": "ui.save", "payload": {}})
	add_button(row2, "battle:menu", "主菜单", {"type": "ui.menu", "payload": {}})
	if not _buttons.has("battle:cancel"):
		var cancel := add_button(
			row, "battle:cancel", "取消预选", {}, Callable(self, "_cancel_selection")
		)
		cancel.disabled = _selected_card_id.is_empty() and _selected_unit_id.is_empty()
		cancel.tooltip_text = "尚未选择卡牌或单位" if cancel.disabled else "只取消本地预选"
	if not _panel_text.is_empty():
		add_text(parent, _panel_text, 16, UiStyle.MUTED)
		add_button(parent, "battle:close_panel", "收起说明", {}, Callable(self, "_close_panel"))


func _render_hand(parent: Node) -> void:
	add_text(parent, "手牌 · 点击卡牌，再选择高亮目标", 18)
	var cards := _array(view.get("hand"))
	if cards.is_empty():
		add_text(parent, "手牌为空。", 17, UiStyle.MUTED)
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var row := add_row(scroll)
	for card_value in cards:
		var card := _dict(card_value)
		var card_id := str(card.get("card_id", ""))
		var panel := _compact_panel(row)
		panel.custom_minimum_size = Vector2(174, 0)
		add_art(panel, str(card.get("definition_id", "")), Vector2(132, 58))
		add_text(panel, UiStyle.label(str(card.get("definition_id", card_id))), 17)
		add_text(
			panel,
			(
				"专注 %s · 精力 %s"
				% [card.get("effective_cost", 0), card.get("effective_vitality_cost", 0)]
			),
			15,
			UiStyle.MUTED
		)
		var face := _dict(card.get("face", card.get("effective_card", {})))
		var effect_text := UiStyle.describe_effects(_array(face.get("effects", [])))
		if not effect_text.is_empty():
			var effect := add_text(panel, effect_text, 14, UiStyle.MUTED)
			effect.max_lines_visible = 2
			effect.tooltip_text = effect_text
		var play := add_button(panel, "card:" + card_id, "打出", {}, _bind_card(card_id))
		play.custom_minimum_size.y = 36
		if card.has("playable"):
			play.disabled = not bool(card.get("playable", false))
			if play.disabled:
				play.tooltip_text = "此牌当前不可出"


func _render_zones_and_log(parent: Node) -> void:
	var zones := _dict(view.get("zones_public"))
	var counts := _dict(view.get("zone_counts"))
	var panel := add_panel(parent)
	add_text(panel, "牌堆公开信息", 21)
	add_text(
		panel,
		(
			"抽牌堆 %s 张 · 弃牌堆 %s 张 · 消耗堆 %s 张"
			% [
				counts.get("draw", 0),
				_array(zones.get("discard")).size(),
				_array(zones.get("exhaust")).size()
			]
		),
		16,
		UiStyle.MUTED
	)
	var log := _array(view.get("event_log"))
	if not log.is_empty():
		add_text(panel, "最近记录", 20)
		for entry_value in log.slice(maxi(0, log.size() - 8), log.size()):
			var entry := _dict(entry_value)
			add_text(panel, _event_text(entry), 15, UiStyle.MUTED)


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


func _show_discard() -> void:
	_panel_text = "弃牌堆：" + _zone_names("discard")
	_render_from_local()


func _show_exhaust() -> void:
	_panel_text = "消耗堆：" + _zone_names("exhaust")
	_render_from_local()


func _show_rules() -> void:
	_panel_text = "玩家行动阶段：选择卡牌、目标或协作目标；结束回合后由规则层推进敌方意图。"
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


func _zone_names(zone: String) -> String:
	var names: Array[String] = []
	for value in _array(_dict(view.get("zones_public")).get(zone)):
		var card := _dict(value)
		names.append(UiStyle.label(str(card.get("definition_id", ""))))
	return "、".join(names) if not names.is_empty() else "暂无公开卡牌"


func _choice_preview_text(preview: Dictionary) -> String:
	if preview.is_empty():
		return ""
	return "、".join(
		PackedStringArray(preview.keys().map(func(key): return "%s:%s" % [key, preview[key]]))
	)


func _event_text(event: Dictionary) -> String:
	var type := str(event.get("type", "事件"))
	var data := _dict(event.get("data"))
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
