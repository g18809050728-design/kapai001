class_name UiTextEditorPage
extends UiPage

const BATCH_SIZE := 12
const TABS := [
	["all", "全部"],
	["names", "名称"],
	["descriptions", "说明"],
	["story", "剧情"],
	["glossary", "词条"],
]
const NAME_CATEGORIES := [
	"人物", "卡牌", "任务 / 怪物", "饰品", "伙伴", "事件", "状态 / 术语",
	"场景 / 房间", "背景", "界面提示", "其他"
]
const DESCRIPTION_CATEGORIES := ["卡牌", "饰品", "人物"]
const STORY_CATEGORIES := ["事件", "房间"]

var library: Array[Dictionary] = []
var counts: Dictionary = {}
var filtered: Array[Dictionary] = []
var visible_entries: Array[Dictionary] = []
var tab := "all"
var query := ""
var name_filter := ""
var description_filter := ""
var story_filter := ""
var selected_uid := ""
var initial_state: Dictionary = {}
var _saved: Dictionary = {}
var _edits: Dictionary = {}
var _entry_by_uid: Dictionary = {}
var _item_buttons: Dictionary = {}
var _item_titles: Dictionary = {}
var _item_meta: Dictionary = {}
var _item_preview: Dictionary = {}
var _selected: Dictionary = {}
var _tabs: Dictionary = {}
var _search: LineEdit
var _filter: OptionButton
var _count: Label
var _list: VBoxContainer
var _left_scroll: ScrollContainer
var _editor_title: Label
var _editor_meta: Label
var _editor_status: Label
var _editor_placeholder: Label
var _text_edit: TextEdit
var _default_panel: PanelContainer
var _default_label: Label
var _default_button: Button
var _reset_entry_button: Button
var _undo_button: Button
var _save_button: Button
var _back_button: Button
var _reset_all_button: Button
var _dirty_label: Label
var _notice: Label
var _search_timer: Timer
var _back_timer: Timer
var _reset_timer: Timer
var _visible_count := 0
var _restoring_text := false
var _exit_armed := false
var _reset_all_armed := false


func render(data: Dictionary) -> void:
	view = data
	library = data.get("entries", [])
	counts = data.get("counts", {})
	_saved = TextOverrides.snapshot()
	_edits = _saved.duplicate(true)
	_entry_by_uid.clear()
	_item_buttons.clear()
	_item_titles.clear()
	_item_meta.clear()
	_item_preview.clear()
	_selected = {}
	selected_uid = ""
	_visible_count = 0
	_restoring_text = false
	_exit_armed = false
	_reset_all_armed = false
	tab = str(initial_state.get("tab", "all"))
	query = str(initial_state.get("query", ""))
	name_filter = str(initial_state.get("name_filter", ""))
	description_filter = str(initial_state.get("description_filter", ""))
	story_filter = str(initial_state.get("story_filter", ""))
	selected_uid = str(initial_state.get("selected", ""))
	if not counts.has(tab):
		tab = "all"
	for entry in library:
		var uid := str(entry.get("uid", ""))
		if uid.is_empty():
			continue
		_entry_by_uid[uid] = entry
		entry["search"] = (
			uid + " " + str(entry.get("id", "")) + " " + str(entry.get("title", "")) + " "
			+ str(entry.get("category", "")) + " " + str(entry.get("default", ""))
		).to_lower()
	_build_ui()
	if data.has("error"):
		_show_library_error(str(data.get("error", "")))
		return
	_build_filter_options()
	_refresh_filter(true)
	var saved_error := TextOverrides.last_error()
	if not saved_error.is_empty():
		_set_notice(saved_error, true)
	else:
		_set_notice("修改保存在本机覆盖文件；原始文本仍保留，可随时恢复默认。", false)
	if int(initial_state.get("scroll", 0)) > 0:
		_restore_initial_scroll.call_deferred(int(initial_state.get("scroll", 0)), 2)
	_focus_search.call_deferred()


func _focus_search() -> void:
	if not UiStyle.web_touch and is_inside_tree() and is_instance_valid(_search):
		_search.grab_focus()


func _focus_editor() -> void:
	if is_inside_tree() and is_instance_valid(_text_edit):
		_text_edit.grab_focus()


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
		"检索并修改名称、剧情、词条与说明；只改显示，不改规则/数值/命令/存档。",
		14,
		Color("b9c7bf")
	)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	header.add_child(tools)
	_search = LineEdit.new()
	_search.name = "TextEditorSearch"
	_search.placeholder_text = "搜索文本、ID、来源或分类  /"
	_search.text = query
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2((220 if UiStyle.web_touch else 300) * minf(UiStyle.text_scale, 1.2), UiStyle.MOBILE_TARGET if UiStyle.web_touch else 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	_search.add_theme_color_override("font_color", UiStyle.CREAM)
	_search.add_theme_color_override("font_placeholder_color", Color("8ea0a2"))
	var search_skin := UiStyle.surface(Color("0d1820"), Color("607a84"), 4)
	_search.add_theme_stylebox_override("normal", search_skin)
	_search.text_changed.connect(_on_search_changed)
	tools.add_child(_search)
	_filter = OptionButton.new()
	_filter.name = "TextEditorFilter"
	_filter.custom_minimum_size = Vector2((148 if UiStyle.web_touch else 190) * minf(UiStyle.text_scale, 1.2), UiStyle.MOBILE_TARGET if UiStyle.web_touch else 44)
	_filter.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
	_filter.add_theme_color_override("font_color", UiStyle.CREAM)
	_filter.add_theme_stylebox_override("normal", UiStyle.surface(Color("20353d"), Color("657c85"), 4))
	_filter.add_theme_stylebox_override("hover", UiStyle.surface(Color("2b4550"), Color("8aa3aa"), 4))
	_filter.add_theme_stylebox_override("pressed", UiStyle.surface(Color("193039"), Color("8aa3aa"), 4))
	_filter.item_selected.connect(_on_filter_selected)
	tools.add_child(_filter)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	header.add_child(tab_row)
	for spec in TABS:
		var key := str(spec[0])
		var button := add_button(
			tab_row,
			"text_editor:tab:" + key,
			"%s  %d" % [str(spec[1]), int(counts.get(key, 0))],
			{},
			func(): show_tab(key)
		)
		button.custom_minimum_size = Vector2((72 if UiStyle.web_touch else 104) * minf(UiStyle.text_scale, 1.2), UiStyle.MOBILE_TARGET if UiStyle.web_touch else 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_save_button = add_button(actions, "text_editor:save", "保存修改  Ctrl+S", {}, _save)
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
	_update_dirty()


func _build_list_pane(parent: Node) -> void:
	var panel := PanelContainer.new()
	var page_width := size.x if size.x > 0 else 1280.0
	panel.custom_minimum_size.x = clampf(page_width * 0.34, (188 if UiStyle.web_touch else 320) * minf(UiStyle.text_scale, 1.1), 440)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var skin := UiStyle.surface(Color("111f28"), Color("3c525d"), 6)
	skin.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", skin)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var hint := add_text(column, "文本条目", 15, Color("d8c9a6"))
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
	form.add_theme_constant_override("separation", 9)
	scroll.add_child(form)
	_editor_title = add_text(form, "从左侧选择一条文本", 23, UiStyle.BRASS)
	_editor_title.add_theme_font_override("font", UiStyle.title_font())
	_editor_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_meta = add_text(form, "", 13, Color("93a8aa"))
	_editor_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_status = add_text(form, "", 13, Color("c5b99f"))
	_editor_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_edit = TextEdit.new()
	_text_edit.name = "TextEditorInput"
	var editor_height := 270.0 - (minf(UiStyle.text_scale, 1.5) - 1.0) * 220.0
	_text_edit.custom_minimum_size = Vector2(0, maxf(150.0, editor_height))
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.placeholder_text = "在此修改文本…"
	_text_edit.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	_text_edit.add_theme_color_override("font_color", UiStyle.CREAM)
	_text_edit.add_theme_color_override("caret_color", Color("ffe0a0"))
	var editor_normal := UiStyle.surface(Color("0c161d"), Color("5d7782"), 4)
	editor_normal.set_content_margin_all(8)
	var editor_focus := UiStyle.surface(Color("0c161d"), Color("d8b468"), 4)
	editor_focus.set_content_margin_all(8)
	_text_edit.add_theme_stylebox_override("normal", editor_normal)
	_text_edit.add_theme_stylebox_override("focus", editor_focus)
	_text_edit.text_changed.connect(_on_edit_text_changed)
	_text_edit.editable = false
	form.add_child(_text_edit)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 6)
	form.add_child(tools)
	_default_button = add_button(
		tools, "text_editor:default", "查看默认文本", {}, _toggle_default
	)
	_default_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_default_button, "quiet", true)
	_reset_entry_button = add_button(
		tools, "text_editor:reset_entry", "恢复本条默认", {}, _reset_entry
	)
	_reset_entry_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_reset_entry_button, "quiet", true)
	_undo_button = add_button(tools, "text_editor:undo", "撤销未保存", {}, _undo_entry)
	_undo_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(_undo_button, "quiet", true)
	_default_panel = PanelContainer.new()
	_default_panel.visible = false
	var default_skin := UiStyle.surface(Color("0b141a"), Color("4c625d"), 4)
	default_skin.set_content_margin_all(10)
	_default_panel.add_theme_stylebox_override("panel", default_skin)
	form.add_child(_default_panel)
	var default_column := VBoxContainer.new()
	default_column.add_theme_constant_override("separation", 4)
	_default_panel.add_child(default_column)
	add_text(default_column, "原始文本（只读）", 13, Color("c5b99f"))
	var default_scroll := ScrollContainer.new()
	default_scroll.custom_minimum_size.y = 150
	default_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	default_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	default_column.add_child(default_scroll)
	_default_label = Label.new()
	_default_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_default_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_default_label.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	_default_label.add_theme_color_override("font_color", Color("cbd6cc"))
	default_scroll.add_child(_default_label)
	_editor_placeholder = add_text(
		form,
		"修改只作用于显示文案。卡面数值、费用、效果、RNG、命令与存档不会被改写。",
		12,
		Color("8ea0a2")
	)
	_editor_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _show_library_error(message: String) -> void:
	_clear_editor()
	_editor_title.text = "文本库暂时不可用"
	_editor_meta.text = message
	_editor_placeholder.text = "可返回主菜单继续游戏；当前文案与规则没有变化。"
	_text_edit.editable = false
	_default_button.disabled = true
	_reset_entry_button.disabled = true
	_undo_button.disabled = true
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
	if _filter == null:
		return
	_filter.clear()
	_filter.visible = tab in ["names", "descriptions", "story"]
	if not _filter.visible:
		return
	var categories: Array = []
	var current := ""
	var first := "全部名称"
	match tab:
		"names":
			categories = NAME_CATEGORIES
			current = name_filter
			first = "全部名称"
		"descriptions":
			categories = DESCRIPTION_CATEGORIES
			current = description_filter
			first = "全部说明"
		"story":
			categories = STORY_CATEGORIES
			current = story_filter
			first = "全部剧情"
	_filter.add_item(first)
	_filter.set_item_metadata(0, "")
	var selected_index := 0
	for category in categories:
		_filter.add_item(str(category))
		var index := _filter.item_count - 1
		_filter.set_item_metadata(index, str(category))
		if str(category) == current:
			selected_index = index
	_filter.select(selected_index)


func _on_filter_selected(index: int) -> void:
	var value := str(_filter.get_item_metadata(index)) if index >= 0 else ""
	match tab:
		"names":
			name_filter = value
		"descriptions":
			description_filter = value
		"story":
			story_filter = value
	_refresh_filter(true)


func show_tab(value: String) -> void:
	if not counts.has(value):
		return
	tab = value
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
	match tab:
		"names":
			name_filter = value
		"descriptions":
			description_filter = value
		"story":
			story_filter = value
		_:
			return
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
	for entry in library:
		if not _matches_tab(entry):
			continue
		if not _matches_category(entry):
			continue
		var search_text := str(entry.get("search", ""))
		search_text += " " + _current_text(entry).to_lower()
		var matched := true
		for token in tokens:
			if not search_text.contains(token):
				matched = false
				break
		if matched:
			filtered.append(entry)
	if reset_scroll and is_instance_valid(_left_scroll):
		_left_scroll.scroll_vertical = 0
	_render_list(true)
	_ensure_selection_in_filter()


func _ensure_selection_in_filter() -> void:
	if filtered.is_empty():
		if not selected_uid.is_empty():
			_clear_editor()
		return
	for entry in filtered:
		if str(entry.get("uid", "")) == selected_uid:
			return
	_select_entry(str(filtered[0].get("uid", "")), false)


func _matches_tab(entry: Dictionary) -> bool:
	if tab == "all":
		return true
	return str(entry.get("group", "")) == tab


func _matches_category(entry: Dictionary) -> bool:
	match tab:
		"names":
			return name_filter.is_empty() or str(entry.get("category", "")) == name_filter
		"descriptions":
			return (
				description_filter.is_empty()
				or str(entry.get("category", "")) == description_filter
			)
		"story":
			return story_filter.is_empty() or str(entry.get("category", "")) == story_filter
	return true


func _render_list(reset: bool) -> void:
	if reset:
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()
		_item_buttons.clear()
		_item_titles.clear()
		_item_meta.clear()
		_item_preview.clear()
		visible_entries.clear()
		_visible_count = mini(BATCH_SIZE, filtered.size())
	else:
		_visible_count = mini(_visible_count + BATCH_SIZE, filtered.size())
	var start := visible_entries.size()
	for index in range(start, _visible_count):
		var entry: Dictionary = filtered[index]
		visible_entries.append(entry)
		_make_item(entry)
	if filtered.is_empty():
		var empty := add_text(
			_list, "没有匹配的文本。可清空搜索，或切换分类后再试。", 15, Color("9fb0ad")
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 80
	_update_count()


func _make_item(entry: Dictionary) -> void:
	var uid := str(entry.get("uid", ""))
	var button := add_button(
		_list,
		"text_editor:item:" + uid,
		"",
		{},
		Callable(self, "_select_entry").bind(uid)
	)
	button.custom_minimum_size.y = 100 * minf(UiStyle.text_scale, 1.2)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = str(entry.get("uid", ""))
	UiStyle.button_skin(button, "selected" if uid == selected_uid else "secondary", true)
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
	title.text = str(entry.get("title", entry.get("uid", "")))
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
	meta.text = "%s  ·  %s" % [str(entry.get("category", "")), uid]
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_theme_font_size_override("font_size", roundi(12 * UiStyle.text_scale))
	meta.add_theme_color_override("font_color", Color("8ea8aa"))
	column.add_child(meta)
	var preview := Label.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.autowrap_mode = TextServer.AUTOWRAP_OFF
	preview.max_lines_visible = 1
	preview.custom_minimum_size.y = roundi(18 * UiStyle.text_scale)
	preview.clip_text = true
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.add_theme_font_size_override("font_size", roundi(13 * UiStyle.text_scale))
	preview.add_theme_color_override("font_color", Color("c1cec5"))
	column.add_child(preview)
	_item_buttons[uid] = button
	_item_titles[uid] = title
	_item_meta[uid] = meta
	_item_preview[uid] = preview
	_update_item(uid)


func _update_item(uid: String) -> void:
	if not _item_buttons.has(uid) or not _entry_by_uid.has(uid):
		return
	var entry: Dictionary = _entry_by_uid[uid]
	var current := _current_text(entry)
	var modified := current != str(entry.get("default", ""))
	_item_meta[uid].text = "%s  ·  %s%s" % [
		str(entry.get("category", "")),
		uid,
		"  ·  已修改" if modified else "",
	]
	_item_preview[uid].text = _short_text(current, 92)
	if current == str(entry.get("title", "")):
		_item_preview[uid].text = ""
	_item_preview[uid].visible = not _item_preview[uid].text.is_empty()
	_item_buttons[uid].custom_minimum_size.y = (
		(100 if _item_preview[uid].visible else 76) * minf(UiStyle.text_scale, 1.2)
	)
	_item_titles[uid].text = str(entry.get("title", uid))


func _update_count() -> void:
	if not is_instance_valid(_count):
		return
	if filtered.is_empty():
		_count.text = "库中 %d 条 · 当前无匹配" % library.size()
		return
	_count.text = "库中 %d 条 · 匹配 %d · 已显示 %d" % [
		library.size(), filtered.size(), visible_entries.size()
	]


func _on_list_scrolled(value: float) -> void:
	if _visible_count >= filtered.size():
		return
	var bar := _left_scroll.get_v_scroll_bar()
	if value >= bar.max_value - bar.page - 48:
		_render_list(false)


func _select_entry(uid: String, focus_editor: bool = true) -> void:
	if not _entry_by_uid.has(uid):
		return
	selected_uid = uid
	_selected = _entry_by_uid[uid]
	_editor_title.text = str(_selected.get("title", uid))
	_editor_meta.text = "%s  ·  %s  ·  %s" % [
		str(_selected.get("category", "")),
		str(_selected.get("source", "")),
		uid,
	]
	_text_edit.editable = true
	_restoring_text = true
	_text_edit.text = _current_text(_selected)
	_restoring_text = false
	_default_label.text = str(_selected.get("default", ""))
	_default_panel.visible = false
	_default_button.text = "查看默认文本"
	_editor_placeholder.text = str(
		_selected.get("note", "修改只作用于显示文案；规则、数值、命令与存档不会被改写。")
	)
	_editor_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_default_button.disabled = false
	_reset_entry_button.disabled = false
	_undo_button.disabled = false
	_save_button.disabled = false
	_reset_all_button.disabled = false
	_update_editor_state()
	for item_uid in _item_buttons:
		UiStyle.button_skin(
			_item_buttons[item_uid],
			"selected" if str(item_uid) == uid else "secondary",
			true
		)
		_update_item(str(item_uid))
	if focus_editor and is_instance_valid(_text_edit):
		_focus_editor.call_deferred()


func _clear_editor() -> void:
	_selected = {}
	selected_uid = ""
	if is_instance_valid(_editor_title):
		_editor_title.text = "从左侧选择一条文本"
	if is_instance_valid(_editor_meta):
		_editor_meta.text = "可按名称、ID、来源或正文自由搜索。"
	if is_instance_valid(_text_edit):
		_restoring_text = true
		_text_edit.text = ""
		_restoring_text = false
		_text_edit.editable = false
	if is_instance_valid(_default_panel):
		_default_panel.visible = false
	if is_instance_valid(_default_button):
		_default_button.text = "查看默认文本"
	if is_instance_valid(_default_label):
		_default_label.text = ""
	if is_instance_valid(_editor_placeholder):
		_editor_placeholder.text = "修改只作用于显示文案；规则、数值、命令与存档不会被改写。"
	if is_instance_valid(_editor_status):
		_editor_status.text = ""
	for button in [_default_button, _reset_entry_button, _undo_button]:
		if is_instance_valid(button):
			button.disabled = true


func _current_text(entry: Dictionary) -> String:
	var uid := str(entry.get("uid", ""))
	return str(_edits[uid]) if _edits.has(uid) else str(entry.get("default", ""))


func select_entry(uid: String) -> bool:
	if not _entry_by_uid.has(uid):
		return false
	_select_entry(uid, false)
	return true


func set_editor_text(value: String) -> void:
	if _selected.is_empty() or not is_instance_valid(_text_edit):
		return
	_restoring_text = true
	_text_edit.text = value
	_restoring_text = false
	_on_edit_text_changed()


func editor_text() -> String:
	return _text_edit.text if is_instance_valid(_text_edit) else ""


func save_changes() -> String:
	_save()
	return TextOverrides.last_error()


func dirty_count() -> int:
	return _dirty_count()


func _on_edit_text_changed() -> void:
	if _restoring_text or _selected.is_empty():
		return
	var uid := str(_selected.get("uid", ""))
	var value := _text_edit.text
	if value == str(_selected.get("default", "")):
		_edits.erase(uid)
	else:
		_edits[uid] = value
	_update_editor_state()
	_update_item(uid)
	_update_dirty()


func _update_editor_state() -> void:
	if _selected.is_empty():
		_editor_status.text = ""
		return
	var uid := str(_selected.get("uid", ""))
	var current := _current_text(_selected)
	var default_text := str(_selected.get("default", ""))
	if current == default_text:
		_editor_status.text = "与原始文本一致 · %d 字" % current.length()
	else:
		_editor_status.text = "已修改 · %d 字 · 尚未保存" % current.length()


func _dirty_count() -> int:
	var keys: Dictionary = {}
	for key in _saved:
		keys[key] = true
	for key in _edits:
		keys[key] = true
	var count := 0
	for key in keys:
		if str(_saved.get(key, "")) != str(_edits.get(key, "")):
			count += 1
	return count


func _update_dirty() -> void:
	var count := _dirty_count()
	if is_instance_valid(_dirty_label):
		_dirty_label.text = (
			"有 %d 条未保存修改" % count if count > 0 else "全部修改已保存"
		)
		_dirty_label.add_theme_color_override(
			"font_color", Color("ffd58a") if count > 0 else Color("9fb0ad")
		)
	if is_instance_valid(_save_button):
		_save_button.text = "保存修改  Ctrl+S" + ("  ·  %d" % count if count > 0 else "")


func _save() -> void:
	var error := TextOverrides.save_values(_edits)
	if not error.is_empty():
		_set_notice(error, true)
		return
	if _reset_all_armed:
		_disarm_reset_all()
	_saved = TextOverrides.snapshot()
	_edits = _saved.duplicate(true)
	_exit_armed = false
	_back_button.text = "返回  Esc"
	_update_dirty()
	if not _selected.is_empty():
		_update_editor_state()
		var uid := str(_selected.get("uid", ""))
		_update_item(uid)
	for uid in _item_buttons:
		_update_item(str(uid))
	_set_notice("已保存到本机。返回菜单或继续游戏后，相关文案使用新内容。", false)


func _toggle_default() -> void:
	if _selected.is_empty():
		return
	_default_panel.visible = not _default_panel.visible
	_default_button.text = "收起默认文本" if _default_panel.visible else "查看默认文本"
	if _default_panel.visible:
		_default_label.text = str(_selected.get("default", ""))


func _reset_entry() -> void:
	if _selected.is_empty():
		return
	var uid := str(_selected.get("uid", ""))
	_edits.erase(uid)
	_restoring_text = true
	_text_edit.text = str(_selected.get("default", ""))
	_restoring_text = false
	_update_editor_state()
	_update_item(uid)
	_update_dirty()
	_set_notice("本条已恢复原始文本；点击保存修改后写入。", false)


func _undo_entry() -> void:
	if _selected.is_empty():
		return
	var uid := str(_selected.get("uid", ""))
	if _saved.has(uid):
		_edits[uid] = str(_saved[uid])
	else:
		_edits.erase(uid)
	_restoring_text = true
	_text_edit.text = _current_text(_selected)
	_restoring_text = false
	_update_editor_state()
	_update_item(uid)
	_update_dirty()
	_set_notice("已撤销本条未保存修改。", false)


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
		_edits.clear()
		if not _selected.is_empty():
			_restoring_text = true
			_text_edit.text = str(_selected.get("default", ""))
			_restoring_text = false
			_update_editor_state()
			_update_item(str(_selected.get("uid", "")))
		for uid in _item_buttons:
			_update_item(str(uid))
		_update_dirty()
		_set_notice("已恢复全部原始文本；点击保存修改后写入。", false)
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
	_notice.add_theme_color_override(
		"font_color", Color("ffb9a8") if error else Color("c5b99f")
	)


func _short_text(value: String, limit: int) -> String:
	var text := value.replace("\n", " ").replace("\r", " ").strip_edges()
	if text.is_empty():
		return "（空白）"
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "…"


func export_state() -> Dictionary:
	return {
		"tab": tab,
		"query": query,
		"name_filter": name_filter,
		"description_filter": description_filter,
		"story_filter": story_filter,
		"selected": selected_uid,
		"scroll": _left_scroll.scroll_vertical if is_instance_valid(_left_scroll) else 0,
	}


func import_state(state: Dictionary) -> void:
	initial_state = state.duplicate(true)
	if not initial_state.has("scroll"):
		return
	var target := int(initial_state.get("scroll", 0))
	if target <= 0 or not is_instance_valid(_left_scroll):
		return
	_left_scroll.scroll_vertical = target


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_S:
			_save()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_default_panel) and _default_panel.visible:
			_toggle_default()
			get_viewport().set_input_as_handled()
			return
		_request_back()
		get_viewport().set_input_as_handled()
