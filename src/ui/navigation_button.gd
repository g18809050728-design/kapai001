class_name UiNavigationButton
extends Button


func configure(kind: String, caption: String, amount: int = -1) -> void:
	set_meta("nav_icon", kind)
	set_meta("nav_count", amount)
	text = caption
	icon = UiNavIcon.primary_texture(kind)
	expand_icon = true
	custom_minimum_size = Vector2(64, 56)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	autowrap_mode = TextServer.AUTOWRAP_OFF
	add_theme_constant_override("icon_max_width", 1)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color", "font_outline_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color", "icon_focus_color", "icon_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		event.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	paint(self)


static func paint(button: Button) -> void:
	var selected := bool(button.get_meta("nav_active", false))
	var hovered := button.is_hovered() and not button.disabled
	var focused := button.has_focus() and not button.disabled
	var bounds := Rect2(Vector2(3, 1), button.size - Vector2(6, 2))
	if selected or hovered or focused:
		var surface := UiStyle.surface(Color("435766") if hovered else Color("354754"), Color("d7bd89") if focused else Color("6c7c7c"), 4)
		surface.shadow_size = 0
		button.draw_style_box(surface, bounds)
	var tint := Color("8b9699") if button.disabled else Color.WHITE
	var texture := UiNavIcon.primary_texture(str(button.get_meta("nav_icon", "map")))
	button.draw_texture_rect(texture, Rect2(Vector2(button.size.x * .5 - 17, 2), Vector2(34, 34)), false, tint)
	var font := button.get_theme_font("font")
	var pixels := roundi(12 * UiStyle.text_scale)
	var ink := Color("899597") if button.disabled else UiStyle.CREAM
	button.draw_string(font, Vector2(0, button.size.y - 5), button.text, HORIZONTAL_ALIGNMENT_CENTER, button.size.x, pixels, ink)
	var count := int(button.get_meta("nav_count", -1))
	if count >= 0:
		var badge := Vector2(button.size.x * .5 + 16, 27)
		button.draw_circle(badge, 11, Color("1d303d"), true, -1, true)
		button.draw_circle(badge, 11, Color("ab9b78") if not button.disabled else Color("657479"), false, 1, true)
		button.draw_string(font, badge + Vector2(-14, 5), str(count), HORIZONTAL_ALIGNMENT_CENTER, 28, 13, ink)
	if selected:
		button.draw_line(Vector2(13, button.size.y - 1), Vector2(button.size.x - 13, button.size.y - 1), UiStyle.GOLD, 2, true)
