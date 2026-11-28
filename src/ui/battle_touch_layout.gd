extends BattleLayout

const INSET := 10.0
const GAP := 6.0
const ACTION := UiStyle.MOBILE_TARGET
const PILES_WIDTH := 146.0
const FOCUS_WIDTH := 54.0

var hand_height: float
var field_bottom: float
var field_top: float
var reading_height: float
var compact_meters: bool
var tray_header: float


func build(screen: BattleScreen) -> void:
	page = screen
	page._reset_stage()
	stage = page._stage
	mobile = true
	short = true
	top = UiRunToolbar.HEIGHT
	minimum_text = 14
	status_edge = 44.0
	touch_height = ACTION
	compact_meters = stage.size.y < 365
	reading_height = maxf(24, ceilf(20 * minf(UiStyle.text_scale, 1.3) + 4))
	hand_height = clampf(floorf(stage.size.y * .33), 104, 156)
	var notice_pixels := roundi(13 * minf(UiStyle.text_scale, 1.3))
	tray_header = maxf(18, ceilf(UiStyle.touch_reading_font().get_height(notice_pixels)))
	hand_top = stage.size.y - hand_height - GAP
	page._hand_top = hand_top
	field_bottom = hand_top - tray_header - 3
	field_top = top + 4
	_background()
	_header()
	_player()
	_tasks()
	_units()
	_touch_hand()
	_controls()
	_hover_window()
	if not page._panel_text.is_empty():
		_info_panel()
	if page.is_locked():
		_choice_panel()
	page._apply_preview_gating()
	page._apply_lock_state()
	page._sync_card_visuals()
	page._fit_stage()


func _background() -> void:
	var art := TextureRect.new()
	art.name = "BattleRoomBackground"
	art.texture = UiStyle.texture("BG_classroom")
	if BattleActorView.pilot_enabled and not BattleActorView.pilot_stage_background.is_empty():
		art.texture = load(BattleActorView.pilot_stage_background) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color("aab8c1")
	page.add_child(art)
	page.move_child(art, 0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	shade.texture = UiStyle.gradient(Color(0, 0, 0, 0), Color("101b24", .64))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_top = .30


func _hud_text(parent: Node, bounds: Rect2, caption: String, size_css: int, ink: Color = UiStyle.CREAM, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var pixels := roundi(size_css * minf(UiStyle.text_scale, 1.3))
	var label := _text(parent, bounds, caption, pixels, ink, alignment)
	label.add_theme_font_override("font", UiStyle.touch_reading_font())
	label.remove_theme_color_override("font_shadow_color")
	label.add_theme_constant_override("outline_size", 0)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.max_lines_visible = 1
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _plate(parent: Node, bounds: Rect2, color: Color, border: Color) -> void:
	var panel := _panel(parent, bounds, color, border)
	var skin := panel.get_theme_stylebox("panel") as StyleBoxFlat
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(5)


func _player() -> void:
	var player := page._dict(page.view.get("player"))
	var id := str(player.get("entity_id", ""))
	var side := _player_width()
	var support := _support_width(side) if not page._array(page.view.get("units")).is_empty() else 0.0
	var foot := field_bottom - reading_height
	var bounds := Rect2(INSET + support + 4, field_top + 2, side - support - 8, maxf(44, foot - field_top - 2))
	_actor(bounds, id, str(page.view.get("character_id", "P01")), "player")
	var status_count := BattleStatusSlot.entries(page.view, id, true).size()
	var status_width := _status_width(status_count, side)
	var vital_bounds := Rect2(INSET, foot, side - status_width - (5 if status_width > 0 else 0), reading_height)
	_plate(stage, vital_bounds, Color("12232d"), Color("66808c"))
	var caption := "精力 %s   放松 %s" if vital_bounds.size.x >= 145 else "♥ %s  ◇ %s"
	var stats := caption % [player.get("vitality", 0), player.get("relax", 0)]
	var vital := _hud_text(stage, vital_bounds, stats, 16, Color("fff0d8"))
	vital.name = "PlayerVitalityValue"
	if status_width > 0:
		_status_bar(id, Rect2(INSET + side - status_width, foot + reading_height - status_edge, status_width, status_edge), true)
	var hit := _button(bounds, "battle:resources", "", {}, func(): page._open_detail_for_uid("battle:resources"))
	_transparent_target(hit)
	hit.accessibility_name = "查看人物能力和场景"


func _player_width() -> float:
	return clampf(floorf(stage.size.x * .27), 142, 260)


func _support_width(area: float) -> float:
	return clampf(floorf(area * .40), 65, 96)


func _status_width(count: int, area: float) -> float:
	if count == 0:
		return 0
	return status_edge * (2 if count > 1 and area >= 222 else 1)


func _tasks() -> void:
	var tasks := page._array(page.view.get("tasks"))
	var left := _player_width() + 2 * INSET + 14
	var width := stage.size.x - left - INSET
	var height := maxf(96, field_bottom - field_top)
	var lane := ScrollContainer.new()
	lane.name = "TouchBattleTasks"
	lane.position = Vector2(left, field_top)
	lane.size = Vector2(width, height + 1)
	lane.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lane.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	lane.follow_focus = true
	stage.add_child(lane)
	page._touch_tasks = lane
	lane.set_deferred("scroll_horizontal", page._touch_tasks_x)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	lane.add_child(row)
	var slot_width := clampf(floorf((width - (tasks.size() - 1) * 10) / maxi(1, tasks.size())), 174, 332 if tasks.size() == 1 else 260)
	for value in tasks:
		var task: Dictionary = value
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(slot_width, height)
		row.add_child(slot)
		_touch_task(slot, task)
	if tasks.is_empty():
		var caption := page.add_text(row, "当前任务已完成", 19, LIGHT)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _touch_task(slot: Control, task: Dictionary) -> void:
	var id := str(task.task_id)
	var width := slot.custom_minimum_size.x
	var height := slot.custom_minimum_size.y
	var previous_stage := stage
	stage = slot
	var phase_count := int(task.get("phase_count", 1))
	var entries := BattleStatusSlot.entries(page.view, id, false)
	var inline_meter := compact_meters or width >= 216
	var status_width := _status_width(entries.size(), width) if not inline_meter else 0.0
	var stats_width := width - status_width - (5 if status_width > 0 else 0)
	var stats_height := reading_height + 6 if inline_meter else reading_height * 2 - 2
	var numbers_top := height - stats_height
	var font := UiStyle.touch_reading_font()
	var intent_width := minf(width - 12, 234)
	var intent_pixels := roundi(16 * minf(UiStyle.text_scale, 1.3))
	var intent := TaskIntentText.hud_caption(task, font, intent_pixels, intent_width - 14)
	var two_lines := intent.contains("
")
	var intent_height := 43.0 if two_lines else 35.0
	var art_top := 44.0
	var art_bounds := Rect2(6, art_top, width - 12, maxf(30, numbers_top - art_top))
	var actor := _actor(art_bounds, id, str(task.definition_id), "task", int(task.get("phase_index", 1)))
	var target_bounds := Rect2(0, status_edge, width, maxf(status_edge, numbers_top - status_edge))
	var target := _button(target_bounds, "task:" + id, "", {}, page._bind_task(id))
	_transparent_target(target)
	var task_name := UiStyle.label(str(task.definition_id))
	target.accessibility_name = "选择 " + task_name
	page._target_frames["task:" + id] = actor

	var intent_bounds := Rect2(floorf((width - intent_width) * .5), 0, intent_width, intent_height)
	_plate(slot, intent_bounds, Color("111f29"), Color("a3926c"))
	var intent_label := _hud_text(slot, Rect2(intent_bounds.position + Vector2(7, 0), intent_bounds.size - Vector2(14, 0)), intent, 14 if two_lines else 16, Color("fff2d6"))
	intent_label.max_lines_visible = 2 if two_lines else 1
	intent_label.name = "TaskIntent_" + id.validate_node_name()
	var intent_hit := _button(Rect2(intent_bounds.position, Vector2(intent_width, status_edge)), "detail:task:" + id, "", {}, func(): page._open_detail_for_uid("detail:task:" + id))
	_transparent_target(intent_hit)
	intent_hit.accessibility_name = "查看 " + task_name + " 的意图和特性"
	intent_hit.accessibility_description = page._task_intent_text(task)

	var stats_bounds := Rect2(0, numbers_top, stats_width, stats_height)
	_plate(slot, stats_bounds, Color("12232d"), Color("66808c"))
	var current := int(task.work_remaining)
	var maximum := maxi(1, int(task.work_max))
	var meter_width := stats_width - 12
	var fill := _bar(slot, Rect2(6, stats_bounds.end.y - 5, meter_width, 3), float(current) / maximum, Color("ed7978"))
	var caption := "%s/%s · 盾%s"
	var value_rect := Rect2(0, numbers_top + reading_height - 3, stats_width, reading_height - 3)
	var name_rect := Rect2(6, numbers_top + 1, stats_width - 12, reading_height - 1)
	if inline_meter:
		var count_width := floorf(stats_width * .51)
		name_rect.size.x = stats_width - count_width - 8
		value_rect = Rect2(stats_width - count_width, numbers_top, count_width - 3, reading_height)
	var work := _hud_text(slot, value_rect, caption % [current, maximum, task.shield], 15, Color("ffd6b3"))
	work.name = "TaskWorkValue_" + id.validate_node_name()
	page._task_meters[id] = {"fill": fill, "label": work, "width": meter_width, "maximum": maximum, "caption": caption}
	if phase_count > 1:
		task_name += "  %s/%s" % [task.phase_index, phase_count]
	var title := _hud_text(slot, name_rect, task_name, 15)
	title.name = "TaskTitle_" + id.validate_node_name()
	if not entries.is_empty():
		if inline_meter:
			_status_bar(id, Rect2(width - status_edge, numbers_top - status_edge, status_edge, status_edge), false)
		else:
			_status_bar(id, Rect2(width - status_width, height - status_edge, status_width, status_edge), false)
	stage = previous_stage


func _units() -> void:
	var units := page._array(page.view.get("units"))
	if units.is_empty():
		return
	var width := _support_width(_player_width())
	var bar := ScrollContainer.new()
	bar.position = Vector2(INSET, field_top + 2)
	bar.size = Vector2(width, field_bottom - field_top - reading_height - 4)
	bar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	stage.add_child(bar)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", GAP)
	bar.add_child(column)
	for value in units:
		var unit: Dictionary = value
		var id := str(unit.unit_id)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(width, 64)
		column.add_child(slot)
		var portrait := BattleActorView.new()
		portrait.configure(str(unit.definition_id), "unit")
		portrait.size = Vector2(width, 44)
		portrait.set_motion(page.animation_enabled)
		slot.add_child(portrait)
		page._actors[id] = portrait
		var unit_name := UiStyle.label(str(unit.definition_id)).split("：")[0]
		_plate(slot, Rect2(0, 42, width, 22), Color("12232d"), Color("547c79"))
		_hud_text(slot, Rect2(2, 41, width - 4, 22), unit_name, 13)
		var old_stage := stage
		stage = slot
		var button := _button(Rect2(Vector2.ZERO, slot.custom_minimum_size), "unit:" + id, "", {}, page._bind_unit(id))
		stage = old_stage
		button.accessibility_name = "选择 " + unit_name
		_transparent_target(button)
		page._target_frames["unit:" + id] = portrait


func _touch_hand() -> void:
	var y := hand_top - tray_header - 1
	_rect(stage, Rect2(0, y, stage.size.x, stage.size.y - y), Color("111f29"))
	_rect(stage, Rect2(0, y, stage.size.x, 1), Color("aa956f"))
	var left := INSET + FOCUS_WIDTH + 2 * GAP
	var available := _pile_left() - left - 2 * GAP
	var cards := page._array(page.view.get("hand"))
	var slots := clampi(floori((available + GAP) / (73 + GAP)), 1, 7)
	var card_width := minf(floorf((available + GAP) / slots) - GAP, floorf((hand_height - 2) * .74))
	var stride := roundi(card_width + GAP)
	var tray_width := slots * stride - GAP
	var notice_left := left + minf(140, tray_width * .36)
	var notice_bounds := Rect2(notice_left, y + 1, stage.size.x - notice_left - INSET, tray_header)
	page._feedback_label = _hud_text(stage, notice_bounds, page._visible_feedback(), 13, Color("edcf95"), HORIZONTAL_ALIGNMENT_RIGHT)
	page._feedback_label.name = "BattleEventNotice"
	page._feedback_label.visible = not page._feedback_label.text.is_empty()
	var counter := _hud_text(stage, Rect2(left, y + 1, notice_left - left, tray_header), "", 13, SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	counter.name = "TouchHandCount"
	counter.visible = cards.size() > slots

	var scroll := ScrollContainer.new()
	scroll.name = "TouchHand"
	scroll.position = Vector2(left, hand_top)
	scroll.size = Vector2(tray_width, hand_height)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	stage.add_child(scroll)
	page._touch_hand = scroll
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	scroll.add_child(row)
	for value in cards:
		var data: Dictionary = value
		var id := str(data.card_id)
		var card := BattleCard.new()
		card.configure(data, page._selected_card_id == id, Vector2(card_width, hand_height))
		card.clip_text = true
		card.set_meta("uid", "card:" + id)
		row.add_child(card)
		page._hand_cards.append(card)
		page._buttons["card:" + id] = card
		card.pressed.connect(func():
			if page._pinned_card_detail.is_empty():
				page._on_card_pressed(id))
	scroll.scroll_started.connect(func(): page._pointer_card = null)
	scroll.scroll_ended.connect(func():
		scroll.set_deferred("scroll_horizontal", roundi(float(scroll.scroll_horizontal) / stride) * stride))
	var update_count := func(value: float):
		var first := clampi(floori(value / stride + .01), 0, maxi(0, cards.size() - slots))
		counter.text = "%d–%d / %d" % [first + 1, mini(first + slots, cards.size()), cards.size()]
	scroll.get_h_scroll_bar().value_changed.connect(update_count)
	update_count.call(0.0)
	scroll.set_deferred("scroll_horizontal", roundi(float(page._touch_hand_x) / stride) * stride)
	if cards.is_empty():
		page.add_text(row, "手牌已空", 18, SOFT)


func _pile_left() -> float:
	return stage.size.x - INSET - PILES_WIDTH


func _controls() -> void:
	var focus := BattleActionButton.new()
	focus.name = "FocusDevice"
	focus.configure("focus", int(page._dict(page.view.get("player")).get("focus", 0)))
	focus.clip_text = true
	focus.position = Vector2(INSET, hand_top + 2)
	focus.size = Vector2(FOCUS_WIDTH, 54)
	focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus.focus_mode = Control.FOCUS_NONE
	stage.add_child(focus)
	var x := _pile_left()
	_rect(stage, Rect2(x - GAP - 1, hand_top + 5, 1, hand_height - 10), Color("455966"))
	for i in 3:
		var kind: String = ["draw", "discard", "exhaust"][i]
		_pile_button(Rect2(x + i * 50, hand_top + 3, 46, status_edge), kind, [page._show_draw, page._show_discard, page._show_exhaust][i])
	var turn_y := stage.size.y - ACTION - GAP
	var turn := page.add_end_turn(stage, Rect2(x, turn_y, PILES_WIDTH, ACTION))
	turn.add_theme_font_size_override("font_size", roundi(18 * minf(UiStyle.text_scale, 1.25)))
	if not page._selected_card_id.is_empty() or not page._selected_unit_id.is_empty():
		var cancel := _button(Rect2(INSET, stage.size.y - status_edge - GAP, FOCUS_WIDTH, status_edge), "battle:cancel", "取消", {}, page._cancel_selection)
		cancel.accessibility_name = "取消选择"
		UiStyle.button_skin(cancel, "quiet", true)
	_touch_retention()


func _touch_retention() -> void:
	if page.is_locked():
		return
	for item in page._required(page._preview({"type": "end_turn", "payload": {"retained_card_ids": []}})):
		if item.get("field") != "retained_card_ids":
			continue
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(INSET, field_bottom - ACTION)
		scroll.size = Vector2(stage.size.x - 2 * INSET, ACTION)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		stage.add_child(scroll)
		var row := HBoxContainer.new()
		scroll.add_child(row)
		var label := page.add_text(row, "保留 %s/%s" % [page._retained_card_ids.size(), item.get("max_count", 0)], 14, SOFT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		for entry in item.get("candidates", []):
			var id := str(entry.get("id", ""))
			var marked := page._retained_card_ids.has(id)
			var button := page.add_button(row, "retain:" + id, UiStyle.label(str(entry.get("label_key", id))), {}, page._bind_retention(id, int(item.get("max_count", 0))))
			UiStyle.button_skin(button, "selected" if marked else "secondary", true)


func _hover_window() -> void:
	super._hover_window()
	var cover := ColorRect.new()
	cover.name = "TouchCardDetailShade"
	cover.color = Color(.02, .04, .06, .66)
	cover.size = stage.size
	cover.z_index = 340
	cover.hide()
	stage.add_child(cover)
	page._touch_detail_cover = cover
	var close := Button.new()
	close.name = "TouchCardDetailClose"
	close.text = "关闭"
	close.custom_minimum_size = Vector2(ACTION, ACTION)
	UiStyle.button_skin(close, "quiet", true)
	close.pressed.connect(page.close_card_preview)
	close.hide()
	page._hover_panel.add_child(close)
	page._touch_detail_close = close


func _info_panel() -> void:
	var overlay := _modal()
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = INSET
	column.offset_right = -INSET
	column.offset_top = GAP
	column.offset_bottom = -GAP
	overlay.add_child(column)
	var heading := page.add_row(column)
	var title := page.add_text(heading, "战斗信息", 22, LIGHT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close := page.add_button(heading, "battle:close_panel", "返回", {}, page._close_panel)
	close.accessibility_name = "返回战斗"
	close.custom_minimum_size.x = 100
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiStyle.button_skin(close, "secondary", true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(words)
	page.populate_info(words, true)
	for term in page._detail_terms:
		var button := page.add_button(words, "term:" + term, UiGlossary.label(term), {}, page._bind_term(term))
		UiStyle.button_skin(button, "quiet", true)
	close.grab_focus.call_deferred()
