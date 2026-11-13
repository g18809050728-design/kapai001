class_name UiOfferCard
extends Button

signal inspect_requested(card: UiOfferCard, immediate: bool)

var definition_id := ""
var detail: Dictionary = {}
var selected := false
var inspection_hint := "悬停查看 · I 固定详情"
var _face: Control
var _base_height := 0.0
var _caption: Label
var _relic := false


func configure(id: String, data: Dictionary, caption: String, picked: bool, relic: bool = false, compact: bool = false) -> void:
	definition_id = id
	detail = data.duplicate(true)
	selected = picked
	_relic = relic
	text = caption
	var width := (160.0 if compact else 194.0) * UiStyle.text_scale
	custom_minimum_size = Vector2(width, width * 244 / 168 + 24 * UiStyle.text_scale)
	_base_height = custom_minimum_size.y
	clip_text = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	if relic:
		_face = PanelContainer.new()
		var style := UiStyle.box(Color("fffbef"))
		style.border_color = UiStyle.GOLD if picked else UiStyle.GREEN
		style.set_border_width_all(2)
		_face.add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		_face.add_child(column)
		var art := TextureRect.new()
		art.texture = UiStyle.texture(id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = 110
		column.add_child(art)
		var description := Label.new()
		description.text = UiContentText.describe_relic(data)
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
	_caption.add_theme_font_size_override("font_size", roundi(13 * UiStyle.text_scale))
	_caption.add_theme_color_override("font_color", UiStyle.INK)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	resized.connect(_fit_contents)
	_fit_contents()
	mouse_entered.connect(func(): _lift(true); inspect_requested.emit(self, false))
	mouse_exited.connect(func(): _lift(has_focus()))
	focus_entered.connect(func(): _lift(true); inspect_requested.emit(self, true))
	focus_exited.connect(func(): _lift(false))


func _fit_contents() -> void:
	if not is_instance_valid(_face):
		return
	var width := minf(size.x, custom_minimum_size.x)
	var height := width * 244 / 168
	_face.position = Vector2((size.x - width) * .5, 0)
	_face.size = Vector2(width, height)
	_caption.position = Vector2(0,height + 5)
	_caption.size = Vector2(size.x, 28 * UiStyle.text_scale)
	custom_minimum_size.y = maxf(_base_height, height + _caption.get_minimum_size().y + 8)


func _lift(active: bool) -> void:
	if not is_instance_valid(_face):
		return
	var lift := -4.0 if active and not UiStyle.reduced_motion else 0.0
	_face.position.y = lift
	_face.queue_redraw()
	z_index = 5 if active else 0
