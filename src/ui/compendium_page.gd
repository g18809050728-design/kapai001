class_name UiCompendiumPage
extends UiPage

const PAGE_SIZE := 8
const TABS := {"cards": "卡牌", "monsters": "怪物", "relics": "饰品"}

var tab := "cards"
var filtered_ids: Array[String] = []
var visible_ids: Array[String] = []
var detail: UiCompendiumDetail
var _entries: Dictionary = {"cards": {}, "monsters": {}, "relics": {}}
var _order: Dictionary = {"cards": [], "monsters": [], "relics": []}
var _states := {
	"cards": {"query": "", "owner": "", "type": "", "rarity": "", "loaded": PAGE_SIZE, "scroll": 0},
	"relics": {"query": "", "owner": "", "rarity": "", "year": "", "loaded": PAGE_SIZE, "scroll": 0},
	"monsters": {"query": "", "kind": "", "year": "", "loaded": PAGE_SIZE, "scroll": 0},
}
var _filters: HFlowContainer
var _search: LineEdit
var _grid: GridContainer
var _gallery: VBoxContainer
var _count: Label
var _page_count: Label
var _tabs: Dictionary = {}
var _timer: Timer
var _layout_columns := 0
var _layout_pending := false
var _restoring_scroll := false
var _append_pending := false


func render(data: Dictionary) -> void:
	if is_instance_valid(detail):
		detail.close()
	view = data.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_drafts.clear()
	_entries = {"cards": {}, "monsters": {}, "relics": {}}
	_order = {"cards": [], "monsters": [], "relics": []}
	for kind_name in TABS:
		for entry in view.get(kind_name, []):
			_entries[kind_name][entry.id] = entry
			_order[kind_name].append(str(entry.id))
			var search_parts: PackedStringArray = [str(entry.id), CompendiumText.title(entry, kind_name == "monsters")]
			if kind_name == "cards":
				for variant in entry.variants:
					search_parts.append(CompendiumText.card_text(variant))
			elif kind_name == "relics":
				search_parts.append(UiContentText.describe_relic(entry.definition) + " " + CompendiumText.relic_group_text(entry) + " " + CompendiumText.relic_source(entry))
			else:
				for section in CompendiumText.monster_sections(entry):
					search_parts.append(section.title + " " + section.text)
			entry["search"] = " ".join(search_parts).to_lower()
	var backdrop := RoomSceneView.new()
	backdrop.room = "settings"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color("091219", .88)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	header = VBoxContainer.new()
	column.add_child(header)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 20)
	header.add_child(heading)
	var title := add_text(heading, "图 鉴", 28, UiStyle.BRASS)
	title.add_theme_font_override("font", UiStyle.title_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	heading.add_child(tabs)
	_tabs.clear()
	for kind_name in TABS:
		var caption := str(TABS[kind_name]) + "  ·  %s" % _order[kind_name].size()
		var button := add_button(tabs, "compendium:tab:" + kind_name, caption, {}, func(): show_tab(kind_name))
		button.custom_minimum_size = Vector2(150 * minf(UiStyle.text_scale, 1.25), 44)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_tabs[kind_name] = button
	_filters = HFlowContainer.new()
	_filters.add_theme_constant_override("h_separation", 10)
	_filters.add_theme_constant_override("v_separation", 8)
	column.add_child(_filters)
	_count = add_text(column, "", 14, Color("c5b99f"))
	_count.name = "CompendiumCount"
	_scroll = ScrollContainer.new()
	_scroll.name = "CompendiumGalleryScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.get_v_scroll_bar().value_changed.connect(_gallery_scrolled)
	column.add_child(_scroll)
	_gallery = VBoxContainer.new()
	_gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_gallery)
	footer = VBoxContainer.new()
	column.add_child(footer)
	var line := HSeparator.new()
	line.modulate = Color(UiStyle.BRASS, .5)
	footer.add_child(line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	footer.add_child(actions)
	var back := add_button(actions, "compendium:back", "返回  Esc", {"type": "ui.compendium_back", "payload": {}})
	back.custom_minimum_size.x = 140 * UiStyle.text_scale
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(back, "quiet", true)
	_page_count = add_text(actions, "", 15, UiStyle.CREAM)
	_page_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_count.tooltip_text = "向下滚动继续浏览 · PageUp / PageDown 滚动 · Home / End 到顶部 / 末尾"
	_timer = Timer.new()
	_timer.wait_time = .16
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(func(): _render_results())
	if not resized.is_connected(_resize_gallery):
		resized.connect(_resize_gallery)
	show_tab(tab)
	if not str(view.get("error", "")).is_empty():
		_count.text = "图鉴加载失败：" + str(view.error)
		_count.add_theme_color_override("font_color", Color("efb4a5"))
	_queue_focus("compendium:tab:" + tab)


func show_tab(value: String) -> void:
	if not _states.has(value) or is_instance_valid(detail):
		return
	_timer.stop()
	if value != tab and is_instance_valid(_scroll) and not _restoring_scroll:
		_states[tab].scroll = _scroll.scroll_vertical
	tab = value
	for kind_name in _tabs:
		UiStyle.button_skin(_tabs[kind_name], "primary" if kind_name == tab else "quiet", true)
		_tabs[kind_name].tooltip_text = "当前分类" if kind_name == tab else "查看全部" + str(TABS[kind_name])
	for key in _buttons.keys():
		if str(key).begins_with("compendium:filter:"):
			_buttons.erase(key)
	for child in _filters.get_children():
		_filters.remove_child(child)
		child.queue_free()
	_search = LineEdit.new()
	_search.name = "CompendiumSearch"
	_search.placeholder_text = "搜索名称、ID、说明  /"
	_search.text = _states[tab].query
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(260 * minf(UiStyle.text_scale, 1.2), 44)
	_search.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	_filters.add_child(_search)
	_search.text_changed.connect(func(value_text):
		_states[tab].query = value_text
		_states[tab].loaded = PAGE_SIZE
		_states[tab].scroll = 0
		_timer.start())
	if tab == "cards":
		_filter("owner", "人物", ["", "C", "P01", "P02", "P03", "P04", "T"], ["全部", "公共", "林序", "许知微", "沈见章", "唐以宁", "衍生"])
		_filter("type", "类型", ["", "work", "strategy", "cooperation", "scene", "ability", "burden"], ["全部", "作业", "策略", "合作", "场景", "能力", "负担"])
		_filter("rarity", "稀有度", ["", "basic", "common", "advanced", "rare", "token"], ["全部", "初始", "普通", "进阶", "稀有", "衍生"])
	elif tab == "relics":
		_filter("owner", "归属", ["", "C", "P01", "P02", "P03", "P04"], ["全部", "通用", "林序", "许知微", "沈见章", "唐以宁"])
		_filter("rarity", "品质", ["", "white", "blue", "purple", "gold"], ["全部", "白色", "蓝色", "紫色", "金色"])
		_filter("year", "学年", ["", "1", "2", "3", "4"], ["全部", "大一", "大二", "大三", "大四"])
	else:
		_filter("kind", "类别", ["", "normal", "elite", "boss", "auxiliary"], ["全部", "普通", "精英", "首领", "附属"])
		_filter("year", "学年", ["", "1", "2", "3", "4"], ["全部", "大一", "大二", "大三", "大四"])
	var clear := add_button(_filters, "compendium:filter:reset", "重置", {}, reset_filters)
	clear.custom_minimum_size.x = 76 * UiStyle.text_scale
	clear.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiStyle.button_skin(clear, "quiet", true)
	_render_results(true)


func _filter(key: String, prefix: String, values: Array, captions: Array) -> void:
	var option := OptionButton.new()
	option.name = "CompendiumFilter_" + key
	option.set_meta("uid", "compendium:filter:" + key)
	option.custom_minimum_size = Vector2((166 if key == "rarity" else 146) * minf(UiStyle.text_scale, 1.25), 44)
	option.add_theme_font_size_override("font_size", roundi(15 * UiStyle.text_scale))
	UiStyle.button_skin(option, "secondary", true)
	for caption in captions:
		option.add_item(prefix + " · " + caption)
	option.select(maxi(0, values.find(_states[tab].get(key, ""))))
	option.item_selected.connect(func(index): set_filter(key, str(values[index])))
	_filters.add_child(option)
	_buttons["compendium:filter:" + key] = option


func set_filter(key: String, value: String) -> void:
	if not _states[tab].has(key) or is_instance_valid(detail):
		return
	_timer.stop()
	_states[tab][key] = value
	_states[tab].loaded = PAGE_SIZE
	_states[tab].scroll = 0
	_render_results()


func search(value: String) -> void:
	_search.text = value
	set_filter("query", value)


func reset_filters() -> void:
	for key in _states[tab]:
		_states[tab][key] = PAGE_SIZE if key == "loaded" else (0 if key in ["page", "scroll"] else "")
	show_tab(tab)


func _matches(entry: Dictionary) -> bool:
	var state: Dictionary = _states[tab]
	for word in str(state.query).strip_edges().to_lower().split(" ", false):
		if not str(entry.search).contains(word):
			return false
	var definition: Dictionary = entry.definition
	if tab == "cards":
		for key in ["owner", "type", "rarity"]:
			var actual := CompendiumText.owner(entry) if key == "owner" else str(definition.get(key, ""))
			if not str(state[key]).is_empty() and actual != state[key]:
				return false
	elif tab == "relics":
		return (str(state.owner).is_empty() or state.owner == CompendiumText.relic_group(entry)) and (str(state.rarity).is_empty() or state.rarity == definition.rarity) and (str(state.year).is_empty() or entry.terms.has(int(state.year)))
	else:
		if not str(state.kind).is_empty():
			if state.kind == "auxiliary":
				if bool(definition.get("victory_required", true)):
					return false
			elif state.kind != definition.get("kind", "normal"):
				return false
		if not str(state.year).is_empty() and not entry.terms.has(int(state.year)):
			return false
	return true


func _render_results(restore: bool = false) -> void:
	_render_generation += 1
	_append_pending = false
	_restoring_scroll = true
	var focused := get_viewport().gui_get_focus_owner()
	var restore_uid := str(focused.get_meta("uid", "")) if is_instance_valid(focused) else ""
	for key in _buttons.keys():
		if str(key).begins_with("compendium:item:"):
			_buttons.erase(key)
	for child in _gallery.get_children():
		_gallery.remove_child(child)
		child.queue_free()
	filtered_ids.clear()
	visible_ids.clear()
	for id in _order[tab]:
		if _matches(_entries[tab][id]):
			filtered_ids.append(id)
	_count.text = "四学年全集 · 全部开放    %s / %s 种%s    点击查看详情" % [filtered_ids.size(), _order[tab].size(), str(TABS[tab])]
	if not str(view.get("error", "")).is_empty():
		_count.text = "图鉴加载失败：" + str(view.error)
	_grid = GridContainer.new()
	_grid.name = "CompendiumGrid"
	_layout_columns = _columns()
	_grid.columns = _layout_columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 16)
	_gallery.add_child(_grid)
	var initial_count := maxi(PAGE_SIZE, int(_states[tab].get("loaded", PAGE_SIZE))) if restore else PAGE_SIZE
	_append_batch(initial_count)
	if filtered_ids.is_empty():
		var empty := add_text(_gallery, "没有匹配的条目\n试试其他关键词，或点击“重置”查看全部。", 20, Color("d7cebb"))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 150
	_states[tab].scroll = int(_states[tab].scroll) if restore else 0
	_restore_gallery_scroll.call_deferred(_render_generation)
	if restore_uid.begins_with("compendium:item:"):
		if _buttons.has(restore_uid):
			_queue_focus(restore_uid)
		else:
			_queue_focus("compendium:tab:" + tab)


func _append_batch(count: int = PAGE_SIZE) -> void:
	for index in range(visible_ids.size(), mini(visible_ids.size() + count, filtered_ids.size())):
		var id := filtered_ids[index]
		var entry: Dictionary = _entries[tab][id]
		visible_ids.append(id)
		if tab == "cards":
			var card := UiOfferCard.new()
			card.configure(id, entry.variants[0].face, str(CompendiumText.OWNER_NAMES.get(CompendiumText.owner(entry), "衍生")) + " · " + CompendiumText.rarity(entry), false, false, true)
			card.inspection_hint = "点击查看完整详情"
			card.set_meta("uid", "compendium:item:" + id)
			_grid.add_child(card)
			_buttons["compendium:item:" + id] = card
			card.pressed.connect(func(): open_detail(id))
		else:
			_art_tile(entry, tab == "relics")
		_buttons["compendium:item:" + id].focus_entered.connect(func(): _prefetch_for_focus(id))
	_states[tab].loaded = visible_ids.size()
	_page_count.text = ("已显示全部 %s 项" % visible_ids.size()) if visible_ids.size() == filtered_ids.size() else ("已显示 %s / %s · 每批 8 项 · 继续下滑" % [visible_ids.size(), filtered_ids.size()])
	_update_item_focus()


func _gallery_scrolled(value: float) -> void:
	if _restoring_scroll or is_instance_valid(detail):
		return
	_states[tab].scroll = roundi(value)
	var bar := _scroll.get_v_scroll_bar()
	if value > 0 and value + bar.page >= bar.max_value - maxf(48, bar.page * .2):
		_queue_append()


func _queue_append() -> void:
	if _append_pending or visible_ids.size() >= filtered_ids.size() or is_instance_valid(detail):
		return
	_append_pending = true
	_append_next.call_deferred(_render_generation)


func _append_next(generation: int) -> void:
	if generation != _render_generation:
		return
	_append_pending = false
	if is_inside_tree() and not is_instance_valid(detail):
		_append_batch()


func _prefetch_for_focus(id: String) -> void:
	if not _restoring_scroll and visible_ids.find(id) >= visible_ids.size() - _layout_columns:
		_queue_append()


func _update_item_focus() -> void:
	for index in visible_ids.size():
		var button: Control = _buttons["compendium:item:" + visible_ids[index]]
		button.focus_previous = _buttons["compendium:item:" + visible_ids[index - 1]].get_path() if index > 0 else _search.get_path()
		button.focus_next = _buttons["compendium:item:" + visible_ids[index + 1]].get_path() if index + 1 < visible_ids.size() else _buttons["compendium:back"].get_path()
		button.focus_neighbor_left = _buttons["compendium:item:" + visible_ids[index - 1]].get_path() if index % _layout_columns > 0 else button.get_path()
		button.focus_neighbor_right = _buttons["compendium:item:" + visible_ids[index + 1]].get_path() if index % _layout_columns < _layout_columns - 1 and index + 1 < visible_ids.size() else button.get_path()
		button.focus_neighbor_top = _buttons["compendium:item:" + visible_ids[index - _layout_columns]].get_path() if index >= _layout_columns else _search.get_path()
		button.focus_neighbor_bottom = _buttons["compendium:item:" + visible_ids[index + _layout_columns]].get_path() if index + _layout_columns < visible_ids.size() else button.get_path()


func _art_tile(entry: Dictionary, relic: bool) -> void:
	var button := Button.new()
	button.custom_minimum_size = (Vector2(194, 216) if relic else Vector2(194, 260)) * UiStyle.text_scale
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("uid", "compendium:item:" + str(entry.id))
	button.tooltip_text = CompendiumText.title(entry, not relic) + " · 点击查看形象与详情"
	UiStyle.button_skin(button, "quiet", true)
	_grid.add_child(button)
	_buttons["compendium:item:" + str(entry.id)] = button
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var art := TextureRect.new()
	art.texture = UiStyle.texture(entry.id)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	var name_label := add_text(column, CompendiumText.title(entry, not relic), 18, UiStyle.CREAM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meta := add_text(column, CompendiumText.relic_group_text(entry) + " · " + CompendiumText.rarity(entry) if relic else CompendiumText.kind(entry), 13, Color(str({"white":"ddd4b7","blue":"94c6eb","purple":"c9a4ed","gold":"eac775"}.get(entry.definition.rarity,"ddd4b7"))) if relic else UiStyle.BRASS)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.pressed.connect(func(): open_detail(str(entry.id)))


func change_page(delta: int) -> void:
	if is_instance_valid(detail):
		return
	_timer.stop()
	var target := _scroll.scroll_vertical + roundi(_scroll.size.y * .85) * delta
	if delta > 0 and target + _scroll.size.y >= _gallery.size.y:
		_append_batch()
	_move_gallery_scroll.call_deferred(target, _render_generation)


func _move_gallery_scroll(target: int, generation: int) -> void:
	if not is_inside_tree(): return
	var tree := get_tree()
	await tree.process_frame
	await tree.process_frame
	if is_inside_tree() and generation == _render_generation and not is_instance_valid(detail):
		_scroll.scroll_vertical = target


func open_detail(id: String) -> void:
	if is_instance_valid(detail) or not filtered_ids.has(id):
		return
	_timer.stop()
	_states[tab].scroll = _scroll.scroll_vertical
	var opening_scroll := _scroll.scroll_vertical
	_ensure_item_loaded(id)
	_scroll.follow_focus = false
	var button: Control = _buttons.get("compendium:item:" + id)
	if button != null:
		button.grab_focus()
	detail = UiCompendiumDetail.new()
	add_child(detail)
	detail.configure(self, tab, filtered_ids, _entries[tab], id, bool(view.get("motion_enabled", true)))
	detail.closed.connect(func(selected_id):
		detail = null
		_scroll.follow_focus = true
		_ensure_item_loaded(selected_id)
		var uid := "compendium:item:" + str(selected_id)
		if _buttons.has(uid):
			_queue_focus(uid)
			if selected_id == id:
				_move_gallery_scroll.call_deferred(opening_scroll, _render_generation)
			else:
				_reveal_item.call_deferred(uid, _render_generation))


func _ensure_item_loaded(id: String) -> void:
	var index := filtered_ids.find(id)
	if index >= visible_ids.size():
		var needed := ceili((index + 1) / float(PAGE_SIZE)) * PAGE_SIZE
		_append_batch(needed - visible_ids.size())


func _reveal_item(uid: String, generation: int) -> void:
	if not is_inside_tree(): return
	var tree := get_tree()
	await tree.process_frame
	await tree.process_frame
	if is_inside_tree() and generation == _render_generation and _buttons.has(uid):
		var bounds := _scroll.get_global_rect()
		var target: Rect2 = _buttons[uid].get_global_rect()
		if target.size.y > bounds.size.y - 16 or target.position.y < bounds.position.y + 8:
			_scroll.scroll_vertical += floori(target.position.y - bounds.position.y - 8)
		elif target.end.y > bounds.end.y - 8:
			_scroll.scroll_vertical += ceili(target.end.y - bounds.end.y + 8)


func _columns() -> int:
	var minimum_width := 160 if tab == "cards" else 194
	return 4 if size.x - 72 >= 4 * minimum_width * UiStyle.text_scale + 60 else 2


func _resize_gallery() -> void:
	if _layout_pending or not is_instance_valid(_grid):
		return
	_layout_pending = true
	_apply_columns.call_deferred()


func _apply_columns() -> void:
	_layout_pending = false
	if is_instance_valid(_grid):
		_layout_columns = _columns()
		_grid.columns = _layout_columns
		_update_item_focus()


func _restore_gallery_scroll(generation: int) -> void:
	if not is_inside_tree() or generation != _render_generation:
		return
	await get_tree().process_frame
	if is_inside_tree() and generation == _render_generation and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_states[tab].scroll)
		_restoring_scroll = false


func _queue_focus(uid: String) -> void:
	_focus_uid.call_deferred(uid, _render_generation)


func _focus_uid(uid: String, generation: int) -> void:
	if is_inside_tree() and generation == _render_generation and _buttons.has(uid):
		var button: Control = _buttons[uid]
		if button.is_inside_tree() and button.focus_mode != Control.FOCUS_NONE and not button.disabled:
			button.grab_focus()


func _input(event: InputEvent) -> void:
	if is_instance_valid(detail) or not visible:
		return
	# A complete first batch can fit on screen; its first wheel step still needs to continue.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _restoring_scroll and _scroll.get_global_rect().has_point(event.position):
		var bar := _scroll.get_v_scroll_bar()
		if visible_ids.size() < filtered_ids.size() and bar.max_value <= bar.page + 1:
			_queue_append()
			_move_gallery_scroll.call_deferred(_scroll.scroll_vertical + roundi(64 * event.factor), _render_generation)
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	for button in _buttons.values():
		if button is OptionButton and button.get_popup().visible:
			return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if typing:
			_buttons["compendium:tab:" + tab].grab_focus()
		else:
			press("compendium:back")
	elif event.keycode == KEY_SLASH or (event.ctrl_pressed and event.keycode == KEY_F):
		if not typing or event.ctrl_pressed:
			_search.grab_focus()
			_search.select_all()
			get_viewport().set_input_as_handled()
	elif not typing and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		change_page(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()
	elif not typing and event.keycode in [KEY_HOME, KEY_END]:
		if event.keycode == KEY_END:
			_append_batch(filtered_ids.size())
		_move_gallery_scroll.call_deferred(0 if event.keycode == KEY_HOME else 1000000, _render_generation)
		get_viewport().set_input_as_handled()
