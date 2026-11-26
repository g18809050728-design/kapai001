class_name BattleLayout
extends RefCounted

const LIGHT := Color("f4eedf")
const SOFT := Color("c1d0c7")
const DARK := Color("192f35")
var page: BattleScreen
var stage: Control
var short := false
var mobile := false
var top := 84.0
var hand_top := 548.0
var touch_height := 52.0
var minimum_text := 0


func build(screen: BattleScreen) -> void:
	page = screen
	page._reset_stage()
	stage = page._stage
	short = page._short_web
	mobile = UiStyle.web_touch
	if short:
		var scale := maxf(.1, minf(page.size.x / stage.size.x, page.size.y / stage.size.y))
		top = UiRunToolbar.HEIGHT / scale + 4
		hand_top = stage.size.y - (235 if mobile else 197)
		touch_height = ceilf((UiStyle.MOBILE_TARGET if mobile else 44) / scale)
		minimum_text = ceili((14 if mobile else 12) * minf(UiStyle.text_scale, 1.2) / scale)
	var background := TextureRect.new()
	background.texture = UiStyle.texture("BG_classroom")
	if BattleActorView.pilot_enabled and not BattleActorView.pilot_stage_background.is_empty():
		background.texture = load(BattleActorView.pilot_stage_background) as Texture2D
	background.name = "BattleRoomBackground"
	background.size = stage.size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	_rect(stage, Rect2(Vector2.ZERO, stage.size), Color(0.035, 0.07, 0.11, 0.34))
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.03, 0.08, 0.1, 0.0), Color(0.03, 0.08, 0.1, 0.96)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.position = Vector2(0, stage.size.y - 430)
	shade.size = Vector2(stage.size.x, 430)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shade)
	_header()
	_player()
	_tasks()
	_units()

	_hand()
	_controls()
	_v3_summary()
	page._aim = BattleAim.new()
	page._aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page._aim.z_index = 70
	stage.add_child(page._aim)
	page._feedback_label = _text(
		stage, Rect2(410, top + 62, 460, 28), page._feedback_text, 13 if not page._dict(page.view.get("v3")).is_empty() else 16, LIGHT, HORIZONTAL_ALIGNMENT_CENTER
	)
	page._feedback_label.visible = not page._feedback_text.is_empty()
	page._hint_label = _text(
		stage, Rect2(250, top + 39, 780, 24), _selection_hint(), 14, LIGHT, HORIZONTAL_ALIGNMENT_CENTER
	)
	page._hint_label.name = "HandActionHint"
	page._hint_label.max_lines_visible = 1
	page._hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hover_window()
	if not page._panel_text.is_empty():
		_info_panel()
	if page.is_locked():
		_choice_panel()
	page._apply_preview_gating()
	page._apply_lock_state()
	page._sync_card_visuals()
	page._fit_stage()


func _field(bounds: Rect2) -> Rect2:
	if not short:
		return bounds
	var field_top := minf(top + (83 if mobile else 92), hand_top - 96)
	var scale := (hand_top - field_top - 24) / 388.0
	return Rect2(bounds.position.x, field_top + (bounds.position.y - 180) * scale, bounds.size.x, bounds.size.y * scale)


func _hover_window() -> void:
	var factor := UiStyle.text_scale
	var panel := Panel.new()
	panel.size = Vector2(360, 168) * factor
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 120
	var style := UiStyle.box(Color("192f35"))
	style.border_color = Color("d8ba7c")
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	stage.add_child(panel)
	page._hover_panel = panel
	page._hover_title = _text(panel, Rect2(Vector2(16, 10) * factor, Vector2(328, 28) * factor), "", roundi(19 * factor), LIGHT)
	page._hover_meta = _text(panel, Rect2(Vector2(16, 38) * factor, Vector2(328, 22) * factor), "", roundi(13 * factor), Color("e5c894"))
	page._hover_scroll = ScrollContainer.new()
	page._hover_scroll.position = Vector2(16, 62) * factor
	page._hover_scroll.size = Vector2(328, 82) * factor
	page._hover_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page._hover_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page._hover_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page._hover_scroll.mouse_force_pass_scroll_events = true
	panel.add_child(page._hover_scroll)
	page._hover_body = Label.new()
	page._hover_body.add_theme_font_size_override("font_size", roundi(16 * factor))
	page._hover_body.add_theme_color_override("font_color", LIGHT)
	page._hover_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page._hover_body.max_lines_visible = 4
	page._hover_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page._hover_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page._hover_scroll.add_child(page._hover_body)
	page._hover_hint = _text(panel, Rect2(Vector2(16, 146) * factor, Vector2(328, 16) * factor), "I 查看详情", roundi(12 * factor), Color("f1c989"), HORIZONTAL_ALIGNMENT_RIGHT)


func _header() -> void:
	var player := page._dict(page.view.get("player"))
	page._toolbar = UiRunToolbar.new()
	page.add_child(page._toolbar)
	page._toolbar.configure(page, {
		"battle": true, "vitality": player.get("vitality", 0), "max_vitality": page.view.get("max_vitality", 0), "money": page.view.get("money", 0),
		"journey": "%s  ·  %s" % [page.view.get("year_label", ""), page._battle_subtitle()],
		"relics_uid": "battle:relics", "relics_count": page._array(page.view.get("relics")).size(), "relics_callback": Callable(page, "_show_relics"),
		"map_uid": "battle:map", "map_callback": Callable(page, "_show_map"),
		"deck_uid": "battle:deck", "deck_count": page._array(page.view.get("cards")).size(), "deck_callback": Callable(page, "_show_deck"),
		"toggle_uid": "battle:options", "close_uid": "battle:close_options", "help_uid": "battle:rules", "help_callback": Callable(page, "_show_rules"),
		"save_uid": "battle:save", "home_uid": "battle:menu", "log_callback": Callable(page, "_show_log"),
		"speed_callback": Callable(page, "_cycle_speed"), "animation_callback": Callable(page, "_toggle_animation")
	})
	page._toolbar.mark_active("deck", page._panel_zone == "deck" and not page._panel_text.is_empty())
	var urgent := int(page.view.get("ddl",0)) <= 3
	_text(stage,Rect2(470,top,340,30),"第 %s 回合  ·  DDL %s 次轮末" % [page.view.get("round_index",0),page.view.get("ddl",0)],18,Color("ffb18e") if urgent else Color("d9c99e"),HORIZONTAL_ALIGNMENT_CENTER)


func _player() -> void:
	var player := page._dict(page.view.get("player"))
	var player_id := str(player.get("entity_id", ""))
	_actor(_field(Rect2(98,186,224,246)),player_id,str(page.view.get("character_id","P01")),"player")
	var hp := int(player.get("vitality",0))
	var max_hp := int(page.view.get("max_vitality",maxi(1,hp)))
	_bar(stage,_field(Rect2(115,423,190,14)),float(hp)/maxi(1,max_hp),Color("659fc5"))
	var vitality := _text(stage,_field(Rect2(115,415,190,28)),"%s / %s" % [hp,max_hp],roundi(18*minf(UiStyle.text_scale,1.2)),LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	vitality.name = "PlayerVitalityValue"
	_text(stage,_field(Rect2(65,415,47,29)),"◇%s" % player.get("relax",0),19,Color("b4d7ed"),HORIZONTAL_ALIGNMENT_CENTER)
	_text(stage,_field(Rect2(102,439,218,22)),UiStyle.label(str(page.view.get("character_id","P01"))).split("·")[0],16,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	_status_bar(player_id, _field(Rect2(70,466,246,26)), true)


func _v3_summary() -> void:
	var v3 := page._dict(page.view.get("v3"))
	if v3.is_empty():
		return
	var paper := page._dict(v3.get("paper"))
	var turn := page._dict(v3.get("turn"))
	var lines: Array[String] = []
	if str(page.view.get("character_id", "")) == "P02":
		lines.append("论文%s · 进度%d/10 · 引用%d/5 · 修正%d · 增幅%d · 持续能力%d" % ["进行中" if paper.get("open", false) else "未开题", int(paper.get("progress", 0)), int(paper.get("citations", 0)), int(paper.get("modifier", 0)), int(paper.get("amplify", 0)), page._array(v3.get("abilities")).size()])
		var slots: Array[String] = []
		var chapters := page._array(paper.get("chapters"))
		for index in 3:
			var name := "空槽"
			if index < chapters.size():
				name = UiStyle.label(str(page._dict(chapters[index]).get("definition_id", "")))
			slots.append("章节%d：%s" % [index + 1, name])
		lines.append("　".join(slots) + "　I 详情 · G 帮助")
	else:
		var info := page._dict(page.view.get("character_info"))
		var opportunity := "可用" if info.get("passive_available", true) else "本回合已使用"
		match str(page.view.get("character_id", "")):
			"P01":
				lines.append("前牌：%s · 策略→工作触发连携 · 步骤复用：%s" % [UiStyle.label(str(turn.get("previous_card_type", "无"))), opportunity])
			"P03":
				lines.append("复合反应：%s · 在已有负面的任务上施加不同负面" % opportunity)
			_:
				lines.append("协同%d/6 · 首张合作机会：%s · 伙伴状态见协作区" % [int(v3.get("synergy", 0)), opportunity])
		lines.append("持续能力%d · 点击资源说明 / I 详情 · G 帮助" % page._array(v3.get("abilities")).size())
	var scene := page._dict(page.view.get("scene"))
	if not scene.is_empty():
		lines[0] += "　场景：" + UiStyle.label(str(scene.get("definition_id", "")))
	var panel := _panel(stage, Rect2(20, top, 272, 36 if short else 31), Color(UiStyle.NIGHT,.72), Color(UiStyle.BRASS,.18))
	panel.name = "V3Summary"
	var compact := lines[0].split(" · ")[0]
	if str(page.view.get("character_id","")) == "P02":
		compact = "论文 %s/10  引用 %s/5  修正 %s" % [paper.get("progress",0),paper.get("citations",0),paper.get("modifier",0)]
	var resource_label := _text(panel, Rect2(10, 3, 252, 25), compact+("  ·  详情" if UiStyle.web_touch else "  ·  I 详情"), 13, SOFT)
	resource_label.max_lines_visible = 2
	resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var info_hit := _button(Rect2(20, top, 272, 36 if short else 31), "battle:resources", "", {}, func(): page._open_detail_for_uid("battle:resources"))
	_transparent_target(info_hit)


func _tasks() -> void:
	var tasks := page._array(page.view.get("tasks"))
	if tasks.is_empty():
		_text(stage,_field(Rect2(610,280,470,50)),"当前任务已完成",25,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
	var width := minf(234,660.0/maxi(1,tasks.size())-12)
	var start := 568+(660-tasks.size()*(width+12))*.5
	for index in tasks.size():
		var task := page._dict(tasks[index])
		var id := str(task.get("task_id",""))
		var x := start+index*(width+12)
		var intent := page._task_intent_text(task)
		var intent_label := _text(stage,_field(Rect2(x-5,180,width+10,56)),intent,roundi(20*minf(UiStyle.text_scale,1.2)),Color("ffe4b9"),HORIZONTAL_ALIGNMENT_CENTER)
		intent_label.name = "TaskIntent_"+id.validate_node_name()
		intent_label.add_theme_color_override("font_shadow_color",Color.BLACK)
		intent_label.add_theme_constant_override("shadow_offset_y",2)
		var phase_count := int(task.get("phase_count",1))
		if phase_count > 1:
			_text(stage,_field(Rect2(x,237,width,36)),"第 %s / %s 阶段 · " % [task.get("phase_index",1),phase_count]+("最终阶段" if int(task.get("phase_index",1)) == phase_count else "完成后进入下一阶段"),13,SOFT,HORIZONTAL_ALIGNMENT_CENTER)
		var frame := _actor(_field(Rect2(x,250,width,167)),id,str(task.get("definition_id","")),"task",int(task.get("phase_index",1)))
		var remaining := int(task.get("work_remaining",0))
		var maximum := maxi(1,int(task.get("work_max",1)))
		var fill := _bar(stage,_field(Rect2(x,423,width,14)),float(remaining)/maximum,Color("c85d5b"))
		var work_bounds := _field(Rect2(x-4,414,width+8,32))
		var title_bounds := _field(Rect2(x,440,width,25))
		if short:
			work_bounds.size.y = minimum_text + 4
			title_bounds.position.y = work_bounds.end.y
			title_bounds.size.y = minimum_text + 4
		var work_caption := "%s/%s · 盾%s" if mobile else "%s / %s  ·  屏障 %s"
		var work_label := _text(stage,work_bounds,work_caption % [remaining,maximum,task.get("shield",0)],roundi((16 if tasks.size() >= 4 else 18)*minf(UiStyle.text_scale,1.2)),LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
		work_label.name = "TaskWorkValue_"+id.validate_node_name()
		if mobile:
			work_label.set_meta("compact_work", true)
		page._task_meters[id] = {"fill":fill,"label":work_label,"width":width,"maximum":maximum}
		var task_title := _text(stage,title_bounds,UiStyle.label(str(task.get("definition_id",""))),16,LIGHT,HORIZONTAL_ALIGNMENT_CENTER)
		task_title.name = "TaskTitle_"+id.validate_node_name()
		task_title.max_lines_visible = 1
		task_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var target_bounds := _field(Rect2(x,243,width,174))
		if mobile:
			var hit_height := maxf(touch_height, title_bounds.end.y - target_bounds.position.y)
			target_bounds.size.y = minf(hit_height, hand_top - target_bounds.position.y)
		var target := _button(target_bounds,"task:"+id,"",{},page._bind_task(id))
		_transparent_target(target)
		page._target_frames["task:"+id] = frame
		var bounds := _field(Rect2(x,466,width,42))
		if short:
			bounds.position.y = title_bounds.end.y
		_status_bar(id, bounds, false)


func _status_bar(id: String, bounds: Rect2, player: bool) -> void:
	var factor := maxf(.1, minf(page.size.x / stage.size.x, page.size.y / stage.size.y))
	var edge := ceilf((UiStyle.MOBILE_TARGET if mobile else 44) / factor)
	var entries := BattleStatusSlot.entries(page.view, id, player)
	var scroll := ScrollContainer.new()
	scroll.name = "PlayerStatusBar" if player else "TaskStatusBar_" + id.validate_node_name()
	scroll.position = Vector2(bounds.position.x, minf(bounds.position.y, hand_top - edge - 20))
	scroll.size = Vector2(bounds.size.x, edge + 12)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.z_index = 5
	stage.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	scroll.add_child(row)
	if entries.is_empty():
		_text(row, Rect2(0,0,bounds.size.x,edge), "暂无状态", 13, SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	for entry in entries:
		var uid := "buff:" + id + ":" + str(entry.key)
		var slot := BattleStatusSlot.new()
		slot.configure(entry, edge)
		# Custom paint replaces the default text, retaining Button.text for accessibility.
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			slot.add_theme_color_override(state, Color.TRANSPARENT)
		slot.set_meta("uid", uid)
		slot.set_meta("status_scroll", scroll)
		row.add_child(slot)
		page._buttons[uid] = slot
		slot.pressed.connect(func():
			if not page.is_locked() and page._panel_text.is_empty() and not page._result_pending:
				page._open_detail_for_uid(uid))
		slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
				scroll.scroll_horizontal += roundi(edge) * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
				slot.accept_event())


func _units() -> void:
	var units := page._array(page.view.get("units"))
	if units.is_empty():
		return
	var height := minf(136, 290.0 / maxi(1, units.size()) - 8)
	for index in units.size():
		var unit := page._dict(units[index])
		var id := str(unit.get("unit_id", ""))
		var bounds := _field(Rect2(324, 205 + index * (height + 12), 205, height))
		var frame := _actor(Rect2(bounds.position, Vector2(94, bounds.size.y)), id, str(unit.get("definition_id", "")), "unit")
		_text(stage, Rect2(bounds.position+Vector2(94, 8), Vector2(111, 34)), UiStyle.label(str(unit.get("definition_id", ""))).split("：")[0], 16, LIGHT)
		_text(stage, Rect2(bounds.position+Vector2(94, 43), Vector2(111, maxf(24, bounds.size.y-45))), "精力 %s\n协作 %s\n放松 %s · 护卫 %s" % [unit.get("vitality",0), unit.get("cooperation",0), unit.get("relax",0), unit.get("guard",0)], 13, SOFT)
		var target := _button(bounds, "unit:" + id, "", {}, page._bind_unit(id))
		_transparent_target(target)
		page._target_frames["unit:" + id] = frame


func _actor(bounds: Rect2, id: String, definition: String, kind: String, phase: int = 1) -> BattleActorView:
	var actor := page._take_pilot_actor(id, definition, kind, phase)
	var fresh := not is_instance_valid(actor)
	if fresh:
		actor = BattleActorView.new()
		actor.configure(definition, kind, phase)
	actor.position = bounds.position
	actor.size = bounds.size
	stage.add_child(actor)
	actor._fit_rig()
	actor.set_motion(page.animation_enabled)
	page._actors[id] = actor
	if fresh and is_instance_valid(actor.rig) and page.animation_enabled:
		page._presentation._tweens.append(actor.cue("enter", page.effect_speed()))
	return actor


func _hand() -> void:
	var cards := page._array(page.view.get("hand"))
	var span := 888.0 if mobile else (810.0 if short else 660.0)
	var step := minf(148.0 if mobile else 126.0, span / maxi(1, cards.size() - 1))
	var face_scale := .92 if mobile else (.76 if short else 1.0)
	var start := (603 if mobile else 640) - (step * (cards.size() - 1) + BattleCard.FACE_SIZE.x * face_scale) * 0.5
	for index in cards.size():
		var data := page._dict(cards[index])
		var id := str(data.get("card_id", ""))
		var card := BattleCard.new()
		card.configure(data, page._selected_card_id == id)
		card.shortcut_index = index + 1 if index < 9 else 0
		card.set_meta("uid", "card:" + id)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset := float(index) - (cards.size() - 1) * 0.5
		card.home_rotation = deg_to_rad(clampf(offset * (3.0 if mobile else 5.0), -16, 16))
		card.home_scale = face_scale
		card.scale = Vector2.ONE * face_scale
		var fan_depth := minf(offset * offset * 2.0, 14 if short else 30)
		card.home_position = Vector2(start + index * step, hand_top + fan_depth) + card.pivot_offset * (face_scale - 1.0)
		card.home_order = 10 + index
		card.position = card.home_position
		card.rotation = card.home_rotation
		card.z_index = card.home_order
		stage.add_child(card)
		page._hand_cards.append(card)
		page._buttons["card:" + id] = card
		card.pressed.connect(page._bind_card(id))
	if cards.is_empty():
		_text(
			stage,
			Rect2(350, hand_top + 70, 580, 60),
			"手牌已空  ·  结束回合以继续",
			22,
			SOFT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	if not short:
		_text(
			stage,
			Rect2(310, 782, 660, 17),
			"1—9 选牌 / 点击或拖拽出牌 / I 详情 / 右键或 Esc 取消",
			11,
			SOFT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	_retention()


func _controls() -> void:
	var player := page._dict(page.view.get("player"))
	var orb := BattleActionButton.new()
	orb.name = "FocusDevice"
	orb.configure("focus", int(player.get("focus", 0)))
	orb.position = Vector2(34, stage.size.y - (touch_height + 100 if short else 197))
	orb.size = Vector2(118, 102 if short else 116)
	orb.tooltip_text = "专注用于支付卡牌费用，准备阶段恢复。"
	orb.focus_mode = Control.FOCUS_NONE
	stage.add_child(orb)
	var turn := Rect2(1094, 610, 172, 62)
	var cancel_bounds := Rect2(1094, 570, 172, 33)
	if short:
		var pile_top := stage.size.y - touch_height - 6
		var pile_width := maxf(96, touch_height) if mobile else 96.0
		var piles_right := 1264.0
		_pile_button(Rect2(12, pile_top, pile_width, touch_height), "draw", Callable(page, "_show_draw"))
		_pile_button(Rect2(piles_right - pile_width, pile_top, pile_width, touch_height), "discard", Callable(page, "_show_discard"))
		_pile_button(Rect2(piles_right - pile_width * 2 - 8, pile_top, pile_width, touch_height), "exhaust", Callable(page, "_show_exhaust"))
		turn = Rect2(1086 if mobile else 1094, pile_top - touch_height - 6, 178 if mobile else 172, touch_height)
		cancel_bounds = Rect2(1094, turn.position.y - touch_height - 6, 172, touch_height)
	else:
		_pile_button(Rect2(12, 716, 86, 78), "draw", Callable(page, "_show_draw"))
		_pile_button(Rect2(1166, 706, 92, 88), "discard", Callable(page, "_show_discard"))
		_pile_button(Rect2(1088, 739, 66, 55), "exhaust", Callable(page, "_show_exhaust"))
	var end_turn := page.add_end_turn(stage, turn)
	if mobile:
		end_turn.add_theme_font_size_override("font_size", roundi(minimum_text * 1.18))
	var cancel := _button(
		cancel_bounds,
		"battle:cancel",
		"取消选择" if UiStyle.web_touch else "取消选择  Esc",
		{},
		Callable(page, "_cancel_selection")
	)
	cancel.visible = not page._selected_card_id.is_empty() or not page._selected_unit_id.is_empty()
	cancel.disabled = not cancel.visible


func _pile_button(bounds: Rect2, kind: String, callback: Callable) -> BattlePileButton:
	var button := page._add_pile_button(stage, kind, callback)
	button.custom_minimum_size = Vector2.ZERO
	button.position = bounds.position
	button.size = bounds.size
	return button


func _retention() -> void:
	if page.is_locked():
		return
	var quote: Variant = page._preview({"type": "end_turn", "payload": {"retained_card_ids": []}})
	for value in page._required(quote):
		var selection := page._dict(value)
		if str(selection.get("field", "")) != "retained_card_ids":
			continue
		var candidates := page._array(selection.get("candidates"))
		_text(
			stage,
			Rect2(1102, 360, 150, 28),
			"保留 · 最多 %s 张" % selection.get("max_count", 0),
			14,
			LIGHT
		)
		for i in candidates.size():
			var candidate := page._dict(candidates[i])
			var id := str(candidate.get("id", ""))
			var button := _button(
				Rect2(1102, 392 + i * 30, 150, 28),
				"retain:" + id,
				(
					("● " if page._retained_card_ids.has(id) else "○ ")
					+ UiStyle.label(str(candidate.get("label_key", id)))
				),
				{},
				page._bind_retention(id, int(selection.get("max_count", 0)))
			)
			button.add_theme_font_size_override("font_size", 12)


func _selection_hint() -> String:
	var focus := int(page._dict(page.view.get("player")).get("focus", 0))
	if page.is_locked():
		return "完成卡牌效果后继续行动"
	if not page._selected_card_id.is_empty():
		return (
			"剩余专注 %s · 已选【%s】· %s"
			% [
				focus,
				UiStyle.label(page._card_definition(page._selected_card_id)),
				"选择要换班的伙伴" if page._selection_kind() == "replace_unit_id" else "选择高亮目标"
			]
		)
	if not page._selected_unit_id.is_empty():
		return (
			"剩余专注 %s · 已选【%s】· 选择高亮任务进行协作"
			% [focus, UiStyle.label(page._unit_definition(page._selected_unit_id))]
		)
	return ("剩余专注 %s · 点击出牌 / 长按读卡" if UiStyle.web_touch else "剩余专注 %s · 选择手牌，或结束回合恢复专注") % focus


func _hint_for(screen: BattleScreen) -> String:
	page = screen
	return _selection_hint()


func _choice_panel() -> void:
	var overlay := _modal()
	var choice := page._choice_dict(page.view.get("pending_choice"))
	var title: String = (
		{
			"discard": "选择要弃置的卡牌",
			"recall": "选择要回忆的卡牌",
			"retain": "选择要保留的卡牌",
			"retrieve_strategy": "是否取回上一张策略",
			"purify": "选择要净化的状态",
			"chapter_replace": "选择要撤下的章节"
		}
		. get(str(choice.get("kind", "")), "完成卡牌效果")
	)
	_text(overlay, Rect2(30, 24, 1020, 48), title, 28, LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	var choice_prompt := (
		"请选择 %s—%s 项  ·  已选 %s 项"
		% [
			choice.get("min_count", 0),
			choice.get("max_count", 0),
			page._choice_selected_ids.size()
		]
	)
	if str(choice.get("kind", "")) == "retrieve_strategy":
		choice_prompt = "选择要取回的牌；不选直接确认则放弃（本回合机会已消耗）"
	_text(
		overlay,
		Rect2(30, 76, 1020, 32),
		choice_prompt,
		17,
		Color("edcc8e"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 128)
	scroll.size = Vector2(1024, minf(285, 490 - touch_height - 140) if mobile else 285)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(row)
	for value in page._array(choice.get("candidates")):
		var option := page._dict(value)
		var id := str(option.get("id", option.get("candidate_id", "")))
		var data := page._dict(option.get("preview")).duplicate(true)
		for hand_value in page._array(page.view.get("hand")):
			var hand_card := page._dict(hand_value)
			if str(hand_card.get("card_id", "")) == id:
				data.merge(hand_card, true)
		for zone_name in ["discard", "exhaust"]:
			for zone_value in page._array(page._dict(page.view.get("zones_public")).get(zone_name, [])):
				var zone_card := page._dict(zone_value)
				if str(zone_card.get("card_id", "")) == id:
					data.merge(zone_card, true)
		data.definition_id = str(data.get("definition_id", option.get("label_key", id)))
		data.description = UiStyle.label(str(option.get("label_key", id)))
		var card := BattleCard.new()
		card.configure(data, page._choice_selected_ids.has(id))
		row.add_child(card)
		card.set_meta("uid", "choice:" + id)
		page._buttons["choice:" + id] = card
		card.pressed.connect(page._bind_choice(id))
		card.tooltip_text = page._choice_preview_text(data)
	var confirm := page.add_button(overlay, "choice:confirm", "确认选择", page._choice_draft())
	confirm.position = Vector2(410, 490 - touch_height)
	confirm.size = Vector2(260, touch_height)
	_style_button(confirm)
	var restart := page.add_button(
		overlay, "choice:menu", "返回主页", {"type": "ui.menu", "payload": {}}
	)
	_style_button(restart)
	restart.position = Vector2(40, 444)
	restart.size = Vector2(210, 42)
	confirm.position.x = 770


func _info_panel() -> void:
	var overlay := _modal()
	_text(overlay, Rect2(35, 22, 1010, 46), "战斗信息", 26, LIGHT)
	var close_top := 490 - touch_height
	var terms_top := close_top - 39 if mobile else 400.0
	var scroll_end := terms_top - 8 if mobile and not page._detail_terms.is_empty() else close_top - 10
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(35, 85)
	scroll.size = Vector2(1010, scroll_end - 85 if mobile else 310)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)
	page.populate_info(scroll, true)
	if short:
		for label: Label in scroll.find_children("*", "Label", true, false):
			label.add_theme_font_size_override("font_size", maxi(label.get_theme_font_size("font_size"), ceili(minimum_text * 1.2)))
	if not page._detail_terms.is_empty():
		var terms_row := HBoxContainer.new()
		terms_row.position = Vector2(40, terms_top)
		terms_row.size = Vector2(1000, 32)
		terms_row.add_theme_constant_override("separation", 8)
		overlay.add_child(terms_row)
		var terms_label := page.add_text(terms_row, "词条：", 14, LIGHT)
		terms_label.custom_minimum_size = Vector2(48, 0)
		terms_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for term in page._detail_terms:
			var chip := page.add_button(
				terms_row, "term:" + term, UiGlossary.label(term), {}, page._bind_term(term)
			)
			chip.custom_minimum_size = Vector2(76, 30)
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			chip.add_theme_font_size_override("font_size", 13)
	var close := page.add_button(
		overlay, "battle:close_panel", "返回战斗" if UiStyle.web_touch else "返回战斗  Esc", {}, Callable(page, "_close_panel")
	)
	close.position = Vector2(410, close_top)
	close.size = Vector2(260, touch_height)
	_style_button(close)


func _modal() -> Control:
	var layer := Control.new()
	layer.size = stage.size
	layer.z_index = 200
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(layer)
	_rect(layer, Rect2(Vector2.ZERO, stage.size), Color(0.02, 0.05, 0.07, 0.8))
	return _panel(layer, Rect2(100, (stage.size.y - 540) * .5, 1080, 520), DARK, Color("c7ae78"))


func _button(
	bounds: Rect2,
	uid: String,
	caption: String,
	draft: Variant = {},
	callback: Callable = Callable()
) -> Button:
	var button := page.add_button(stage, uid, caption, draft, callback)
	button.custom_minimum_size = Vector2.ZERO
	_style_button(button)
	button.position = bounds.position
	button.size = bounds.size
	return button


func _style_button(button: Button) -> void:
	UiStyle.button_skin(button,"secondary",true)
	button.add_theme_font_size_override("font_size",maxi(14,minimum_text))
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.set_content_margin_all(2)
		button.add_theme_stylebox_override(state,style)


func _transparent_target(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		if state in ["hover", "focus"]:
			style.border_color = Color("f3d38a")
			style.set_border_width_all(3)
		button.add_theme_stylebox_override(state, style)


func _text(
	parent: Node,
	bounds: Rect2,
	value: String,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", maxi(font_size, minimum_text))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0,0,0,.8))
	label.add_theme_color_override("font_outline_color", Color("14212a"))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.size = bounds.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = bounds.position
	label.size = bounds.size
	label.set_deferred("size", bounds.size)
	return label


func _panel(parent: Node, bounds: Rect2, color: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.box(color)
	style.border_color = border
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _art(parent: Node, id: String, bounds: Rect2) -> void:
	var art := TextureRect.new()
	art.set_meta("art_id", id)
	art.texture = UiStyle.texture(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	art.position = bounds.position
	art.size = bounds.size


func _rect(parent: Node, bounds: Rect2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = bounds.position
	rect.size = bounds.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func _bar(parent: Node, bounds: Rect2, fraction: float, color: Color) -> Control:
	_rect(parent, bounds, Color("1c3034"))
	_rect(
		parent,
		Rect2(bounds.position, Vector2(bounds.size.x * clampf(fraction, 0, 1), bounds.size.y)),
		color
	)
	return parent.get_child(parent.get_child_count() - 1) as Control
