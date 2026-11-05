class_name BattleLayout
extends RefCounted

const LIGHT := Color("f4eedf")
const SOFT := Color("c1d0c7")
const DARK := Color("192f35")
var page: BattleScreen
var stage: Control


func build(screen: BattleScreen) -> void:
	page = screen
	page._reset_stage()
	stage = page._stage
	var background := TextureRect.new()
	background.texture = UiStyle.texture("BG_classroom")
	background.size = Vector2(1280, 800)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	_rect(stage, Rect2(0, 0, 1280, 800), Color(0.04, 0.1, 0.13, 0.36))
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.03, 0.08, 0.1, 0.0), Color(0.03, 0.08, 0.1, 0.96)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.position = Vector2(0, 370)
	shade.size = Vector2(1280, 430)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shade)
	_header()
	_player()
	_tasks()
	_units()
	_rect(stage, Rect2(176, 761, 920, 39), Color(0.04, 0.1, 0.13, 0.85))
	_hand()
	_controls()
	_v3_summary()
	page._aim = BattleAim.new()
	page._aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page._aim.z_index = 70
	stage.add_child(page._aim)
	page._feedback_label = _text(
		stage, Rect2(26, 78, 210, 34) if not page._dict(page.view.get("v3")).is_empty() else Rect2(290, 78, 710, 44), page._feedback_text, 13 if not page._dict(page.view.get("v3")).is_empty() else 16, LIGHT, HORIZONTAL_ALIGNMENT_CENTER
	)
	page._feedback_label.visible = not page._feedback_text.is_empty()
	page._hint_label = _text(
		stage, Rect2(176, 762, 920, 23), _selection_hint(), 14, LIGHT, HORIZONTAL_ALIGNMENT_CENTER
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


func _hover_window() -> void:
	var factor := UiStyle.text_scale if page._compact_layout else 1.0
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
	page._hover_body = _text(panel, Rect2(Vector2(16, 62) * factor, Vector2(328, 82) * factor), "", roundi(14 * factor), LIGHT)
	page._hover_body.max_lines_visible = 4
	_text(panel, Rect2(Vector2(16, 146) * factor, Vector2(328, 16) * factor), "I 查看详情", roundi(12 * factor), Color("f1c989"), HORIZONTAL_ALIGNMENT_RIGHT)


func _header() -> void:
	_rect(stage, Rect2(0, 0, 1280, 66), Color(0.035, 0.09, 0.11, 0.9))
	_text(stage, Rect2(26, 10, 350, 23), "DDL 战争  /  " + str(page.view.get("year_label", "第一学期")), 16, Color("e6c68d"))
	_text(stage, Rect2(26, 34, 400, 25), page._battle_subtitle(), 18, LIGHT)
	_text(
		stage,
		Rect2(414, 14, 320, 38),
		(
			"第 %s 回合 · %s | DDL %s次轮末"
			% [
				page.view.get("round_index", 0),
				UiStyle.label(str(page.view.get("phase", ""))),
				page.view.get("ddl", 0)
			]
		),
		17,
		Color("ffab91") if int(page.view.get("ddl", 0)) <= 1 else (Color("f6d184") if int(page.view.get("ddl", 0)) <= 3 else LIGHT),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if int(page.view.get("ddl", 0)) <= 3:
		_text(stage, Rect2(430, 53, 290, 22), "DDL 紧迫：请尽快完成任务" if int(page.view.get("ddl", 0)) > 1 else "DDL 仅剩 1：本轮必须推进", 13, Color("ffcbab"), HORIZONTAL_ALIGNMENT_CENTER)
	_pile_button(Rect2(752, 3, 72, 58), "deck", Callable(page, "_show_deck"))
	_pile_button(Rect2(830, 3, 72, 58), "log", Callable(page, "_show_log"))
	_button(Rect2(908, 14, 72, 36), "battle:rules", "规则", {}, Callable(page, "_show_rules"))
	_button(
		Rect2(986, 14, 62, 36),
		"battle:speed",
		"×%s" % page.speed_scale,
		{},
		Callable(page, "_cycle_speed")
	)
	_button(
		Rect2(1054, 14, 66, 36),
		"battle:animation",
		"动画" + ("开" if page.animation_enabled else "关"),
		{},
		Callable(page, "_toggle_animation")
	)
	_button(Rect2(1126, 14, 62, 36), "battle:save", "保存", {"type": "ui.save", "payload": {}})
	_button(Rect2(1194, 14, 62, 36), "battle:menu", "菜单", {"type": "ui.menu", "payload": {}})


func _player() -> void:
	var player := page._dict(page.view.get("player"))
	var portrait := _panel(stage, Rect2(48, 183, 186, 239), Color("ebe5d5"), Color("cfb57c"))
	_art(portrait, str(page.view.get("character_id", "P01")), Rect2(6, 6, 174, 194))
	_text(
		portrait,
		Rect2(6, 202, 174, 28),
		UiStyle.label(str(page.view.get("character_id", "P01"))).split("·")[0],
		20,
		UiStyle.INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var hp := int(player.get("vitality", 0))
	var max_hp := int(page.view.get("max_vitality", maxi(1, hp)))
	_bar(stage, Rect2(48, 435, 186, 11), float(hp) / maxi(1, max_hp), Color("ba7469"))
	_text(
		stage,
		Rect2(48, 450, 230, 26),
		"精力 %s / %s  ·  放松 %s" % [hp, max_hp, player.get("relax", 0)],
		16,
		LIGHT
	)
	_text(stage, Rect2(48, 117, 330, 28), "我的行动", 23, LIGHT)
	var statuses := page._array(page.view.get("statuses"))
	var player_id := str(player.get("entity_id", ""))
	var player_statuses: Array = []
	for value in statuses:
		if str(page._dict(value).get("target_id", "")) == player_id:
			player_statuses.append(value)
	if not player_statuses.is_empty():
		var status_label := _text(stage, Rect2(26, 484, 148, 68), page._status_text(player_statuses), 14, Color("e5c894"))
		status_label.max_lines_visible = 3
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var status_hit := _button(
			Rect2(26, 484, 148, 68),
			"statuses:player",
			"",
			{},
			Callable(page, "_open_detail_for_uid").bind("statuses:player")
		)
		_transparent_target(status_hit)
	var scene := page._dict(page.view.get("scene"))
	if not scene.is_empty() and page._dict(page.view.get("v3")).is_empty():
		_text(
			stage,
			Rect2(280, 86, 310, 30),
			"场景 · " + UiStyle.label(str(scene.get("definition_id", ""))),
			16,
			SOFT
		)


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
	var panel := _panel(stage, Rect2(255, 74, 1000, 58), Color(0.05, 0.12, 0.15, 0.96), Color("6b8c85"))
	panel.name = "V3Summary"
	_text(panel, Rect2(12, 4, 976, 50), "\n".join(lines), 17, LIGHT)
	var info_hit := _button(Rect2(255, 74, 1000, 58), "battle:resources", "", {}, func(): page._open_detail_for_uid("battle:resources"))
	_transparent_target(info_hit)


func _tasks() -> void:
	var tasks := page._array(page.view.get("tasks"))
	if tasks.is_empty():
		_text(stage, Rect2(600, 240, 450, 80), "当前任务已完成", 25, LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	var width := minf(234, 752.0 / maxi(1, tasks.size()) - 16)
	var start := 500 + (752 - tasks.size() * (width + 16)) * 0.5
	for index in tasks.size():
		var task := page._dict(tasks[index])
		var id := str(task.get("task_id", ""))
		var x := start + index * (width + 16)
		var intent := page._intent_text(page._dict(task.get("intent_snapshot")))
		var badge := _panel(
			stage, Rect2(x, 136, width, 56), Color(0.09, 0.16, 0.18, 0.9), Color("b98968")
		)
		_text(
			badge,
			Rect2(8, 4, width - 16, 48),
			"下回合意图\n" + intent,
			15,
			Color("f3d2a1"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var frame := _panel(stage, Rect2(x, 207, width, 236), Color("eee7d7"), Color("d0b785"))
		var phase_count := int(task.get("phase_count", 1))
		var has_phases := phase_count > 1
		_art(
			frame,
			str(task.get("definition_id", "")),
			Rect2(7, 7, width - 14, 142 if has_phases else 162)
		)
		_text(
			frame,
			Rect2(8, 155 if has_phases else 177, width - 16, 30 if has_phases else 48),
			UiStyle.label(str(task.get("definition_id", ""))),
			20,
			UiStyle.INK,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var phase_text := UiStyle.label(str(task.get("phase_key", "")))
		if has_phases:
			var phase_index := int(task.get("phase_index", 1))
			phase_text = "第 %s / %s 阶段 · %s" % [phase_index, phase_count, phase_text]
			phase_text += "\n最终阶段，完成即可获胜" if phase_index == phase_count else "\n完成后进入下一阶段"
			_text(
				frame,
				Rect2(8, 187, width - 16, 42),
				phase_text,
				13,
				UiStyle.INK,
				HORIZONTAL_ALIGNMENT_CENTER
			)
		var remaining := int(task.get("work_remaining", 0))
		var maximum := maxi(1, int(task.get("work_max", 1)))
		_bar(stage, Rect2(x, 447, width, 10), float(remaining) / maximum, Color("b77566"))
		_text(
			stage,
			Rect2(x - 4, 463, width + 8, 24),
			"剩余 %s/%s  ·  屏障 %s" % [remaining, maximum, task.get("shield", 0)],
			16,
			LIGHT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var target := _button(Rect2(x, 207, width, 236), "task:" + id, "", {}, page._bind_task(id))
		_transparent_target(target)
		page._target_frames["task:" + id] = frame
		var status_text := _task_status_text(id)
		if not status_text.is_empty():
			var statuses := _text(stage, Rect2(x + 7, 312, width - 14, 44), status_text, 13, Color("ffe0aa"), HORIZONTAL_ALIGNMENT_CENTER)
			statuses.name = "TaskStatus_" + id.validate_node_name()
			var status_style := UiStyle.box(Color("233d43"))
			status_style.set_content_margin_all(3)
			statuses.add_theme_stylebox_override("normal", status_style)
			statuses.max_lines_visible = 2
			statuses.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			statuses.z_index = 2
			statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _task_status_text(task_id: String) -> String:
	var parts: PackedStringArray = []
	for value in page._array(page.view.get("statuses")):
		var status := page._dict(value)
		if str(status.get("target_id", "")) != task_id:
			continue
		parts.append(
			"%s×%s" % [UiStyle.label(str(status.get("status_id", ""))), status.get("stacks", 0)]
		)
	return "、".join(parts)


func _units() -> void:
	var units := page._array(page.view.get("units"))
	if units.is_empty():
		_text(
			stage,
			Rect2(272, 376, 190, 55),
			"协作区\n合作伙伴将在这里加入",
			14,
			SOFT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	var height := minf(132, 300.0 / maxi(1, units.size()) - 8)
	for index in units.size():
		var unit := page._dict(units[index])
		var id := str(unit.get("unit_id", ""))
		var bounds := Rect2(270, 170 + index * (height + 8), 192, height)
		var frame := _panel(stage, bounds, Color("e7e6d8"), Color("8fa793"))
		_art(frame, str(unit.get("definition_id", "")), Rect2(5, 5, 65, height - 10))
		_text(
			frame,
			Rect2(77, 7, 108, 30),
			UiStyle.label(str(unit.get("definition_id", ""))).split("：")[0],
			16,
			UiStyle.INK
		)
		_text(
			frame,
			Rect2(77, 39, 108, height - 42),
			(
				"精力 %s · 协作 %s\n放松 %s · 护卫 %s"
				% [
					unit.get("vitality", 0),
					unit.get("cooperation", 0),
					unit.get("relax", 0),
					unit.get("guard", 0)
				]
			),
			13,
			UiStyle.MUTED
		)
		var target := _button(bounds, "unit:" + id, "", {}, page._bind_unit(id))
		_transparent_target(target)
		page._target_frames["unit:" + id] = frame


func _hand() -> void:
	var cards := page._array(page.view.get("hand"))
	var step := minf(146, 720.0 / maxi(1, cards.size() - 1))
	var start := 640 - (step * (cards.size() - 1) + BattleCard.FACE_SIZE.x) * 0.5
	for index in cards.size():
		var data := page._dict(cards[index])
		var id := str(data.get("card_id", ""))
		var card := BattleCard.new()
		card.configure(data, page._selected_card_id == id)
		card.shortcut_index = index + 1 if index < 9 else 0
		card.set_meta("uid", "card:" + id)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var offset := float(index) - (cards.size() - 1) * 0.5
		card.home_rotation = deg_to_rad(clampf(offset * 1.6, -5, 5))
		card.home_position = Vector2(start + index * step, 495 + minf(absf(offset), 3) * 2)
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
			Rect2(350, 630, 580, 60),
			"手牌已空  ·  结束回合以继续",
			22,
			SOFT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	_text(
		stage,
		Rect2(300, 786, 680, 14),
		"1—9 选牌 / 点击或拖拽出牌 / I 详情 / 右键或 Esc 取消",
		11,
		SOFT,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_retention()


func _controls() -> void:
	var player := page._dict(page.view.get("player"))
	var orb := BattleActionButton.new()
	orb.configure("focus", int(player.get("focus", 0)))
	orb.position = Vector2(40, 572)
	orb.size = Vector2(120, 92)
	orb.tooltip_text = "专注用于支付卡牌费用，准备阶段恢复。"
	orb.focus_mode = Control.FOCUS_NONE
	stage.add_child(orb)
	_pile_button(Rect2(40, 684, 104, 108), "draw", Callable(page, "_show_draw"))
	_pile_button(Rect2(1106, 690, 72, 102), "discard", Callable(page, "_show_discard"))
	_pile_button(Rect2(1188, 690, 72, 102), "exhaust", Callable(page, "_show_exhaust"))
	page.add_end_turn(stage, Rect2(1102, 587, 150, 72))
	var cancel := _button(
		Rect2(1102, 541, 150, 34),
		"battle:cancel",
		"取消选择  Esc",
		{},
		Callable(page, "_cancel_selection")
	)
	cancel.visible = not page._selected_card_id.is_empty() or not page._selected_unit_id.is_empty()
	cancel.disabled = not cancel.visible
	var notice := _text(stage, Rect2(22, 666, 148, 20), str(page.view.get("notice", "")), 12, SOFT)
	notice.max_lines_visible = 1
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


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
	return "剩余专注 %s · 选择手牌，或结束回合恢复专注" % focus


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
			"purify": "选择要净化的状态",
			"chapter_replace": "选择要撤下的章节"
		}
		. get(str(choice.get("kind", "")), "完成卡牌效果")
	)
	_text(overlay, Rect2(30, 24, 1020, 48), title, 28, LIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_text(
		overlay,
		Rect2(30, 76, 1020, 32),
		(
			"请选择 %s—%s 项  ·  已选 %s 项"
			% [
				choice.get("min_count", 0),
				choice.get("max_count", 0),
				page._choice_selected_ids.size()
			]
		),
		17,
		Color("edcc8e"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 128)
	scroll.size = Vector2(1024, 285)
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
	confirm.position = Vector2(410, 438)
	confirm.size = Vector2(260, 52)
	_style_button(confirm)
	var restart := page.add_button(
		overlay, "choice:new_run", "新一局", {"type": "ui.new_run", "payload": {}}
	)
	_style_button(restart)
	restart.position = Vector2(820, 444)
	restart.size = Vector2(210, 42)


func _info_panel() -> void:
	var overlay := _modal()
	_text(overlay, Rect2(35, 22, 1010, 46), "战斗信息", 26, LIGHT)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(35, 85)
	scroll.size = Vector2(1010, 310)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)
	page.populate_info(scroll, true)
	if not page._detail_terms.is_empty():
		var terms_row := HBoxContainer.new()
		terms_row.position = Vector2(40, 400)
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
		overlay, "battle:close_panel", "返回战斗  Esc", {}, Callable(page, "_close_panel")
	)
	close.position = Vector2(410, 438)
	close.size = Vector2(260, 52)
	_style_button(close)


func _modal() -> Control:
	var layer := Control.new()
	layer.size = Vector2(1280, 800)
	layer.z_index = 200
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(layer)
	_rect(layer, Rect2(0, 0, 1280, 800), Color(0.02, 0.05, 0.07, 0.8))
	return _panel(layer, Rect2(100, 130, 1080, 520), DARK, Color("c7ae78"))


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
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", LIGHT)
	button.add_theme_color_override("font_hover_color", Color("ffde9d"))
	button.add_theme_color_override("font_disabled_color", Color("788b88"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := UiStyle.box(Color("27474a") if state == "normal" else Color("365957"))
		style.border_color = Color("d8ba7c") if state in ["hover", "focus"] else Color("718d82")
		style.set_border_width_all(1)
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		style.content_margin_left = 3
		style.content_margin_right = 3
		button.add_theme_stylebox_override(state, style)


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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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


func _bar(parent: Node, bounds: Rect2, fraction: float, color: Color) -> void:
	_rect(parent, bounds, Color("1c3034"))
	_rect(
		parent,
		Rect2(bounds.position, Vector2(bounds.size.x * clampf(fraction, 0, 1), bounds.size.y)),
		color
	)
