class_name UiRunToolbar
extends Control

const HEIGHT := 60.0
var page: UiPage
var _options: Dictionary
var _menu: Control
var _panel: PanelContainer
var _menu_column: VBoxContainer
var _toggle: Button
var _return_focus: Control
var _disabled: Dictionary = {}
var _focus: Dictionary = {}
var _main_buttons: Array[Button] = []
var _menu_buttons: Array[Button] = []
var _shortcut_uids: Dictionary = {}


func configure(owner: UiPage, options: Dictionary) -> void:
	page = owner
	_options = options
	name = "RunTopBar"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rail := SpireTopRail.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rail)
	var row := HBoxContainer.new()
	row.name = "NavigationRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -12
	row.offset_top = 2
	row.offset_bottom = -2
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	row.add_child(stats)
	var hp := _label(stats, "♥ %s/%s" % [options.get("vitality", 0), options.get("max_vitality", 0)], 19, Color("f2877d"))
	hp.name = "TopVitality"
	hp.tooltip_text = "精力 %s / %s" % [options.get("vitality", 0), options.get("max_vitality", 0)]
	var coins := _label(stats, "◉ %s" % options.get("money", 0), 18, Color("efd18a"))
	coins.name = "TopMoney"
	coins.tooltip_text = "当前金币；服务和商品会在确认前展示实际价格。"
	_main(row, "relics", str(options.relics_uid), "饰品", int(options.get("relics_count", 0)), options.relics_callback, "查看携带饰品的实际效果")
	var equipment := HBoxContainer.new()
	equipment.name = "EquippedRelics"
	equipment.add_theme_constant_override("separation", 4)
	row.add_child(equipment)
	var relics: Array = page.view.get("relics", [])
	for slot in mini(3, int(page.view.get("relic_slots", 3))):
		var entry: Dictionary = {}
		for relic in relics:
			if int(relic.get("slot", relics.find(relic))) == slot:
				entry = relic
		var button := page.add_button(equipment, "toolbar:relic:" + str(slot), "", {}, func():
			close_menu()
			page.call("_open_reference", "relics", str(entry.get("relic_id", entry.get("definition_id", "")))))
		button.set_script(UiRelicSlotButton)
		button.call("configure", entry, slot)
	var journey := _label(row, str(options.get("journey", "")), 15, Color("d0d6c8"))
	journey.name = "TopJourney"
	journey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journey.clip_text = true
	journey.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	journey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	journey.tooltip_text = journey.text
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 6)
	row.add_child(navigation)
	if bool(options.get("show_map", true)):
		_main(navigation, "map", str(options.map_uid), "地图", -1, options.map_callback, "查看完整本学年地图 · M")
	_main(navigation, "deck", str(options.deck_uid), "牌组", int(options.get("deck_count", 0)), options.deck_callback, "查看本局牌组、费用与完整效果 · D", bool(options.get("battle", false)))
	_toggle = _main(navigation, "settings", str(options.toggle_uid), "菜单", -1, toggle_menu, "冒险菜单：记录、帮助、演出与进度 · F10 / Esc")
	_build_menu()
	resized.connect(_fit_menu)
	_fit_menu.call_deferred()
	tree_exiting.connect(func(): close_menu(false))


func _main(parent: Node, kind: String, uid: String, title: String, count: int, callback: Callable, hint: String, pile: bool = false) -> Button:
	var button: Button
	var activate := func():
		if kind != "settings":
			close_menu()
		callback.call()
	if pile:
		button = page.call("_add_pile_button", parent, "deck", activate, true)
		button.set_meta("nav_icon", kind)
		button.set_meta("nav_count", count)
		button.set_meta("toolbar_button", true)
		button.custom_minimum_size = Vector2(64, 56)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		button = page.add_button(parent, uid, title, {}, activate)
		button.set_script(UiNavigationButton)
		button.call("configure", kind, title, count)
	button.tooltip_text = "" if pile else hint
	button.set_meta("navigation_hint", hint)
	_main_buttons.append(button)
	return button


func _label(parent: Node, text: String, pixels: int, color: Color = UiStyle.CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(pixels * UiStyle.text_scale))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _build_menu() -> void:
	_menu = Control.new()
	_menu.name = "AdventureMenu"
	_menu.z_index = 160
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	var shade := ColorRect.new()
	shade.name = "DismissMenu"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(.02, .04, .06, .28)
	_menu.add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_menu()
			shade.accept_event())
	_panel = PanelContainer.new()
	_panel.name = "NavigationMenuPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiStyle.surface(Color("203541"), Color("9b9478"), 5)
	style.shadow_size = 16
	style.shadow_color = Color(0, 0, 0, .45)
	_panel.add_theme_stylebox_override("panel", style)
	_menu.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label(heading, "冒险菜单", 20, Color("ead29f"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := page.add_button(heading, str(_options.close_uid), "关闭", {}, close_menu)
	close.custom_minimum_size = Vector2(110, 44)
	close.autowrap_mode = TextServer.AUTOWRAP_OFF
	close.tooltip_text = "收起冒险菜单 · Esc"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiStyle.button_skin(close, "quiet", true)
	_menu_buttons.append(close)
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_menu_column = VBoxContainer.new()
	_menu_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_column.add_theme_constant_override("separation", 6)
	scroll.add_child(_menu_column)
	var info := _label(_menu_column, "%s · %s" % [UiStyle.label(str(page.view.get("character_id", ""))).split("·")[0], str({"normal": "标准难度", "relaxed": "宽松难度", "hard": "挑战难度"}.get(page.view.get("difficulty", ""), "当前冒险"))], 14, Color("c8b68e"))
	info.name = "MenuRunInfo"
	_section("查阅")
	_entry("battle:log" if bool(_options.get("battle", false)) else "flow:log", "log", "战斗记录", "%d 条已记录事件 · 查看来源、目标与结算" % (page.view.get("event_log", []) as Array).size(), func(): page.call("_open_reference", "log"), {}, KEY_L, "L")
	_entry(str(_options.help_uid), "rules", "规则帮助", "胜负、资源与操作说明", _options.help_callback, {}, KEY_G, "G / F1")
	_entry("flow:info", "info", "冒险信息", "人物、资源、难度与保存状态", func(): page.call("_open_reference", "info"))
	if bool(_options.get("battle", false)):
		_section("演出")
		_entry("battle:speed", "speed", "演出速度", "基础 ×4，叠加下方所选倍速", _options.speed_callback)
		_entry("battle:animation", "animation", "战斗动画", "关闭可立即展示结果", _options.animation_callback)
		refresh_presentation()
	_section("进度")
	_entry("flow:settings", "settings", "游戏设置", "音量、字号、动态和自动保存", Callable(), {"type": "ui.settings", "payload": {}})
	_entry(str(_options.save_uid), "save", "保存进度", str(page.view.get("save_reason", "保存当前完整进度")), Callable(), {"type": "ui.save", "payload": {}})
	_entry(str(_options.home_uid), "menu", "返回主页", "保留当前冒险，稍后可继续", Callable(), {"type": "ui.menu", "payload": {}})
	_menu.hide()


func _section(caption: String) -> void:
	var label := _label(_menu_column, caption, 12, Color("b9b79c"))
	label.custom_minimum_size.y = 22


func _entry(uid: String, kind: String, title: String, hint: String, callback: Callable = Callable(), draft: Dictionary = {}, key: int = 0, shortcut: String = "") -> void:
	var keep_open := kind in ["speed", "animation"]
	var button := page.add_button(_menu_column, uid, title, draft, func():
		if not keep_open:
			close_menu()
		if callback.is_valid():
			callback.call())
	button.custom_minimum_size = Vector2(0, 74 * UiStyle.text_scale)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiNavIcon.apply(button, kind, title, hint + (" · " + shortcut if not shortcut.is_empty() else ""))
	button.text = ""
	button.add_theme_font_size_override("font_size", roundi(17 * UiStyle.text_scale))
	button.add_theme_constant_override("h_separation", 14)
	button.set_meta("menu_title", title)
	var skin := UiStyle.surface(Color("293f4c"), Color("50646b"), 3)
	skin.set_content_margin_all(12)
	button.add_theme_stylebox_override("normal", skin)
	var hover := skin.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3e5360")
	hover.border_color = Color("bcb08b")
	button.add_theme_stylebox_override("hover", hover)
	var caption := _label(button, title, 17)
	caption.name = "MenuCaption"
	caption.position = Vector2(48, 8 * UiStyle.text_scale)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var explanation := _label(button, hint, 12, Color("bdc8bd"))
	explanation.name = "MenuHint"
	explanation.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	explanation.offset_left = 48
	explanation.offset_right = -10
	explanation.offset_top = -29 * UiStyle.text_scale
	explanation.autowrap_mode = TextServer.AUTOWRAP_OFF
	explanation.clip_text = true
	explanation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	explanation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shortcut_label := _label(button, shortcut, 13, Color("cfbd91"))
	shortcut_label.name = "MenuValue"
	shortcut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	shortcut_label.offset_top = 4 * UiStyle.text_scale
	shortcut_label.offset_bottom = -32 * UiStyle.text_scale
	shortcut_label.offset_left = -94
	shortcut_label.offset_right = -12
	shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_menu_buttons.append(button)
	if key != 0:
		_shortcut_uids[key] = uid


func refresh_presentation() -> void:
	if not is_instance_valid(page) or not bool(_options.get("battle", false)):
		return
	for entry in [["battle:speed", "×%s" % page.get("speed_scale")], ["battle:animation", "开启" if page.get("animation_enabled") else "关闭"]]:
		var button: Button = page._buttons.get(entry[0])
		if is_instance_valid(button):
			(button.get_node("MenuValue") as Label).text = entry[1]
			button.tooltip_text = str(button.get_meta("navigation_hint", "")) + " · 当前" + str(entry[1])


func is_menu_open() -> bool:
	return is_instance_valid(_menu) and _menu.visible


func mark_active(kind: String, active: bool) -> void:
	for button in _main_buttons:
		if str(button.get_meta("nav_icon", "")) == kind:
			button.set_meta("nav_active", active)
			button.queue_redraw()


func toggle_menu() -> void:
	if is_menu_open():
		close_menu()
		return
	page.close_card_preview()
	# GUI picking follows sibling order, independently of drawing z_index.
	# Map previews and room content are created after this bar; raise the
	# existing bar so its expanded menu receives clicks above that content.
	page.move_child(self, page.get_child_count() - 1)
	_return_focus = page.get_viewport().gui_get_focus_owner()
	for control in page.find_children("*", "Control", true, false):
		if _menu.is_ancestor_of(control) or (control is Button and control in _main_buttons):
			continue
		if control is BaseButton:
			_disabled[control] = control.disabled
			control.disabled = true
		if control.focus_mode != Control.FOCUS_NONE:
			_focus[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	_menu.show()
	_toggle.set_meta("nav_active", true)
	_toggle.queue_redraw()
	_fit_menu()
	_menu_buttons[0].grab_focus()


func close_menu(restore_focus: bool = true) -> void:
	if not is_menu_open():
		return
	_menu.hide()
	for button in _disabled:
		if is_instance_valid(button):
			button.disabled = _disabled[button]
	_disabled.clear()
	for control in _focus:
		if is_instance_valid(control):
			control.focus_mode = _focus[control]
	_focus.clear()
	_toggle.set_meta("nav_active", false)
	_toggle.queue_redraw()
	if restore_focus and is_instance_valid(_return_focus) and _return_focus.is_inside_tree():
		_return_focus.grab_focus()


func _fit_menu() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(page) or not is_instance_valid(_panel):
		return
	_menu.size = page.size
	var width := 376.0 * minf(UiStyle.text_scale, 1.25)
	var height := minf(page.size.y - HEIGHT - 12, 694 * UiStyle.text_scale)
	_panel.position = Vector2(page.size.x - width - 12, HEIGHT + 4)
	_panel.size = Vector2(width, height)


func route_input(event: InputEvent) -> bool:
	if not is_menu_open():
		return false
	var viewport := get_viewport()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_F10]:
			close_menu()
			viewport.set_input_as_handled()
		elif not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and (_shortcut_uids.has(event.keycode) or event.keycode in [KEY_M, KEY_D, KEY_F1]):
			var uid := str(_shortcut_uids.get(event.keycode, _options.get("map_shortcut_uid", _options.map_uid) if event.keycode == KEY_M else (_options.deck_uid if event.keycode == KEY_D else _options.help_uid)))
			var target: Button = page._buttons.get(uid)
			# Background controls are temporarily disabled by this menu. Consult
			# their saved legal state before restoring and invoking the shortcut.
			if is_instance_valid(target) and not bool(_disabled.get(target, target.disabled)):
				close_menu()
				page.press(uid)
			viewport.set_input_as_handled()
		elif event.keycode not in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			viewport.set_input_as_handled()
	return true
