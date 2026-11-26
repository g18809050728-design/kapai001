class_name TestHud
extends Control

## In-battle test HUD: identity bar plus the draft-based TestEditorPanel.

signal test_command(command_type: String, payload: Dictionary)

const BAR_HEIGHT := 46.0

var session: GameSession
var editor: TestEditorPanel
var _view: Dictionary = {}
var _bar: PanelContainer
var _identity: Label
var _state_label: Label
var _pause_button: Button
var _buttons: Dictionary = {}
var _open := false
var _return_focus: Control


func _ready() -> void:
	z_index = 500
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()
	editor = TestEditorPanel.new()
	editor.setup(session)
	add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.command.connect(func(command_type: String, payload: Dictionary):
		test_command.emit(command_type, payload)
	)
	editor.close_requested.connect(_close_editor)
	editor.catalogue_requested.connect(func(): test_command.emit("test.compendium", {}))


func setup(p_session: GameSession) -> void:
	session = p_session
	if editor != null:
		editor.setup(p_session)


func render(view: Dictionary) -> void:
	_view = view
	var test_state: Dictionary = view.get("test", {})
	var result: Dictionary = view.get("result", {})
	var overlay: Dictionary = view.get("overlay", {})
	if _identity != null:
		var run: Dictionary = view.get("run", {})
		var character := UiStyle.label(str(view.get("config", {}).get("character_id", ""))).split("·")[0]
		var term := int(run.get("term", 0))
		var location := "测试房间 · %s" % character
		if term > 0:
			location += " · 第 %d 学年" % term
		_identity.text = "测试房间" if size.x < 1100 and UiStyle.text_scale > 1.0 else location
		_identity.tooltip_text = "%s\n%s · 分支 %s · 版本 %s\n干预 %s 次 · 定义覆盖 %s 项" % [
			location,
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
		elif marker == "运行中" and bool(test_state.get("dirty", false)):
			marker += " · 未保存"
		_state_label.text = marker
		_state_label.tooltip_text = "本次实验有未保存的进度" if bool(test_state.get("dirty", false)) else ""
		if _pause_button != null:
			_pause_button.text = "继续" if bool(test_state.get("paused", false)) else "暂停"
	var history: Dictionary = view.get("history", {})
	var editing := bool(test_state.get("editing", false))
	for direction in ["undo", "redo"]:
		var button: Button = _buttons["test:" + direction]
		var available := bool(history.get("can_" + direction, false))
		button.disabled = editing or not available
		button.tooltip_text = ""
		if editing:
			button.tooltip_text = "可在编辑器的历史与存档中操作"
		elif not available:
			button.tooltip_text = "没有可撤销的操作" if direction == "undo" else "没有可重做的操作"
	_buttons["test:jump"].disabled = (view.get("nodes", []) as Array).is_empty()
	if editor != null:
		editor.render(view)


func is_editor_open() -> bool:
	return _open


func open_editor() -> void:
	if _open:
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	_open = true
	test_command.emit("test.begin_edit", {})
	if editor != null:
		editor.open()


func _close_editor() -> void:
	if not _open:
		return
	_open = false
	if editor != null:
		editor.close()
	test_command.emit("test.cancel_edit", {})
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	else:
		_buttons["test:open_editor"].grab_focus()


func open_node_map(node_key: String = "", confirm_start: bool = false) -> void:
	open_editor()
	if editor != null:
		editor.open_node_map(node_key, confirm_start)


func _jump_to_room() -> void:
	var from_room := not _open
	open_editor()
	editor.open_node_map("", false, from_room)


func _toggle_editor() -> void:
	if _open:
		if editor != null:
			editor.request_close()
	else:
		open_editor()


func editor_result(accepted: bool) -> void:
	if editor != null:
		editor.handle_result(accepted)


func finish_node_jump() -> void:
	_open = false
	if editor != null:
		editor.close()


func button_uids() -> Array:
	return _buttons.keys()


func press(uid: String) -> bool:
	if not is_visible_in_tree() or not _buttons.has(uid) or not is_instance_valid(_buttons[uid]):
		return false
	var button: Button = _buttons[uid]
	if button.disabled:
		return false
	button.pressed.emit()
	return true


func _short_id(test_id: String) -> String:
	if test_id.length() <= 18:
		return test_id
	return test_id.substr(test_id.length() - 18)


static func bar_height() -> float:
	return maxf(48, TestUiTokens.height(BAR_HEIGHT))


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_top = 0
	_bar.offset_bottom = bar_height()
	var skin := UiStyle.surface(UiStyle.NIGHT, Color("657c85"), 0)
	skin.shadow_size = 0
	skin.content_margin_top = 2
	skin.content_margin_bottom = 2
	skin.content_margin_left = 8
	skin.content_margin_right = 8
	_bar.add_theme_stylebox_override("panel", skin)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)
	_identity = Label.new()
	_identity.text = "测试房间"
	_identity.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	_identity.add_theme_color_override("font_color", UiStyle.CREAM)
	_identity.clip_text = true
	_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_identity)
	_state_label = Label.new()
	_state_label.text = "运行中"
	_state_label.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	_state_label.add_theme_color_override("font_color", UiStyle.GOLD)
	row.add_child(_state_label)
	_pause_button = _button(row, "test:pause", "暂停", func(): test_command.emit("test.pause", {}))
	_button(row, "test:jump", "跳转地图", _jump_to_room).tooltip_text = "查看四学年地图，选择要测试的房间"
	_button(row, "test:open_editor", "编辑实验", func(): _toggle_editor()).tooltip_text = "编辑实验（F2）"
	_button(row, "test:compendium", "图鉴", func(): test_command.emit("test.compendium", {}))
	_button(row, "test:undo", "撤销", func(): test_command.emit("test.undo", {}))
	_button(row, "test:redo", "重做", func(): test_command.emit("test.redo", {}))
	_button(row, "test:save", "保存快照", func(): test_command.emit("test.save_snapshot", {}))
	_button(row, "test:close", "退出", func(): test_command.emit("test.close", {}))


func _button(parent: Node, uid: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(48, maxf(44, TestUiTokens.height(32)))
	button.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	button.set_meta("uid", uid)
	UiStyle.button_skin(button, "primary" if uid == "test:open_editor" else "secondary", true)
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons[uid] = button
	return button


func _input(event: InputEvent) -> void:
	if editor != null and is_instance_valid(editor.map_picker) and editor.map_picker.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode != KEY_F2:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	_toggle_editor()
	accept_event()

