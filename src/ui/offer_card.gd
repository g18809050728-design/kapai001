class_name UiOfferCard
extends Button

signal inspect_requested(card: UiOfferCard, immediate: bool)

var definition_id := ""
var detail: Dictionary = {}
var selected := false
var inspection_hint := "悬停查看 · I 固定详情"
var short_relic_face := false
var _face: Control
var _base_height := 0.0
var _caption: Label
var _relic := false
var _highlighted := false


func configure(id: String, data: Dictionary, caption: String, picked: bool, relic: bool = false, compact: bool = false) -> void:
	definition_id = id
	detail = data.duplicate(true)
	selected = picked
	_relic = relic
	text = caption
	var width := (160.0 if compact else 194.0) * (minf(UiStyle.text_scale, 1.15) if relic else UiStyle.text_scale)
	custom_minimum_size = Vector2(width, width * _face_ratio() + 36 * UiStyle.text_scale)
	_base_height = custom_minimum_size.y
	clip_text = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	if relic:
		_face = PanelContainer.new()
		var style := UiStyle.surface(Color("27353a"), UiStyle.GOLD if picked else Color("a19373"), 4)
		style.set_content_margin_all(10)
		style.set_border_width_all(2 if picked else 1)
		_face.add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		_face.add_child(column)
		var art := TextureRect.new()
		art.texture = UiStyle.texture(id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = (50.0 if short_relic_face else 88.0) * minf(UiStyle.text_scale, 1.25)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(art)
		var category := Label.new()
		category.text = "饰品" + (" · " + str({"white": "白色", "blue": "蓝色", "purple": "紫色", "gold": "金色"}.get(data.get("rarity", ""), "")) if data.has("rarity") else "")
		category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		category.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
		category.add_theme_color_override("font_color", Color("d6bf8b"))
		column.add_child(category)
		if not short_relic_face:
			var description := Label.new()
			description.text = UiContentText.describe_relic(data)
			description.add_theme_color_override("font_color",UiStyle.CREAM)
			description.max_lines_visible = 2
			description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			description.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
			column.add_child(description)
	else:
		var face := CardFaceView.new()
		face.configure(CardDisplayModel.from_card(data, id), picked)
		_face = face
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	_caption = Label.new()
	_caption.text = ("✓ " if picked else "") + caption
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	_caption.add_theme_color_override("font_color", UiStyle.CREAM)
	var caption_skin := UiStyle.surface(Color("293d49"), UiStyle.BRASS if picked else Color("546a74"), 3)
	caption_skin.content_margin_left = 6
	caption_skin.content_margin_right = 6
	caption_skin.content_margin_top = 4
	caption_skin.content_margin_bottom = 4
	caption_skin.shadow_size = 0
	_caption.add_theme_stylebox_override("normal", caption_skin)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	resized.connect(_fit_contents)
	_fit_contents()
	mouse_entered.connect(func(): _lift(true); inspect_requested.emit(self, false))
	mouse_exited.connect(func(): _lift(has_focus()))
	focus_entered.connect(func(): _lift(true); inspect_requested.emit(self, true))
	focus_exited.connect(func(): _lift(false))


func _face_ratio() -> float:
	if not _relic:
		return 244.0 / 168
	return .58 if short_relic_face else 1.05


func _fit_contents() -> void:
	if not is_instance_valid(_face):
		return
	var width := minf(size.x, custom_minimum_size.x)
	var height := width * _face_ratio()
	if _relic:
		height = maxf(height, _face.get_combined_minimum_size().y)
	_face.position = Vector2((size.x - width) * .5, 0)
	_face.size = Vector2(width, height)
	_caption.position = Vector2(0,height + 5)
	_caption.size = Vector2(size.x, 30 * UiStyle.text_scale)
	var caption_height := _caption.get_minimum_size().y + 8 if _caption.visible else 0.0
	custom_minimum_size.y = maxf(_base_height, height + caption_height)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_face) or not (selected or _highlighted):
		return
	var outline := UiStyle.surface(Color.TRANSPARENT, Color("ffe29a") if selected else Color("c8e8ed"), 10)
	outline.set_border_width_all(3 if selected else 2)
	outline.shadow_color = Color(UiStyle.BRASS if selected else Color("9bd4df"), .28)
	outline.shadow_size = 8 if selected else 4
	outline.shadow_offset = Vector2.ZERO
	draw_style_box(outline, _face.get_rect().grow(3))


func _lift(active: bool) -> void:
	if not is_instance_valid(_face):
		return
	var lift := -4.0 if active and not UiStyle.reduced_motion else 0.0
	_highlighted = active
	_face.position.y = lift
	_face.queue_redraw()
	z_index = 5 if active else 0
	queue_redraw()
