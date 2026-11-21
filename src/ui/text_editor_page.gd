class_name UiTextEditorPage
extends UiPage

const BATCH_SIZE := 12
const TABS := [
	["all", "全部"],
	["cards", "卡牌"],
	["relics", "饰品"],
	["characters", "人物"],
	["stories", "剧情"],
	["glossary", "词条"],
	["monsters", "怪物"],
	["terms", "其他"],
]
const TYPE_ORDER := ["cards", "relics", "characters", "stories", "glossary", "monsters", "terms"]

var library: Array[Dictionary] = []
var counts: Dictionary = {}
var field_count := 0
var filtered: Array[Dictionary] = []
var visible_entities: Array[Dictionary] = []
var tab := "all"
var query := ""
var filter_value := ""
var filter2_value := ""
var selected_id := ""
var initial_state: Dictionary = {}
var _entity_by_id: Dictionary = {}
var _field_by_uid: Dictionary = {}
var _fields_all: Array[Dictionary] = []
var _saved_uid_values: Dictionary = {}
var _saved_orphans: Dictionary = {}
var _orphans_draft: Dictionary = {}
var _saved_by_field: Dictionary = {}
var _drafts_by_field: Dictionary = {}
var _conflict_fields: Dictionary = {}
var _match_by_id: Dictionary = {}
var _item_buttons: Dictionary = {}
var _item_meta: Dictionary = {}
var _item_match: Dictionary = {}
var _tabs: Dictionary = {}
var _search: LineEdit
var _filter: OptionButton
var _filter2: OptionButton
var _count: Label
var _subtitle: Label
var _list: VBoxContainer
var _left_scroll: ScrollContainer
var _entity_title: Label
var _entity_meta: Label
var _entity_status: Label
var _entity_note: Label
var _fields_box: VBoxContainer
var _selected: Dictionary = {}
var _field_blocks: Dictionary = {}
var _expanded_field := ""
var _initial_expanded := ""
var _save_entity_button: Button
var _undo_entity_button: Button
var _reset_entity_button: Button
var _save_button: Button
var _back_button: Button
var _reset_all_button: Button
var _dirty_label: Label
var _notice: Label
var _search_timer: Timer
var _back_timer: Timer
var _reset_timer: Timer
var _visible_count := 0
var _restoring_input := false
var _exit_armed := false
var _reset_all_armed := false


func render(data: Dictionary) -> void:
	view = data
	library = data.get("entities", [])
	counts = data.get("counts", {})
	field_count = int(data.get("field_count", 0))
	_saved_uid_values = TextOverrides.snapshot()
	_orphans_draft = {}
	_saved_by_field = {}
	_drafts_by_field = {}
	_conflict_fields = {}
	_entity_by_id.clear()
	_field_by_uid.clear()
	_fields_all.clear()
	_item_buttons.clear()
	_item_meta.clear()
	_item_match.clear()
	_field_blocks.clear()
	_selected = {}
	selected_id = ""
	_expanded_field = ""
	_visible_count = 0
	_restoring_input = false
	_exit_armed = false
	_reset_all_armed = false
	tab = str(initial_state.get("tab", "all"))
	query = str(initial_state.get("query", ""))
	filter_value = str(initial_state.get("filter", ""))
	filter2_value = str(initial_state.get("filter2", ""))
	selected_id = str(initial_state.get("selected", ""))
	_initial_expanded = str(initial_state.get("expanded", ""))
	if not counts.has(tab):
		tab = "all"
	for entity in library:
		var id := str(entity.get("id", ""))
		if id.is_empty():
			continue
		_entity_by_id[id] = entity
		for field in entity.fields:
			_field_by_uid[field.key] = field
			_fields_all.append(field)
			for uid in field.uids:
				_field_by_uid[uid] = field
	# Preserve overrides from older/removed entries. They are not shown, but a
	# global save must not silently drop them.
	for uid in _saved_uid_values:
		if not _field_by_uid.has(uid):
			_saved_orphans[uid] = str(_saved_uid_values[uid])
	_orphans_draft = _saved_orphans.duplicate(true)
	_initialise_field_values()
	_build_ui()
	if data.has("error"):
		_show_library_error(str(data.get("error", "")))
		return
	_build_filter_options()
	_refresh_filter(true)
	if not _initial_expanded.is_empty() and _field_blocks.has(_initial_expanded):
		_expand_field(_initial_expanded, false)
	_initial_expanded = ""
	var saved_error := TextOverrides.last_error()
	if not saved_error.is_empty():
		_set_notice(saved_error, true)
	else:
		_set_notice("先选择实体，再编辑它的全部文本字段；只改显示，不改规则/数值/命令/存档。", false)
	if int(initial_state.get("scroll", 0)) > 0:
		_restore_initial_scroll.call_deferred(int(initial_state.get("scroll", 0)), 2)
	_focus_search.call_deferred()


func _initialise_field_values() -> void:
	for field in _fields_all:
		var value := _read_field_from(_saved_uid_values, field)
		_saved_by_field[field.key] = value
		_drafts_by_field[field.key] = value
		if _field_has_conflict(_saved_uid_values, field):
			_conflict_fields[field.key] = true


func _read_field_from(overrides: Dictionary, field: Dictionary) -> String:
	for uid in field.uids:
		if overrides.has(uid):
			return str(overrides[uid])
	return str(field.default)


func _field_has_conflict(overrides: Dictionary, field: Dictionary) -> bool:
	var found: Variant = null
	for uid in field.uids:
		if not overrides.has(uid):
			continue
		if found == null:
			found = str(overrides[uid])
		elif found != str(overrides[uid]):
			return true
	return false


func _focus_search() -> void:
	if is_inside_tree() and is_instance_valid(_search):
		_search.grab_focus()


func _restore_initial_scroll(target: int, frames_left: int) -> void:
	if not is_inside_tree() or not is_instance_valid(_left_scroll):
		return
	if frames_left > 0:
		get_tree().create_timer(0.0).timeout.connect(
			_restore_initial_scroll.bind(target, frames_left - 1), CONNECT_ONE_SHOT
		)
		return
	_left_scroll.scroll_vertical = target


func _build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_drafts.clear()
	var backdrop := RoomSceneView.new()
	backdrop.room = "settings"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color("071017", .9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 7)
	column.add_child(header)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	header.add_child(heading)
	var title := add_text(heading, "文 本 编 辑", 30, UiStyle.BRASS)
	title.add_theme_font_override("font", UiStyle.title_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count = add_text(heading, "", 14, Color("c5b99f"))
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_text(
		header,
		"按实体检索：卡牌、饰品、人物、剧情、词条、怪物；选中后编辑该实体的全部字段。只改显示，不改规则/数值/命令/存档。",
		14,
		Color("b9c7bf")
	)
	_subtitle = header.get_child(header.get_child_count() - 1) as Label
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	header.add_child(tools)
	_search = LineEdit.new()
	_search.name = "TextEditorSearch"
	_search.placeholder_text = "搜索实体、ID、字段正文  /"
	_search.text = query
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(300 * minf(UiStyle.text_scale, 1.2), 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	_search.add_theme_color_override("font_color", UiStyle.CREAM)
	_search.add_theme_color_override("font_placeholder_color", Color("8ea0a2"))
	_search.add_theme_stylebox_override(
		"normal", UiStyle.surface(Color("0d1820"), Color("607a84"), 4)
	)
	_search.text_changed.connect(_on_search_changed)
	tools.add_child(_search)
	_filter = _make_filter()
	_filter.item_selected.connect(_on_filter_selected)
	tools.add_child(_filter)
	_filter2 = _make_filter()
	_filter2.item_selected.connect(_on_filter2_selected)
	tools.add_child(_filter2)
	var tab_row := HFlowContainer.new()
	tab_row.add_theme_constant_override("h_separation", 8)
	tab_row.add_theme_constant_override("v_separation", 6)
	header.add_child(tab_row)
	for spec in TABS:
		var key := str(spec[0])
		var compact_tab := UiStyle.text_scale > 1.0
		var button := add_button(
			tab_row,
			"text_editor:tab:" + key,
			str(spec[1]) if compact_tab else "%s %d" % [str(spec[1]), int(counts.get(key, 0))],
			{},
			func(): show_tab(key)
		)
		button.tooltip_text = "%s · %d 个实体" % [str(spec[1]), int(counts.get(key, 0))]
		button.custom_minimum_size = Vector2((100 if not compact_tab else 88) * minf(UiStyle.text_scale, 1.2), 44)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
		_tabs[key] = button
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	column.add_child(content)
	_build_list_pane(content)
	_build_editor_pane(content)
	footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 5)
	column.add_child(footer)
	var line := HSeparator.new()
	line.modulate = Color(UiStyle.BRASS, .5)
	footer.add_child(line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	footer.add_child(actions)
	_back_button = add_button(actions, "text_editor:back", "返回  Esc", {}, _request_back)
	_back_button.custom_minimum_size.x = 140 * UiStyle.text_scale
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_back_button, "quiet", true)
	_save_button = add_button(actions, "text_editor:save", "保存全部  Ctrl+S", {}, _save)
	_save_button.custom_minimum_size.x = 190 * UiStyle.text_scale
	_save_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_save_button, "primary", true)
	_dirty_label = add_text(actions, "", 14, Color("c5b99f"))
	_dirty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dirty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reset_all_button = add_button(
		actions, "text_editor:reset_all", "全部重置", {}, _request_reset_all
	)
	_reset_all_button.tooltip_text = "清除全部本机文本覆盖，恢复原始文案"
	_reset_all_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiStyle.button_skin(_reset_all_button, "quiet", true)
	_notice = add_text(footer, "", 13, Color("c5b99f"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_search_timer = Timer.new()
	_search_timer.wait_time = .12
	_search_timer.one_shot = true
	_search_timer.timeout.connect(func(): _refresh_filter(true))
	add_child(_search_timer)
	_back_timer = Timer.new()
	_back_timer.wait_time = 4.0
	_back_timer.one_shot = true
	_back_timer.timeout.connect(_disarm_back)
	add_child(_back_timer)
	_reset_timer = Timer.new()
	_reset_timer.wait_time = 5.0
	_reset_timer.one_shot = true
	_reset_timer.timeout.connect(_disarm_reset_all)
	add_child(_reset_timer)
	_update_tab_skins()
	_apply_compact_header()
	if not resized.is_connected(_apply_compact_header):
		resized.connect(_apply_compact_header)
	_update_dirty()


func _apply_compact_header() -> void:
	var compact := size.y > 0 and size.y < 640 and UiStyle.text_scale >= 1.25
	if is_instance_valid(_entity_meta):
		_entity_meta.visible = not compact
	if is_instance_valid(_entity_status):
		_entity_status.visible = not compact
	if is_instance_valid(_entity_note):
		_entity_note.visible = not compact
	if is_instance_valid(_subtitle):
		_subtitle.visible = not compact


func _make_filter() -> OptionButton:
	var filter := OptionButton.new()
	filter.custom_minimum_size = Vector2(190 * minf(UiStyle.text_scale, 1.2), 44)
	filter.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
	filter.add_theme_color_override("font_color", UiStyle.CREAM)
	filter.add_theme_stylebox_override("normal", UiStyle.surface(Color("20353d"), Color("657c85"), 4))
	filter.add_theme_stylebox_override("hover", UiStyle.surface(Color("2b4550"), Color("8aa3aa"), 4))
	filter.add_theme_stylebox_override("pressed", UiStyle.surface(Color("193039"), Color("8aa3aa"), 4))
	return filter


func _build_list_pane(parent: Node) -> void:
	var panel := PanelContainer.new()
	var page_width := size.x if size.x > 0 else 1280.0
	panel.custom_minimum_size.x = clampf(page_width * 0.34, 320 * minf(UiStyle.text_scale, 1.1), 440)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var skin := UiStyle.surface(Color("111f28"), Color("3c525d"), 6)
	skin.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", skin)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var hint := add_text(column, "实体列表", 15, Color("d8c9a6"))
	hint.add_theme_font_override("font", UiStyle.title_font())
	_left_scroll = ScrollContainer.new()
	_left_scroll.name = "TextEditorListScroll"
	_left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_scroll.follow_focus = true
	_left_scroll.focus_mode = Control.FOCUS_ALL
	_left_scroll.get_v_scroll_bar().value_changed.connect(_on_list_scrolled)
	column.add_child(_left_scroll)
	_scroll = _left_scroll
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	_left_scroll.add_child(_list)


func _build_editor_pane(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var skin := UiStyle.surface(Color("13232c"), Color("4b626c"), 6)
	skin.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", skin)
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)
	_entity_title = add_text(form, "从左侧选择一个实体", 23, UiStyle.BRASS)
	_entity_title.add_theme_font_override("font", UiStyle.title_font())
	_entity_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entity_meta = add_text(form, "", 13, Color("93a8aa"))
	_entity_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entity_status = add_text(form, "", 13, Color("c5b99f"))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	form.add_child(actions)
	_save_entity_button = add_button(
		actions, "text_editor:save_entity", "保存", {}, _save_entity
	)
	_save_entity_button.tooltip_text = "保存当前实体的全部字段"
	_save_entity_button.custom_minimum_size.x = 130 * minf(UiStyle.text_scale, 1.2)
	_save_entity_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_save_entity_button, "primary", true)
	_undo_entity_button = add_button(
		actions, "text_editor:undo_entity", "撤销", {}, _undo_entity
	)
	_undo_entity_button.tooltip_text = "撤销当前实体的未保存修改"
	_undo_entity_button.custom_minimum_size.x = 90 * minf(UiStyle.text_scale, 1.2)
	_undo_entity_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_undo_entity_button, "quiet", true)
	_reset_entity_button = add_button(
		actions, "text_editor:reset_entity", "恢复", {}, _reset_entity
	)
	_reset_entity_button.tooltip_text = "恢复当前实体的全部字段默认文本"
	_reset_entity_button.custom_minimum_size.x = 90 * minf(UiStyle.text_scale, 1.2)
	_reset_entity_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_reset_entity_button, "quiet", true)
	_fields_box = VBoxContainer.new()
	_fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_box.add_theme_constant_override("separation", 7)
	form.add_child(_fields_box)
	_entity_note = add_text(form, "", 12, Color("8ea0a2"))
	_entity_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _show_library_error(message: String) -> void:
	_clear_editor()
	_entity_title.text = "文本库暂时不可用"
	_entity_meta.text = message
	_entity_note.text = "可返回主菜单继续游戏；当前文案与规则没有变化。"
	_save_button.disabled = true
	_reset_all_button.disabled = true
	_set_notice(message, true)


func _update_tab_skins() -> void:
	for key in _tabs:
		UiStyle.button_skin(_tabs[key], "primary" if str(key) == tab else "quiet", true)
		_tabs[key].tooltip_text = "当前分类" if str(key) == tab else "切换到" + _tab_name(str(key))


func _tab_name(key: String) -> String:
	for spec in TABS:
		if str(spec[0]) == key:
			return str(spec[1])
	return key


func _build_filter_options() -> void:
	_filter.clear()
	_filter2.clear()
	_filter.visible = tab in ["cards", "relics", "stories", "glossary", "monsters", "terms"]
	_filter2.visible = tab == "cards"
	if _filter.visible:
		var options := _filter_options_for(tab)
		_filter.add_item(_all_filter_label(tab))
		_filter.set_item_metadata(0, "")
		var selected_index := 0
		for option in options:
			_filter.add_item(str(option.label))
			var index := _filter.item_count - 1
			_filter.set_item_metadata(index, str(option.value))
			if str(option.value) == filter_value:
				selected_index = index
		_filter.select(selected_index)
	if _filter2.visible:
		_filter2.add_item("全部类型")
		_filter2.set_item_metadata(0, "")
		var selected2 := 0
		for option in _card_type_options():
			_filter2.add_item(str(option.label))
			var index := _filter2.item_count - 1
			_filter2.set_item_metadata(index, str(option.value))
			if str(option.value) == filter2_value:
				selected2 = index
		_filter2.select(selected2)


func _all_filter_label(key: String) -> String:
	match key:
		"cards":
			return "全部拥有者"
		"relics":
			return "全部稀有度"
		"stories":
			return "全部剧情"
		"glossary":
			return "全部词条分类"
		"monsters":
			return "全部怪物类型"
		"terms":
			return "全部名称分类"
	return "全部"


func _filter_options_for(key: String) -> Array[Dictionary]:
	var values: Dictionary = {}
	for entity in library:
		if str(entity.type) != key:
			continue
		var value := _entity_filter_value(entity, key)
		if value.is_empty():
			continue
		values[value] = _entity_filter_label(entity, key)
	var result: Array[Dictionary] = []
	for value in values:
		result.append({"value": str(value), "label": str(values[value])})
	result.sort_custom(func(a, b): return str(a.label) < str(b.label))
	return result


func _card_type_options() -> Array[Dictionary]:
	var values: Dictionary = {}
	for value in TextEntityLibrary.CARD_TYPE_NAMES:
		values[value] = TextEntityLibrary.CARD_TYPE_NAMES[value]
	var result: Array[Dictionary] = []
	for value in values:
		result.append({"value": str(value), "label": str(values[value])})
	result.sort_custom(func(a, b): return str(a.label) < str(b.label))
	return result


func _entity_filter_value(entity: Dictionary, key: String) -> String:
	match key:
		"cards":
			return str(entity.meta.get("owner", ""))
		"relics":
			return str(entity.meta.get("rarity", ""))
		"stories":
			return str(entity.meta.get("story_kind", ""))
		"glossary":
			return str(entity.meta.get("glossary_type", ""))
		"monsters":
			return str(entity.meta.get("kind", ""))
		"terms":
			return str(entity.meta.get("label_category", ""))
	return ""


func _entity_filter_label(entity: Dictionary, key: String) -> String:
	var value := _entity_filter_value(entity, key)
	match key:
		"cards":
			return str(TextEntityLibrary.OWNER_NAMES.get(value, value))
		"relics":
			return str(TextEntityLibrary.RARITY_NAMES.get(value, value))
		"monsters":
			return str(TextEntityLibrary.MONSTER_KIND_NAMES.get(value, value))
	return value


func _on_filter_selected(index: int) -> void:
	filter_value = str(_filter.get_item_metadata(index)) if index >= 0 else ""
	_refresh_filter(true)


func _on_filter2_selected(index: int) -> void:
	filter2_value = str(_filter2.get_item_metadata(index)) if index >= 0 else ""
	_refresh_filter(true)


func show_tab(value: String) -> void:
	if not counts.has(value):
		return
	tab = value
	filter_value = ""
	filter2_value = ""
	_update_tab_skins()
	_build_filter_options()
	_refresh_filter(true)


func search(value: String) -> void:
	query = value
	if is_instance_valid(_search):
		_search.text = value
	if is_instance_valid(_search_timer):
		_search_timer.stop()
	_refresh_filter(true)


func set_filter(value: String) -> void:
	filter_value = value
	_build_filter_options()
	_refresh_filter(true)


func set_filter2(value: String) -> void:
	filter2_value = value
	_build_filter_options()
	_refresh_filter(true)


func _on_search_changed(value: String) -> void:
	query = value
	if is_instance_valid(_search_timer):
		_search_timer.start()


func _refresh_filter(reset_scroll: bool) -> void:
	if _list == null:
		return
	var tokens := query.strip_edges().to_lower().split(" ", false)
	filtered.clear()
	_match_by_id.clear()
	for entity in library:
		if not _matches_tab(entity):
			continue
		if not _matches_filters(entity):
			continue
		var match := _match_entity(entity, tokens)
		if not bool(match.matched):
			continue
		filtered.append(entity)
		_match_by_id[str(entity.id)] = match
	filtered.sort_custom(func(a, b): return _match_before(a, b))
	if reset_scroll and is_instance_valid(_left_scroll):
		_left_scroll.scroll_vertical = 0
	_render_list(true)
	_ensure_selection_in_filter()


func _matches_tab(entity: Dictionary) -> bool:
	return tab == "all" or str(entity.type) == tab


func _matches_filters(entity: Dictionary) -> bool:
	if tab != "all" and not filter_value.is_empty():
		if _entity_filter_value(entity, tab) != filter_value:
			return false
	if tab == "cards" and not filter2_value.is_empty():
		if str(entity.meta.get("card_type", "")) != filter2_value:
			return false
	return true


func _match_entity(entity: Dictionary, tokens: PackedStringArray) -> Dictionary:
	var title := str(entity.title).to_lower()
	var id := str(entity.id).to_lower()
	var base := str(entity.get("search", "")).to_lower()
	var all_text := base
	for field in entity.fields:
		all_text += " " + _draft_text(field).to_lower()
	var matched := true
	for token in tokens:
		if not all_text.contains(token):
			matched = false
			break
	if not matched:
		return {"matched": false}
	var rank := 3
	if tokens.size() == 1:
		var token := str(tokens[0])
		if title == token or id == token:
			rank = 0
		elif title.begins_with(token) or id.begins_with(token):
			rank = 1
		elif title.contains(token):
			rank = 2
	var matched_field := ""
	var snippet := ""
	if not tokens.is_empty():
		var first := str(tokens[0])
		for field in entity.fields:
			var field_text := (
				str(field.label) + " " + _draft_text(field) + " " + " ".join(field.uids)
			).to_lower()
			if field_text.contains(first):
				matched_field = str(field.key)
				snippet = _short_text(_draft_text(field), 74)
				break
	return {
		"matched": true,
		"rank": rank,
		"field": matched_field,
		"snippet": snippet,
		"query": query,
	}


func _match_before(a: Dictionary, b: Dictionary) -> bool:
	var a_match: Dictionary = _match_by_id.get(str(a.id), {})
	var b_match: Dictionary = _match_by_id.get(str(b.id), {})
	var a_rank := int(a_match.get("rank", 3))
	var b_rank := int(b_match.get("rank", 3))
	if a_rank != b_rank:
		return a_rank < b_rank
	var a_type := TYPE_ORDER.find(str(a.type))
	var b_type := TYPE_ORDER.find(str(b.type))
	if a_type != b_type:
		return a_type < b_type
	if str(a.category) != str(b.category):
		return str(a.category) < str(b.category)
	if str(a.title) != str(b.title):
		return str(a.title) < str(b.title)
	return str(a.id) < str(b.id)


func _ensure_selection_in_filter() -> void:
	if filtered.is_empty():
		if not selected_id.is_empty():
			_clear_editor()
		return
	if not query.is_empty():
		var current: Variant = _entity_by_id.get(selected_id)
		if current == null or _entity_dirty_count(current) == 0:
			var first_match: Dictionary = _match_by_id.get(str(filtered[0].id), {})
			_select_entity(
				str(filtered[0].id), str(first_match.get("field", "")), false
			)
			return
	for entity in filtered:
		if str(entity.id) == selected_id:
			if _selected.is_empty() or str(_selected.get("id", "")) != selected_id:
				var match: Dictionary = _match_by_id.get(selected_id, {})
				_select_entity(selected_id, str(match.get("field", "")), false)
			return
	var first: Dictionary = filtered[0]
	var match: Dictionary = _match_by_id.get(str(first.id), {})
	_select_entity(str(first.id), str(match.get("field", "")), false)


func _render_list(reset: bool) -> void:
	if reset:
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()
		_item_buttons.clear()
		_item_meta.clear()
		_item_match.clear()
		visible_entities.clear()
		_visible_count = mini(BATCH_SIZE, filtered.size())
	else:
		_visible_count = mini(_visible_count + BATCH_SIZE, filtered.size())
	var start := visible_entities.size()
	for index in range(start, _visible_count):
		var entity: Dictionary = filtered[index]
		visible_entities.append(entity)
		_make_item(entity)
	if filtered.is_empty():
		var empty := add_text(
			_list, "没有匹配的实体。可清空搜索，或切换分类后再试。", 15, Color("9fb0ad")
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 80
	_update_count()


func _make_item(entity: Dictionary) -> void:
	var id := str(entity.id)
	var match: Dictionary = _match_by_id.get(id, {})
	var button := add_button(
		_list,
		"text_editor:entity:" + id,
		"",
		{},
		Callable(self, "_select_entity").bind(id, str(match.get("field", "")))
	)
	button.custom_minimum_size.y = 104 * minf(UiStyle.text_scale, 1.2)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = id
	UiStyle.button_skin(button, "selected" if id == selected_id else "secondary", true)
	var copy := MarginContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		copy.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		copy.add_theme_constant_override("margin_" + side, 6)
	button.add_child(copy)
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	copy.add_child(column)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 6)
	column.add_child(heading)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = str(entity.title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	title.add_theme_color_override("font_color", UiStyle.CREAM)
	heading.add_child(title)
	var modified := Label.new()
	modified.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modified.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	modified.add_theme_color_override("font_color", Color("ffd58a"))
	heading.add_child(modified)
	var meta := Label.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.text = "%s · %s · %d 字段" % [str(entity.type_label), str(entity.subtitle), entity.fields.size()]
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	meta.add_theme_color_override("font_color", Color("8ea8aa"))
	column.add_child(meta)
	var match_label := Label.new()
	match_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match_label.clip_text = true
	match_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	match_label.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	match_label.add_theme_color_override("font_color", Color("c1cec5"))
	column.add_child(match_label)
	_item_buttons[id] = button
	_item_meta[id] = meta
	_item_match[id] = match_label
	_update_item(id)


func _update_item(id: String) -> void:
	if not _item_buttons.has(id) or not _entity_by_id.has(id):
		return
	var entity: Dictionary = _entity_by_id[id]
	var modified := _entity_modified_count(entity)
	_item_meta[id].text = "%s · %s · %d 字段%s" % [
		str(entity.type_label),
		str(entity.subtitle),
		entity.fields.size(),
		(" · %d 已修改" % modified) if modified > 0 else "",
	]
	var match: Dictionary = _match_by_id.get(id, {})
	if bool(match.get("matched", false)) and not str(match.get("snippet", "")).is_empty():
		var field_label := _field_label(entity, str(match.get("field", "")))
		_item_match[id].text = "命中 %s：%s" % [field_label, str(match.get("snippet", ""))]
		_item_match[id].visible = true
	else:
		_item_match[id].text = ""
		_item_match[id].visible = false


func _field_label(entity: Dictionary, field_key: String) -> String:
	for field in entity.fields:
		if str(field.key) == field_key:
			return str(field.label)
	return "字段"


func _on_list_scrolled(value: float) -> void:
	if _visible_count >= filtered.size():
		return
	var bar := _left_scroll.get_v_scroll_bar()
	if value >= bar.max_value - bar.page - 48:
		_render_list(false)


func _select_entity(id: String, match_field: String = "", focus_editor: bool = true) -> void:
	if not _entity_by_id.has(id):
		return
	selected_id = id
	_selected = _entity_by_id[id]
	_entity_title.text = str(_selected.title)
	_entity_meta.text = "%s · %s · %s" % [
		str(_selected.type_label),
		str(_selected.subtitle),
		str(_selected.id),
	]
	_entity_note.text = str(_selected.note)
	_expanded_field = ""
	_build_fields(str(match_field))
	_update_entity_status()
	for item_id in _item_buttons:
		UiStyle.button_skin(
			_item_buttons[item_id],
			"selected" if str(item_id) == id else "secondary",
			true
		)
		_update_item(str(item_id))
	_save_entity_button.disabled = false
	_undo_entity_button.disabled = false
	_reset_entity_button.disabled = false
	if focus_editor and not _expanded_field.is_empty():
		_focus_field(_expanded_field)


func _build_fields(match_field: String) -> void:
	for child in _fields_box.get_children():
		_fields_box.remove_child(child)
		child.queue_free()
	_field_blocks.clear()
	_expanded_field = ""
	var first_key := ""
	for field in _selected.fields:
		var key := str(field.key)
		if first_key.is_empty():
			first_key = key
		_build_field_block(field)
	if not match_field.is_empty() and _field_blocks.has(match_field):
		_expand_field(match_field, false)
	elif not first_key.is_empty():
		_expand_field(first_key, false)


func _build_field_block(field: Dictionary) -> void:
	var panel := PanelContainer.new()
	var skin := UiStyle.surface(Color("0e1a22"), Color("3f555f"), 5)
	skin.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", skin)
	_fields_box.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	var key := str(field.key)
	var header := add_button(
		column, "text_editor:field:" + key, "", {}, Callable(self, "_toggle_field").bind(key)
	)
	header.custom_minimum_size.y = 48 * minf(UiStyle.text_scale, 1.15)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.button_skin(header, "secondary", true)
	var copy := MarginContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		copy.add_theme_constant_override("margin_" + side, 10)
	button_copy(header, copy)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	copy.add_child(row)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = str(field.label)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
	title.add_theme_color_override("font_color", UiStyle.CREAM)
	row.add_child(title)
	var status := Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	status.add_theme_color_override("font_color", Color("ffd58a"))
	row.add_child(status)
	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", 6)
	body.add_theme_constant_override("margin_left", 0)
	column.add_child(body)
	var input: Control
	if bool(field.multiline):
		var edit := TextEdit.new()
		edit.custom_minimum_size = Vector2(0, 190 * minf(UiStyle.text_scale, 1.05))
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
		edit.add_theme_color_override("font_color", UiStyle.CREAM)
		edit.add_theme_color_override("caret_color", Color("ffe0a0"))
		var normal := UiStyle.surface(Color("0c161d"), Color("5d7782"), 4)
		normal.set_content_margin_all(8)
		var focused := UiStyle.surface(Color("0c161d"), Color("d8b468"), 4)
		focused.set_content_margin_all(8)
		edit.add_theme_stylebox_override("normal", normal)
		edit.add_theme_stylebox_override("focus", focused)
		edit.text = _draft_text(field)
		edit.text_changed.connect(func(): _on_field_changed(key))
		input = edit
	else:
		var line := LineEdit.new()
		line.custom_minimum_size.y = 44 * minf(UiStyle.text_scale, 1.15)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
		line.add_theme_color_override("font_color", UiStyle.CREAM)
		line.add_theme_stylebox_override(
			"normal", UiStyle.surface(Color("0c161d"), Color("5d7782"), 4)
		)
		line.add_theme_stylebox_override(
			"focus", UiStyle.surface(Color("0c161d"), Color("d8b468"), 4)
		)
		line.text = _draft_text(field)
		line.text_changed.connect(func(_value): _on_field_changed(key))
		input = line
	body.add_child(input)
	var note := Label.new()
	note.text = str(field.note)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	note.add_theme_color_override("font_color", Color("8ea0a2"))
	body.add_child(note)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	body.add_child(tools)
	var reset := add_button(
		tools,
		"text_editor:field_reset:" + key,
		"恢复此字段",
		{},
		Callable(self, "_reset_field").bind(key)
	)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(reset, "quiet", true)
	var source := Label.new()
	source.text = str(field.source).get_file()
	source.tooltip_text = str(field.source)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source.clip_text = true
	source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	source.add_theme_font_size_override("font_size", roundi(11 * UiStyle.text_scale))
	source.add_theme_color_override("font_color", Color("758a8d"))
	tools.add_child(source)
	_field_blocks[key] = {
		"field": field,
		"header": header,
		"body": body,
		"status": status,
		"input": input,
	}
	_refresh_field_state(key)


func button_copy(button: Button, copy: MarginContainer) -> void:
	button.add_child(copy)
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _toggle_field(key: String) -> void:
	if not _field_blocks.has(key):
		return
	if _expanded_field == key:
		_collapse_field(key)
		return
	if not _expanded_field.is_empty():
		_collapse_field(_expanded_field)
	_expand_field(key, true)


func _expand_field(key: String, focus_input: bool) -> void:
	if not _field_blocks.has(key):
		return
	if not _expanded_field.is_empty() and _expanded_field != key:
		_collapse_field(_expanded_field)
	_expanded_field = key
	_field_blocks[key].body.visible = true
	UiStyle.button_skin(_field_blocks[key].header, "selected", true)
	if focus_input:
		_focus_field(key)


func _collapse_field(key: String) -> void:
	if not _field_blocks.has(key):
		return
	_field_blocks[key].body.visible = false
	UiStyle.button_skin(_field_blocks[key].header, "secondary", true)
	if _expanded_field == key:
		_expanded_field = ""


func _focus_field(key: String) -> void:
	if not is_inside_tree() or not _field_blocks.has(key):
		return
	var input: Control = _field_blocks[key].input
	if is_instance_valid(input):
		input.grab_focus()


func _focus_field_deferred(key: String) -> void:
	_focus_field.call_deferred(key)


func _on_field_changed(key: String) -> void:
	if _restoring_input or not _field_blocks.has(key):
		return
	var block: Dictionary = _field_blocks[key]
	var value := ""
	if block.input is TextEdit:
		value = str(block.input.text)
	elif block.input is LineEdit:
		value = str(block.input.text)
	_drafts_by_field[key] = value
	_refresh_field_state(key)
	_update_entity_status()
	_update_dirty()
	if not selected_id.is_empty():
		_update_item(selected_id)


func _refresh_field_state(key: String) -> void:
	if not _field_blocks.has(key):
		return
	var block: Dictionary = _field_blocks[key]
	var field: Dictionary = block.field
	var value := str(_drafts_by_field.get(key, field.default))
	var saved := str(_saved_by_field.get(key, field.default))
	var conflict := bool(_conflict_fields.get(key, false))
	var parts: PackedStringArray = []
	if conflict:
		parts.append("入口不一致")
	elif value != str(field.default):
		parts.append("已修改")
	else:
		parts.append("默认")
	if value != saved:
		parts.append("未保存")
	parts.append("%d 字" % value.length())
	block.status.text = " · ".join(parts)
	var color := Color("ffd58a") if value != saved or conflict else Color("9fb0ad")
	block.status.add_theme_color_override("font_color", color)


func _draft_text(field: Dictionary) -> String:
	return str(_drafts_by_field.get(str(field.key), str(field.default)))


func _update_entity_status() -> void:
	if _selected.is_empty():
		_entity_status.text = ""
		return
	var modified := _entity_modified_count(_selected)
	var dirty := _entity_dirty_count(_selected)
	_entity_status.text = "%d 个字段 · %d 已修改%s" % [
		_selected.fields.size(),
		modified,
		(" · %d 未保存" % dirty) if dirty > 0 else "",
	]
	if is_instance_valid(_save_entity_button):
		_save_entity_button.text = "保存" + ("  ·  %d" % dirty if dirty > 0 else "")


func _entity_modified_count(entity: Dictionary) -> int:
	var count := 0
	for field in entity.fields:
		if _draft_text(field) != str(field.default):
			count += 1
	return count


func _entity_dirty_count(entity: Dictionary) -> int:
	var count := 0
	for field in entity.fields:
		if _draft_text(field) != str(_saved_by_field.get(field.key, field.default)):
			count += 1
	return count


func _dirty_count() -> int:
	var count := 0
	for field in _fields_all:
		if _draft_text(field) != str(_saved_by_field.get(field.key, field.default)):
			count += 1
	if _orphans_draft != _saved_orphans:
		count += 1
	return count


func _update_dirty() -> void:
	var count := _dirty_count()
	if is_instance_valid(_dirty_label):
		_dirty_label.text = ("有 %d 条未保存修改" % count if count > 0 else "全部修改已保存")
		_dirty_label.add_theme_color_override(
			"font_color", Color("ffd58a") if count > 0 else Color("9fb0ad")
		)
	if is_instance_valid(_save_button):
		_save_button.text = "保存全部  Ctrl+S" + ("  ·  %d" % count if count > 0 else "")
	_update_entity_status()


func _values_for_fields(only_keys: Array = []) -> Dictionary:
	var values: Dictionary = _saved_orphans.duplicate(true)
	if only_keys.is_empty():
		values = _orphans_draft.duplicate(true)
	var restrict: Dictionary = {}
	for key in only_keys:
		restrict[str(key)] = true
	for field in _fields_all:
		var key := str(field.key)
		var use_draft := only_keys.is_empty() or restrict.has(key)
		var text := _draft_text(field) if use_draft else str(_saved_by_field.get(key, field.default))
		if text == str(field.default):
			for uid in field.uids:
				values.erase(uid)
		else:
			for uid in field.uids:
				values[uid] = text
	return values


func _save_entity() -> void:
	if _selected.is_empty():
		return
	var keys: Array = []
	var entity_id := str(_selected.id)
	for field in _selected.fields:
		keys.append(str(field.key))
	var error := TextOverrides.save_values(_values_for_fields(keys))
	if not error.is_empty():
		_set_notice(error, true)
		return
	_after_save()
	_set_notice("已保存「%s」的全部字段。" % str(_selected.title), false)


func _save() -> void:
	var error := TextOverrides.save_values(_values_for_fields())
	if not error.is_empty():
		_set_notice(error, true)
		return
	if _reset_all_armed:
		_disarm_reset_all()
	_after_save()
	_set_notice("已保存全部修改。返回菜单或继续游戏后使用新文案。", false)


func _after_save() -> void:
	_saved_uid_values = TextOverrides.snapshot()
	_saved_orphans.clear()
	for uid in _saved_uid_values:
		if not _field_by_uid.has(uid):
			_saved_orphans[uid] = str(_saved_uid_values[uid])
	_orphans_draft = _saved_orphans.duplicate(true)
	_conflict_fields.clear()
	for field in _fields_all:
		var value := _read_field_from(_saved_uid_values, field)
		_saved_by_field[field.key] = value
		if _field_has_conflict(_saved_uid_values, field):
			_conflict_fields[field.key] = true
	_exit_armed = false
	if is_instance_valid(_back_button):
		_back_button.text = "返回  Esc"
	for key in _field_blocks:
		_refresh_field_state(str(key))
	_update_dirty()
	for id in _item_buttons:
		_update_item(str(id))
	if not selected_id.is_empty():
		_update_entity_status()


func _reset_field(key: String) -> void:
	if not _field_blocks.has(key):
		return
	var field: Dictionary = _field_blocks[key].field
	_drafts_by_field[key] = str(field.default)
	_restoring_input = true
	var input: Control = _field_blocks[key].input
	if input is TextEdit:
		input.text = str(field.default)
	elif input is LineEdit:
		input.text = str(field.default)
	_restoring_input = false
	_refresh_field_state(key)
	_update_entity_status()
	_update_dirty()
	if not selected_id.is_empty():
		_update_item(selected_id)
	_set_notice("已恢复「%s」的原始文本；保存后写入。" % str(field.label), false)


func _reset_entity() -> void:
	if _selected.is_empty():
		return
	for field in _selected.fields:
		_drafts_by_field[str(field.key)] = str(field.default)
	_refresh_entity_fields()
	_set_notice("已恢复「%s」的全部字段；保存后写入。" % str(_selected.title), false)


func _undo_entity() -> void:
	if _selected.is_empty():
		return
	for field in _selected.fields:
		_drafts_by_field[str(field.key)] = str(_saved_by_field.get(field.key, field.default))
	_refresh_entity_fields()
	_set_notice("已撤销「%s」的未保存修改。" % str(_selected.title), false)


func _refresh_entity_fields() -> void:
	for key in _field_blocks:
		var block: Dictionary = _field_blocks[key]
		var field: Dictionary = block.field
		var value := str(_drafts_by_field.get(str(field.key), field.default))
		_restoring_input = true
		var input: Control = block.input
		if input is TextEdit:
			input.text = value
		elif input is LineEdit:
			input.text = value
		_restoring_input = false
		_refresh_field_state(str(key))
	_update_entity_status()
	_update_dirty()
	if not selected_id.is_empty():
		_update_item(selected_id)


func _clear_editor() -> void:
	_selected = {}
	selected_id = ""
	_expanded_field = ""
	if is_instance_valid(_entity_title):
		_entity_title.text = "从左侧选择一个实体"
	if is_instance_valid(_entity_meta):
		_entity_meta.text = "先搜索实体，再编辑它的全部文本字段。"
	if is_instance_valid(_entity_status):
		_entity_status.text = ""
	if is_instance_valid(_entity_note):
		_entity_note.text = "修改只作用于显示文案；规则、数值、命令与存档不会被改写。"
	if is_instance_valid(_fields_box):
		for child in _fields_box.get_children():
			_fields_box.remove_child(child)
			child.queue_free()
	_field_blocks.clear()
	for button in [_save_entity_button, _undo_entity_button, _reset_entity_button]:
		if is_instance_valid(button):
			button.disabled = true


func _request_back() -> void:
	if _dirty_count() > 0 and not _exit_armed:
		_exit_armed = true
		_back_button.text = "再次返回（放弃修改）"
		_set_notice("有未保存的修改。再次点击返回或按 Esc 将放弃这些修改。", true)
		_back_timer.start()
		return
	action_requested.emit({"type": "ui.text_editor_back", "payload": {}})


func _disarm_back() -> void:
	if not is_instance_valid(_back_button):
		return
	_exit_armed = false
	_back_button.text = "返回  Esc"


func _request_reset_all() -> void:
	if _reset_all_armed:
		_disarm_reset_all()
		for field in _fields_all:
			_drafts_by_field[str(field.key)] = str(field.default)
		_orphans_draft.clear()
		_refresh_entity_fields()
		_update_dirty()
		_set_notice("已恢复全部原始文本；点击保存全部后写入。", false)
		return
	_reset_all_armed = true
	_reset_all_button.text = "确认恢复全部？再次点击"
	_set_notice("再次点击将清除所有本机文本覆盖（取消可点击其他按钮）。", true)
	_reset_timer.start()


func _disarm_reset_all() -> void:
	_reset_all_armed = false
	if is_instance_valid(_reset_all_button):
		_reset_all_button.text = "全部重置"


func _set_notice(message: String, error: bool) -> void:
	if not is_instance_valid(_notice):
		return
	_notice.text = message
	_notice.add_theme_color_override("font_color", Color("ffb9a8") if error else Color("c5b99f"))


func _short_text(value: String, limit: int) -> String:
	var text := value.replace("\n", " ").replace("\r", " ").strip_edges()
	if text.is_empty():
		return "（空白）"
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "…"


func _update_count() -> void:
	if not is_instance_valid(_count):
		return
	_count.text = "实体 %d · 字段 %d · 匹配 %d · 已显示 %d" % [
		library.size(), field_count, filtered.size(), visible_entities.size()
	]


func export_state() -> Dictionary:
	return {
		"tab": tab,
		"query": query,
		"filter": filter_value,
		"filter2": filter2_value,
		"selected": selected_id,
		"expanded": _expanded_field,
		"scroll": _left_scroll.scroll_vertical if is_instance_valid(_left_scroll) else 0,
	}


func import_state(state: Dictionary) -> void:
	initial_state = state.duplicate(true)


func select_entity(id: String) -> bool:
	if not _entity_by_id.has(id):
		return false
	_select_entity(id, "", false)
	return true


func select_entity_matching(id: String) -> bool:
	if not _entity_by_id.has(id):
		return false
	var match: Dictionary = _match_by_id.get(id, {})
	_select_entity(id, str(match.get("field", "")), false)
	return true


func expand_field(key: String) -> bool:
	if not _field_blocks.has(key):
		return false
	_expand_field(key, true)
	return true


func set_field_text(key: String, value: String) -> bool:
	if not _field_blocks.has(key):
		return false
	var block: Dictionary = _field_blocks[key]
	_restoring_input = true
	if block.input is TextEdit:
		block.input.text = value
	elif block.input is LineEdit:
		block.input.text = value
	_restoring_input = false
	_on_field_changed(key)
	return true


func field_text(key: String) -> String:
	if not _field_blocks.has(key):
		return ""
	var input: Control = _field_blocks[key].input
	if input is TextEdit:
		return str(input.text)
	if input is LineEdit:
		return str(input.text)
	return ""


func field_key_for_uid(uid: String) -> String:
	return str(_field_by_uid.get(uid, {}).get("key", ""))


func entity_field_keys(id: String) -> Array:
	var keys: Array = []
	if not _entity_by_id.has(id):
		return keys
	for field in _entity_by_id[id].fields:
		keys.append(str(field.key))
	return keys


func save_entity() -> String:
	_save_entity()
	return TextOverrides.last_error()


func save_changes() -> String:
	_save()
	return TextOverrides.last_error()


func dirty_count() -> int:
	return _dirty_count()


func entity_count(id: String) -> int:
	return _entity_by_id.size() if id.is_empty() else (1 if _entity_by_id.has(id) else 0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_S:
			_save()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()
