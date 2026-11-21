class_name UiCompendiumDetail
extends UiPage

signal closed(selected_id: String)

var selected_id := ""
var selected_variant := 0
var _owner: UiPage
var _kind := "cards"
var _ids: Array[String] = []
var _entries: Dictionary = {}
var _disabled: Dictionary = {}
var _focus_modes: Dictionary = {}
var _return_focus: Control
var _closing := false
var _motion_enabled := true
var _title: Label
var _meta: Label
var _visual: Control
var _words: VBoxContainer
var _variants: OptionButton
var _variant_row: HBoxContainer
var _counter: Label
var _actor: BattleActorView
var _relic_art: TextureRect
var _face: CardFaceView
var _motion: HBoxContainer


func configure(owner: UiPage, kind_name: String, ids: Array[String], entries: Dictionary, id: String, motion_enabled: bool) -> void:
	_owner = owner
	_kind = kind_name
	_ids = ids.duplicate()
	_entries = entries
	_motion_enabled = motion_enabled
	name = "CompendiumDetail"
	z_index = 400
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_return_focus = get_viewport().gui_get_focus_owner()
	for control in owner.find_children("*", "Control", true, false):
		if control == self or is_ancestor_of(control):
			continue
		if control is BaseButton:
			_disabled[control] = control.disabled
			control.disabled = true
		if control.focus_mode != Control.FOCUS_NONE:
			_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	var shade := ColorRect.new()
	shade.color = Color("070b11")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_title = add_text(column, "", 28, UiStyle.BRASS)
	_title.add_theme_font_override("font", UiStyle.title_font())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta = add_text(column, "", 14, Color("b9b09f"))
	_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 28)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = clampf(owner.size.x * .30, 220, 370)
	content.add_child(left)
	_visual = Control.new()
	_visual.name = "CompendiumVisual"
	_visual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_visual)
	_visual.resized.connect(_fit_visual)
	_motion = HBoxContainer.new()
	_motion.add_theme_constant_override("separation", 8)
	left.add_child(_motion)
	for cue in [["idle", "待机"], ["attack", "出手"], ["hit", "受击"]]:
		var button := add_button(_motion, "compendium:motion:" + cue[0], cue[1], {}, func(): _cue(cue[0]))
		button.custom_minimum_size.x = 64
		button.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
		UiStyle.button_skin(button, "quiet", true)
		button.disabled = not motion_enabled
		button.tooltip_text = "已在设置中关闭动态表现" if not motion_enabled else "仅预览形象动作"
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	content.add_child(right)
	_variant_row = HBoxContainer.new()
	right.add_child(_variant_row)
	_variants = OptionButton.new()
	_variants.name = "CompendiumVariants"
	_variants.custom_minimum_size = Vector2(190, 44)
	_variants.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variants.add_theme_font_size_override("font_size", roundi(17 * UiStyle.text_scale))
	UiStyle.button_skin(_variants, "secondary", true)
	_variant_row.add_child(_variants)
	_variants.item_selected.connect(select_variant)
	_scroll = ScrollContainer.new()
	_scroll.name = "CompendiumDetailScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(_scroll)
	_words = VBoxContainer.new()
	_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_words.add_theme_constant_override("separation", 16)
	_scroll.add_child(_words)
	var line := HSeparator.new()
	line.modulate = Color(UiStyle.BRASS, .5)
	column.add_child(line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var close_button := add_button(actions, "compendium:detail:close", "关闭  Esc", {}, close)
	close_button.custom_minimum_size.x = 130 * UiStyle.text_scale
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(close_button, "quiet", true)
	_counter = add_text(actions, "", 15, Color("cfc6b2"))
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for spec in [["previous", "上一项", -1], ["next", "下一项", 1]]:
		var button := add_button(actions, "compendium:detail:" + spec[0], spec[1], {}, func(): change_entry(spec[2]))
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		button.custom_minimum_size.x = 100 * UiStyle.text_scale
		UiStyle.button_skin(button, "secondary", true)
	show_entry(id)
	close_button.grab_focus()
	tree_exiting.connect(_restore)


func show_entry(id: String) -> void:
	if not _entries.has(id):
		return
	selected_id = id
	selected_variant = 0
	var entry: Dictionary = _entries[id]
	_title.text = CompendiumText.title(entry, _kind == "monsters")
	_meta.text = id + "   ·   " + (CompendiumText.kind(entry) if _kind == "monsters" else str(CompendiumText.OWNER_NAMES.get(CompendiumText.owner(entry), "衍生")) + " · " + CompendiumText.rarity(entry))
	if _kind == "relics":
		_meta.text = id + "   ·   " + CompendiumText.relic_group_text(entry) + " · " + CompendiumText.rarity(entry)
	_counter.text = "%s / %s" % [_ids.find(id) + 1, _ids.size()]
	_buttons["compendium:detail:previous"].disabled = _ids.find(id) <= 0
	_buttons["compendium:detail:next"].disabled = _ids.find(id) >= _ids.size() - 1
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	_actor = null
	_face = null
	_relic_art = null
	_variant_row.visible = _kind == "cards"
	_motion.visible = _kind == "monsters"
	if _kind == "cards":
		_variants.clear()
		for variant in entry.variants:
			_variants.add_item(CompendiumText.variant_name(variant))
		_face = CardFaceView.new()
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_visual.add_child(_face)
		select_variant(0)
	elif _kind == "relics":
		_relic_art = TextureRect.new()
		_relic_art.texture = UiStyle.texture(id)
		_relic_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_relic_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_relic_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_visual.add_child(_relic_art)
		_clear_words()
		add_text(_words, "装备效果", 20, UiStyle.BRASS)
		add_text(_words, UiContentText.describe_relic(entry.definition), 17, UiStyle.CREAM)
		add_text(_words, "获取方式", 20, UiStyle.BRASS)
		add_text(_words, CompendiumText.relic_source(entry), 16, UiStyle.CREAM)
		add_text(_words, "只在佩戴时生效 · 同时最多装备三件", 14, Color("aebcc2"))
	else:
		_actor = BattleActorView.new()
		_visual.add_child(_actor)
		_actor.configure(id, "task")
		_actor.set_motion(_motion_enabled)
		_clear_words()
		add_text(_words, "以下为基础定义值；实战还受难度、状态与规则修正。", 14, Color("aebcc2"))
		add_text(_words, CompendiumText.years(entry.get("terms", [])) + " · %s 个阶段" % entry.definition.get("phases", []).size(), 16, UiStyle.BRASS)
		for section in CompendiumText.monster_sections(entry):
			add_text(_words, section.title, 20, UiStyle.BRASS)
			add_text(_words, section.text, 17, UiStyle.CREAM)
	_fit_visual()
	_scroll.scroll_vertical = 0


func select_variant(index: int) -> void:
	if _kind != "cards" or not _entries.has(selected_id):
		return
	var entry: Dictionary = _entries[selected_id]
	selected_variant = clampi(index, 0, entry.variants.size() - 1)
	_variants.select(selected_variant)
	var variant: Dictionary = entry.variants[selected_variant]
	_face.configure(CardDisplayModel.from_card(variant.face, selected_id))
	_clear_words()
	add_text(_words, CompendiumText.variant_name(variant), 20, UiStyle.BRASS)
	add_text(_words, CompendiumText.card_text(variant), 17, UiStyle.CREAM)
	_scroll.scroll_vertical = 0


func _clear_words() -> void:
	for child in _words.get_children():
		_words.remove_child(child)
		child.queue_free()


func _fit_visual() -> void:
	if is_instance_valid(_relic_art):
		_relic_art.size = _visual.size - Vector2(20, 20)
		_relic_art.position = Vector2(10, 10)
	if is_instance_valid(_face):
		var width := minf(_visual.size.x - 12, _visual.size.y * 168.0 / 244.0)
		_face.size = Vector2(width, width * 244.0 / 168.0)
		_face.position = (_visual.size - _face.size) * .5
		_face.queue_redraw()
	if is_instance_valid(_actor):
		_actor.position = Vector2.ZERO
		_actor.size = _visual.size


func _cue(kind_name: String) -> void:
	if not _motion_enabled or not is_instance_valid(_actor):
		return
	if kind_name == "idle":
		_actor.reset_pose()
	else:
		_actor.cue(kind_name, maxf(1, float(_owner.view.get("animation_speed", 1))))


func change_entry(delta: int) -> void:
	var index := _ids.find(selected_id) + delta
	if index >= 0 and index < _ids.size():
		show_entry(_ids[index])


func close() -> void:
	if _closing:
		return
	_closing = true
	hide()
	_restore()
	closed.emit(selected_id)
	queue_free()


func _restore() -> void:
	for button in _disabled:
		if is_instance_valid(button):
			button.disabled = _disabled[button]
	_disabled.clear()
	for control in _focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _focus_modes[control]
	_focus_modes.clear()
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree() and not _return_focus.is_queued_for_deletion():
		_return_focus.grab_focus()
	_return_focus = null


func _input(event: InputEvent) -> void:
	if _closing or not visible:
		return
	if _variants.get_popup().visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
			change_entry(-1 if event.keycode == KEY_LEFT else 1)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
			if event.keycode in [KEY_HOME, KEY_END]:
				_scroll.scroll_vertical = 0 if event.keycode == KEY_HOME else int(_scroll.get_v_scroll_bar().max_value)
			else:
				_scroll.scroll_vertical += roundi(_scroll.size.y * .85) * (-1 if event.keycode == KEY_PAGEUP else 1)
			get_viewport().set_input_as_handled()
