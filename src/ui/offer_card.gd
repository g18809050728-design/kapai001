class_name UiOfferCard
extends Button

signal inspect_requested(card: UiOfferCard, immediate: bool)

var definition_id := ""
var detail: Dictionary = {}
var selected := false
var _face: PanelContainer
var _base_height := 0.0


func configure(id: String, data: Dictionary, caption: String, picked: bool, relic: bool = false, compact: bool = false) -> void:
	definition_id = id
	detail = data.duplicate(true)
	selected = picked
	text = caption
	custom_minimum_size = Vector2(184, 218) if compact else Vector2(208, 286)
	custom_minimum_size.y += 100 * maxf(0, UiStyle.text_scale - 1)
	var caption_lines := ceili(caption.length() * 18.0 * UiStyle.text_scale / (custom_minimum_size.x - 24))
	custom_minimum_size.y += maxi(0, caption_lines - 1) * 24 * UiStyle.text_scale
	_base_height = custom_minimum_size.y
	clip_text = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)
	add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	_face = PanelContainer.new()
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.box(Color("fffbef"))
	style.border_color = UiStyle.GOLD if picked else Color("a9b9aa")
	style.set_border_width_all(3)
	style.shadow_color = Color(0.08, 0.16, 0.16, 0.17)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_face.add_theme_stylebox_override("panel", style)
	add_child(_face)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	_face.add_child(column)
	var metadata := "饰品" if relic else "专注 %s · %s" % [data.get("cost", "—"), UiStyle.label(str(data.get("type", "")))]
	if not relic and int(data.get("vitality_cost", 0)) > 0:
		metadata += " · 精力%s" % data.vitality_cost
	if int(data.get("upgrade_level", 0)) > 0:
		metadata += " · 升级+%s" % data.upgrade_level
	_label(column, ("✓ " if picked else "") + metadata, 13, UiStyle.MUTED)
	if not str(data.get("rarity", "")).is_empty():
		_label(column, UiStyle.label(str(data.rarity)), 12, UiStyle.MUTED)
	var art := TextureRect.new()
	art.texture = UiStyle.texture(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 94 if compact else 144
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art)
	if art.texture == null:
		var placeholder := _label(art, "暂无插画 · 可查看规则", 12, UiStyle.MUTED)
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label(column, caption, 18, UiStyle.INK)
	_label(column, "悬停 / 聚焦看说明 · 点击预选", 12, UiStyle.MUTED)
	# The face is a visual child, so Button does not inherit its wrapped minimum.
	# Wait for the real width before fitting; a zero-width column overestimates it.
	resized.connect(_queue_content_fit)
	_queue_content_fit()
	mouse_entered.connect(func(): _lift(true); inspect_requested.emit(self, false))
	mouse_exited.connect(func(): _lift(has_focus()))
	focus_entered.connect(func(): _lift(true); inspect_requested.emit(self, true))
	focus_exited.connect(func(): _lift(false))


func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", roundi(font_size * UiStyle.text_scale))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _queue_content_fit() -> void:
	if is_inside_tree():
		get_tree().create_timer(0).timeout.connect(_fit_contents, CONNECT_ONE_SHOT)


func _fit_contents() -> void:
	if not is_instance_valid(_face) or size.x < custom_minimum_size.x:
		return
	custom_minimum_size.y = maxf(_base_height, _face.get_combined_minimum_size().y)


func _lift(active: bool) -> void:
	if not is_instance_valid(_face):
		return
	# Only the artwork moves; the button hit area and keyboard focus stay stable.
	# Focus may arrive while the new face is still at its zero-width minimum.
	# Moving position preserves that temporary height in offset_bottom (968px).
	# Set both anchored offsets explicitly so focus can never capture that size.
	var lift := -6.0 if active and not UiStyle.reduced_motion else 0.0
	_face.offset_top = lift
	_face.offset_bottom = lift
	z_index = 5 if active else 0
