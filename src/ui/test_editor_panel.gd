class_name TestEditorPanel
extends Control

## Draft-based test editor. All domain writes leave through `command`; the panel
## only holds UI drafts, search text and scroll state.

signal command(command_type: String, payload: Dictionary)
signal close_requested

const TABS := [
	["character", "角色"],
	["cards", "牌区"],
	["resources", "资源"],
	["enemies", "敌人"],
	["allies", "伙伴饰品"],
	["statuses", "状态"],
	["time", "时间随机"],
	["rules", "规则覆盖"],
	["history", "检查点"],
]
const DRAWER_WIDTH := 520.0

var session: GameSession
var _view: Dictionary = {}
var _options: Dictionary = {}
var _open := false
var _tab := "character"
var _zone := "hand"
var _search := ""
var _status_target := ""
var _status_text := ""
var _draft: Dictionary = {}
var _draft_revision := -1
var _show_policy := false
var _applying := false
var _override_card := ""
var _override_field := "cost"
var _seq := 0
var _buttons: Dictionary = {}

var _panel: PanelContainer
var _column: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _search_input: LineEdit
var _draft_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color("fffbf1")))
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "EditorRoot"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_column = column
	_panel.visible = false
	notification(NOTIFICATION_RESIZED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_update_layout()


func _update_layout() -> void:
	var compact := size.x < 1100 or size.y < 700
	if compact:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.offset_left = 8
		_panel.offset_right = -8
		_panel.offset_top = 54
		_panel.offset_bottom = -8
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_panel.offset_left = -DRAWER_WIDTH
		_panel.offset_right = -8
		_panel.offset_top = 54
		_panel.offset_bottom = -8


func setup(p_session: GameSession) -> void:
	session = p_session


func is_open() -> bool:
	return _open


func draft_count() -> int:
	return _draft.size()


func open() -> void:
	_open = true
	_panel.visible = true
	_render_all()


func close() -> void:
	_open = false
	_panel.visible = false


func render(view: Dictionary) -> void:
	_view = view
	if _options.is_empty() and session != null:
		var options := session.get_test_room_options()
		if options.ok:
			_options = options.data
	if _status_target.is_empty() or not _holder_exists(_status_target):
		_status_target = str(_player().get("entity_id", ""))
	if not _open:
		_panel.visible = false
		return
	_panel.visible = true
	_render_all()


func button_uids() -> Array:
	return _buttons.keys()


func press(uid: String) -> bool:
	if not _buttons.has(uid) or not is_instance_valid(_buttons[uid]):
		return false
	var control: Control = _buttons[uid]
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	if control.has_signal("pressed"):
		control.emit_signal("pressed")
		return true
	return false


func handle_result(accepted: bool) -> void:
	_applying = false
	_show_policy = false
	if accepted:
		_draft.clear()
		_status_text = "已应用修改"
	else:
		_status_text = "应用失败，草稿保留"
	_render_all()


func _render_all() -> void:
	if _panel == null:
		return
	var scroll_value := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
	var column := _column
	if column == null:
		return
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_build_header(column)
	_build_tabs(column)
	_build_content(column)
	_build_footer(column)
	call_deferred("_restore_scroll", scroll_value)


func _restore_scroll(value: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = value


func _build_header(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var title := Label.new()
	title.text = "测试编辑器"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var test_state := _test()
	var meta := Label.new()
	meta.text = "分支 %s · rev %s" % [test_state.get("branch_id", 0), test_state.get("revision", 0)]
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", UiStyle.MUTED)
	row.add_child(meta)
	_button(row, "test:editor:close", "关闭", func(): close_requested.emit())


func _build_tabs(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for entry in TABS:
		var tab_id: String = entry[0]
		var button := _button(
			grid,
			"test:editor:tab:" + tab_id,
			entry[1],
			func(): _tab = tab_id; _render_all()
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(84, 32)
		if tab_id == _tab:
			button.add_theme_color_override("font_color", UiStyle.GOLD)
			button.add_theme_stylebox_override("normal", UiStyle.box(Color("f3e7c9")))


func _build_content(parent: VBoxContainer) -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)
	match _tab:
		"character":
			_build_character()
		"cards":
			_build_cards()
		"resources":
			_build_resources()
		"enemies":
			_build_enemies()
		"allies":
			_build_allies()
		"statuses":
			_build_statuses()
		"time":
			_build_time()
		"rules":
			_build_rules()
		"history":
			_build_history()


func _build_character() -> void:
	_label(_content, "当前角色：%s" % UiStyle.label(str(_config().get("character_id", ""))), 16)
	for character in _options.get("characters", []):
		var row := _row(_content)
		var id := str(character.get("id", ""))
		_label(row, "%s · 被动 %s" % [UiStyle.label(id), str(character.get("passive_id", ""))], 14)
		_button(
			row,
			"test:editor:character:" + id,
			"切换",
			func():
				_set_draft(
					"character",
					{"op": "set_character", "character_id": id, "keep_deck": true, "keep_relics": true}
				)
		)
	_hint("切换默认保留牌与通用状态；目标角色专属状态按默认建立，旧状态进入撤销快照。")


func _build_cards() -> void:
	var zone_row := _row(_content)
	for zone in ["hand", "draw", "discard", "exhaust"]:
		var counts: Dictionary = _battle().get("zone_counts", {})
		var caption := "%s %s" % [_zone_name(zone), counts.get(zone, 0)]
		var button := _button(
			zone_row, "test:editor:zone:" + zone, caption, func(): _zone = zone; _render_all()
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if zone == _zone:
			button.add_theme_color_override("font_color", UiStyle.GOLD)
	var cards := _zone_cards(_zone)
	_label(_content, "%s · %d 张" % [_zone_name(_zone), cards.size()], 15, UiStyle.MUTED)
	for entry in cards:
		var row := _row(_content)
		var name := UiStyle.label(str(entry.get("definition_id", "")))
		if int(entry.get("upgrade_level", 0)) > 0:
			name += " +%s" % entry.get("upgrade_level", 0)
		_label(row, name, 15)
		var card_id := str(entry.get("card_id", ""))
		if _zone != "hand":
			_button(row, "test:editor:card:%s:move" % card_id, "移手", func():
				_set_draft("card.%s.move" % card_id, {"op": "move_instance", "instance_id": card_id, "zone": "hand"})
			)
		_button(row, "test:editor:card:%s:dup" % card_id, "复制", func():
			_set_draft("card.%s.dup" % card_id, {"op": "duplicate_instance", "instance_id": card_id, "zone": _zone, "count": 1})
		)
		_button(row, "test:editor:card:%s:up" % card_id, "升/降", func():
			var level := 0 if int(entry.get("upgrade_level", 0)) > 0 else 1
			_set_draft("card.%s.up" % card_id, {"op": "set_card_field", "scope": "instance", "target": card_id, "field": "upgrade_level", "value": level})
		)
		_button(row, "test:editor:card:%s:rm" % card_id, "移除", func():
			_set_draft("card.%s.rm" % card_id, {"op": "remove_instance", "instance_id": card_id})
		)
	_search_card_list(_content, "加入卡牌")
	var actions := _row(_content)
	_button(actions, "test:editor:cards:shuffle", "洗抽牌堆", func():
		_set_draft("cards.shuffle", {"op": "shuffle_zone", "zone": "draw"})
	)
	_button(actions, "test:editor:cards:clear_discard", "清弃牌堆", func():
		_set_draft("cards.clear_discard", {"op": "clear_zone", "zone": "discard"})
	)
	_button(actions, "test:editor:cards:draw", "执行抽 1 张", func():
		_set_draft("cards.draw", {"op": "run_rule_op", "rule": "draw", "args": {"count": 1}})
	)


func _build_resources() -> void:
	var player := _player()
	_label(_content, "战斗资源", 17)
	_player_row("精力", "player.vitality", int(player.get("vitality", 0)), 1, 0, 9999, "vitality")
	_player_row("精力上限", "player.max_vitality", int(player.get("max_vitality", 0)), 1, 1, 9999, "max_vitality")
	_player_row("专注", "player.focus", int(player.get("focus", 0)), 1, 0, 999, "focus")
	_player_row("放松", "player.relax", int(player.get("relax", 0)), 1, 0, 999, "relax")
	var character_id := str(_config().get("character_id", ""))
	if character_id == "P02":
		_label(_content, "论文区", 17)
		var paper: Dictionary = _battle().get("v3", {}).get("paper", {})
		var open_check := CheckBox.new()
		open_check.text = "已开题"
		open_check.button_pressed = bool(paper.get("open", false))
		open_check.add_theme_font_size_override("font_size", 14)
		open_check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		open_check.toggled.connect(func(value: bool):
			_set_draft("v3.paper.open", {"op": "set_v3_field", "path": "paper.open", "value": value})
		)
		_content.add_child(open_check)
		_v3_row("进度", "paper.progress", int(paper.get("progress", 0)), 0, 999)
		_v3_row("引用", "paper.citations", int(paper.get("citations", 0)), 0, 5)
		_v3_row("修正", "paper.modifier", int(paper.get("modifier", 0)), 0, 999)
		_v3_row("放大", "paper.amplify", int(paper.get("amplify", 0)), 0, 999)
	if character_id == "P04":
		_label(_content, "协同", 17)
		_v3_row("协同", "synergy", int(_battle().get("v3", {}).get("synergy", 0)), 0, 999)
	_hint("数值会进入草稿，应用后一次发布；精力为 0 需要先打开对应开关。")


func _build_enemies() -> void:
	var battle := _battle()
	_label(_content, "遭遇 %s · DDL %s · 回合 %s" % [
		battle.get("encounter_id", ""), battle.get("ddl", 0), battle.get("round_index", 0)
	], 15)
	var ddl_row := _row(_content)
	_label(ddl_row, "DDL", 14)
	_button(ddl_row, "test:editor:ddl:minus", "-1", func():
		_set_draft("ddl", {"op": "set_ddl", "ddl": maxi(0, int(battle.get("ddl", 0)) - 1)})
	)
	_button(ddl_row, "test:editor:ddl:plus", "+1", func():
		_set_draft("ddl", {"op": "set_ddl", "ddl": mini(99, int(battle.get("ddl", 0)) + 1)})
	)
	for task in battle.get("tasks", []):
		var row := _row(_content)
		var task_id := str(task.get("task_id", ""))
		_label(row, "%s · %s/%s · 屏障 %s" % [
			UiStyle.label(str(task.get("definition_id", ""))),
			task.get("work_remaining", 0),
			task.get("work_max", 0),
			task.get("shield", 0),
		], 14)
		_button(row, "test:editor:task:%s:work_minus" % task_id, "-1", func():
			_set_draft("task.%s.work" % task_id, {"op": "set_task_field", "task_id": task_id, "field": "work_remaining", "value": maxi(0, int(task.get("work_remaining", 0)) - 1)})
		)
		_button(row, "test:editor:task:%s:work_plus" % task_id, "+1", func():
			_set_draft("task.%s.work" % task_id, {"op": "set_task_field", "task_id": task_id, "field": "work_remaining", "value": mini(int(task.get("work_max", 1)), int(task.get("work_remaining", 0)) + 1)})
		)
		_button(row, "test:editor:task:%s:rm" % task_id, "移除", func():
			_set_draft("task.%s.rm" % task_id, {"op": "remove_task", "task_id": task_id})
		)
	_search_task_list(_content, "加入任务")
	_search_encounter_list(_content, "替换遭遇")


func _build_allies() -> void:
	_label(_content, "伙伴/单位", 17)
	for unit in _battle().get("units", []):
		var row := _row(_content)
		var unit_id := str(unit.get("unit_id", ""))
		_label(row, "%s · 精力 %s · 协同 %s" % [
			UiStyle.label(str(unit.get("definition_id", ""))),
			unit.get("vitality", 0),
			unit.get("cooperation", 0),
		], 14)
		_button(row, "test:editor:unit:%s:minus" % unit_id, "-1", func():
			_set_draft("unit.%s.vitality" % unit_id, {"op": "set_unit_field", "unit_id": unit_id, "field": "vitality", "value": maxi(0, int(unit.get("vitality", 0)) - 1)})
		)
		_button(row, "test:editor:unit:%s:plus" % unit_id, "+1", func():
			_set_draft("unit.%s.vitality" % unit_id, {"op": "set_unit_field", "unit_id": unit_id, "field": "vitality", "value": int(unit.get("vitality", 0)) + 1})
		)
		_button(row, "test:editor:unit:%s:rm" % unit_id, "移除", func():
			_set_draft("unit.%s.rm" % unit_id, {"op": "remove_unit", "unit_id": unit_id})
		)
	_search_unit_list(_content, "加入伙伴")
	_label(_content, "饰品", 17)
	for relic_id in _battle().get("relics", []):
		var row := _row(_content)
		_label(row, UiStyle.label(str(relic_id)), 14)
		_button(row, "test:editor:relic:%s:rm" % str(relic_id), "移除", func():
			_set_draft("relic.%s.rm" % str(relic_id), {"op": "remove_relic", "relic_id": str(relic_id)})
		)
	_search_relic_list(_content, "加入饰品")
	var scene: Variant = _battle().get("scene")
	if typeof(scene) == TYPE_DICTIONARY:
		var row := _row(_content)
		_label(row, "场景 %s" % UiStyle.label(str(scene.get("definition_id", ""))), 14)
		_button(row, "test:editor:scene:clear", "清除", func():
			_set_draft("scene.clear", {"op": "clear_scene"})
		)


func _build_statuses() -> void:
	_label(_content, "目标", 15)
	var target_row := _row(_content)
	var selector := OptionButton.new()
	var target_ids: Array[String] = []
	selector.add_item("主角", 0)
	target_ids.append(str(_player().get("entity_id", "")))
	for task in _battle().get("tasks", []):
		selector.add_item("任务 " + UiStyle.label(str(task.get("definition_id", ""))), selector.item_count)
		target_ids.append(str(task.get("task_id", "")))
	for unit in _battle().get("units", []):
		selector.add_item("伙伴 " + UiStyle.label(str(unit.get("definition_id", ""))), selector.item_count)
		target_ids.append(str(unit.get("unit_id", "")))
	var current_index := target_ids.find(_status_target)
	selector.selected = maxi(0, current_index)
	selector.item_selected.connect(func(index: int):
		_status_target = target_ids[index]
		_render_all()
	)
	target_row.add_child(selector)
	_label(_content, "给该目标添加状态", 15)
	_search_status_list(_content)
	_label(_content, "当前状态", 17)
	for status in _battle().get("statuses", []):
		var row := _row(_content)
		var instance_id := str(status.get("instance_id", ""))
		_label(row, "%s → %s · %s" % [
			UiStyle.label(str(status.get("status_id", ""))),
			UiStyle.label(str(status.get("target_id", ""))),
			status.get("stacks", 0),
		], 14)
		_button(row, "test:editor:status:%s:minus" % instance_id, "-1", func():
			_set_draft("status.%s.stacks" % instance_id, {"op": "set_status_field", "instance_id": instance_id, "field": "stacks", "value": maxi(1, int(status.get("stacks", 1)) - 1)})
		)
		_button(row, "test:editor:status:%s:plus" % instance_id, "+1", func():
			_set_draft("status.%s.stacks" % instance_id, {"op": "set_status_field", "instance_id": instance_id, "field": "stacks", "value": int(status.get("stacks", 1)) + 1})
		)
		_button(row, "test:editor:status:%s:rm" % instance_id, "移除", func():
			_set_draft("status.%s.rm" % instance_id, {"op": "remove_status", "instance_id": instance_id})
		)


func _build_time() -> void:
	var battle := _battle()
	_label(_content, "回合 %s · DDL %s · 阶段 %s" % [
		battle.get("round_index", 0), battle.get("ddl", 0), battle.get("phase", "")
	], 15)
	var round_row := _row(_content)
	_label(round_row, "回合", 14)
	_button(round_row, "test:editor:round:minus", "-1", func():
		_set_draft("round", {"op": "set_round", "round_index": maxi(1, int(battle.get("round_index", 1)) - 1)})
	)
	_button(round_row, "test:editor:round:plus", "+1", func():
		_set_draft("round", {"op": "set_round", "round_index": int(battle.get("round_index", 1)) + 1})
	)
	var ddl_row := _row(_content)
	_label(ddl_row, "DDL", 14)
	_button(ddl_row, "test:editor:time:ddl_minus", "-1", func():
		_set_draft("time.ddl", {"op": "set_ddl", "ddl": maxi(0, int(battle.get("ddl", 0)) - 1)})
	)
	_button(ddl_row, "test:editor:time:ddl_plus", "+1", func():
		_set_draft("time.ddl", {"op": "set_ddl", "ddl": mini(99, int(battle.get("ddl", 0)) + 1)})
	)
	_button(_content, "test:editor:time:end_turn", "结束回合（真实规则）", func():
		command.emit("test.end_turn", {})
	)
	var seed_row := _row(_content)
	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "新 seed"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_input)
	_button(seed_row, "test:editor:time:seed_all", "重置四流", func():
		var value := seed_input.text.strip_edges()
		if not value.is_empty():
			_set_draft("time.seed", {"op": "reset_rng", "mode": "all", "seed": value})
	)
	_label(_content, "计次", 17)
	for key in battle.get("counters", {}):
		var row := _row(_content)
		_label(row, "%s = %s" % [key, battle.counters[key]], 14)
		_button(row, "test:editor:counter:%s:rm" % str(key), "删除", func():
			_set_draft("counter.%s" % str(key), {"op": "remove_counter", "key": str(key)})
		)


func _build_rules() -> void:
	_label(_content, "规则开关（草稿）", 17)
	for entry in _options.get("switches", []):
		var key := str(entry.get("key", ""))
		var check := CheckBox.new()
		check.text = str(entry.get("description", key))
		check.button_pressed = bool(_view.get("switches", {}).get(key, false))
		check.add_theme_font_size_override("font_size", 14)
		check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		check.toggled.connect(func(value: bool):
			_set_draft("switch." + key, {"op": "set_switch", "key": key, "value": value})
		)
		_buttons["test:editor:switch:" + key] = check
		_content.add_child(check)
	_label(_content, "规则数值", 17)
	var ruleset: Dictionary = _options.get("ruleset", {})
	_ruleset_row("手牌上限", "battle.hand_limit", int(_nested(ruleset, "battle.hand_limit", 10)), 0, 99)
	_ruleset_row("专注上限", "battle.focus_cap", int(_nested(ruleset, "battle.focus_cap", 10)), 0, 99)
	_ruleset_row("单位槽位", "battle.unit_slots", int(_nested(ruleset, "battle.unit_slots", 3)), 0, 32)
	_ruleset_row("饰品槽位", "run.relic_slots", int(_nested(ruleset, "run.relic_slots", 3)), 0, 64)
	_label(_content, "定义覆盖", 17)
	_search_override_cards(_content)


func _build_history() -> void:
	_label(_content, "检查点", 17)
	for checkpoint in _view.get("checkpoints", []):
		var row := _row(_content)
		_label(row, "%s · rev %s · 回合 %s" % [
			checkpoint.get("label", ""), checkpoint.get("revision", 0), checkpoint.get("round_index", 0)
		], 14)
		var checkpoint_id := str(checkpoint.get("id", ""))
		_button(row, "test:editor:checkpoint:" + checkpoint_id, "恢复", func():
			command.emit("test.restore_checkpoint", {"checkpoint_id": checkpoint_id})
		)
	var actions := _row(_content)
	_button(actions, "test:editor:undo", "撤销", func(): command.emit("test.undo", {}))
	_button(actions, "test:editor:redo", "重做", func(): command.emit("test.redo", {}))
	var save_row := _row(_content)
	_button(save_row, "test:editor:save_snapshot", "保存快照", func(): command.emit("test.save_snapshot", {}))
	_button(save_row, "test:editor:save_preset", "保存预设", func(): command.emit("test.save_preset", {}))
	_button(save_row, "test:editor:save_record", "保存记录", func(): command.emit("test.save_record", {}))
	_label(_content, "日志 %s 条 · 分支 %s" % [
		_view.get("journal_size", 0), _test().get("branch_id", 0)
	], 14, UiStyle.MUTED)


func _build_footer(parent: VBoxContainer) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	_draft_label = Label.new()
	_draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draft_label.add_theme_font_size_override("font_size", 14)
	line.add_child(_draft_label)
	var preview := _button(line, "test:editor:preview", "预览", func(): _preview_draft())
	preview.custom_minimum_size = Vector2(64, 34)
	var apply := _button(line, "test:editor:apply", "应用", func(): _begin_apply())
	apply.custom_minimum_size = Vector2(64, 34)
	var discard := _button(line, "test:editor:discard", "丢弃草稿", func():
		_draft.clear()
		_status_text = "已丢弃草稿"
		_render_all()
	)
	discard.custom_minimum_size = Vector2(88, 34)
	if _show_policy:
		var policy_row := HBoxContainer.new()
		parent.add_child(policy_row)
		_label(policy_row, "待选：", 14)
		_button(policy_row, "test:editor:apply:rollback", "回到命令前并应用", func(): _send_apply("rollback"))
		_button(policy_row, "test:editor:apply:truncate", "保留并截断", func(): _send_apply("truncate"))
		_button(policy_row, "test:editor:apply:cancel", "取消", func():
			_show_policy = false
			_render_all()
		)
	var status := Label.new()
	status.text = _status_text
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override(
		"font_color", UiStyle.RED if _status_text.begins_with("错误") else UiStyle.MUTED
	)
	parent.add_child(status)
	_draft_label.text = "待应用 %d 项 · 基于 rev %s" % [
		_draft.size(), _test().get("revision", 0)
	]


func _begin_apply() -> void:
	if _draft.is_empty():
		_status_text = "没有待应用修改"
		_render_all()
		return
	if _view.get("pending_choice") is Dictionary and not _show_policy:
		_show_policy = true
		_render_all()
		return
	_send_apply("rollback")


func _send_apply(policy: String) -> void:
	_show_policy = false
	_applying = true
	_status_text = "应用中…"
	var ops: Array = []
	for key in _draft:
		ops.append((_draft[key] as Dictionary).duplicate(true))
	command.emit("test.patch", {"ops": ops, "policy": policy})
	_render_all()


func _preview_draft() -> void:
	if _draft.is_empty():
		_status_text = "没有待应用修改"
		_render_all()
		return
	var ops: Array = []
	for key in _draft:
		ops.append((_draft[key] as Dictionary).duplicate(true))
	var result := session.preview_test_patch(_context(), {"schema_version": 1, "ops": ops})
	if not result.ok:
		_status_text = "错误：" + result.error.message_key
		_render_all()
		return
	var preview: ActionPreview = result.data
	if not preview.blocking_errors.is_empty():
		_status_text = "错误：" + preview.blocking_errors[0].message_key
	else:
		_status_text = "%d 项可应用 · 级联 %d 项" % [ops.size(), preview.known_effects.size()]
	_render_all()


func _set_draft(key: String, op: Dictionary) -> void:
	_draft[key] = op
	_draft_revision = int(_test().get("revision", 0))
	_status_text = "已加入草稿"
	_render_all()


func _draft_value(key: String, actual: Variant) -> Variant:
	if _draft.has(key):
		var op: Dictionary = _draft[key]
		match str(op.get("op", "")):
			"set_player_field", "set_task_field", "set_unit_field", "set_status_field", "set_v3_field", "set_ddl", "set_round", "set_rule_field", "set_counter":
				return op.get("value", actual)
			"adjust_player_field":
				return int(actual) + int(op.get("delta", 0))
	return actual


func _player_row(caption: String, key: String, actual: int, step: int, minimum: int, maximum: int, field: String) -> void:
	var row := _row(_content)
	_row_label(row, "%s %s" % [caption, _draft_value(key, actual)])
	_button(row, "test:editor:field:%s:minus" % key, "-%d" % step, func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_player_field", "field": field, "value": maxi(minimum, value - step)})
	)
	_button(row, "test:editor:field:%s:plus" % key, "+%d" % step, func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_player_field", "field": field, "value": mini(maximum, value + step)})
	)
	var input := LineEdit.new()
	input.text = str(_draft_value(key, actual))
	input.custom_minimum_size = Vector2(56, 30)
	row.add_child(input)
	_button(row, "test:editor:field:%s:set" % key, "设为", func():
		if input.text.strip_edges().is_valid_int():
			var value := int(input.text.strip_edges())
			_set_draft(key, {"op": "set_player_field", "field": field, "value": clampi(value, minimum, maximum)})
	)


func _v3_row(caption: String, path: String, actual: int, minimum: int, maximum: int) -> void:
	var key := "v3." + path
	var row := _row(_content)
	_row_label(row, "%s %s" % [caption, _draft_value(key, actual)])
	_button(row, "test:editor:field:%s:minus" % key, "-1", func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_v3_field", "path": path, "value": maxi(minimum, value - 1)})
	)
	_button(row, "test:editor:field:%s:plus" % key, "+1", func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_v3_field", "path": path, "value": mini(maximum, value + 1)})
	)


func _ruleset_row(caption: String, path: String, actual: int, minimum: int, maximum: int) -> void:
	var key := "rule." + path
	var row := _row(_content)
	_row_label(row, "%s %s" % [caption, _draft_value(key, actual)])
	_button(row, "test:editor:field:%s:minus" % key, "-1", func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_rule_field", "path": path, "value": maxi(minimum, value - 1)})
	)
	_button(row, "test:editor:field:%s:plus" % key, "+1", func():
		var value := int(_draft_value(key, actual))
		_set_draft(key, {"op": "set_rule_field", "path": path, "value": mini(maximum, value + 1)})
	)


func _search_card_list(parent: VBoxContainer, caption: String) -> void:
	_label(parent, caption, 15)
	var input := LineEdit.new()
	input.placeholder_text = "按名称或 ID 搜索卡牌"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	_search_input = input
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_card_results(box, "")
	input.text_changed.connect(func(text: String): _fill_card_results(box, text))


func _fill_card_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var cards: Array = _options.get("cards", [])
	var shown := 0
	for card in cards:
		if not _matches(card, query):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		_label(row, "%s · %s费 · %s" % [
			UiStyle.label(str(card.get("id", ""))),
			card.get("cost", 0),
			card.get("type", ""),
		], 13)
		var card_id := str(card.get("id", ""))
		_button(row, "test:editor:add:%s:%d" % [card_id, _seq], "加手", func(): _add_card_to(card_id, "hand"))
		_seq += 1
		_button(row, "test:editor:adddiscard:%s:%d" % [card_id, _seq], "弃牌", func(): _add_card_to(card_id, "discard"))
		_seq += 1
		shown += 1
		if shown >= 24:
			break
	if shown == 0:
		_label(box, "没有匹配卡牌", 13, UiStyle.MUTED)


func _search_task_list(parent: VBoxContainer, caption: String) -> void:
	_label(parent, caption, 15)
	var input := LineEdit.new()
	input.placeholder_text = "搜索任务定义"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_task_results(box, "")
	input.text_changed.connect(func(text: String): _fill_task_results(box, text))


func _fill_task_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for task in _options.get("tasks", []):
		if not _matches(task, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s · %s" % [UiStyle.label(str(task.get("id", ""))), task.get("work_max", 0)], 13)
		var definition_id := str(task.get("id", ""))
		_button(row, "test:editor:addtask:%s:%d" % [definition_id, _seq], "加入", func():
			_set_draft("addtask.%d" % _seq, {"op": "add_task", "definition_id": definition_id})
		)
		_seq += 1
		shown += 1
		if shown >= 16:
			break


func _search_encounter_list(parent: VBoxContainer, caption: String) -> void:
	_label(parent, caption, 15)
	var input := LineEdit.new()
	input.placeholder_text = "搜索遭遇"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_encounter_results(box, "")
	input.text_changed.connect(func(text: String): _fill_encounter_results(box, text))


func _fill_encounter_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for encounter in _options.get("encounters", []):
		if not _matches(encounter, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s · DDL %s" % [
			UiStyle.label(str(encounter.get("id", ""))), encounter.get("base_ddl", 0)
		], 13)
		var encounter_id := str(encounter.get("id", ""))
		_button(row, "test:editor:encounter:%s:%d" % [encounter_id, _seq], "替换", func():
			_set_draft("encounter", {"op": "replace_encounter", "encounter_id": encounter_id})
		)
		_seq += 1
		shown += 1
		if shown >= 12:
			break


func _search_unit_list(parent: VBoxContainer, caption: String) -> void:
	_label(parent, caption, 15)
	var input := LineEdit.new()
	input.placeholder_text = "搜索伙伴/单位"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_unit_results(box, "")
	input.text_changed.connect(func(text: String): _fill_unit_results(box, text))


func _fill_unit_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for unit in _options.get("units", []):
		if not _matches(unit, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s · 精力 %s" % [UiStyle.label(str(unit.get("id", ""))), unit.get("vitality", 0)], 13)
		var definition_id := str(unit.get("id", ""))
		_button(row, "test:editor:addunit:%s:%d" % [definition_id, _seq], "加入", func():
			_set_draft("addunit.%d" % _seq, {"op": "add_unit", "definition_id": definition_id})
		)
		_seq += 1
		shown += 1
		if shown >= 12:
			break


func _search_relic_list(parent: VBoxContainer, caption: String) -> void:
	_label(parent, caption, 15)
	var input := LineEdit.new()
	input.placeholder_text = "搜索饰品"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_relic_results(box, "")
	input.text_changed.connect(func(text: String): _fill_relic_results(box, text))


func _fill_relic_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for relic in _options.get("relics", []):
		if not _matches(relic, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s · %s" % [UiStyle.label(str(relic.get("id", ""))), relic.get("rarity", "")], 13)
		var relic_id := str(relic.get("id", ""))
		_button(row, "test:editor:addrelic:%s:%d" % [relic_id, _seq], "加入", func():
			_set_draft("addrelic.%d" % _seq, {"op": "add_relic", "relic_id": relic_id})
		)
		_seq += 1
		shown += 1
		if shown >= 16:
			break


func _search_status_list(parent: VBoxContainer) -> void:
	var input := LineEdit.new()
	input.placeholder_text = "搜索状态并添加 1 层"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	_search_input = input
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_status_results(box, "")
	input.text_changed.connect(func(text: String): _fill_status_results(box, text))


func _fill_status_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for status in _options.get("statuses", []):
		if not _matches(status, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s" % UiStyle.label(str(status.get("id", ""))), 13)
		var status_id := str(status.get("id", ""))
		_button(row, "test:editor:addstatus:%s:%d" % [status_id, _seq], "添加", func():
			_set_draft(
				"addstatus.%d" % _seq,
				{
					"op": "add_status",
					"status_id": status_id,
					"target_id": _status_target,
					"stacks": 1,
				}
			)
		)
		_seq += 1
		shown += 1
		if shown >= 16:
			break


func _search_override_cards(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var input := LineEdit.new()
	input.placeholder_text = "搜索卡牌并选择覆盖对象"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_override_results(box, "")
	input.text_changed.connect(func(text: String): _fill_override_results(box, text))
	if not _override_card.is_empty():
		var field_row := HBoxContainer.new()
		parent.add_child(field_row)
		_label(field_row, "对 %s 覆盖" % UiStyle.label(_override_card), 14)
		var selector := OptionButton.new()
		for field in ["cost", "type", "target"]:
			selector.add_item(field, selector.item_count)
			if field == _override_field:
				selector.selected = selector.item_count - 1
		selector.item_selected.connect(func(index: int):
			_override_field = selector.get_item_text(index)
			_render_all()
		)
		field_row.add_child(selector)
		var value_input := LineEdit.new()
		value_input.custom_minimum_size = Vector2(90, 30)
		field_row.add_child(value_input)
		_button(field_row, "test:editor:override:add", "加入草稿", func():
			var raw := value_input.text.strip_edges()
			var value: Variant = int(raw) if raw.is_valid_int() else raw
			_set_draft(
				"override.%s.%s" % [_override_card, _override_field],
				{
					"op": "set_definition_field",
					"kind": "card",
					"id": _override_card,
					"path": _override_field,
					"value": value,
				}
			)
		)


func _fill_override_results(box: VBoxContainer, query: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shown := 0
	for card in _options.get("cards", []):
		if not _matches(card, query):
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, "%s · %s费" % [UiStyle.label(str(card.get("id", ""))), card.get("cost", 0)], 13)
		var card_id := str(card.get("id", ""))
		_button(row, "test:editor:override:%s" % card_id, "选择", func():
			_override_card = card_id
			_render_all()
		)
		shown += 1
		if shown >= 10:
			break


func _add_card_to(card_id: String, zone: String) -> void:
	_set_draft(
		"addcard.%s.%s.%d" % [card_id, zone, _seq],
		{"op": "add_card", "definition_id": card_id, "zone": zone, "count": 1}
	)
	_seq += 1


func _zone_cards(zone: String) -> Array:
	var result: Array = []
	var battle := _battle()
	if zone == "hand":
		for card in battle.get("hand", []):
			result.append(card)
		return result
	if zone == "draw":
		var by_id := {}
		for card in battle.get("zones_public", {}).get("draw", []):
			by_id[str(card.get("card_id", ""))] = card
		for card_id in battle.get("draw_order", []):
			if by_id.has(str(card_id)):
				result.append(by_id[str(card_id)])
		return result
	for card in battle.get("zones_public", {}).get(zone, []):
		result.append(card)
	return result


func _zone_name(zone: String) -> String:
	return str({"hand": "手牌", "draw": "抽牌堆", "discard": "弃牌堆", "exhaust": "消耗堆"}.get(zone, zone))


func _holder_exists(target_id: String) -> bool:
	if target_id.is_empty():
		return false
	if target_id == str(_player().get("entity_id", "")):
		return true
	for task in _battle().get("tasks", []):
		if str(task.get("task_id", "")) == target_id:
			return true
	for unit in _battle().get("units", []):
		if str(unit.get("unit_id", "")) == target_id:
			return true
	return false


func _matches(entry: Dictionary, query: String) -> bool:
	if query.strip_edges().is_empty():
		return true
	var needle := query.strip_edges().to_lower()
	var haystack := "%s %s %s" % [
		entry.get("id", ""), entry.get("name_key", ""), UiStyle.label(str(entry.get("id", "")))
	]
	return haystack.to_lower().contains(needle)


func _nested(source: Dictionary, path: String, fallback: Variant) -> Variant:
	var current: Variant = source
	for segment in path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY or not current.has(segment):
			return fallback
		current = current[segment]
	return current


func _button(parent: Node, uid: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 32)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons[uid] = button
	return button


func _label(parent: Node, text: String, size: int = 14, color: Color = UiStyle.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	return row


func _row_label(parent: Node, text: String, size: int = 14) -> Label:
	var label := _label(parent, text, size)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x = 110
	return label


func _hint(text: String) -> void:
	_label(_content, text, 13, UiStyle.MUTED)


func _battle() -> Dictionary:
	return _view.get("battle", {})


func _player() -> Dictionary:
	return _battle().get("player", {})


func _config() -> Dictionary:
	return _view.get("config", {})


func _test() -> Dictionary:
	return _view.get("test", {})


func _context() -> Dictionary:
	var test_state := _test()
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	if key.keycode == KEY_ESCAPE:
		close_requested.emit()
		accept_event()
	elif key.keycode == KEY_SLASH and not typing:
		if is_instance_valid(_search_input):
			_search_input.grab_focus()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_Z and not typing:
		command.emit("test.redo" if key.shift_pressed else "test.undo", {})
		accept_event()

