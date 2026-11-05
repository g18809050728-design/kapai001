class_name UiPage
extends Control

signal action_requested(draft: Dictionary)
signal local_selection_changed(selection: Dictionary)

var view: Dictionary = {}
var audio: AudioManager
var body: VBoxContainer
var _buttons: Dictionary = {}
var _drafts: Dictionary = {}
var _last_action: Dictionary = {}
var _scroll: ScrollContainer
var _scroll_scope := ""
var _scroll_position := Vector2i.ZERO
var _scroll_restore_pending := false
var _render_generation := 0
var header: VBoxContainer
var footer: VBoxContainer
var _preview_card: UiOfferCard
var _card_preview: PanelContainer
var _preview_delay := 0.0
var _preview_leave_delay := 0.0
var _preview_pinned := false
var _preview_focus: Control
var _preview_focus_modes: Dictionary = {}
var _restoring_preview_focus := false


func render(data: Dictionary) -> void:
	view = data.duplicate(true)
	reset_page("")


func reset_page(title: String, subtitle: String = "", compact: bool = false) -> VBoxContainer:
	close_card_preview()
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
	header = VBoxContainer.new()
	header.name = "FixedHeader"
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 14
	header.offset_right = -14
	footer = VBoxContainer.new()
	footer.name = "FixedActions"
	footer.add_theme_constant_override("separation", 6)
	add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 14
	footer.offset_right = -14
	header.minimum_size_changed.connect(_layout_regions)
	footer.minimum_size_changed.connect(_layout_regions)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8 if compact else 16)
	margin.add_child(body)
	if not title.is_empty():
		add_text(header, title, 25)
	if not subtitle.is_empty():
		add_text(header, subtitle, 14, UiStyle.MUTED)
	_layout_regions.call_deferred()
	_restore_scroll.call_deferred(_render_generation)
	return body


func _layout_regions() -> void:
	if not is_instance_valid(header) or not is_instance_valid(footer):
		return
	var top := header.get_combined_minimum_size().y + 10
	var bottom := footer.get_combined_minimum_size().y + 12
	header.offset_top = 4
	header.offset_bottom = top
	footer.offset_top = -bottom
	footer.offset_bottom = -4
	_scroll.offset_top = top + 4
	_scroll.offset_bottom = -bottom - 6


func _restore_scroll(generation: int, frames_left: int = 2) -> void:
	# Container sizing spans frames; restoring earlier clamps the offset to zero.
	if not is_inside_tree():
		return
	if frames_left > 0:
		get_tree().create_timer(0.0).timeout.connect(_restore_scroll.bind(generation, frames_left - 1), CONNECT_ONE_SHOT)
		return
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
	button.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	button.set_meta("uid", uid)
	var source_run := str(view.get("run_id", ""))
	var source_revision := int(view.get("revision", -1))
	parent.add_child(button)
	_buttons[uid] = button
	if draft is Callable or (draft is Dictionary and not draft.is_empty()):
		_drafts[uid] = draft
	button.pressed.connect(
		func():
			if button.disabled:
				return
			if audio != null:
				audio.play_ui("ui_click")
			if local_callback.is_valid():
				local_callback.call()
			if _drafts.has(uid):
				_last_action = action_draft(uid)
				if not _last_action.is_empty():
					_last_action["source_run_id"] = source_run
					_last_action["source_revision"] = source_revision
					action_requested.emit(_last_action.duplicate(true))
	)
	return button


func add_text(
	parent: Node, value: String, font_size: int = 18, color: Color = UiStyle.INK
) -> Label:
	var label_node := Label.new()
	label_node.text = value
	label_node.add_theme_font_size_override("font_size", roundi(font_size * UiStyle.text_scale))
	label_node.add_theme_color_override("font_color", color)
	label_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label_node)
	return label_node


func add_card(parent: Node, uid: String, id: String, detail: Dictionary, caption: String, picked: bool, callback: Callable, relic: bool = false) -> UiOfferCard:
	var card := UiOfferCard.new()
	card.configure(id, detail, caption, picked, relic, size.y < 580 or bool(get_meta("compact_cards", false)))
	card.set_meta("uid", uid)
	parent.add_child(card)
	_buttons[uid] = card
	card.pressed.connect(callback)
	card.inspect_requested.connect(func(value: UiOfferCard, immediate: bool):
		if _preview_pinned or _restoring_preview_focus:
			return
		if not immediate and is_instance_valid(_card_preview) and _card_preview.get_global_rect().grow(8).has_point(get_global_mouse_position()):
			# The small bridge into interactive details may cross a grid edge.
			# Keep the current text while the pointer enters the popup.
			return
		if _preview_card != value:
			close_card_preview()
		_preview_card = value
		_preview_delay = 0.0 if immediate else 0.25
		_preview_leave_delay = 0.0
		if immediate:
			_show_card_preview(false))
	return card


func _process(delta: float) -> void:
	if _preview_pinned or not is_instance_valid(_preview_card):
		return
	var point := get_global_mouse_position()
	var over := _preview_card.get_global_rect().has_point(point) or _preview_card.has_focus()
	if is_instance_valid(_card_preview):
		over = over or _card_preview.get_global_rect().has_point(point)
	if not over:
		# Allow the pointer to cross the small gap into the scrollable details.
		_preview_leave_delay += delta
		if _preview_leave_delay >= 0.18:
			close_card_preview()
		return
	_preview_leave_delay = 0.0
	if _preview_delay > 0:
		_preview_delay -= delta
	if _preview_delay <= 0 and not is_instance_valid(_card_preview):
		_show_card_preview(false)


func _show_card_preview(pinned: bool) -> void:
	if not is_instance_valid(_preview_card):
		return
	if is_instance_valid(_card_preview):
		_card_preview.queue_free()
	_preview_pinned = pinned
	_card_preview = PanelContainer.new()
	_card_preview.name = "CardDetails"
	_card_preview.z_index = 400
	var preview_style := UiStyle.box(Color("fffbef"))
	preview_style.border_color = UiStyle.GREEN
	preview_style.set_border_width_all(1)
	preview_style.shadow_color = Color(0.02, 0.06, 0.07, .18)
	preview_style.shadow_size = 8
	_card_preview.add_theme_stylebox_override("panel", preview_style)
	var width := minf(380 * minf(UiStyle.text_scale, 1.2), size.x - 28)
	var content_rect := Rect2(_scroll.position, _scroll.size) if is_instance_valid(_scroll) else Rect2(Vector2(16, 110), size - Vector2(32, 170))
	var height := minf(360 * UiStyle.text_scale, maxf(180, content_rect.size.y))
	var card_rect := _preview_card.get_global_rect()
	var x := card_rect.end.x - global_position.x + 8
	if x + width > size.x - 12:
		x = card_rect.position.x - global_position.x - width - 8
	_card_preview.position = Vector2(clampf(x, 12, maxf(12, size.x - width - 12)), content_rect.position.y + 4)
	_card_preview.size = Vector2(width, height)
	add_child(_card_preview)
	var column := VBoxContainer.new()
	_card_preview.add_child(column)
	add_text(column, _preview_card.text, 20)
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(text_column)
	var detail := _preview_card.detail
	add_text(text_column, UiContentText.describe_relic(detail) if detail.has("campaign") or detail.has("hooks") else UiContentText.describe_card(detail), 16)
	add_text(text_column, UiContentText.keyword_help(detail), 14, UiStyle.MUTED)
	var controls := add_row(column)
	var pin := add_button(controls, "card:pin", "关闭 · Esc" if pinned else "固定 · I", {}, close_card_preview if pinned else func(): _show_card_preview(true))
	if pinned:
		_preview_focus = get_viewport().gui_get_focus_owner()
		for control in find_children("*", "Control", true, false):
			if not _card_preview.is_ancestor_of(control) and control.focus_mode != Control.FOCUS_NONE:
				_preview_focus_modes[control] = control.focus_mode
				control.focus_mode = Control.FOCUS_NONE
		pin.grab_focus()
	_place_card_preview(weakref(_card_preview), 0)
	_place_card_preview.call_deferred(weakref(_card_preview))


func _place_card_preview(panel_ref: WeakRef, frames_left: int = 3) -> void:
	var panel := panel_ref.get_ref() as PanelContainer
	if not is_inside_tree() or not is_instance_valid(panel) or panel != _card_preview or not is_instance_valid(_preview_card):
		return
	if frames_left > 0:
		get_tree().create_timer(0).timeout.connect(_place_card_preview.bind(panel_ref, frames_left - 1), CONNECT_ONE_SHOT)
		return
	# Focus can arrive during page rebuilding, before the fixed header is laid out.
	# Place the popup using the settled content region, never its temporary offsets.
	var content := Rect2(_scroll.position, _scroll.size) if is_instance_valid(_scroll) else Rect2(Vector2(16, 110), size - Vector2(32, 170))
	var width := minf(380 * minf(UiStyle.text_scale, 1.2), size.x - 28)
	var height := minf(minf(360 * UiStyle.text_scale, maxf(160, content.size.y - 8)), size.y - 28)
	var card := _preview_card.get_global_rect()
	var x := card.end.x - global_position.x + 8
	if x + width > size.x - 12:
		x = card.position.x - global_position.x - width - 8
	if not _preview_pinned:
		# Keep hover details outside the whole candidate grid, so moving to the
		# next card never requires dismissing a popup first. Pinned details can
		# use the full reading width and deliberately own input until closed.
		var left := size.x
		var right := 0.0
		for candidate in _buttons.values():
			if candidate is UiOfferCard and candidate.is_visible_in_tree():
				var bounds: Rect2 = candidate.get_global_rect()
				if bounds.intersects(Rect2(global_position + content.position, content.size)):
					left = minf(left, bounds.position.x - global_position.x)
					right = maxf(right, bounds.end.x - global_position.x)
		var left_space := left - 20
		var right_space := size.x - right - 20
		var use_right := right_space >= left_space
		width = minf(width, maxf(160 * minf(UiStyle.text_scale, 1.2), right_space if use_right else left_space))
		x = size.x - width - 12 if use_right else 12.0
	panel.size = Vector2(width, height)
	panel.position = Vector2(clampf(x, 12, maxf(12, size.x - width - 12)), clampf(content.position.y + 4, 12, maxf(12, size.y - height - 12)))


func close_card_preview() -> void:
	if is_instance_valid(_card_preview):
		remove_child(_card_preview)
		_card_preview.queue_free()
	_card_preview = null
	_buttons.erase("card:pin")
	_preview_card = null
	_preview_pinned = false
	for control in _preview_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _preview_focus_modes[control]
	_preview_focus_modes.clear()
	if is_instance_valid(_preview_focus) and _preview_focus.is_inside_tree():
		_restoring_preview_focus = true
		_preview_focus.grab_focus()
		_restoring_preview_focus = false
	_preview_focus = null


func add_art(parent: Node, id: String, art_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = UiStyle.texture(id)
	art.set_meta("art_id", id)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
