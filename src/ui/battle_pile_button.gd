class_name BattlePileButton
extends Button

var kind := "deck"
var count := 0
var on_dark := true


func configure(pile_kind: String, amount: int, dark_background: bool) -> void:
	kind = pile_kind
	count = amount
	on_dark = dark_background
	text = str({"deck": "牌组", "log": "记录", "draw": "抽牌堆", "discard": "弃牌堆", "exhaust": "消耗堆"}.get(kind, kind))
	# Native Button input/focus remains intact; the paper stack supplies its visuals.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	queue_redraw()


func hover_content() -> Dictionary:
	var purpose := str({
		"deck": "查看本局全部卡牌、基础费用与效果，以及携带的饰品。快捷键 D。",
		"log": "回看已经发生的战斗事件与结算记录。快捷键 L。",
		"draw": "抽牌效果从此补充手牌。点击查看剩余卡牌，按卡牌整理，不显示实际抽取顺序。",
		"discard": "存放已弃置的卡牌。点击查看这些公开卡牌的完整费用与效果。",
		"exhaust": "存放本场已消耗的卡牌。点击查看这些公开卡牌的完整费用与效果。"
	}.get(kind, ""))
	return {
		"uid": str(get_meta("uid", "")), "title": text,
		"meta": ("%d 条已发生记录" if kind == "log" else "%d 张 · 点击查看") % count,
		"body": purpose, "detail": text + "\n\n" + purpose,
		"terms": [], "rect": get_global_rect()
	}


func _draw() -> void:
	var active := (is_hovered() or has_focus()) and not disabled
	var ink := UiStyle.INK if not disabled else UiStyle.MUTED
	var accent := UiStyle.GOLD if active else Color("78978e")
	var font := get_theme_font("font")
	var caption_size := roundi(14 * UiStyle.text_scale)
	var caption_height := font.get_height(caption_size) + 2
	var height := maxf(26, size.y - caption_height - 9)
	var width := minf(size.x - 16, height * 0.72)
	var face := Rect2((size.x - width) * 0.5 - 3, 2 if active else 4, width, height)
	for offset in [Vector2(6, 4), Vector2(3, 2), Vector2.ZERO]:
		var paper := UiStyle.box(Color("d7d4c5") if offset != Vector2.ZERO else UiStyle.PAPER)
		paper.set_corner_radius_all(3)
		paper.border_color = accent
		paper.set_border_width_all(2 if active else 1)
		draw_style_box(paper, Rect2(face.position + offset, face.size))
	var inset := minf(7, width * 0.18)
	var x := face.position.x + inset
	var line_width := width - inset * 2
	if kind == "log":
		for row in 3:
			var y := face.position.y + height * (0.3 + row * 0.2)
			draw_line(Vector2(x, y), Vector2(x + line_width, y), ink, 1.5, true)
	else:
		draw_line(Vector2(x, face.position.y + height * 0.2), Vector2(x + line_width, face.position.y + height * 0.2), accent, 1, true)
		draw_line(Vector2(x, face.end.y - height * 0.2), Vector2(x + line_width, face.end.y - height * 0.2), accent, 1, true)
		var number_size := roundi(clampf(height * 0.35, 14, 27))
		while number_size > 10 and font.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x > width - 6:
			number_size -= 1
		draw_string(font, Vector2(face.position.x, face.get_center().y + number_size * 0.35), str(count), HORIZONTAL_ALIGNMENT_CENTER, width, number_size, ink)
	var label_color := Color("f4eedf") if on_dark else UiStyle.INK
	if disabled:
		label_color.a = 0.5
	draw_string(font, Vector2(0, size.y - font.get_descent(caption_size)), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, caption_size, label_color)
