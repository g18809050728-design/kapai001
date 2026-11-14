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
	caption.add_theme_font_override("font", UiStyle.title_font())
	caption.add_theme_color_override("font_color", Color("928468") if status == "不可达" else (Color("786d54") if status == "后续" else Color("504a39")))
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
	var ink := MapNodeGlyph.ink(subtype)
	if map_status == "不可达":
		ink.a = .40
	elif map_status == "后续":
		ink.a = .82
	if current or button_pressed or is_hovered():
		var ring := PackedVector2Array()
		for index in 65:
			var angle := TAU*index/64.0
			var radius := 24.0+sin(angle*3.0+.7)*.65
			ring.append(center+Vector2(cos(angle)*radius,sin(angle)*radius*.91))
		draw_polyline(ring,Color("8c4031") if button_pressed else Color("494535", .7),2.0 if button_pressed or current else 1.2,true)
	elif available:
		for arc_start in [-2.7, .45]:
			draw_arc(center, 24, arc_start, arc_start + 1.3, 16, Color("63553b", .8), 1.5, true)
	if has_focus():
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			var corner: Vector2 = center + direction * Vector2(29, 24)
			draw_polyline(PackedVector2Array([corner - Vector2(direction.x*5, 0),corner,corner-Vector2(0,direction.y*5)]),Color("403d30"),1.5,true)
	if node_texture != null:
		draw_texture_rect(node_texture, Rect2(center - Vector2(13, 13), Vector2(26, 26)), false)
	else:
		draw_set_transform(center, 0, Vector2.ONE * 1.2)
		_draw_type(Vector2.ZERO, ink)
		draw_set_transform(Vector2.ZERO)
	_draw_status(center + Vector2(21, 15))


func _draw_status(point: Vector2) -> void:
	if map_status not in ["当前", "已过"]:
		return
	var color := Color("8c3526") if map_status == "当前" else Color("4d5032")
	draw_circle(point, 5, Color("d6c297"), true, -1, true)
	match map_status:
		"当前":
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(4, 0), point + Vector2(0, 5), point + Vector2(-4, 0)]), color)
		"已过":
			draw_polyline(PackedVector2Array([point + Vector2(-4, 0), point + Vector2(-1, 3), point + Vector2(4, -4)]), color, 2, true)
		_:
			pass


func _draw_type(center: Vector2, color: Color) -> void:
	MapNodeGlyph.paint(self, subtype, center, color)
