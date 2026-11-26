class_name TestRoomPage
extends UiPage

## Test room home and result page. Configuration is local UI state; starting and
## loading are submitted as test commands handled by GameShell/GameSession.

const MapPicker = preload("res://src/ui/test_map_picker.gd")

var screen: String = "test_room_home"
var map_picker: Control
var _character_id := "P01"
var _seed := "42"
var _prepared := false
var node_options: Callable
var _node_key := ""
var _year := 1
var _starting_relics: Array[String] = []
var _snapshot_to_delete: Dictionary = {}
var _snapshot_list_scroll := Vector2i.ZERO
var _start_nodes: Array = []
var _start_location: Label
var _section := "setup"
var _advanced_open := false
var _advanced_fields: VBoxContainer
var _character_art: TextureRect


func add_button(parent: Node, uid: String, caption: String, draft: Variant = {}, local_callback: Callable = Callable()) -> Button:
	var button := super.add_button(parent, uid, caption, draft, local_callback)
	var selected := uid == "test:character:" + _character_id or uid == "test:home:" + _section
	var primary := uid in ["test:start", "test:result:continue", "test:result:exit", "test:delete_snapshot:confirm"]
	var quiet := uid in ["test:back", "test:result:discard", "test:delete_snapshot:cancel"]
	UiStyle.button_skin(button, "selected" if selected else ("primary" if primary else ("quiet" if quiet else "secondary")), true)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	return button


func add_text(parent: Node, value: String, font_size: int = 18, color: Color = UiStyle.INK) -> Label:
	var on_paper := false
	var ancestor := parent
	while ancestor != null and ancestor != self:
		if ancestor is PanelContainer:
			var skin: StyleBox = ancestor.get_theme_stylebox("panel")
			on_paper = skin is StyleBoxFlat and skin.bg_color.get_luminance() > .5
			break
		ancestor = ancestor.get_parent()
	var text_color := color
	if not on_paper:
		if color == UiStyle.MUTED:
			text_color = Color("c4d0cf")
		elif color == UiStyle.INK:
			text_color = UiStyle.CREAM
	var label := super.add_text(parent, value, font_size, text_color)
	if font_size >= 22:
		label.add_theme_font_override("font", UiStyle.title_font())
	return label


func render(data: Dictionary) -> void:
	z_index = 1
	map_picker = null
	view = data.duplicate(true)
	if screen == "test_room_result":
		_render_result()
	elif not _snapshot_to_delete.is_empty():
		_render_snapshot_delete_confirmation()
	else:
		_render_home()
	var scene := RoomSceneView.new()
	scene.room = "setup" if screen == "test_room_home" else "summary"
	scene.z_index = -1
	add_child(scene)
	move_child(scene, 0)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func press(uid: String) -> bool:
	if is_instance_valid(map_picker) and map_picker.visible:
		return map_picker.call("press", uid)
	return super.press(uid)


func _refresh_start_nodes() -> void:
	var seed_value := _seed if not _seed.is_empty() else "42"
	_start_nodes = node_options.call(seed_value) if node_options.is_valid() else []
	if not _start_nodes.any(func(node): return str(node.key) == _node_key and int(node.year) == _year):
		_node_key = ""
	_update_start_location()


func _update_start_location() -> void:
	if not is_instance_valid(_start_location):
		return
	_start_location.text = "第 %d 学年 · 从本学年地图开始" % _year
	for node in _start_nodes:
		if str(node.key) == _node_key:
			_start_location.text = MapPicker.describe_node(node)
	_buttons["test:start:map_default"].visible = not _node_key.is_empty()
	_buttons["test:start:map_default"].disabled = _node_key.is_empty()
	_buttons["test:start"].text = "开始实验" if not _node_key.is_empty() else "进入学年地图"


func _open_start_map() -> void:
	_refresh_start_nodes()
	if not is_instance_valid(map_picker):
		map_picker = MapPicker.new()
		add_child(map_picker)
		map_picker.connect("cancelled", _close_start_map)
		map_picker.connect("node_confirmed", func(key: String):
			for node in _start_nodes:
				if str(node.key) == key:
					_node_key = key
					_year = int(node.year)
					(find_child("TestStartYear", true, false) as OptionButton).select(_year - 1)
					break
			_update_start_location()
			_close_start_map())
	for region in [header, _scroll, footer, _character_art]:
		if is_instance_valid(region):
			region.hide()
	map_picker.call("open", {"nodes": _start_nodes, "run": {"term": _year, "current_node_id": ""}}, _node_key, 0, true)


func _close_start_map() -> void:
	for region in [header, _scroll, footer, _character_art]:
		if is_instance_valid(region):
			region.show()
	_buttons["test:start:open_map"].grab_focus()


func _render_home() -> void:
	var options: Dictionary = view.get("options", {})
	if options.is_empty():
		reset_page("测试房间", "内容加载失败。")
		add_button(body, "test:back", "返回主菜单", {"type": "ui.menu"})
		return
	if not _prepared:
		var characters: Array = options.get("characters", [])
		if not characters.is_empty():
			_character_id = str(characters[0].get("id", "P01"))
		_prepared = true
	reset_page("测试房间", "", true)
	var tabs := add_row(header)
	for section in [["setup", "新建实验"], ["files", "测试档案"]]:
		var id: String = section[0]
		var tab := add_button(tabs, "test:home:" + id, section[1], {}, _switch_section.bind(id))
		tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tab.toggle_mode = true
		tab.set_pressed_no_signal(_section == id)
	add_button(tabs, "test:compendium", "图鉴", {"type": "test.compendium"}).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var actions := add_row(footer)
	var back := add_button(actions, "test:back", "返回主菜单", {"type": "ui.menu"})
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	if _section == "files":
		_render_files()
		return
	var advanced := add_button(actions, "test:start:advanced", "", {}, _toggle_advanced)
	advanced.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var right_gap := Control.new()
	right_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(right_gap)
	var start := add_button(actions, "test:start", "开始实验", func():
		return {"type": "test.start", "payload": {"locate_node_key": _node_key, "config": {
			"character_id": _character_id, "seed": _seed, "start_year": _year,
			"relics": _starting_relics.filter(func(id): return not id.is_empty()),
		}}}
	)
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	_character_art = TextureRect.new()
	_character_art.name = "TestCharacterArt"
	var art_path := CharacterArt.texture_path(_character_id)
	_character_art.texture = load(art_path) as Texture2D if not art_path.is_empty() else UiStyle.character_portrait(_character_id)
	_character_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_art.z_index = -1
	add_child(_character_art)
	_character_art.set_anchor(SIDE_LEFT, 0.51, true)
	_character_art.set_anchor(SIDE_TOP, 0.01, true)
	_character_art.set_anchor(SIDE_RIGHT, 0.99, true)
	_character_art.set_anchor(SIDE_BOTTOM, 0.86, true)
	move_child(_character_art, 0)
	var inset := _scroll.get_child(0) as MarginContainer
	inset.add_theme_constant_override("margin_left", 32)
	inset.add_theme_constant_override("margin_top", 26)
	var layout := add_row(body)
	var config_panel := _home_panel(layout)
	config_panel.get_parent().size_flags_stretch_ratio = 0.9
	var art_space := Control.new()
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(art_space)
	add_text(config_panel, UiStyle.label(_character_id), 28, UiStyle.GOLD)
	add_text(config_panel, "实验使用独立进度。", 14, UiStyle.MUTED)
	add_text(config_panel, "起始位置", 20)
	var location_row := add_row(config_panel)
	var year_picker := OptionButton.new()
	year_picker.name = "TestStartYear"
	_style_picker(year_picker)
	for year in range(1, 5):
		year_picker.add_item("第 %d 学年" % year, year)
	year_picker.select(_year - 1)
	location_row.add_child(year_picker)
	var node_picker := add_button(location_row, "test:start:open_map", "在地图选点", {}, _open_start_map)
	node_picker.name = "TestStartNode"
	node_picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_location = add_text(config_panel, "", 15, UiStyle.MUTED)
	_start_location.name = "TestStartLocation"
	add_button(config_panel, "test:start:map_default", "清除节点，从学年地图开始", {}, func():
		_node_key = ""
		_update_start_location()).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	year_picker.item_selected.connect(func(index: int):
		_year = index + 1
		_node_key = ""
		_update_start_location())
	_advanced_fields = VBoxContainer.new()
	_advanced_fields.add_theme_constant_override("separation", 8)
	config_panel.add_child(_advanced_fields)
	add_text(_advanced_fields, "种子", 14, UiStyle.MUTED)
	var seed_input := LineEdit.new()
	seed_input.name = "TestStartSeed"
	seed_input.custom_minimum_size.y = 44
	seed_input.text = _seed
	seed_input.placeholder_text = "留空时使用种子 42"
	seed_input.add_theme_font_size_override("font_size", TestUiTokens.font(15))
	TestUiTokens.style_input(seed_input)
	seed_input.text_changed.connect(func(value: String):
		var next_seed := value.strip_edges()
		if next_seed != _seed:
			_seed = next_seed
			_node_key = ""
			_update_start_location())
	_advanced_fields.add_child(seed_input)
	if view.get("relic_pilot", false):
		add_text(_advanced_fields, "起始饰品 · 按槽位顺序结算", 14, UiStyle.MUTED)
		_build_relic_slots(options.get("relics", []))
	_update_start_location()
	_update_advanced()
	var characters := add_row(footer)
	characters.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.move_child(characters, 0)
	for character in options.get("characters", []):
		var id := str(character.id)
		var pick := add_button(characters, "test:character:" + id, UiStyle.label(id).split("·")[0], {}, _select_character.bind(id))
		pick.icon = UiStyle.character_portrait(id)
		pick.expand_icon = true
		pick.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		pick.add_theme_constant_override("icon_max_width", 56)
		pick.custom_minimum_size = Vector2(106 * UiStyle.text_scale, 66 + 16 * UiStyle.text_scale)
		pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick.toggle_mode = true
		pick.set_pressed_no_signal(id == _character_id)


func _home_panel(parent: Node) -> VBoxContainer:
	var panel := add_panel(parent)
	var style := UiStyle.surface(Color(UiStyle.NIGHT, 0.90), Color("657c85"))
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	(panel.get_parent() as PanelContainer).add_theme_stylebox_override("panel", style)
	return panel


func _switch_section(section: String) -> void:
	if _section == section:
		_buttons["test:home:" + section].set_pressed_no_signal(true)
		return
	_section = section
	_scroll_scope = ""
	render(view)
	_buttons["test:home:" + section].grab_focus()


func _select_character(id: String) -> void:
	_character_id = id
	for index in _starting_relics.size():
		if not RelicPilot.owns_definition(_starting_relics[index], id):
			_starting_relics[index] = ""
	render(view)
	_buttons["test:character:" + id].grab_focus()


func _toggle_advanced() -> void:
	_advanced_open = not _advanced_open
	_update_advanced()
	if _advanced_open:
		_scroll.ensure_control_visible.call_deferred(_advanced_fields.get_child(0))


func _update_advanced() -> void:
	_advanced_fields.visible = _advanced_open
	_buttons["test:start:advanced"].text = "收起种子与饰品" if _advanced_open else "种子与起始饰品"


func _style_picker(picker: OptionButton) -> void:
	picker.custom_minimum_size.y = 44
	picker.add_theme_font_size_override("font_size", TestUiTokens.font(15))
	picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	picker.get_popup().add_theme_font_size_override("font_size", TestUiTokens.font(15))


func _build_relic_slots(relics: Array) -> void:
	var pickers: Array[OptionButton] = []
	var legal := relics.filter(func(relic): return str(relic.id).begins_with("RX-") and RelicPilot.owns_definition(relic.id, _character_id))
	_starting_relics.resize(3)
	for index in 3:
		var picker := OptionButton.new()
		picker.name = "PilotRelicSlot%d" % (index + 1)
		_style_picker(picker)
		picker.fit_to_longest_item = false
		picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		picker.tooltip_text = "实验饰品槽 %d" % (index + 1)
		pickers.append(picker)
		picker.add_item("饰品槽 %d · 空" % (index + 1))
		picker.set_item_metadata(0, "")
		for relic in legal:
			var relic_id := str(relic.id)
			picker.add_item(UiStyle.label(relic_id))
			var item := picker.item_count - 1
			picker.set_item_metadata(item, relic_id)
			if _starting_relics[index] == relic_id:
				picker.select(item)
		picker.item_selected.connect(func(item: int):
			var chosen := str(picker.get_item_metadata(item))
			if not chosen.is_empty():
				for other in 3:
					if other != index and _starting_relics[other] == chosen:
						_starting_relics[other] = ""
						pickers[other].select(0)
			_starting_relics[index] = chosen)
		_advanced_fields.add_child(picker)


func _render_files() -> void:
	var files: Dictionary = view.get("files", {})
	for entry in [
		["snapshot", "快照", "从保存时的进度继续", "继续", "还没有快照。"],
		["preset", "预设", "用保存的配置开启新实验", "使用预设", "还没有预设。"],
		["record", "记录", "载入结算时的状态和实验日志", "载入记录", "还没有记录。"],
	]:
		var kind: String = entry[0]
		var items: Array = files.get(kind + "s", [])
		var panel := _home_panel(body)
		add_text(panel, "%s  ·  %d" % [entry[1], items.size()], 22)
		add_text(panel, entry[2], 14, UiStyle.MUTED)
		if items.is_empty():
			add_text(panel, entry[4], 15)
		for item in items:
			var id := str(item.id)
			var row := add_row(panel)
			var details := VBoxContainer.new()
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(details)
			add_text(details, str(item.name), 16)
			add_text(details, id, 12, UiStyle.MUTED)
			var load_button := add_button(row, "test:load_%s:%s" % [kind, id], entry[3],
				{"type": "test.load_" + kind, "payload": {"id": id}})
			load_button.size_flags_horizontal = Control.SIZE_SHRINK_END
			load_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if kind == "snapshot":
				var delete := add_button(row, "test:delete_snapshot:" + id, "删除", {}, _request_snapshot_deletion.bind(item))
				delete.size_flags_horizontal = Control.SIZE_SHRINK_END
				delete.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				delete.custom_minimum_size.x = 72


func _request_snapshot_deletion(snapshot: Dictionary) -> void:
	_snapshot_list_scroll = _scroll_position if _scroll_restore_pending else Vector2i(_scroll.scroll_horizontal, _scroll.scroll_vertical)
	_snapshot_to_delete = {"id": str(snapshot.get("id", "")), "name": str(snapshot.get("name", ""))}
	render(view)


func _cancel_snapshot_deletion() -> void:
	var uid := "test:delete_snapshot:" + str(_snapshot_to_delete.get("id", ""))
	_snapshot_to_delete.clear()
	render(view)
	_scroll_position = _snapshot_list_scroll
	if _buttons.has(uid):
		_buttons[uid].grab_focus()


func _render_snapshot_delete_confirmation() -> void:
	reset_page("删除测试快照", "删除后无法撤销，请确认要移除的快照。")
	var panel := add_panel(body)
	add_text(panel, str(_snapshot_to_delete.name), 22)
	add_text(panel, "ID：" + str(_snapshot_to_delete.id), 14, UiStyle.MUTED)
	add_text(panel, "仅删除这份已保存的测试快照，其他测试文件和正式进度保持原样。", 16)
	var row := add_row(footer)
	var cancel := add_button(row, "test:delete_snapshot:cancel", "取消", {}, _cancel_snapshot_deletion)
	add_button(
		row, "test:delete_snapshot:confirm", "确认删除",
		{"type": "test.delete_snapshot", "payload": {"id": str(_snapshot_to_delete.id)}},
		func(): _snapshot_to_delete.clear()
	)
	cancel.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _snapshot_to_delete.is_empty() and event.is_action_pressed("ui_cancel"):
		_cancel_snapshot_deletion()
		get_viewport().set_input_as_handled()


func _render_result() -> void:
	var test_view: Dictionary = view.get("view", {})
	var battle: Dictionary = test_view.get("battle", {})
	var result: Dictionary = test_view.get("result", {})
	var test_state: Dictionary = test_view.get("test", {})
	reset_page("实验结束", "结果来源：%s" % _source_name(str(result.get("source", ""))))
	var summary := _home_panel(body)
	var outcome := str(result.get("outcome", ""))
	add_text(summary, {"won": "挑战成功", "lost": "挑战失败", "abandoned": "主动结束"}.get(outcome, UiStyle.label(outcome)), 27, UiStyle.GOLD)
	add_text(summary, "回合 %s · DDL %s · 剩余精力 %s" % [
		battle.get("round_index", 0),
		battle.get("ddl", 0),
		(battle.get("player", {}) as Dictionary).get("vitality", 0),
	])
	add_text(summary, "第 %s 次尝试 · 干预 %s 次" % [test_state.get("attempt", 1), test_state.get("interventions", 0)], 14, UiStyle.MUTED)
	var row := GridContainer.new()
	row.columns = 2 if size.x < 1100 or UiStyle.text_scale > 1.0 else 3
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	body.add_child(row)
	add_button(row, "test:result:continue", "继续编辑", {"type": "test.continue"})
	add_button(row, "test:result:retry_same", "同条件重试", {"type": "test.retry_same"})
	add_button(row, "test:result:retry_current", "以当前为新起点", {"type": "test.retry_current"})
	add_button(row, "test:result:save", "保存记录", {"type": "test.save_record"})
	add_button(row, "test:compendium", "图鉴", {"type": "test.compendium"})
	var actions := add_row(footer)
	add_button(actions, "test:result:discard", "丢弃并返回", {"type": "test.close"}).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	add_button(actions, "test:result:exit", "保存并返回", {"type": "test.save_and_exit"}).size_flags_horizontal = Control.SIZE_SHRINK_END


func _source_name(source: String) -> String:
	return str(
		{
			"normal": "正常结算",
			"manual": "人工判定",
			"truncated": "截断结算",
			"abandoned": "主动结束",
			"none": "未结束",
		}
		.get(source, source)
	)
