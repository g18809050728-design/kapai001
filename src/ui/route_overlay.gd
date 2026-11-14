class_name UiRouteOverlay
extends Control

signal closed

var _nodes: Array = []
var _current := ""
var _reachable: Array = []
var _return_focus: Control
var _focus_modes: Dictionary = {}
var _disabled_buttons: Dictionary = {}
var _panel: PanelContainer
var _route: UiRouteCanvas
var _title: Label
var _details: Label
var _close: Button


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
	_panel.offset_left = 24
	_panel.offset_top = 28
	_panel.offset_right = -24
	_panel.offset_bottom = -24
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
	_close.text = "关闭  M / Esc"
	_close.custom_minimum_size = Vector2(136, 42)
	UiStyle.button_skin(_close, "secondary", true)
	_close.pressed.connect(close)
	heading.add_child(_close)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	_route = UiRouteCanvas.new()
	_route.name = "CompleteAnnualMap"
	_route.overview = true
	_route.detailed_overview = true
	_route.overview_height = 160
	_route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_route.configure(_nodes, _reachable, _current)
	content.add_child(_route)
	_route.node_inspected.connect(_inspect)
	for node in _nodes:
		var id := str(node.node_id)
		var marker := Button.new()
		marker.set_meta("node_id", id)
		marker.name = "MapRead_" + id.validate_node_name()
		marker.tooltip_text = "第%d层 · %s" % [int(node.get("layer", 0)), str(node.get("title", "校园节点"))]
		marker.size = Vector2(36, 28)
		for state in ["normal", "hover", "pressed", "focus"]:
			marker.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		marker.pressed.connect(func(): _inspect(id))
		marker.focus_entered.connect(func(): _inspect(id))
		_route.add_child(marker)
	var reading := ScrollContainer.new()
	reading.custom_minimum_size.x = 220
	reading.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(reading)
	_details = _label(reading, "点击节点查看房间与后续路线。\n\n地图查看不会前进，也不会改变当前选择。", 15)
	_details.custom_minimum_size.x = 200
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(column, "圈记当前与已走路线 · 圈记可达节点 · 点击图标查看详情", 14)
	_label(column, "仅展示已生成的本学年 · 关闭后继续原来的行动", 13)
	if _nodes.is_empty():
		_details.text = "本学年尚未生成，确认方向或去向后生成；不会提前揭示未来学年。"
	resized.connect(_fit)
	_fit.call_deferred()
	_focus_close.call_deferred()
	if not _current.is_empty():
		_inspect(_current)
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
	if is_instance_valid(_route):
		_route.arrange.call_deferred()


func _focus_close() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(_close):
		_close.grab_focus()


func _inspect(id: String) -> void:
	_route.select_node(id)
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
