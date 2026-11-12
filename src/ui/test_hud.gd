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
		if _pause_button != null:
			_pause_button.text = "继续" if bool(test_state.get("paused", false)) else "暂停"
	if editor != null:
		editor.render(view)


func is_editor_open() -> bool:
	return _open


func open_editor() -> void:
	if _open:
		return
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


func _toggle_editor() -> void:
	if _open:
		_close_editor()
	else:
		open_editor()


func editor_result(accepted: bool) -> void:
	if editor != null:
		editor.handle_result(accepted)


func button_uids() -> Array:
	return _buttons.keys()


func press(uid: String) -> bool:
	if not _buttons.has(uid) or not is_instance_valid(_buttons[uid]):
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


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_top = 4
	_bar.offset_bottom = TestUiTokens.height(BAR_HEIGHT)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)
	_identity = Label.new()
	_identity.text = "测试房间"
	_identity.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	_identity.clip_text = true
	_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_identity)
	_state_label = Label.new()
	_state_label.text = "运行中"
	_state_label.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	_state_label.add_theme_color_override("font_color", TestUiTokens.ACCENT_TEXT)
	row.add_child(_state_label)
	_pause_button = _button(row, "test:pause", "暂停", func(): test_command.emit("test.pause", {}))
	_button(row, "test:open_editor", "编辑器", func(): _toggle_editor())
	_button(row, "test:undo", "撤销", func(): test_command.emit("test.undo", {}))
	_button(row, "test:redo", "重做", func(): test_command.emit("test.redo", {}))
	_button(row, "test:save", "保存", func(): test_command.emit("test.save_snapshot", {}))
	_button(row, "test:close", "退出", func(): test_command.emit("test.close", {}))


func _button(parent: Node, uid: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, TestUiTokens.height(32))
	button.add_theme_font_size_override("font_size", TestUiTokens.font(14))
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons[uid] = button
	return button


func _input(event: InputEvent) -> void:
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

