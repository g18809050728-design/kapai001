class_name UiRelicSlotButton
extends Button

var entry: Dictionary = {}
var slot := 0


func configure(relic: Dictionary, position_index: int) -> void:
	entry = relic.duplicate(true)
	slot = position_index
	custom_minimum_size = Vector2(44, 48)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	var title := UiStyle.label(str(relic.get("definition_id", ""))) if not relic.is_empty() else "空槽%d" % (slot + 1)
	text = ""
	autowrap_mode = TextServer.AUTOWRAP_OFF
	tooltip_text = ("槽%d · %s\n%s\n点击查看完整效果" % [slot + 1, title, UiContentText.describe_relic(relic.get("detail", {}))]) if not relic.is_empty() else "空槽%d · 点击查看装备和获取说明" % (slot + 1)
	for signal_value in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		signal_value.connect(queue_redraw)


func _draw() -> void:
	var active := (is_hovered() or has_focus()) and not disabled
	var border := Color("dfc48b") if active else Color("78847e")
	var skin := UiStyle.surface(Color("23323a"), border, 3)
	skin.shadow_size = 0
	draw_style_box(skin, Rect2(1, 5, size.x - 2, size.y - 10))
	var texture := UiStyle.texture(str(entry.get("definition_id", ""))) if not entry.is_empty() else null
	if texture != null:
		draw_texture_rect(texture, Rect2(4, 9, size.x - 8, size.y - 18), false, Color("9bada9") if disabled else Color.WHITE)
	else:
		draw_texture_rect(UiNavIcon.texture("relics"), Rect2(size.x * .5 - 10, size.y * .5 - 10, 20, 20), false, Color("697770"))
	if has_focus() and not disabled:
		draw_line(Vector2(4, size.y - 3), Vector2(size.x - 4, size.y - 3), Color("f1d59f"), 2, true)
