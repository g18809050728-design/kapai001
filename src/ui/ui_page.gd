class_name UiPage
extends Control

signal action_requested(draft: Dictionary)
signal local_selection_changed(selection: Dictionary)

var view: Dictionary = {}
var body: VBoxContainer
var _buttons: Dictionary = {}
var _drafts: Dictionary = {}
var _last_action: Dictionary = {}
var _scroll: ScrollContainer
var _scroll_scope := ""
var _scroll_position := Vector2i.ZERO
var _scroll_restore_pending := false
var _render_generation := 0


func render(data: Dictionary) -> void:
	view = data.duplicate(true)
	reset_page("")


func reset_page(title: String, subtitle: String = "", compact: bool = false) -> VBoxContainer:
	var scope := "%s|%s|%s" % [title, view.get("run_id", ""), view.get("current_node_id", "")]
	if scope != _scroll_scope:
		_scroll_position = Vector2i.ZERO
	elif is_instance_valid(_scroll) and not _scroll_restore_pending:
		_scroll_position = Vector2i(_scroll.scroll_horizontal, _scroll.scroll_vertical)
	_scroll_scope = scope
	_scroll_restore_pending = true
	_render_generation += 1
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_drafts.clear()
	_last_action.clear()
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if compact else 24)
	scroll.add_child(margin)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8 if compact else 16)
	margin.add_child(body)
	if not title.is_empty():
		add_text(body, title, 30)
	if not subtitle.is_empty():
		add_text(body, subtitle, 17, UiStyle.MUTED)
	_restore_scroll.call_deferred(_render_generation)
	return body


func _restore_scroll(generation: int) -> void:
	# Container sizing spans frames; restoring earlier clamps the offset to zero.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _render_generation or not is_instance_valid(_scroll):
		return
	_scroll.scroll_horizontal = _scroll_position.x
	_scroll.scroll_vertical = _scroll_position.y
	_scroll_restore_pending = false


func add_button(
	parent: Node,
	uid: String,
	caption: String,
	draft: Variant = {},
	local_callback: Callable = Callable()
) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(120, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.set_meta("uid", uid)
	parent.add_child(button)
	_buttons[uid] = button
	if draft is Callable or (draft is Dictionary and not draft.is_empty()):
		_drafts[uid] = draft
	button.pressed.connect(
		func():
			if button.disabled:
				return
			if local_callback.is_valid():
				local_callback.call()
			if _drafts.has(uid):
				_last_action = action_draft(uid)
				if not _last_action.is_empty():
					action_requested.emit(_last_action.duplicate(true))
	)
	return button


func add_text(
	parent: Node, value: String, font_size: int = 18, color: Color = UiStyle.INK
) -> Label:
	var label_node := Label.new()
	label_node.text = value
	label_node.add_theme_font_size_override("font_size", font_size)
	label_node.add_theme_color_override("font_color", color)
	label_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label_node)
	return label_node


func add_art(parent: Node, id: String, art_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = UiStyle.texture(id)
	art.custom_minimum_size = art_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(art)
	return art


func add_row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row


func add_panel(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return column


func build_action() -> Dictionary:
	return _last_action.duplicate(true)


func press(uid: String) -> bool:
	if not _buttons.has(uid) or _buttons[uid].disabled:
		return false
	_buttons[uid].pressed.emit()
	return true


func button_uids() -> Array:
	return _buttons.keys()


func action_uids() -> Array:
	var result: Array = []
	for uid in _drafts:
		var draft := action_draft(uid)
		if not draft.is_empty() and not str(draft.get("type", "")).begins_with("ui."):
			result.append(uid)
	return result


func action_draft(uid: String) -> Dictionary:
	var value: Variant = _drafts.get(uid, {})
	if value is Callable:
		value = value.call()
	return value.duplicate(true) if value is Dictionary else {}


func apply_gating(results: Dictionary) -> void:
	for uid in results:
		if _buttons.has(uid):
			_buttons[uid].disabled = not results[uid].get("ok", false)
			_buttons[uid].tooltip_text = str(results[uid].get("reason", ""))


func button_disabled(uid: String) -> bool:
	return not _buttons.has(uid) or _buttons[uid].disabled


func button_reason(uid: String) -> String:
	return str(_buttons[uid].tooltip_text) if _buttons.has(uid) else "按钮不存在"


func button_text(uid: String) -> String:
	return str(_buttons[uid].text) if _buttons.has(uid) else ""
