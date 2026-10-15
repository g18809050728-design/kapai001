class_name BattleCard
extends Button

const FACE_SIZE := Vector2(168, 244)
var card_data: Dictionary = {}
var selected: bool = false
var highlighted: bool = false
var home_position := Vector2.ZERO
var home_rotation: float = 0.0
var home_order: int = 0
var accent := Color("739d95")


func configure(data: Dictionary, is_selected: bool = false) -> void:
	card_data = data.duplicate(true)
	selected = is_selected
	size = FACE_SIZE
	custom_minimum_size = FACE_SIZE
	pivot_offset = FACE_SIZE * 0.5
	text = UiStyle.label(str(data.get("definition_id", "")))
	var face: Dictionary = data.get("face", data.get("effective_card", {}))
	var kind := str(face.get("type", face.get("card_type", "work")))
	accent = (
		{
			"strategy": Color("6989a1"),
			"cooperation": Color("7c9d74"),
			"scene": Color("b49765"),
			"burden": Color("a26767")
		}
		. get(kind, Color("739d95"))
	)
	queue_redraw()


func _draw() -> void:
	var border := Color("f1cf83") if selected or highlighted else accent
	if disabled:
		border = Color("69716e")
	var shadow := UiStyle.box(Color(0.02, 0.06, 0.07, 0.5))
	draw_style_box(shadow, Rect2(Vector2(4, 7), FACE_SIZE))
	var outer := UiStyle.box(Color("182e35"))
	outer.border_color = border
	outer.set_border_width_all(3 if selected or highlighted else 2)
	draw_style_box(outer, Rect2(Vector2.ZERO, FACE_SIZE))
	var inner := UiStyle.box(Color("f3eddd"))
	draw_style_box(inner, Rect2(7, 7, 154, 230))
	var art := UiStyle.texture(str(card_data.get("definition_id", "")))
	if art != null:
		# Crop to fill; the source remains a solid-background illustration.
		var source := Rect2(Vector2.ZERO, art.get_size())
		var ratio := 148.0 / 96.0
		if source.size.x / source.size.y > ratio:
			var crop := source.size.y * ratio
			source.position.x = (source.size.x - crop) * 0.5
			source.size.x = crop
		else:
			var crop := source.size.x / ratio
			source.position.y = (source.size.y - crop) * 0.5
			source.size.y = crop
		draw_texture_rect_region(art, Rect2(10, 39, 148, 96), source)
	draw_rect(Rect2(10, 132, 148, 3), accent)
	var font := get_theme_font("font")
	var name_text := UiStyle.label(str(card_data.get("definition_id", "")))
	name_text = name_text.split("：")[0]
	draw_string(font, Vector2(39, 28), name_text, HORIZONTAL_ALIGNMENT_CENTER, 116, 16, UiStyle.INK)
	draw_circle(Vector2(21, 22), 19, Color("243e4a"))
	draw_arc(Vector2(21, 22), 19, 0, TAU, 40, border, 2, true)
	draw_string(
		font,
		Vector2(3, 29),
		str(card_data.get("effective_cost", "—")),
		HORIZONTAL_ALIGNMENT_CENTER,
		36,
		22,
		Color("fff2d5")
	)
	var face: Dictionary = card_data.get("face", card_data.get("effective_card", {}))
	var effect := UiStyle.describe_effects(face.get("effects", []))
	if effect.is_empty():
		effect = str(card_data.get("description", ""))
	var lines := TextParagraph.new()
	lines.add_string(effect, font, 14)
	lines.width = 136
	lines.alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	lines.max_lines_visible = 4
	lines.draw(get_canvas_item(), Vector2(16, 145), UiStyle.INK)
	draw_line(Vector2(16, 216), Vector2(152, 216), Color("d5ceba"))
	var cost_text := (
		(
			"专注 %s  ·  精力 %s"
			% [card_data.get("effective_cost", 0), card_data.get("effective_vitality_cost", 0)]
		)
		if card_data.has("effective_cost")
		else "效果候选"
	)
	draw_string(
		font, Vector2(12, 233), cost_text, HORIZONTAL_ALIGNMENT_CENTER, 144, 12, UiStyle.MUTED
	)
	if disabled:
		draw_style_box(UiStyle.box(Color(0.09, 0.14, 0.15, 0.3)), Rect2(Vector2.ZERO, FACE_SIZE))
	if selected:
		draw_circle(Vector2(148, 21), 10, Color("e3b96c"))
		draw_string(font, Vector2(138, 26), "✓", HORIZONTAL_ALIGNMENT_CENTER, 20, 14, UiStyle.INK)


func contains_global(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(
		get_global_transform_with_canvas().affine_inverse() * point
	)


func contains_home(point: Vector2) -> bool:
	var local: Vector2 = get_parent().get_global_transform_with_canvas().affine_inverse() * point
	var transform := Transform2D(home_rotation, home_position + pivot_offset)
	return Rect2(-pivot_offset, size).has_point(transform.affine_inverse() * local)
