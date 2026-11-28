class_name UiRouteOverlay
extends Control

signal closed

var _nodes: Array = []
var _current := ""
var _route_scroll: ScrollContainer
var _reachable: Array = []
var _return_focus: Control
var _focus_modes: Dictionary = {}
var _disabled_buttons: Dictionary = {}
var _panel: PanelContainer
var _route: UiRouteCanvas
var _title: Label
var _details: Label
var _close: Button
var _content: BoxContainer
var _reading: ScrollContainer


func configure(nodes: Array, current: String, reachable: Array, year_title: String) -> void:
	_nodes = nodes.duplicate(true)
	_current = current
	_reachable = reachable.duplicate()
	name = "FullMapOverlay"
	set_meta("year_title", year_title)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	_return_focus = get_viewport().gui_get_focus_owner()
	for control in get_parent().find_children("*", "Control", true, false):
		if control is BaseButton and not is_ancestor_of(control):
			_disabled_buttons[control] = control.disabled
			control.disabled = true
		if control != self and not is_ancestor_of(control) and control.focus_mode != Control.FOCUS_NONE:
			_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	var shade := ColorRect.new()
	shade.color = Color(.02, .04, .06, .86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 8 if UiStyle.web_touch else 24
	_panel.offset_top = 8 if UiStyle.web_touch else 28
	_panel.offset_right = -8 if UiStyle.web_touch else -24
	_panel.offset_bottom = -8 if UiStyle.web_touch else -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiStyle.surface(UiStyle.NIGHT, UiStyle.BRASS))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_title = _label(heading, "校园路线 · " + year_title, 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close = Button.new()
	_close.name = "CloseFullMap"
	_close.text = "关闭" if UiStyle.web_touch else "关闭  M / Esc"
	_close.custom_minimum_size = Vector2(80, UiStyle.MOBILE_TARGET) if UiStyle.web_touch else Vector2(136, 42)
	UiStyle.button_skin(_close, "secondary", true)
	_close.pressed.connect(close)
	heading.add_child(_close)
	var content := BoxContainer.new()
	_content = content
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	_route = UiRouteCanvas.new()
	_route.name = "CompleteAnnualMap"
	_route.overview = not UiStyle.web_touch
	_route.detailed_overview = true
	_route.overview_height = 160
	_route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_route.configure(_nodes, _reachable, _current)
	if UiStyle.web_touch:
		_route_scroll = ScrollContainer.new()
		_route_scroll.name = "AnnualMapScroll"
		_route_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_route_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_route_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(_route_scroll)
		_route_scroll.add_child(_route)
	else:
		content.add_child(_route)
	_route.node_inspected.connect(_inspect)
	for node in _nodes:
		var id := str(node.node_id)
		var marker := Button.new()
		marker.set_meta("node_id", id)
		marker.name = "MapRead_" + id.validate_node_name()
		marker.tooltip_text = "第%d层 · %s" % [int(node.get("layer", 0)), str(node.get("title", "校园节点"))]
		_route.add_child(marker)
		if UiStyle.web_touch:
			marker.set_script(UiRouteCanvas.NodeStamp)
			marker.toggle_mode = true
			var kind := str(node.get("kind", ""))
			var subtype := str(node.get("subtype", ""))
			if subtype.is_empty():
				subtype = str({"normal": "N", "elite": "EL", "boss": "B", "shop": "S", "rest": "R", "event": "E"}.get(kind, "E"))
			var status := "当前" if id == _current else ("已过" if node.get("status") == "completed" else ("可入" if _reachable.has(id) else "后续"))
			marker.call("configure", subtype, "", status, false, _route.node_textures.get(id))
		else:
			marker.size = Vector2(36, 28)
			for state in ["normal", "hover", "pressed", "focus"]:
				marker.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			marker.focus_entered.connect(func(): _inspect(id))
		marker.pressed.connect(func(): _inspect(id))
	var reading := ScrollContainer.new()
	_reading = reading
	reading.custom_minimum_size.x = 220
	reading.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(reading)
	_details = _label(reading, "点击节点查看房间与后续路线。\n\n地图查看不会前进，也不会改变当前选择。", 15)
	_details.custom_minimum_size.x = 200
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(column, "上下滑查看本学年路线 · 点按节点查看详情" if UiStyle.web_touch else "圈记当前与已走路线 · 圈记可达节点 · 点击图标查看详情", 14)
	if not UiStyle.web_touch:
		_label(column, "仅展示已生成的本学年 · 关闭后继续原来的行动", 13)
	if _nodes.is_empty():
		_details.text = "本学年尚未生成，确认方向或去向后生成；不会提前揭示未来学年。"
	resized.connect(_fit)
	_fit.call_deferred()
	_focus_close.call_deferred()
	if not _current.is_empty():
		_inspect(_current)
	if UiStyle.web_touch:
		_focus_route.call_deferred()
	tree_exiting.connect(_restore_focus)


func _label(parent: Node, caption: String, pixels: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", UiStyle.CREAM)
	label.add_theme_font_size_override("font_size", roundi(pixels * minf(UiStyle.text_scale, 1.25)))
	parent.add_child(label)
	return label


func _fit() -> void:
	if is_instance_valid(_reading):
		var stacked := UiStyle.narrow_touch(size)
		_content.vertical = stacked
		_reading.custom_minimum_size = Vector2(0, clampf(size.y * .22, 90, 180)) if stacked else Vector2(220, 0)
	if is_instance_valid(_route):
		_route.arrange.call_deferred()


func _focus_route() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var target := _current if not _current.is_empty() else str(_reachable[0]) if not _reachable.is_empty() else ""
	if _route.positions.has(target):
		_route_scroll.scroll_vertical = roundi(float(_route.positions[target].y) - _route_scroll.size.y * .5)


func _focus_close() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(_close):
		_close.grab_focus()


func _inspect(id: String) -> void:
	_route.select_node(id)
	if is_instance_valid(_route_scroll):
		for marker in _route.get_children():
			if marker is Button:
				var marker_id := str(marker.get_meta("node_id", ""))
				marker.set_pressed_no_signal(marker_id == id)
				marker.set("forecast", _route.forecast_node_ids.has(marker_id))
				marker.queue_redraw()
	for node in _nodes:
		if str(node.node_id) == id:
			var status := "当前房间" if id == _current else ("下一站可达" if _reachable.has(id) else ("已完成" if node.get("status") == "completed" else "后续 / 其他路线"))
			_details.text = "第 %02d 层 · %s\n%s\n\n%s" % [int(node.get("layer", 0)), node.get("title", "校园节点"), status, UiRouteCanvas.Forecast.describe(_nodes, id).text]
			return


func close() -> void:
	if is_queued_for_deletion():
		return
	hide()
	_restore_focus()
	closed.emit()
	queue_free()


func _restore_focus() -> void:
	for button in _disabled_buttons:
		if is_instance_valid(button):
			button.disabled = _disabled_buttons[button]
	_disabled_buttons.clear()
	for control in _focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _focus_modes[control]
	_focus_modes.clear()
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree():
		_return_focus.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_M]:
		close()
		get_viewport().set_input_as_handled()
