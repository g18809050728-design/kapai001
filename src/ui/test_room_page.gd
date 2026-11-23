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


func add_button(parent: Node, uid: String, caption: String, draft: Variant = {}, local_callback: Callable = Callable()) -> Button:
	var button := super.add_button(parent, uid, caption, draft, local_callback)
	var selected := uid == "test:character:" + _character_id
	var primary := uid in ["test:start", "test:result:continue", "test:result:exit", "test:delete_snapshot:confirm"]
	var quiet := uid in ["test:back", "test:result:discard", "test:delete_snapshot:cancel"]
	UiStyle.button_skin(button, "selected" if selected else ("primary" if primary else ("quiet" if quiet else "secondary")), true)
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
	var label := super.add_text(parent, value, font_size, color if on_paper else (Color("c4d0cf") if color == UiStyle.MUTED else UiStyle.CREAM))
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
	scene.room = "settings" if screen == "test_room_home" else "summary"
	scene.story_background = UiStyle.texture("BG_study" if screen == "test_room_home" else "BG_success")
	scene.z_index = -1
	add_child(scene)
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
	_buttons["test:start:map_default"].disabled = _node_key.is_empty()


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
	for region in [header, _scroll, footer]:
		region.hide()
	map_picker.call("open", {"nodes": _start_nodes, "run": {"term": _year, "current_node_id": ""}}, _node_key, 0, true)


func _close_start_map() -> void:
	for region in [header, _scroll, footer]:
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
	reset_page("测试房间", "修改只作用于本实验，不影响正式存档；随时可打开编辑器。")
	add_text(body, "默认从校园地图开始；也可选择学年和节点，直接测试任意房间。")
	var character_row: HBoxContainer = add_row(body)
	for character in options.get("characters", []):
		var id := str(character.get("id", ""))
		var caption := UiStyle.label(id) + (" ✓" if id == _character_id else "")
		add_button(
			character_row,
			"test:character:" + id,
			caption,
			{},
			func():
				_character_id = id
				for index in _starting_relics.size():
					if not RelicPilot.owns_definition(_starting_relics[index], id):
						_starting_relics[index] = ""
				render(view)
		)
	var config_panel: VBoxContainer = add_panel(body)
	add_text(config_panel, "种子", 14, UiStyle.MUTED)
	var seed_input := LineEdit.new()
	seed_input.name = "TestStartSeed"
	seed_input.custom_minimum_size.y = 44
	seed_input.text = _seed
	seed_input.placeholder_text = "seed"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.text_changed.connect(func(value: String):
		var next_seed := value.strip_edges()
		if next_seed != _seed:
			_seed = next_seed
			_node_key = ""
			_update_start_location())
	config_panel.add_child(seed_input)
	add_text(config_panel, "起始位置 · 在地图上选择具体节点", 14, UiStyle.MUTED)
	var node_row: HBoxContainer = add_row(config_panel)
	var year_picker := OptionButton.new()
	year_picker.name = "TestStartYear"
	year_picker.custom_minimum_size.y = 44
	for year in range(1, 5):
		year_picker.add_item("第 %d 学年" % year, year)
	year_picker.select(_year - 1)
	node_row.add_child(year_picker)
	var node_picker := add_button(node_row, "test:start:open_map", "地图选点", {}, _open_start_map)
	node_picker.name = "TestStartNode"
	add_button(node_row, "test:start:map_default", "从地图开始", {}, func():
		_node_key = ""
		_update_start_location())
	_start_location = add_text(config_panel, "", 14, UiStyle.MUTED)
	_start_location.name = "TestStartLocation"
	year_picker.item_selected.connect(func(index: int):
		_year = index + 1
		_node_key = ""
		_update_start_location())
	seed_input.text_submitted.connect(func(_value: String): _refresh_start_nodes())
	seed_input.focus_exited.connect(_refresh_start_nodes)
	_refresh_start_nodes()
	if view.get("relic_pilot", false):
		add_text(config_panel, "为本场实验佩戴至多三件，按槽位顺序结算。", 14, UiStyle.MUTED)
		var slots := add_row(config_panel)
		var pickers: Array[OptionButton] = []
		var legal: Array = options.get("relics", []).filter(func(relic): return str(relic.id).begins_with("RX-") and RelicPilot.owns_definition(relic.id, _character_id))
		_starting_relics.resize(3)
		for index in 3:
			var picker := OptionButton.new()
			picker.name = "PilotRelicSlot%d" % (index + 1)
			picker.tooltip_text = "实验饰品槽 %d" % (index + 1)
			pickers.append(picker)
			picker.custom_minimum_size = Vector2(0, 44)
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			slots.add_child(picker)
	var start_row: HBoxContainer = add_row(footer)
	add_button(start_row, "test:back", "返回主菜单", {"type": "ui.menu"})
	add_button(
		start_row,
		"test:start",
		"开始实验",
		func():
			return {"type": "test.start", "payload": {"locate_node_key": _node_key, "config": {
				"character_id": _character_id, "seed": _seed, "start_year": _year,
				"relics": _starting_relics.filter(func(id): return not id.is_empty()),
			}}}
	)
	var files: Dictionary = view.get("files", {})
	var presets: Array = files.get("presets", [])
	if not presets.is_empty():
		add_text(body, "预设", 18)
		for preset in presets:
			var preset_row: HBoxContainer = add_row(body)
			add_text(preset_row, "%s · %s" % [preset.get("name", ""), preset.get("id", "")], 14)
			add_button(
				preset_row,
				"test:load_preset:" + str(preset.get("id", "")),
				"载入",
				{"type": "test.load_preset", "payload": {"id": str(preset.get("id", ""))}}
			)
	var snapshots: Array = files.get("snapshots", [])
	if not snapshots.is_empty():
		add_text(body, "快照", 18)
		for snapshot in snapshots:
			var snapshot_row: HBoxContainer = add_row(body)
			add_text(snapshot_row, "%s · %s" % [snapshot.get("name", ""), snapshot.get("id", "")], 14)
			var load_button := add_button(
				snapshot_row,
				"test:load_snapshot:" + str(snapshot.get("id", "")),
				"载入",
				{"type": "test.load_snapshot", "payload": {"id": str(snapshot.get("id", ""))}}
			)
			var delete_button := add_button(
				snapshot_row,
				"test:delete_snapshot:" + str(snapshot.get("id", "")),
				"删除",
				{},
				func(): _request_snapshot_deletion(snapshot)
			)
			for button in [load_button, delete_button]:
				button.size_flags_horizontal = Control.SIZE_SHRINK_END
				button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var records: Array = files.get("records", [])
	if not records.is_empty():
		add_text(body, "记录", 18)
		for record in records:
			var record_row: HBoxContainer = add_row(body)
			add_text(record_row, "%s · %s" % [record.get("name", ""), record.get("id", "")], 14)
			add_button(
				record_row,
				"test:load_record:" + str(record.get("id", "")),
				"载入",
				{"type": "test.load_record", "payload": {"id": str(record.get("id", ""))}}
			)


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
	add_text(body, "分支 %s · rev %s · 干预 %s 次" % [
		test_state.get("branch_id", 0), test_state.get("revision", 0), test_state.get("interventions", 0)
	])
	add_text(body, "回合 %s · DDL %s · 剩余精力 %s" % [
		battle.get("round_index", 0),
		battle.get("ddl", 0),
		(battle.get("player", {}) as Dictionary).get("vitality", 0),
	])
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
	add_button(row, "test:result:exit", "保存并返回", {"type": "test.save_and_exit"})
	add_button(row, "test:result:discard", "丢弃并返回", {"type": "test.close"})


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
