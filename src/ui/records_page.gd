extends UiPage

const MUTED := Color("a2b0ad")
const LINE := Color("c6ad7e", .25)
const REASONS := {"deadline_expired": "DDL 已到期", "vitality_depleted": "精力耗尽", "battle_lost": "战斗失败", "first_term_completed": "第一学期已完成", "four_years_completed": "四学年已完成", "graduated": "已毕业", "player_abandoned": "主动结束冒险", "abandoned": "主动结束冒险"}

class ArchiveMark:
	extends Control
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var center := size * .5
		var radius := minf(size.x, size.y) * .46
		draw_circle(center, radius, Color("b6a47d", .06))
		draw_arc(center, radius, 0, TAU, 64, Color("b6a47d", .18), 1, true)
		var scale := radius / 30.0
		var points := PackedVector2Array([Vector2(-20,-12),Vector2(-9,-15),Vector2(0,-11),Vector2(9,-15),Vector2(20,-12),Vector2(20,15),Vector2(9,12),Vector2(0,16),Vector2(-9,12),Vector2(-20,15),Vector2(-20,-12)])
		for index in points.size():
			points[index] = center + points[index] * scale
		draw_polyline(points, Color("d0bb90"), 1.5, true)
		draw_line(center + Vector2(0,-11)*scale,center + Vector2(0,16)*scale,Color("d0bb90"),1.5,true)
		for y in [-5, 1, 7]:
			draw_line(center + Vector2(-15,y)*scale,center + Vector2(-6,y-1)*scale,Color("b1a181",.65),1,true)
			draw_line(center + Vector2(6,y-1)*scale,center + Vector2(15,y)*scale,Color("b1a181",.65),1,true)

var _compact := false
var _resize_pending := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and not view.is_empty() and not _resize_pending:
		_resize_pending = true
		_reflow.call_deferred()

func _reflow() -> void:
	_resize_pending = false
	if is_inside_tree() and _compact != (size.y < 550 or size.x < 760):
		render(view)

func render(data: Dictionary) -> void:
	var offset := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
	view = data.duplicate(true)
	_compact = size.y < 550 or size.x < 760
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_drafts.clear()
	var scene := RoomSceneView.new()
	scene.room = "settings"
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene)
	var shade := TextureRect.new()
	shade.texture = UiStyle.gradient(Color("101c22", .94), Color("142329", .86))
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24 if _compact else clampi(roundi(size.x * .075), 40, 100))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14 if _compact else 38)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12 if _compact else 22)
	margin.add_child(column)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 20)
	header.add_child(heading)
	var title := _text(heading, "游戏记录", 26 if _compact else 38, UiStyle.CREAM, true)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if view.get("account_state", "") == "ready":
		var cloud := add_button(heading, "records:cloud", "账号对局  ↗", {"type":"ui.web_history", "payload":{}})
		_skin(cloud)
		cloud.size_flags_horizontal = Control.SIZE_SHRINK_END
		cloud.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cloud.custom_minimum_size.x = 140 * minf(UiStyle.text_scale, 1.3)
	if not _compact:
		_text(header, "每次出发，都在这里留下足迹。", 16, MUTED)
	var records: Array = view.get("records", [])
	var wins := 0
	var furthest := 0
	for record in records:
		wins += 1 if record.get("result", "") == "won" else 0
		furthest = maxi(furthest, int(record.get("term", 0)))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24 if _compact else 38)
	header.add_child(stats)
	for value in ["已结算  %d" % records.size(), "胜利  %d" % wins, "最远  " + ("第 %d 学年" % furthest if furthest > 0 else "—")]:
		var label := _text(stats, value, 13 if _compact else 15, Color("c6bda8"))
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var panel := PanelContainer.new()
	panel.name = "RecordsPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var skin := UiStyle.surface(Color("122329", .80), LINE, 10)
	skin.set_content_margin_all(14 if _compact else 28)
	skin.shadow_size = 16
	skin.shadow_color = Color(0,0,0,.18)
	panel.add_theme_stylebox_override("panel", skin)
	column.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8 if _compact else 14)
	panel.add_child(content)
	var section := HBoxContainer.new()
	content.add_child(section)
	_text(section, "过往对局", 14 if _compact else 16, Color("ddcfb2"), true)
	var count := _text(section, "本机记录 · %d 条" % records.size(), 12, MUTED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var divider := HSeparator.new()
	divider.modulate = Color("a69777", .3)
	content.add_child(divider)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	content.add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_scroll.add_child(body)
	if not str(view.get("records_error", "")).is_empty():
		_empty("记录暂时无法读取", str(view.records_error))
	elif records.is_empty():
		_empty("还没有冒险记录", "完成一场冒险后，角色、结局与学年进度会收录在这里。")
	else:
		for record in records:
			_record(record)
	footer = VBoxContainer.new()
	column.add_child(footer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 20)
	footer.add_child(actions)
	var back := add_button(actions, "records:back", "‹  返回主菜单", {"type":"ui.records_back", "payload":{}})
	_skin(back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 160 * minf(UiStyle.text_scale, 1.25)
	var hint := _text(actions, "已结算的冒险会自动留存", 12, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.visible = not _compact
	_scroll.set_deferred("scroll_vertical", offset)

func _empty(title: String, description: String) -> void:
	var center := CenterContainer.new()
	center.name = "RecordsEmptyState"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var group: BoxContainer = HBoxContainer.new() if _compact else VBoxContainer.new()
	group.add_theme_constant_override("separation", 16 if _compact else 20)
	center.add_child(group)
	var mark := ArchiveMark.new()
	mark.custom_minimum_size = Vector2(48,48) if _compact else Vector2(88,88)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group.add_child(mark)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 10)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(words)
	var heading := _text(words, title, 19 if _compact else 27, UiStyle.CREAM, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _compact else HORIZONTAL_ALIGNMENT_CENTER
	var description_label := _text(words, description, 13 if _compact else 16, MUTED)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.horizontal_alignment = heading.horizontal_alignment
	description_label.custom_minimum_size.x = 280 if _compact else 410

func _record(record: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "RunRecord"
	var skin := UiStyle.surface(Color("23363c", .65), Color("78867e", .18), 8)
	skin.set_content_margin_all(8 if _compact else 18)
	skin.shadow_size = 0
	panel.add_theme_stylebox_override("panel", skin)
	body.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var art_path := CharacterArt.texture_path(str(record.get("character_id", "")), true)
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(52,64) if _compact else Vector2(66,80)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = load(art_path)
		row.add_child(portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 4 if _compact else 8)
	row.add_child(words)
	var character := str(record.get("character_id", ""))
	_text(words, UiStyle.label(character), 20 if _compact else 25, UiStyle.CREAM, true)
	var difficulty := str({"relaxed":"轻松", "normal":"标准", "hard":"困难"}.get(record.get("difficulty", ""), UiStyle.label(str(record.get("difficulty", "")))))
	var reason := _text(words, difficulty + "难度 · " + str(REASONS.get(record.get("reason", ""), "冒险已结束")), 13 if _compact else 15, MUTED)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var outcome := str(record.get("result", ""))
	var result_color := Color("d7bb7f") if outcome == "won" else (Color("cf9c8a") if outcome == "lost" else MUTED)
	var result := VBoxContainer.new()
	result.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(result)
	var badge := _text(result, str({"won":"胜利", "lost":"失败", "abandoned":"已放弃"}.get(outcome,"已结算")), 16, result_color)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var term := _text(result, "第 %s 学年" % record.get("term",1), 13, MUTED)
	term.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _text(parent: Node, value: String, font_size: int, color: Color, serif: bool = false) -> Label:
	var label := add_text(parent, value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if serif:
		label.add_theme_font_override("font", UiStyle.title_font())
	return label

func _skin(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var skin := UiStyle.surface(Color("263a40", .5), Color("bbaa87", .3), 6)
		skin.set_content_margin_all(9)
		skin.shadow_size = 0
		if state in ["hover", "hover_pressed", "pressed"]:
			skin.bg_color = Color("35494c")
			skin.border_color = Color("d0bd94",.7)
		if state == "focus":
			skin.bg_color = Color.TRANSPARENT
			skin.border_color = UiStyle.BRASS
		button.add_theme_stylebox_override(state, skin)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, UiStyle.CREAM)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		action_requested.emit({"type":"ui.records_back", "payload":{}})
		get_viewport().set_input_as_handled()
