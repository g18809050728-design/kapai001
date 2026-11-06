class_name BattleCompactLayout
extends RefCounted


func build(page: BattleScreen) -> void:
	page._reset_stage()
	page.reset_page("第%d回合 · DDL 剩余%d次完整轮末" % [int(page.view.get("round_index", 0)), int(page.view.get("ddl", 0))], "点击手牌，再点击目标 · 停留查看介绍 · I 固定 / 取消", true)
	page._stage = Control.new()
	page._stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page._stage.size = page.size
	page.add_child(page._stage)
	page._hover_panel = null
	page._aim = null
	var descriptions := BattleLayout.new()
	descriptions.page = page
	descriptions.stage = page._stage
	descriptions._hover_window()
	var player: Dictionary = page.view.get("player", {})
	var info: Dictionary = page.view.get("character_info", {})
	var resource_text := "%s · 精力%s · 放松%s · 专注%s" % [UiStyle.label(str(page.view.get("character_id", ""))).split("·")[0], player.get("vitality", 0), player.get("relax", 0), player.get("focus", 0)]
	var v3: Dictionary = page.view.get("v3", {})
	if str(page.view.get("character_id", "")) == "P02":
		var paper: Dictionary = v3.get("paper", {})
		resource_text += " · 论文进度%s · 引用%s" % [paper.get("progress", 0), paper.get("citations", 0)]
	elif str(page.view.get("character_id", "")) == "P04":
		resource_text += " · 协同%s" % v3.get("synergy", 0)
	var passive_name := str({"P01": "步骤复用", "P03": "复合反应", "P04": "首张合作"}.get(str(page.view.get("character_id", "")), "能力"))
	if str(page.view.get("character_id", "")) == "P01":
		resource_text += " · 前牌" + UiStyle.label(str(info.get("previous_type", "无")))
	resource_text += " · " + passive_name + ("可用" if info.get("passive_available", true) else "已使用")
	page.add_button(page.header, "battle:resources", resource_text, {}, func(): page._open_detail_for_uid("battle:resources"))
	var tools := page.add_row(page.header)
	page._add_pile_button(tools, "deck", page._show_deck, false)
	page._add_pile_button(tools, "log", page._show_log, false)
	page.add_button(tools, "battle:rules", "规则", {}, page._show_rules)
	page.add_button(tools, "battle:animation", "动画" + ("开" if page.animation_enabled else "关"), {}, page._toggle_animation)
	page.add_button(tools, "battle:speed", "×%s" % page.speed_scale, {}, page._cycle_speed)
	page.add_button(tools, "battle:save", "保存", {"type": "ui.save", "payload": {}})
	page.add_button(tools, "battle:menu", "菜单", {"type": "ui.menu", "payload": {}})
	if not page._panel_text.is_empty():
		page.body.get_parent().get_parent().visible = false
		for button in page._buttons.values():
			button.focus_mode = Control.FOCUS_NONE
			button.disabled = true
		page.add_text(page.footer, "关闭详情后继续战斗", 15)
		var overlay := PanelContainer.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.z_index = 200
		page.add_child(overlay)
		var column := VBoxContainer.new()
		overlay.add_child(column)
		page.add_text(column, "战斗信息", 22)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(scroll)
		page.populate_info(scroll)
		var close := page.add_button(column, "battle:close_panel", "返回战斗 · Esc", {}, page._close_panel)
		close.grab_focus()
		return
	if page.is_locked():
		_choice(page)
	else:
		var columns := page.add_row(page.body)
		columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var targets := ScrollContainer.new()
		targets.custom_minimum_size.x = 250 * minf(UiStyle.text_scale, 1.2)
		targets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		targets.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		columns.add_child(targets)
		var target_column := VBoxContainer.new()
		target_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		targets.add_child(target_column)
		_targets(page, target_column)
		var hand_column := VBoxContainer.new()
		hand_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hand_column.size_flags_stretch_ratio = 2
		columns.add_child(hand_column)
		_hand(page, hand_column)
		var retain: Variant = page._preview({"type": "end_turn", "payload": {"retained_card_ids": []}})
		for value in page._required(retain):
			if value.get("field", "") != "retained_card_ids":
				continue
			page.add_text(page.body, "选择保留 · 最多 %s 张" % value.get("max_count", 0), 16)
			for candidate in value.get("candidates", []):
				var id := str(candidate.get("id", ""))
				page.add_button(page.body, "retain:" + id, ("✓ " if page._retained_card_ids.has(id) else "") + UiStyle.label(str(candidate.get("label_key", id))), {}, page._bind_retention(id, int(value.get("max_count", 0))))
		page._hint_label = page.add_text(page.footer, BattleLayout.new()._hint_for(page), 16)
		var actions := page.add_row(page.footer)
		page.add_end_turn(actions)
		page.add_button(actions, "battle:cancel", "取消预选", {}, page._cancel_selection)
		for entry in [["draw", "抽牌堆", page._show_draw], ["discard", "弃牌堆", page._show_discard], ["exhaust", "消耗堆", page._show_exhaust]]:
			page._add_pile_button(actions, entry[0], entry[2], false)
	page._feedback_label = page.add_text(page.footer, page._feedback_text, 14)
	page._feedback_label.visible = not page._feedback_text.is_empty()
	page._apply_preview_gating()
	page._apply_lock_state()
	page._layout_regions.call_deferred()


func _targets(page: BattleScreen, parent: Node) -> void:
	var grid := VBoxContainer.new()
	parent.add_child(grid)
	var descriptions := BattleLayout.new()
	descriptions.page = page
	for task in page.view.get("tasks", []):
		var id := str(task.task_id)
		var column := page.add_panel(grid)
		page._target_frames["task:" + id] = column.get_parent()
		column.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_text(column, UiStyle.label(str(task.definition_id)), 18)
		if int(task.get("phase_count", 1)) > 1:
			page.add_text(column, "第%s/%s阶段 · %s" % [task.get("phase_index", 1), task.get("phase_count", 1), UiStyle.label(str(task.get("phase_key", "")))], 14)
		var meter := ProgressBar.new()
		meter.max_value = maxi(1, int(task.work_max))
		meter.value = task.work_remaining
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(0, 10)
		column.add_child(meter)
		var work_label := page.add_text(column, "剩余 %s/%s · 屏障 %s" % [task.work_remaining, task.work_max, task.shield], 14)
		page._task_meters[id] = {"fill": meter, "label": work_label, "maximum": maxi(1, int(task.work_max))}
		page.add_text(column, "%s\n%s" % [page._intent_text(task.get("intent_snapshot", {})), descriptions._task_status_text(id)], 14)
		var actions := page.add_row(column)
		page.add_button(actions, "task:" + id, "选择目标", {}, page._bind_task(id))
		page.add_button(actions, "detail:task:" + id, "详情", {}, func(): page._open_detail_for_uid("task:" + id))
	var statuses := page._status_text(page.view.get("statuses", []).filter(func(status): return str(status.get("target_id", "")) == str(page.view.get("player", {}).get("entity_id", ""))))
	if not statuses.is_empty():
		page.add_button(parent, "statuses:player", statuses, {}, func(): page._open_detail_for_uid("statuses:player"))
	for unit in page.view.get("units", []):
		var id := str(unit.unit_id)
		page.add_button(parent, "unit:" + id, "%s · 精力%s · 协作%s · 放松%s" % [UiStyle.label(str(unit.definition_id)), unit.vitality, unit.cooperation, unit.relax], {}, page._bind_unit(id))


func _hand(page: BattleScreen, parent: Node) -> void:
	page.add_text(parent, "手牌 · %d 张 · 横向浏览 · I固定详情" % page.view.get("hand", []).size(), 16)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 250 + 100 * (UiStyle.text_scale - 1)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	scroll.add_child(row)
	for card in page.view.get("hand", []):
		var id := str(card.card_id)
		var detail: Dictionary = card.get("face", card.get("effective_card", {})).duplicate(true)
		detail.cost = card.get("effective_cost", detail.get("cost", 0))
		detail.vitality_cost = card.get("effective_vitality_cost", detail.get("vitality_cost", 0))
		page.add_card(row, "card:" + id, str(card.definition_id), detail, UiStyle.label(str(card.definition_id)), page._selected_card_id == id, page._bind_card(id))


func _choice(page: BattleScreen) -> void:
	var choice := page._choice_dict(page.view.get("pending_choice"))
	page.add_text(page.body, "必须完成当前效果 · 已选%d / %s—%s项" % [page._choice_selected_ids.size(), choice.get("min_count", 0), choice.get("max_count", 0)], 20)
	var grid := GridContainer.new()
	grid.columns = 3
	page.body.add_child(grid)
	for option in choice.get("candidates", []):
		var id := str(option.get("id", option.get("candidate_id", "")))
		var detail: Dictionary = option.get("preview", {})
		var definition := str(detail.get("definition_id", option.get("label_key", id)))
		page.add_card(grid, "choice:" + id, definition, detail.get("face", detail.get("detail", detail)), UiStyle.label(definition), page._choice_selected_ids.has(id), page._bind_choice(id))
	page.add_button(page.footer, "choice:confirm", "确认必选结果", page._choice_draft())
	page.add_button(page.footer, "choice:new_run", "配置新一局", {"type": "ui.new_run", "payload": {}})
