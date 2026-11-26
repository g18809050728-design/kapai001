extends Control

## UI-only map browsing. The caller handles the confirmed key.
signal node_confirmed(node_key: String)
signal cancelled

var _nodes: Array = []
var _year := 1
var _selected := ""
var _current := ""
var _current_year := 1
var _draft_count := 0
var _selection_only := false
var _return_to_room := false
var _fixed_node_key := ""
var _submitted := false
var _generation := 0
var _buttons: Dictionary = {}
var _column: VBoxContainer
var _scroll: ScrollContainer
var _canvas: UiRouteCanvas
var _overview: UiRouteCanvas
var _summary: Label
var _detail: Label
var _press_id := ""
var _press_origin := Vector2.ZERO
var _press_selected := false
var _press_dragged := false
var _press_double := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := UiMapPaper.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	paper.add_child(_column)
	resized.connect(_resize_map)
	hide()


func open(view: Dictionary, selected_key: String = "", draft_count: int = 0, selection_only: bool = false, fixed_node_key: String = "", return_to_room: bool = false) -> void:
	_nodes = view.get("nodes", []).duplicate(true)
	_current = str(view.get("run", {}).get("current_node_id", "")).get_slice("|", 1)
	_current_year = int(view.get("run", {}).get("term", 1))
	_year = _current_year
	_fixed_node_key = fixed_node_key
	_selected = _fixed_node_key if not _fixed_node_key.is_empty() else selected_key
	_draft_count = draft_count
	_selection_only = selection_only
	_return_to_room = return_to_room
	_submitted = false
	for node in _nodes:
		if str(node.key) == _selected:
			_year = int(node.year)
			break
	show()
	_build()


func press(uid: String) -> bool:
	if not visible or _submitted or not _buttons.has(uid):
		return false
	var button: Button = _buttons[uid]
	if not is_instance_valid(button) or button.disabled:
		return false
	button.pressed.emit()
	return true


func _build() -> void:
	_generation += 1
	_press_id = ""
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_buttons.clear()
	var heading := HBoxContainer.new()
	_column.add_child(heading)
	_label(heading, "测试地图 · 确认起始节点" if not _fixed_node_key.is_empty() else ("测试地图 · 选择起始节点" if _selection_only else "测试地图 · 自由选点"), 22)
	_button(heading, "test:map:current", "定位起点" if _selection_only or not _fixed_node_key.is_empty() else "定位当前", _locate_current)
	var current_node := _find(_current)
	var location := "第 %d 学年 · 地图起点" % _current_year
	if not current_node.is_empty():
		location = describe_node(current_node)
	_label(_column, ("起始位置：" if _selection_only else "当前位置：") + location, 14)
	var years := HBoxContainer.new()
	_column.add_child(years)
	for year in range(1, 5):
		var button := _button(years, "test:map:year:%d" % year, "第 %d 学年" % year, func(): _switch_year(year))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.set_pressed_no_signal(year == _year)
		UiStyle.button_skin(button, "primary" if year == _year else "secondary")
	_summary = _label(_column, "", 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	_summary.clip_text = true
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(_column, "只能进入首次选定的起始节点；其他节点仅展示位置。" if not _fixed_node_key.is_empty() else ("红圈预选 · 所有节点均可选择 · 首次点击预览，再点或确认选择" if _selection_only else "◆ 当前　✓ 已过　红圈预选　· 所有节点均可进入 · 首次点击预览，再点或确认进入"), 12)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 12)
	map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(map_row)
	_scroll = ScrollContainer.new()
	_scroll.name = "TestMapScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_row.add_child(_scroll)
	var entries := _year_nodes()
	var keys := entries.map(func(node): return str(node.key))
	var available := keys.filter(_node_allowed)
	_canvas = UiRouteCanvas.new()
	_canvas.name = "TestRouteMap"
	_canvas.configure(entries, available, _current, _selected)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_canvas)
	var generation := _generation
	for node in entries:
		var key := str(node.key)
		var allowed := _node_allowed(key)
		var button := UiRouteCanvas.NodeStamp.new() as Button
		button.set_meta("node_id", key)
		button.toggle_mode = true
		_canvas.add_child(button)
		button.call("configure", str(node.subtype), _type_name(node), "不可达" if not allowed else ("当前" if key == _current else ("已过" if node.status == "completed" else "可入")), false, _canvas.node_textures.get(key))
		button.disabled = not allowed
		if not allowed:
			button.modulate.a = .45
		button.set_pressed_no_signal(key == _selected)
		button.tooltip_text = describe_node(node) + "\n" + key + ("\n首次点击预览 · 再次点击或双击选择" if _selection_only else "\n首次点击预览 · 再次点击或双击进入")
		if not allowed:
			button.tooltip_text = describe_node(node) + "\n仅可进入首次选定的起始节点"
		button.pressed.connect(func(): _activate(key))
		button.gui_input.connect(_node_input.bind(key, generation))
		button.focus_entered.connect(func(): _ensure_visible(key, generation))
		_buttons["test:map:node:" + key] = button
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 210
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_row.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	_label(side, "第 %d 学年 · 全图" % _year, 16)
	_overview = UiRouteCanvas.new()
	_overview.overview = true
	_overview.detailed_overview = true
	_overview.overview_height = 260
	_overview.configure(entries, available, _current, _selected)
	side.add_child(_overview)
	_overview.node_inspected.connect(func(key):
		if _node_allowed(key):
			_select(key)
			_focus_node.call_deferred(key, _generation))
	_detail = _label(side, "", 14)
	_label(side, "拖动滚条或滚轮查看路线。方向键移动焦点，空格/回车选点，再次激活" + ("选择。" if _selection_only else "进入。"), 12)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_column.add_child(footer)
	var back_label := "返回编辑器"
	if _selection_only:
		back_label = "返回配置"
	elif _return_to_room:
		back_label = "返回当前房间"
	_button(footer, "test:map:cancel", back_label, _cancel)
	var hint := _label(footer, "选好后返回配置，点击“开始实验”启动" if _selection_only else ("确认时同时应用已有 %d 项草稿" % _draft_count if _draft_count > 0 else "确认后进入所选房间，可在编辑器撤销"), 12)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button(footer, "test:map:enter", "选择此节点" if _selection_only else "进入此节点", _confirm, true)
	_select(_selected)
	_canvas.arrange.call_deferred()
	_overview.arrange.call_deferred()
	_focus_node.call_deferred(_selected if keys.has(_selected) else (_current if keys.has(_current) else str(keys[0]) if not keys.is_empty() else ""), generation)
	_grab_focus.call_deferred("test:map:node:" + _selected if keys.has(_selected) else "test:map:cancel", generation)


func _switch_year(year: int) -> void:
	if year == _year:
		return
	_year = year
	_selected = ""
	_build()


func _select(key: String) -> void:
	if not key.is_empty() and not _node_allowed(key):
		return
	var node := _find(key)
	_selected = key if not node.is_empty() and int(node.year) == _year else ""
	_canvas.select_node(_selected)
	_overview.select_node(_selected)
	for entry in _year_nodes():
		var button: Button = _buttons.get("test:map:node:" + str(entry.key))
		if is_instance_valid(button):
			button.set_pressed_no_signal(str(entry.key) == _selected)
	_summary.text = "请选择地图上的节点" if _selected.is_empty() else "已选目标：" + describe_node(node)
	if not _fixed_node_key.is_empty() and _selected.is_empty():
		_summary.text = "仅可进入：" + describe_node(_find(_fixed_node_key)) + "（点击定位起点）"
	_summary.tooltip_text = _summary.text
	_detail.text = ("首次点击预览，确认后选择。" if _selection_only else "首次点击预览，确认后进入。") if _selected.is_empty() else describe_node(node) + "\n" + str(node.key)
	var enter: Button = _buttons["test:map:enter"]
	enter.disabled = _selected.is_empty()


func _activate(key: String) -> void:
	if not _node_allowed(key):
		return
	var confirmed := key == _selected
	_select(key)
	if confirmed:
		_confirm()


func _confirm() -> void:
	if _submitted or _selected.is_empty() or not visible or not _node_allowed(_selected):
		return
	_submitted = true
	var key := _selected
	hide()
	node_confirmed.emit(key)


func _cancel() -> void:
	if not visible:
		return
	hide()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ESCAPE, KEY_F2]:
		_cancel()
		accept_event()
	elif event.keycode == KEY_TAB:
		var available: Array = _buttons.values().filter(func(button): return is_instance_valid(button) and not button.disabled)
		var index := available.find(get_viewport().gui_get_focus_owner())
		var next := posmod(index + (-1 if event.shift_pressed else 1), available.size())
		available[next].grab_focus()
		accept_event()


func _locate_current() -> void:
	_year = _current_year if _fixed_node_key.is_empty() else int(_find(_fixed_node_key).year)
	_selected = _current if _fixed_node_key.is_empty() else _fixed_node_key
	_build()


func _node_allowed(key: String) -> bool:
	return _fixed_node_key.is_empty() or key == _fixed_node_key


func _find(key: String) -> Dictionary:
	for node in _nodes:
		if str(node.key) == key:
			return node
	return {}


func _year_nodes() -> Array:
	return _nodes.filter(func(node): return int(node.year) == _year)


static func describe_node(node: Dictionary) -> String:
	return "第 %d 学年 · 第 %d 层 · %s · %s" % [int(node.year), int(node.layer), _type_name(node), str(node.title)]


static func _type_name(node: Dictionary) -> String:
	return str({"N": "战斗", "EL": "精英", "K": "竞赛", "B": "首领", "S": "商店", "R": "休息", "E": "事件", "L": "图书", "LAB": "实验", "T": "导师", "C": "社团", "I": "实习", "ST": "毕设"}.get(str(node.subtype), str(node.title)))


func _node_input(event: InputEvent, key: String, generation: int) -> void:
	if generation != _generation or not visible or _submitted or not _node_allowed(key):
		return
	var button: Button = _buttons.get("test:map:node:" + key)
	if event is InputEventMouseMotion and _press_id == key:
		_press_dragged = _press_dragged or event.global_position.distance_to(_press_origin) > 8
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	button.accept_event()
	if event.pressed:
		_press_id = key
		_press_origin = event.global_position
		_press_selected = _selected == key
		_press_double = event.double_click
		_press_dragged = false
		button.grab_focus()
	elif _press_id == key:
		_press_id = ""
		if _press_dragged or not Rect2(Vector2.ZERO, button.size).has_point(event.position):
			return
		_select(key)
		if _press_selected or _press_double:
			_confirm()


func _ensure_visible(key: String, generation: int) -> void:
	if generation == _generation and visible:
		var button: Button = _buttons.get("test:map:node:" + key)
		if is_instance_valid(button):
			_scroll.ensure_control_visible(button)


func _focus_node(key: String, generation: int, frames: int = 3) -> void:
	if not is_inside_tree() or generation != _generation or not visible:
		return
	if frames > 0:
		get_tree().create_timer(0).timeout.connect(_focus_node.bind(key, generation, frames - 1), CONNECT_ONE_SHOT)
		return
	_canvas.arrange()
	_overview.arrange()
	if _canvas.positions.has(key):
		_scroll.scroll_vertical = maxi(0, roundi(_canvas.positions[key].y - _scroll.size.y * .5))


func _resize_map() -> void:
	if visible and _column != null:
		_build()


func _grab_focus(uid: String, generation: int) -> void:
	if not is_inside_tree() or generation != _generation or not visible:
		return
	var button: Button = _buttons.get(uid)
	if is_instance_valid(button) and button.is_inside_tree():
		button.grab_focus()


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", TestUiTokens.font(font_size))
	label.add_theme_color_override("font_color", UiStyle.INK)
	parent.add_child(label)
	return label


func _button(parent: Node, uid: String, text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = maxf(44, TestUiTokens.height(36))
	button.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	UiStyle.button_skin(button, "primary" if primary else "secondary")
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons[uid] = button
	return button
