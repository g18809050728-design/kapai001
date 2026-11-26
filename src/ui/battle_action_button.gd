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
	var ink := UiStyle.CREAM if not disabled else Color("83949c")
	var font := get_theme_font("font")
	if kind == "focus":
		var c := Vector2(size.x * .5, size.y * .43)
		var radius := minf(size.x * .37, size.y * .38)
		draw_circle(c + Vector2(0, 5), radius + 5, Color(0, 0, 0, .5), true, -1, true)
		draw_circle(c, radius + 3, Color("15262b"), true, -1, true)
		draw_circle(c, radius, Color("7e8576"), true, -1, true)
		draw_arc(c, radius, PI * 1.05, PI * 1.93, 48, Color("ead5a6"), 3, true)
		draw_arc(c, radius - 2, .1, PI * .92, 48, Color("4c5955"), 3, true)
		draw_circle(c, radius - 5, Color("142f42") if amount > 0 else Color("283a40"), true, -1, true)
		for index in 18:
			var fraction := index / 18.0
			draw_circle(c + Vector2(-2, -3) * fraction, (radius - 7) * (1.0 - fraction), Color("347d9c") if amount > 0 else Color("3c535b"), true, -1, true)
		draw_arc(c, radius - 7, PI * 1.02, PI * 1.84, 40, Color("9bc7cc") if amount > 0 else Color("688486"), 1.5, true)
		for angle in [PI * .25, PI * .75, PI * 1.25, PI * 1.75]:
			draw_circle(c + Vector2.from_angle(angle) * (radius - 1), 2, Color("e2cca1"), true, -1, true)
		var pixels := roundi(34 * minf(UiStyle.text_scale, 1.25))
		draw_string_outline(font, c + Vector2(-radius, pixels * .31), str(amount), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, pixels, 5, Color("102934"))
		draw_string(font, c + Vector2(-radius, pixels * .31), str(amount), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, pixels, Color("f2f5e6"))
		draw_string(font, Vector2(0, size.y - 4), "专注", HORIZONTAL_ALIGNMENT_CENTER, size.x, roundi(15 * UiStyle.text_scale), Color("ede0c2"))
	else:
		var color := Color("475563") if not disabled else Color("28333e")
		draw_style_box(UiStyle.cut_surface(color.lightened(.15) if active else color,UiStyle.GOLD if active else UiStyle.BRASS),Rect2(2,2,size.x-4,size.y-4))
		var pixels := mini(roundi((size.x - 18) / maxf(4.0, text.length())), get_theme_font_size("font_size")) if UiStyle.web_touch else 20
		var baseline := Vector2(9, size.y * .5 + (font.get_ascent(pixels) - font.get_descent(pixels)) * .5) if UiStyle.web_touch else Vector2(9, size.y * .5 + 7)
		draw_string_outline(font,baseline,text,HORIZONTAL_ALIGNMENT_CENTER,size.x-18,pixels,3,Color("1d252b"))
		draw_string(font,baseline,text,HORIZONTAL_ALIGNMENT_CENTER,size.x-18,pixels,ink)
