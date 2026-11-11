class_name TestHud
extends Control

## Lightweight in-battle test HUD: identity bar plus a drawer editor that sends
## typed test commands to GameShell. It never writes domain state directly.

signal test_command(command_type: String, payload: Dictionary)

const BAR_HEIGHT := 46.0
const DRAWER_WIDTH := 420.0

var session: GameSession
var _view: Dictionary = {}
var _bar: PanelContainer
var _identity: Label
var _state_label: Label
var _drawer: PanelContainer
var _drawer_body: VBoxContainer
var _open := false
var _tab := "resources"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()
	_build_drawer()


func setup(p_session: GameSession) -> void:
	session = p_session


func render(view: Dictionary) -> void:
	_view = view
	var test_state: Dictionary = view.get("test", {})
	var result: Dictionary = view.get("result", {})
	var overlay: Dictionary = view.get("overlay", {})
	if _identity != null:
		_identity.text = "测试房间 · %s · 分支 %s · rev %s · 干预 %s · 覆盖 %s" % [
			_short_id(str(test_state.get("test_id", ""))),
			test_state.get("branch_id", 0),
			test_state.get("revision", 0),
			test_state.get("interventions", 0),
			overlay.get("definition_count", 0),
		]
	if _state_label != null:
		var marker := "运行中"
		if bool(test_state.get("editing", false)):
			marker = "编辑中"
		elif bool(test_state.get("paused", false)):
			marker = "已暂停"
		elif view.get("pending_choice") is Dictionary:
			marker = "待选"
		if not str(result.get("outcome", "")).is_empty():
			marker = "实验结束"
		_state_label.text = marker
	_drawer.visible = _open
	_refresh_drawer()


func _short_id(test_id: String) -> String:
	if test_id.length() <= 18:
		return test_id
	return test_id.substr(test_id.length() - 18)


func _build_bar() -> void:
	if _bar != null:
		return
	_bar = PanelContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_top = 4
	_bar.offset_bottom = BAR_HEIGHT
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)
	_identity = Label.new()
	_identity.text = "测试房间"
	_identity.add_theme_font_size_override("font_size", 14)
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_identity)
	_state_label = Label.new()
	_state_label.text = "运行中"
	_state_label.add_theme_font_size_override("font_size", 14)
	_state_label.add_theme_color_override("font_color", UiStyle.GOLD)
	row.add_child(_state_label)
	_button(row, "暂停", func(): test_command.emit("test.pause", {}))
	_button(row, "编辑器", func(): _toggle_drawer())
	_button(row, "撤销", func(): test_command.emit("test.undo", {}))
	_button(row, "重做", func(): test_command.emit("test.redo", {}))
	_button(row, "保存", func(): test_command.emit("test.save_snapshot", {}))
	_button(row, "退出", func(): test_command.emit("test.close", {}))


func _build_drawer() -> void:
	if _drawer != null:
		return
	_drawer = PanelContainer.new()
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_left = -DRAWER_WIDTH
	_drawer.offset_top = BAR_HEIGHT + 8
	_drawer.offset_bottom = -8
	_drawer.visible = false
	add_child(_drawer)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_drawer.add_child(margin)
	_drawer_body = VBoxContainer.new()
	_drawer_body.add_theme_constant_override("separation", 8)
	margin.add_child(_drawer_body)


func _toggle_drawer() -> void:
	_open = not _open
	if _open:
		test_command.emit("test.begin_edit", {})
	else:
		test_command.emit("test.cancel_edit", {})
	_drawer.visible = _open


func _refresh_drawer() -> void:
	if _drawer_body == null:
		return
	for child in _drawer_body.get_children():
		_drawer_body.remove_child(child)
		child.queue_free()
	if not _open:
		return
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 4)
	_drawer_body.add_child(tabs_row)
	for entry in [
		["resources", "资源"],
		["cards", "牌区"],
		["enemies", "敌人"],
		["statuses", "状态"],
		["time", "时间"],
		["rules", "规则"],
		["history", "历史"],
	]:
		var tab_id: String = entry[0]
		var button := _button(tabs_row, entry[1], func(): _tab = tab_id; _refresh_drawer())
		button.custom_minimum_size = Vector2(52, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	match _tab:
		"resources":
			_build_resources(content)
		"cards":
			_build_cards(content)
		"enemies":
			_build_enemies(content)
		"statuses":
			_build_statuses(content)
		"time":
			_build_time(content)
		"rules":
			_build_rules(content)
		"history":
			_build_history(content)
	_button(_drawer_body, "关闭编辑器", func(): _toggle_drawer())


func _build_resources(parent: VBoxContainer) -> void:
	var battle: Dictionary = _view.get("battle", {})
	var player: Dictionary = battle.get("player", {})
	_label(parent, "精力 %s / %s · 专注 %s · 放松 %s" % [
		player.get("vitality", 0),
		player.get("max_vitality", 0),
		player.get("focus", 0),
		player.get("relax", 0),
	])
	_number_row(parent, "精力", "vitality", int(player.get("vitality", 0)), 1, 50)
	_number_row(parent, "精力上限", "max_vitality", int(player.get("max_vitality", 0)), 1, 9999)
	_number_row(parent, "专注", "focus", int(player.get("focus", 0)), 1, 50)
	_number_row(parent, "放松", "relax", int(player.get("relax", 0)), 1, 50)
	_label(parent, "角色专属：论文/协同等通过“牌区/状态/时间”页与执行操作调整。", 13, UiStyle.MUTED)


func _number_row(
	parent: VBoxContainer, caption: String, field: String, value: int, step: int, maximum: int
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	_label(row, "%s %d" % [caption, value])
	_button(row, "-%d" % step, func(): _patch([{"op": "adjust_player_field", "field": field, "delta": -step}]))
	_button(row, "+%d" % step, func(): _patch([{"op": "adjust_player_field", "field": field, "delta": step}]))
	if field != "vitality":
		_button(row, "满", func(): _patch([{"op": "set_player_field", "field": field, "value": maximum}]))


func _build_cards(parent: VBoxContainer) -> void:
	var battle: Dictionary = _view.get("battle", {})
	var hand: Array = battle.get("hand", [])
	_label(parent, "手牌 %d 张" % hand.size())
	for card in hand:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		_label(row, "%s%s" % [
			UiStyle.label(str(card.get("definition_id", ""))),
			" +%s" % card.get("upgrade_level", 0) if int(card.get("upgrade_level", 0)) > 0 else "",
		])
		var card_id := str(card.get("card_id", ""))
		_button(row, "移除", func(): _patch([{"op": "remove_instance", "instance_id": card_id}]))
		_button(row, "复制", func(): _patch([{"op": "duplicate_instance", "instance_id": card_id, "zone": "hand", "count": 1}]))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	parent.add_child(add_row)
	_label(add_row, "加入卡牌")
	var input := LineEdit.new()
	input.placeholder_text = "定义 ID，如 R3-P01-01"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(input)
	_button(add_row, "手牌", func():
		if not input.text.strip_edges().is_empty():
			_patch([{"op": "add_card", "definition_id": input.text.strip_edges(), "zone": "hand", "count": 1}])
	)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	parent.add_child(actions)
	_button(actions, "洗抽牌堆", func(): _patch([{"op": "shuffle_zone", "zone": "draw"}]))
	_button(actions, "清弃牌堆", func(): _patch([{"op": "clear_zone", "zone": "discard"}]))
	_button(actions, "抽牌堆 → 手牌", func(): _draw_one())


func _draw_one() -> void:
	var battle: Dictionary = _view.get("battle", {})
	var order: Array = battle.get("draw_order", [])
	if order.is_empty():
		return
	_patch([{"op": "move_instance", "instance_id": str(order[0]), "zone": "hand", "position": 0}])


func _build_enemies(parent: VBoxContainer) -> void:
	var battle: Dictionary = _view.get("battle", {})
	var tasks: Array = battle.get("tasks", [])
	_label(parent, "敌方任务 %d 个 · DDL %s · 回合 %s" % [
		tasks.size(), battle.get("ddl", 0), battle.get("round_index", 0)
	])
	for task in tasks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		_label(row, "%s · %s/%s · 屏障 %s" % [
			UiStyle.label(str(task.get("definition_id", ""))),
			task.get("work_remaining", 0),
			task.get("work_max", 0),
			task.get("shield", 0),
		])
		var task_id := str(task.get("task_id", ""))
		var work := int(task.get("work_remaining", 0))
		_button(row, "-1", func(): _patch([{"op": "set_task_field", "task_id": task_id, "field": "work_remaining", "value": maxi(0, work - 1)}]))
		_button(row, "+1", func(): _patch([{"op": "set_task_field", "task_id": task_id, "field": "work_remaining", "value": mini(int(task.get("work_max", 1)), work + 1)}]))
		_button(row, "移除", func(): _patch([{"op": "remove_task", "task_id": task_id}]))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	parent.add_child(add_row)
	var input := LineEdit.new()
	input.placeholder_text = "任务定义 ID，如 N01"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(input)
	_button(add_row, "加任务", func():
		if not input.text.strip_edges().is_empty():
			_patch([{"op": "add_task", "definition_id": input.text.strip_edges()}])
	)
	var encounter_row := HBoxContainer.new()
	encounter_row.add_theme_constant_override("separation", 4)
	parent.add_child(encounter_row)
	var encounter_input := LineEdit.new()
	encounter_input.placeholder_text = "替换遭遇 ID，如 N13"
	encounter_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encounter_row.add_child(encounter_input)
	_button(encounter_row, "替换遭遇", func():
		if not encounter_input.text.strip_edges().is_empty():
			_patch([{"op": "replace_encounter", "encounter_id": encounter_input.text.strip_edges()}])
	)


func _build_statuses(parent: VBoxContainer) -> void:
	var battle: Dictionary = _view.get("battle", {})
	var player: Dictionary = battle.get("player", {})
	var player_id := str(player.get("entity_id", ""))
	var statuses: Array = battle.get("statuses", [])
	_label(parent, "状态 %d 条" % statuses.size())
	for status in statuses:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		_label(row, "%s → %s · %s" % [
			UiStyle.label(str(status.get("status_id", ""))),
			UiStyle.label(str(status.get("target_id", ""))),
			status.get("stacks", 0),
		])
		var instance_id := str(status.get("instance_id", ""))
		_button(row, "移除", func(): _patch([{"op": "remove_status", "instance_id": instance_id}]))
		_button(row, "+1", func(): _patch([{"op": "set_status_field", "instance_id": instance_id, "field": "stacks", "value": int(status.get("stacks", 0)) + 1}]))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	parent.add_child(add_row)
	_label(add_row, "给主角加")
	for status_id in ["inspiration", "anxiety", "work_boost"]:
		_button(add_row, UiStyle.label(status_id), func(): _patch([{"op": "add_status", "status_id": status_id, "target_id": player_id, "stacks": 1}]))
	_button(parent, "清除主角状态", func(): _patch([{"op": "clear_statuses", "target_id": player_id}]))


func _build_time(parent: VBoxContainer) -> void:
	var battle: Dictionary = _view.get("battle", {})
	var round_index := int(battle.get("round_index", 1))
	var ddl := int(battle.get("ddl", 0))
	_label(parent, "回合 %d · DDL %d" % [round_index, ddl])
	var round_row := HBoxContainer.new()
	parent.add_child(round_row)
	_button(round_row, "回合 -1", func():
		if round_index > 1:
			_patch([{"op": "set_round", "round_index": round_index - 1}])
	)
	_button(round_row, "回合 +1", func(): _patch([{"op": "set_round", "round_index": round_index + 1}]))
	var ddl_row := HBoxContainer.new()
	parent.add_child(ddl_row)
	_button(ddl_row, "DDL -1", func():
		if ddl > 0:
			_patch([{"op": "set_ddl", "ddl": ddl - 1}])
	)
	_button(ddl_row, "DDL +1", func(): _patch([{"op": "set_ddl", "ddl": ddl + 1}]))
	_button(parent, "结束回合（真实规则）", func(): test_command.emit("test.end_turn", {}))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 4)
	parent.add_child(seed_row)
	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "新 seed"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_input)
	_button(seed_row, "重置四流", func():
		var value := seed_input.text.strip_edges()
		if not value.is_empty():
			_patch([{"op": "reset_rng", "mode": "all", "seed": value}])
	)


func _build_rules(parent: VBoxContainer) -> void:
	var switches: Dictionary = _view.get("switches", {})
	_label(parent, "规则开关（勾选即应用）")
	for key in switches:
		var check := CheckBox.new()
		check.text = str(key)
		check.button_pressed = bool(switches[key])
		check.add_theme_font_size_override("font_size", 14)
		var switch_key := str(key)
		check.toggled.connect(func(value: bool): _patch([{"op": "set_switch", "key": switch_key, "value": value}]))
		parent.add_child(check)


func _build_history(parent: VBoxContainer) -> void:
	var checkpoints: Array = _view.get("checkpoints", [])
	_label(parent, "检查点 %d 个" % checkpoints.size())
	for checkpoint in checkpoints:
		var row := HBoxContainer.new()
		parent.add_child(row)
		_label(row, "%s · rev %s" % [checkpoint.get("label", ""), checkpoint.get("revision", 0)])
		var checkpoint_id := str(checkpoint.get("id", ""))
		_button(row, "恢复", func(): test_command.emit("test.restore_checkpoint", {"checkpoint_id": checkpoint_id}))
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	_button(actions, "撤销", func(): test_command.emit("test.undo", {}))
	_button(actions, "重做", func(): test_command.emit("test.redo", {}))
	_button(parent, "保存快照", func(): test_command.emit("test.save_snapshot", {}))
	_button(parent, "保存预设", func(): test_command.emit("test.save_preset", {}))


func _label(parent: Node, text: String, size: int = 15, color: Color = UiStyle.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _patch(ops: Array) -> void:
	test_command.emit("test.patch", {"ops": ops})
