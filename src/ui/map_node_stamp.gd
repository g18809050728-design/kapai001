extends Button

## A native Button keeps focus/activation semantics; only its appearance is drawn.
var subtype := "N"
var map_status := "后续"
var forecast := false
var node_texture: Texture2D
var caption: Label


func configure(type: String, title: String, status: String, highlighted: bool, texture: Texture2D) -> void:
	subtype = type
	map_status = status
	forecast = highlighted
	node_texture = texture
	text = ""
	focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	caption = Label.new()
	caption.text = title
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	caption.add_theme_color_override("font_color", UiStyle.INK if status != "不可达" else UiStyle.MUTED)
	add_child(caption)
	custom_minimum_size = Vector2(76, 48 + caption.get_minimum_size().y)
	size = custom_minimum_size
	caption.position = Vector2(0, 46)
	caption.size = Vector2(size.x, caption.get_minimum_size().y)
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, toggled]:
		event.connect(func(_value = null): queue_redraw())
	queue_redraw()


func stamp_center() -> Vector2:
	return Vector2(size.x * .5, 23)


func label_rect() -> Rect2:
	var width := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
	return Rect2(Vector2((size.x - width) * .5, caption.position.y), Vector2(width, caption.size.y))


func _draw() -> void:
	var center := stamp_center()
	var current := map_status == "当前"
	var available := map_status == "可入"
	var ink := UiStyle.PAPER if current else UiStyle.INK
	var border := UiStyle.INK if current else (UiStyle.GREEN.darkened(.2) if available or forecast else UiStyle.MUTED)
	var fill := UiStyle.INK if current else UiStyle.PAPER.lerp(UiStyle.GREEN, .16 if available or forecast or is_hovered() else .04)
	draw_circle(center + Vector2(0, 2), 20, Color(UiStyle.INK, .08), true, -1, true)
	draw_circle(center, 19, fill, true, -1, true)
	if map_status == "不可达":
		for segment in 10:
			draw_arc(center, 19, segment * TAU / 10, (segment + .55) * TAU / 10, 6, border, 1, true)
	else:
		draw_circle(center, 19, border, false, 2 if available or current else 1.25, true)
	if forecast and not current:
		draw_arc(center, 22, .15, TAU - .15, 48, UiStyle.GREEN.darkened(.15), 1, true)
	if button_pressed:
		draw_circle(center, 24, UiStyle.GOLD.darkened(.18), false, 2, true)
	if has_focus():
		for segment in 12:
			draw_arc(center, 27, segment * TAU / 12, (segment + .55) * TAU / 12, 5, UiStyle.INK, 1.5, true)
	if node_texture != null:
		draw_texture_rect(node_texture, Rect2(center - Vector2(13, 13), Vector2(26, 26)), false)
	else:
		_draw_type(center, ink)
	_draw_status(center + Vector2(17, -13))


func _draw_status(point: Vector2) -> void:
	var color := UiStyle.INK if map_status == "当前" else (UiStyle.GREEN.darkened(.25) if map_status == "可入" else UiStyle.MUTED)
	draw_circle(point, 7, UiStyle.PAPER, true, -1, true)
	match map_status:
		"当前":
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(4, 0), point + Vector2(0, 5), point + Vector2(-4, 0)]), color)
		"已过":
			draw_polyline(PackedVector2Array([point + Vector2(-4, 0), point + Vector2(-1, 3), point + Vector2(4, -4)]), color, 2, true)
		"可入":
			draw_line(point + Vector2(-4, 0), point + Vector2(4, 0), color, 2, true)
			draw_polyline(PackedVector2Array([point + Vector2(0, -4), point + Vector2(4, 0), point + Vector2(0, 4)]), color, 2, true)
		"不可达":
			draw_line(point - Vector2(3, 3), point + Vector2(3, 3), color, 1.5, true)
			draw_line(point + Vector2(-3, 3), point + Vector2(3, -3), color, 1.5, true)
		_:
			draw_circle(point, 3, color, false, 1, true)


func _draw_type(center: Vector2, color: Color) -> void:
	# Each type has its own silhouette, independent of font symbol coverage.
	match subtype:
		"N", "EL":
			_stroke(center, [Vector2(-8, 8), Vector2(7, -8), Vector2(9, -9), Vector2(8, -6), Vector2(-7, 9)], color)
			_stroke(center, [Vector2(-8, -8), Vector2(8, 8)], color)
			if subtype == "EL":
				_stroke(center, [Vector2(-10, -10), Vector2(-7, -14), Vector2(-3, -10), Vector2(1, -14), Vector2(4, -10)], color)
		"B":
			_stroke(center, [Vector2(-10, -6), Vector2(-5, -2), Vector2(0, -10), Vector2(5, -2), Vector2(10, -6), Vector2(7, 7), Vector2(-7, 7), Vector2(-10, -6)], color)
			draw_line(center + Vector2(-7, 10), center + Vector2(7, 10), color, 2, true)
		"S":
			draw_rect(Rect2(center + Vector2(-8, -3), Vector2(16, 13)), color, false, 2)
			draw_arc(center + Vector2(0, -3), 5, PI, TAU, 16, color, 2, true)
		"R":
			_stroke(center, [Vector2(-9, -5), Vector2(-8, 6), Vector2(-5, 9), Vector2(4, 9), Vector2(7, 6), Vector2(8, -5), Vector2(-9, -5)], color)
			draw_arc(center + Vector2(8, 0), 4, -PI / 2, PI / 2, 14, color, 2, true)
			draw_line(center + Vector2(-3, -12), center + Vector2(-3, -8), color, 1.5, true)
		"L":
			_stroke(center, [Vector2(0, -6), Vector2(-9, -9), Vector2(-9, 7), Vector2(0, 10), Vector2(9, 7), Vector2(9, -9), Vector2(0, -6), Vector2(0, 10)], color)
		"LAB":
			_stroke(center, [Vector2(-4, -10), Vector2(4, -10), Vector2(4, -2), Vector2(10, 9), Vector2(-10, 9), Vector2(-4, -2), Vector2(-4, -10)], color)
			draw_line(center + Vector2(-6, 4), center + Vector2(6, 4), color, 2, true)
		"K":
			_stroke(center, [Vector2(-7, -9), Vector2(7, -9), Vector2(5, 3), Vector2(0, 6), Vector2(-5, 3), Vector2(-7, -9)], color)
			_stroke(center, [Vector2(-8, -6), Vector2(-11, -6), Vector2(-10, 0), Vector2(-5, 2)], color)
			_stroke(center, [Vector2(8, -6), Vector2(11, -6), Vector2(10, 0), Vector2(5, 2)], color)
			_stroke(center, [Vector2(0, 6), Vector2(0, 11), Vector2(-5, 11), Vector2(5, 11)], color)
		"C":
			for x in [-7, 7]:
				draw_circle(center + Vector2(x, -5), 3, color, false, 1.5, true)
				draw_arc(center + Vector2(x, 7), 5, PI, TAU, 12, color, 2, true)
		"T":
			_stroke(center, [Vector2(-12, -4), Vector2(0, -10), Vector2(12, -4), Vector2(0, 2), Vector2(-12, -4)], color)
			_stroke(center, [Vector2(-7, 0), Vector2(-7, 6), Vector2(0, 9), Vector2(7, 6), Vector2(7, 0)], color)
		"I":
			draw_rect(Rect2(center + Vector2(-10, -5), Vector2(20, 15)), color, false, 2)
			_stroke(center, [Vector2(-4, -5), Vector2(-4, -10), Vector2(4, -10), Vector2(4, -5)], color)
			draw_line(center + Vector2(-9, 1), center + Vector2(9, 1), color, 1.5, true)
		"ST":
			_stroke(center, [Vector2(-7, -11), Vector2(4, -11), Vector2(9, -6), Vector2(9, 11), Vector2(-7, 11), Vector2(-7, -11)], color)
			for y in [-3, 2, 7]:
				draw_line(center + Vector2(-3, y), center + Vector2(5, y), color, 1.5, true)
		_:
			_stroke(center, [Vector2(-6, -6), Vector2(-3, -10), Vector2(4, -10), Vector2(7, -6), Vector2(5, -2), Vector2(0, 1), Vector2(0, 4)], color)
			draw_circle(center + Vector2(0, 10), 1.5, color, true, -1, true)


func _stroke(center: Vector2, points: Array, color: Color) -> void:
	var line := PackedVector2Array()
	for point in points:
		line.append(center + point)
	draw_polyline(line, color, 1.8, true)
