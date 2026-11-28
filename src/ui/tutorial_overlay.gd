class_name UiTutorialOverlay
extends Control

## First-run teaching layer. It sits above the game page, dims everything except
## the control named by the current step and walks the player through the real
## interface. The page below is intentionally left enabled for automated
## button presses and capture tools: mouse input is blocked by this layer's
## mouse_filter, while an explicit page command closes the tutorial first.

signal finished(skipped: bool)

const SHADE := Color(0.015, 0.03, 0.04, 0.76)
const GOLD := Color("f2cf87")
const CREAM := Color("f6edd8")
const PANEL_BG := Color("1c2b34")
const PANEL_BORDER := Color("c6ad7c")
const MAX_WIDTH := 600.0
const MAX_HEIGHT := 560.0

var steps: Array = []
var step_index := 0
var anchor_provider: Callable = Callable()

var _panel: PanelContainer
var _body_scroll: ScrollContainer
var _body_column: VBoxContainer
var _body_label: Label
var _bullets: VBoxContainer
var _tip: Label
var _scroll_hint: Label
var _title: Label
var _kicker: Label
var _icon: TextureRect
var _next: Button
var _prev: Button
var _skip: Button
var _dots: Label
var _buttons: Dictionary = {}
var _shades: Array[ColorRect] = []
var _border: Panel
var _highlight := Rect2()
var _return_focus: Control
var _closed := false
var _body_min_height := 100.0


func _ready() -> void:
	name = "TutorialOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 450
	_return_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_build()
	if steps.is_empty():
		close(true)
		return
	_present_step()


func _build() -> void:
	for _index in 4:
		var shade := ColorRect.new()
		shade.color = SHADE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		_shades.append(shade)
	_border = Panel.new()
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.z_index = 2
	var border_skin := StyleBoxFlat.new()
	border_skin.bg_color = Color(0, 0, 0, 0)
	border_skin.border_color = GOLD
	border_skin.set_border_width_all(3)
	border_skin.set_corner_radius_all(9)
	border_skin.shadow_color = Color(1, 0.85, 0.52, 0.28)
	border_skin.shadow_size = 12
	_border.add_theme_stylebox_override("panel", border_skin)
	_border.hide()
	add_child(_border)
	_panel = PanelContainer.new()
	_panel.name = "TutorialPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.z_index = 3
	var skin := UiStyle.surface(PANEL_BG, PANEL_BORDER, 8)
	skin.set_content_margin_all(0)
	skin.shadow_color = Color(0, 0, 0, 0.55)
	skin.shadow_size = 24
	skin.shadow_offset = Vector2(0, 8)
	_panel.add_theme_stylebox_override("panel", skin)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 9)
	column.add_child(top)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(26, 26)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_icon)
	_kicker = Label.new()
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kicker.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	_kicker.add_theme_color_override("font_color", Color("d9bd85"))
	_kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if UiStyle.web_touch:
		_kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_kicker)
	_skip = _make_button("跳过教程", "quiet")
	_skip.name = "TutorialSkip"
	_skip.autowrap_mode = TextServer.AUTOWRAP_OFF
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_skip.custom_minimum_size = Vector2(96 * maxf(1.0, UiStyle.text_scale), _touch_height())
	_skip.pressed.connect(func(): close(true))
	top.add_child(_skip)
	_buttons["tutorial:skip"] = _skip

	_title = Label.new()
	_title.add_theme_font_override("font", UiStyle.title_font())
	_title.add_theme_font_size_override("font_size", roundi(28 * minf(UiStyle.text_scale, 1.2)))
	_title.add_theme_color_override("font_color", Color("f4d79b"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	var rule := HSeparator.new()
	rule.modulate = Color("7f8f84")
	column.add_child(rule)

	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.custom_minimum_size = Vector2(0, _body_min_height)
	_body_scroll.follow_focus = true
	_body_scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(_body_scroll)
	_body_column = VBoxContainer.new()
	_body_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_column.add_theme_constant_override("separation", 9)
	_body_scroll.add_child(_body_column)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", roundi(17 * UiStyle.text_scale))
	_body_label.add_theme_color_override("font_color", CREAM)
	_body_column.add_child(_body_label)
	_bullets = VBoxContainer.new()
	_bullets.add_theme_constant_override("separation", 9)
	_body_column.add_child(_bullets)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	_tip.add_theme_color_override("font_color", Color("dcc28d"))
	_body_column.add_child(_tip)
	_scroll_hint = Label.new()
	_scroll_hint.text = "↓ 滚动查看更多"
	_scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scroll_hint.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	_scroll_hint.add_theme_color_override("font_color", Color("d9bd85"))
	_scroll_hint.hide()
	column.add_child(_scroll_hint)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_prev = _make_button("上一步", "secondary")
	_prev.name = "TutorialPrev"
	_prev.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_prev.custom_minimum_size = Vector2(80 if UiStyle.web_touch else 128, _touch_height())
	_prev.pressed.connect(_back)
	footer.add_child(_prev)
	_buttons["tutorial:prev"] = _prev
	_dots = Label.new()
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dots.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
	_dots.add_theme_color_override("font_color", Color("d9bd85"))
	footer.add_child(_dots)
	_next = _make_button("下一步", "primary")
	_next.name = "TutorialNext"
	_next.size_flags_horizontal = Control.SIZE_SHRINK_END
	_next.custom_minimum_size = Vector2(100 if UiStyle.web_touch else 168, _touch_height())
	_next.pressed.connect(_advance)
	footer.add_child(_next)
	_buttons["tutorial:next"] = _next


func _make_button(caption: String, role: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(120, _touch_height())
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	UiStyle.button_skin(button, role, true)
	return button


func _touch_height() -> float:
	return UiStyle.MOBILE_TARGET if UiStyle.web_touch else 44.0


func _present_step() -> void:
	if steps.is_empty():
		return
	step_index = clampi(step_index, 0, steps.size() - 1)
	var step: Dictionary = steps[step_index]
	_kicker.text = "新手教程 · %s · %d / %d" % [
		str(step.get("chapter", "引导")),
		step_index + 1,
		steps.size(),
	]
	_title.text = str(step.get("title", ""))
	_body_label.text = str(step.get("body", ""))
	_body_label.visible = not _body_label.text.is_empty()
	_icon.texture = UiNavIcon.texture(str(step.get("icon", "rules")))
	for child in _bullets.get_children():
		_bullets.remove_child(child)
		child.queue_free()
	for value in step.get("bullets", []):
		if not value is Dictionary:
			continue
		var bullet: Dictionary = value
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_bullets.add_child(row)
		var dot := Label.new()
		dot.text = "◆"
		dot.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
		dot.add_theme_color_override("font_color", GOLD)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var term := Label.new()
		term.text = str(bullet.get("term", ""))
		term.custom_minimum_size.x = (76 if UiStyle.narrow_touch(size) else 108) * UiStyle.text_scale
		term.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		term.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
		term.add_theme_color_override("font_color", Color("f0d092"))
		term.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(term)
		var text := Label.new()
		text.text = str(bullet.get("text", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
		text.add_theme_color_override("font_color", CREAM)
		row.add_child(text)
	var tip := str(step.get("tip", ""))
	_tip.text = ("提示 · " + tip) if not tip.is_empty() else ""
	_tip.visible = not tip.is_empty()
	_prev.visible = step_index > 0
	_prev.disabled = step_index <= 0
	_next.text = str(step.get("next", "完成" if step_index == steps.size() - 1 else "下一步"))
	var marks: PackedStringArray = []
	for index in steps.size():
		marks.append("●" if index == step_index else "○")
	_dots.text = "  ".join(marks)
	_body_scroll.scroll_vertical = 0
	_layout()
	_layout.call_deferred()
	if is_inside_tree() and is_instance_valid(_next):
		_next.call_deferred("grab_focus")


func _process(_delta: float) -> void:
	if not visible:
		return
	_layout()
	if is_inside_tree():
		var focus := get_viewport().gui_get_focus_owner()
		if not is_instance_valid(focus) or not is_ancestor_of(focus):
			if is_instance_valid(_next):
				_next.grab_focus()


func _layout() -> void:
	if not is_instance_valid(_panel) or size.x < 1 or size.y < 1:
		return
	var target := _target_rect()
	_highlight = target
	_layout_shades(target)
	var scale := maxf(1.0, minf(UiStyle.text_scale, 1.5))
	var panel_width := minf(MAX_WIDTH + 140 * (scale - 1.0), size.x - 32.0)
	panel_width = maxf(minf(320.0, size.x - 32.0), panel_width)
	if is_instance_valid(_body_column):
		var body_width := maxf(200.0, panel_width - 54.0)
		if absf(_body_column.custom_minimum_size.x - body_width) > .5:
			_body_column.custom_minimum_size.x = body_width
	var natural := 0.0
	if is_instance_valid(_body_column):
		natural = _body_column.get_combined_minimum_size().y + 238.0
	var panel_height := clampf(
		minf(maxf(natural, 320.0), size.y - 240.0),
		minf(320.0, size.y - 32.0),
		MAX_HEIGHT
	)
	panel_height = minf(panel_height, size.y - 32.0)
	_body_min_height = maxf(90.0, panel_height - 238.0 - 30.0 * (scale - 1.0))
	if is_instance_valid(_body_scroll) and absf(_body_scroll.custom_minimum_size.y - _body_min_height) > .5:
		_body_scroll.custom_minimum_size.y = _body_min_height
	if UiStyle.web_touch:
		panel_height = minf(size.y - 24, MAX_HEIGHT if UiStyle.narrow_touch(size) else 340)
		_body_min_height = maxf(40, panel_height - 236)
		_body_scroll.custom_minimum_size.y = _body_min_height
	var panel_size := Vector2(panel_width, panel_height)
	if _panel.size != panel_size:
		_panel.size = panel_size
	var position := _panel_position(panel_size, target)
	if _panel.position != position:
		_panel.position = position
	if is_instance_valid(_scroll_hint) and is_instance_valid(_body_scroll) and is_instance_valid(_body_column):
		_scroll_hint.visible = (
			_body_column.get_combined_minimum_size().y > _body_scroll.size.y + 2.0
		)


func _panel_position(panel_size: Vector2, target: Rect2) -> Vector2:
	var margin := 16.0
	var centered := Vector2(
		(size.x - panel_size.x) * .5, (size.y - panel_size.y) * .5
	)
	if not target.has_area():
		return Vector2(
			clampf(centered.x, margin, maxf(margin, size.x - panel_size.x - margin)),
			clampf(centered.y, margin, maxf(margin, size.y - panel_size.y - margin))
		)
	var candidates := [
		Vector2((size.x - panel_size.x) * .5, size.y - panel_size.y - margin),
		Vector2((size.x - panel_size.x) * .5, margin),
		Vector2(margin, (size.y - panel_size.y) * .5),
		Vector2(size.x - panel_size.x - margin, (size.y - panel_size.y) * .5),
	]
	# Keep the panel above controls that live near the bottom edge, so the
	# tutorial never hides the very hand or end-turn control it is describing.
	if target.get_center().y > size.y * .55:
		candidates = [candidates[1], candidates[2], candidates[3], candidates[0]]
	elif target.get_center().y < size.y * .45:
		candidates = [candidates[0], candidates[2], candidates[3], candidates[1]]
	var best: Vector2 = candidates[0]
	var best_overlap := INF
	for candidate in candidates:
		var point := Vector2(
			clampf(candidate.x, margin, maxf(margin, size.x - panel_size.x - margin)),
			clampf(candidate.y, margin, maxf(margin, size.y - panel_size.y - margin))
		)
		var panel_rect := Rect2(point, panel_size)
		var overlap := 0.0
		if panel_rect.grow(10).intersects(target):
			overlap = panel_rect.intersection(target).get_area()
		if overlap < best_overlap:
			best_overlap = overlap
			best = point
		if overlap <= 0.0:
			break
	return best


func _layout_shades(target: Rect2) -> void:
	if _shades.size() != 4:
		return
	var rect := target
	if rect.has_area():
		rect = rect.intersection(Rect2(Vector2.ZERO, size))
	if not rect.has_area():
		_shades[0].position = Vector2.ZERO
		_shades[0].size = size
		for index in range(1, 4):
			_shades[index].position = Vector2.ZERO
			_shades[index].size = Vector2.ZERO
		if is_instance_valid(_border):
			_border.hide()
		return
	_shades[0].position = Vector2.ZERO
	_shades[0].size = Vector2(size.x, rect.position.y)
	_shades[1].position = Vector2(0, rect.end.y)
	_shades[1].size = Vector2(size.x, maxf(0, size.y - rect.end.y))
	_shades[2].position = Vector2(0, rect.position.y)
	_shades[2].size = Vector2(rect.position.x, rect.size.y)
	_shades[3].position = Vector2(rect.end.x, rect.position.y)
	_shades[3].size = Vector2(maxf(0, size.x - rect.end.x), rect.size.y)
	if is_instance_valid(_border):
		_border.position = rect.position
		_border.size = rect.size
		_border.show()


func _target_rect() -> Rect2:
	if steps.is_empty() or step_index < 0 or step_index >= steps.size():
		return Rect2()
	var key := str(steps[step_index].get("anchor", ""))
	if key.is_empty() or not anchor_provider.is_valid():
		return Rect2()
	var value: Variant = anchor_provider.call(key)
	if not value is Rect2:
		return Rect2()
	var rect: Rect2 = value
	if not rect.has_area():
		return Rect2()
	rect.position -= get_global_rect().position
	return rect


func _advance() -> void:
	if _closed:
		return
	if step_index >= steps.size() - 1:
		close(false)
		return
	step_index += 1
	_present_step()


func _back() -> void:
	if _closed or step_index <= 0:
		return
	step_index -= 1
	_present_step()


func _cycle_focus(direction: int) -> void:
	var focusables: Array[Control] = []
	for control in [_skip, _body_scroll, _prev, _next]:
		if is_instance_valid(control) and control.visible and not control.disabled:
			focusables.append(control)
	if focusables.is_empty():
		return
	var current := -1
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for index in focusables.size():
		if focusables[index] == owner:
			current = index
			break
	var next := (current + direction + focusables.size()) % focusables.size()
	focusables[next].grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or _closed:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			close(true)
		KEY_LEFT:
			_back()
		KEY_RIGHT:
			_advance()
		KEY_TAB:
			_cycle_focus(-1 if event.shift_pressed else 1)
		KEY_UP:
			_body_scroll.scroll_vertical = maxi(0, _body_scroll.scroll_vertical - 40)
		KEY_DOWN:
			_body_scroll.scroll_vertical = _body_scroll.scroll_vertical + 40
		KEY_PAGEUP:
			_body_scroll.scroll_vertical = maxi(0, _body_scroll.scroll_vertical - 160)
		KEY_PAGEDOWN:
			_body_scroll.scroll_vertical = _body_scroll.scroll_vertical + 160
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# The focused tutorial button receives the normal accept event.
			return
		_:
			pass
	# Swallow D / G / M / I and every other page shortcut while teaching.
	get_viewport().set_input_as_handled()


func state() -> Dictionary:
	var step: Dictionary = steps[step_index] if step_index < steps.size() else {}
	return {
		"step": step_index + 1,
		"count": steps.size(),
		"title": str(step.get("title", "")),
		"chapter": str(step.get("chapter", "")),
		"highlight": _highlight,
		"skippable": true,
	}


func highlight_rect() -> Rect2:
	return _highlight


func has_uid(uid: String) -> bool:
	return _buttons.has(uid) and is_instance_valid(_buttons[uid])


func press(uid: String) -> bool:
	if not has_uid(uid):
		return false
	var button: Button = _buttons[uid]
	if button.disabled:
		return false
	button.pressed.emit()
	return true


func close(skipped: bool) -> void:
	if _closed:
		return
	_closed = true
	visible = false
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree():
		_return_focus.grab_focus()
	finished.emit(skipped)
	queue_free()
