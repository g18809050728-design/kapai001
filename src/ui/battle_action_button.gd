class_name BattleActionButton
extends Button

var kind := "turn"
var amount := 0


func configure(control_kind: String, value: int = 0) -> void:
	kind = control_kind
	amount = value
	text = "可用专注 %d" % amount if kind == "focus" else "结束回合"
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var active := (is_hovered() or has_focus()) and not disabled
	var ink := UiStyle.INK if not disabled else UiStyle.MUTED
	var paper := UiStyle.box(Color("ece7d6") if disabled else UiStyle.PAPER)
	paper.border_color = UiStyle.GOLD if active else UiStyle.GREEN
	paper.set_border_width_all(2)
	paper.shadow_color = Color(0.02, 0.06, 0.07, 0.24)
	paper.shadow_size = 4
	paper.shadow_offset = Vector2(0, 3)
	draw_style_box(paper, Rect2(Vector2(3, 2), size - Vector2(6, 6)))
	var font := get_theme_font("font")
	if kind == "focus":
		var center := Vector2(size.x * 0.5, size.y * 0.34)
		draw_circle(center, 22, Color("e0e7da"))
		draw_arc(center, 22, 0, TAU, 48, UiStyle.GREEN, 1.5, true)
		draw_string(font, center + Vector2(-22, 9), str(amount), HORIZONTAL_ALIGNMENT_CENTER, 44, 27, ink)
		draw_string(font, Vector2(0, size.y - 18), "可用专注", HORIZONTAL_ALIGNMENT_CENTER, size.x, roundi(14 * UiStyle.text_scale), ink)
	else:
		var center := Vector2(size.x - 24, size.y * 0.5)
		draw_arc(center, 10, -.8, 4.7, 32, UiStyle.GREEN, 1.7, true)
		draw_polyline(PackedVector2Array([center + Vector2(3, -14), center + Vector2(8, -7), center + Vector2(1, -5)]), UiStyle.GREEN, 1.7, true)
		draw_string(font, Vector2(10, size.y * 0.5 + 6), "结束回合", HORIZONTAL_ALIGNMENT_CENTER, size.x - 46, roundi(16 * UiStyle.text_scale), ink)
