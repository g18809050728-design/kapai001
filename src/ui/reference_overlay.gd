class_name UiReferenceOverlay
extends Control

signal closed

var page: UiPage
var data: Dictionary = {}
var section := "relics"
var selected_relic := ""
var _return_focus: Control
var _disabled: Dictionary = {}
var _focus_modes: Dictionary = {}
var _body: VBoxContainer
var _title: Label
var _close: Button
var _tabs: Dictionary = {}
var _search: LineEdit
var _log_list: VBoxContainer
var _log_count: Label
var _battle_only := true
var _newest := true
var _log_query := ""
var _closing := false


func configure(owner: UiPage, kind: String, snapshot: Dictionary, relic_id: String = "") -> void:
	page = owner
	data = snapshot.duplicate(true)
	section = kind
	selected_relic = relic_id
	name = "AdventureReference"
	z_index = 350
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_return_focus = get_viewport().gui_get_focus_owner()
	for control in page.find_children("*", "Control", true, false):
		if control == self or is_ancestor_of(control):
			continue
		if control is BaseButton:
			_disabled[control] = control.disabled
			control.disabled = true
		if control.focus_mode != Control.FOCUS_NONE:
			_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	var shade := ColorRect.new()
	shade.color = Color(.02, .035, .045, .88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close(); shade.accept_event())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.name = "ReferencePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var skin := UiStyle.surface(Color("1c2b34"), Color("ad9872"), 4)
	skin.set_content_margin_all(18)
	skin.shadow_size = 18
	skin.shadow_color = Color(0, 0, 0, .5)
	panel.add_theme_stylebox_override("panel", skin)
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_title = _label(heading, "", 25, Color("f1d59f"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close = _button(heading, "关闭  Esc", close)
	_close.name = "CloseReference"
	_close.custom_minimum_size.x = 132
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for item in [["relics", "饰品", "relics"], ["rules", "规则帮助", "rules"], ["log", "战斗记录", "log"], ["info", "冒险信息", "info"]]:
		var key: String = item[0]
		var button := _button(tabs, item[1], func(): show_section(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = UiNavIcon.texture(item[2])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		_tabs[key] = button
	_body = VBoxContainer.new()
	_body.name = "ReferenceBody"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	column.add_child(_body)
	show_section(kind)
	_close.grab_focus()
	tree_exiting.connect(_restore)


func _label(parent: Node, caption: String, pixels: int = 17, ink: Color = UiStyle.CREAM) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", roundi(pixels * UiStyle.text_scale))
	label.add_theme_color_override("font_color", ink)
	parent.add_child(label)
	return label


func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	UiStyle.button_skin(button, "secondary", true)
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func _scroll(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	return column


func show_section(kind: String) -> void:
	section = kind
	_title.text = str({"relics": "携带饰品", "rules": "规则帮助", "log": "战斗记录", "info": "冒险信息"}.get(kind, "冒险信息"))
	for key in _tabs:
		UiStyle.button_skin(_tabs[key], "primary" if key == kind else "quiet", true)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match kind:
		"relics": _relics()
		"rules": _rules()
		"log": _logs()
		_: _info()


func _relics() -> void:
	var relics: Array = data.get("relics", []).duplicate(true)
	relics.sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	var slots := int(data.get("relic_slots", 3))
	_label(_body, "%d / %d 件已装备 · 点击装备槽查看完整效果" % [relics.size(), slots], 15, Color("c8b68e"))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 22)
	_body.add_child(row)
	var list := _scroll(row)
	list.get_parent().custom_minimum_size.x = 240 * minf(UiStyle.text_scale, 1.2)
	list.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var selected: Dictionary = {}
	for relic in relics:
		if selected_relic in [str(relic.get("relic_id", "")), str(relic.get("definition_id", ""))]:
			selected = relic
	if selected.is_empty() and not relics.is_empty():
		selected = relics[0]
		selected_relic = str(selected.get("relic_id", selected.get("definition_id", "")))
	for slot in slots:
		var entry: Dictionary = {}
		for relic in relics:
			if int(relic.get("slot", relics.find(relic))) == slot:
				entry = relic
		var id := str(entry.get("definition_id", ""))
		var button := _button(list, "", func():
			selected_relic = str(entry.get("relic_id", id)); show_section("relics"))
		button.name = "RelicSlot" + str(slot)
		button.custom_minimum_size.y = 78 * minf(UiStyle.text_scale, 1.2)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = UiStyle.texture(id) if not id.is_empty() else UiNavIcon.texture("relics")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 54)
		var title := _label(button, UiStyle.label(id) if not id.is_empty() else "空槽", 16)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		title.offset_left = 76
		title.offset_right = -12
		title.offset_top = 10
		var subtitle := _label(button, "槽 %d · %s" % [slot + 1, "已装备" if not id.is_empty() else "待获得饰品"], 12, Color("b9c5bb"))
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		subtitle.offset_left = 76
		subtitle.offset_right = -12
		subtitle.offset_top = -30
		button.disabled = entry.is_empty()
		button.tooltip_text = "从学年奖励、商店或事件获得饰品；领取时选择替换。" if entry.is_empty() else UiContentText.describe_relic(entry.get("detail", {}))
		if not entry.is_empty() and entry == selected:
			UiStyle.button_skin(button, "primary", true)
	var reading := _scroll(row)
	if selected.is_empty():
		_label(reading, "尚未携带饰品", 25, Color("efcf95"))
		_label(reading, "开局没有饰品。沿地图前进，在学年饰品奖励、商店或事件中获得。装备槽满时，确认领取前可以比较并选择替换。", 19)
		return
	var art := TextureRect.new()
	art.name = "RelicDetailArt"
	art.texture = UiStyle.texture(str(selected.get("definition_id", "")))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 132
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reading.add_child(art)
	_label(reading, UiStyle.label(str(selected.get("definition_id", ""))), 26, Color("f1d59f"))
	_label(reading, "装备槽 %d · 已装备" % (int(selected.get("slot", relics.find(selected))) + 1), 14, Color("b9c5bb"))
	_label(reading, UiContentText.describe_relic(selected.get("detail", {})), 19)
	_label(reading, "更换饰品在领取或购买时确认；查看不会消耗触发次数。", 14, Color("b9c5bb"))


func _article(parent: Node, title: String, text: String, kind: String = "rules") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiNavIcon.texture(kind)
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	_label(row, title, 20, Color("e8c78d"))
	_label(parent, text, 18)
	var line := HSeparator.new()
	line.modulate = Color("61716e")
	parent.add_child(line)


func _rules() -> void:
	var column := _scroll(_body)
	_article(column, "胜负与资源", "完成全部任务的所有阶段，才能赢得战斗。精力耗尽，或DDL到期仍有任务时失败。\n专注支付卡牌费用；放松抵挡压力。DDL表示剩余完整轮末次数，按轮末时序结算。", "focus")
	_article(column, "出牌与目标", "点击或拖拽整张牌；数字1—9对应从左到右的手牌。需要目标时选牌后点高亮目标，或拖到目标松手。无目标牌可点击直接使用。拖回手牌区、右键或Esc取消。\n连携：前牌策略→本牌工作。点击伙伴再点击任务，可指定协作目标。", "deck")
	_article(column, "读卡与查阅", "悬停卡牌0.7秒查看全文，I固定详情，Esc关闭。D查看牌组，M查看本学年地图，L查看记录，G / F1查看规则，F10打开菜单。\n抽牌堆只展示剩余成员，按卡牌整理，隐藏真实抽取顺序。", "rules")
	_article(column, "地图与饰品", "首次点击可达节点预选，再次点击同一节点进入；也可双击、使用确认按钮或键盘。房间和战斗中的全图只供查阅。\n饰品槽数以本局规则为准；同名唯一。满槽时在领取或购买前比较旧效果并选择替换。", "relics")
	_article(column, "保存与返回", "卡牌效果内的强制待选必须完成；此时不能保存半条效果。返回主页保留当前冒险，继续后回到原工作区。手动保存是否可用，以菜单当前状态为准。", "save")
	var passive := UiContentText.describe_character_passive("r3_" + str(data.get("character_id", "")).to_lower() + str({"P01": "_link_replay", "P02": "_paper_record", "P03": "_compound_reaction", "P04": "_teamwork"}.get(data.get("character_id", ""), "")))
	if not passive.is_empty():
		_article(column, "当前人物 · " + UiStyle.label(str(data.get("character_id", ""))), passive, "info")


func _info() -> void:
	var column := _scroll(_body)
	_article(column, "本次冒险", "%s\n%s · %s" % [UiStyle.label(str(data.get("character_id", ""))), str(data.get("year_label", data.get("year_title", "校园冒险"))), str({"normal": "标准", "relaxed": "宽松", "hard": "挑战"}.get(data.get("difficulty", ""), "难度未提供"))], "info")
	var player: Dictionary = data.get("player", data)
	var resources := "精力 %s / %s · 金钱 %s\n牌组 %d 张 · 饰品 %d / %d 件" % [player.get("vitality", data.get("vitality", 0)), data.get("max_vitality", "—"), data.get("money", 0), (data.get("cards", []) as Array).size(), (data.get("relics", []) as Array).size(), int(data.get("relic_slots", 3))]
	if player.has("focus"):
		resources += "\n当前专注 %s · 放松 %s · DDL %s" % [player.focus, player.get("relax", 0), data.get("ddl", 0)]
	_article(column, "当前资源", resources, "focus")
	_article(column, "保存状态", str(data.get("save_reason", "当前可保存完整进度" if data.get("can_save", false) else "当前无法保存")) + "\n自动保存：" + ("开启" if data.get("autosave", false) else "关闭") + "\n" + str(data.get("save_status", "尚无本次会话的保存记录")), "save")
	if not str(data.get("map_influence", "")).is_empty():
		_article(column, "当前路线影响", str(data.map_influence), "map")


func _logs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	_search = LineEdit.new()
	_search.name = "LogSearch"
	_search.placeholder_text = "查找卡牌、任务或结算"
	_search.text = _log_query
	_search.custom_minimum_size = Vector2(180, 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", roundi(16 * UiStyle.text_scale))
	row.add_child(_search)
	_search.text_changed.connect(func(value): _log_query = value; _fill_logs())
	var clear := _button(row, "清空", func(): _search.text = ""; _log_query = ""; _fill_logs())
	clear.name = "ClearLogSearch"
	var filter := _button(row, "仅战斗" if _battle_only else "全部事件", func(): _battle_only = not _battle_only; show_section("log"))
	filter.name = "LogFilter"
	var order := _button(row, "最新在前" if _newest else "最早在前", func(): _newest = not _newest; show_section("log"))
	order.name = "LogOrder"
	_log_count = _label(_body, "", 14, Color("b9c5bb"))
	_log_list = _scroll(_body)
	_log_list.name = "EventRows"
	_fill_logs()


func _fill_logs() -> void:
	for child in _log_list.get_children():
		_log_list.remove_child(child)
		child.queue_free()
	var events: Array = data.get("event_log", []).duplicate(true)
	if _newest:
		events.reverse()
	var found := 0
	var revision := -1
	for event in events:
		if _battle_only and not battle_event(event):
			continue
		var text := event_text(event)
		if not _log_query.is_empty() and not text.to_lower().contains(_log_query.to_lower()):
			continue
		found += 1
		var current_revision := int(event.get("revision", 0))
		if current_revision != revision:
			revision = current_revision
			_label(_log_list, "行动 %d" % revision, 14, Color("c8b68e"))
		var line := _label(_log_list, text, 16)
		line.set_meta("event_key", "%s:%d:%d" % [event.get("run_id", ""), current_revision, int(event.get("index", 0))])
	_log_count.text = "%d 条匹配 · %s · 仅保留本局最近1000条事件" % [found, "战斗事件（可能含此前战斗）" if _battle_only else "含地图与奖励事件"]
	if found == 0:
		_label(_log_list, "没有匹配记录。清空搜索或切换全部事件。" if not _log_query.is_empty() else "暂无战斗记录；进入战斗后会记录真实行动与结算。", 19)


static func battle_event(event: Dictionary) -> bool:
	return str(event.get("type", "")) not in ["run_started", "node_entered", "node_left", "node_completed", "reward_generated", "reward_claimed", "reward_skipped", "year_reward_created", "item_purchased", "shop_left", "rest_taken", "event_resolved", "campaign_reward_claimed", "year_completed", "term_settled", "year_advanced", "ending_requested", "run_finished", "relic_gained", "card_gained", "card_removed", "card_upgraded", "money_changed"]


static func event_text(event: Dictionary) -> String:
	var kind := str(event.get("type", "event"))
	var values: Dictionary = event.get("data", {})
	var titles := {"completion_applied": "完成量结算", "pressure_applied": "压力结算", "card_played": "打出卡牌", "resource_changed": "资源变化", "ddl_ticked": "DDL推进", "round_started": "回合开始", "battle_finished": "战斗结束", "battle_started": "战斗开始", "task_completed": "任务完成", "task_advanced": "进入下一阶段", "card_drawn": "抽牌", "card_moved": "卡牌移动", "relic_triggered": "饰品触发", "node_entered": "进入房间", "node_completed": "完成房间", "item_purchased": "购买商品", "event_resolved": "事件选择", "campaign_reward_claimed": "学年选择", "year_completed": "学年完成", "run_started": "冒险开始"}
	var text := str(titles.get(kind, UiStyle.label(kind)))
	var source := str(event.get("source_label", event.get("source_id", "")))
	if not source.is_empty():
		text += " · " + UiStyle.label(source)
	var targets: Array = event.get("target_labels", event.get("target_ids", []))
	if not targets.is_empty():
		text += " → " + "、".join(targets.map(func(value): return UiStyle.label(str(value))))
	var changes: Array[String] = []
	for pair in [["work", "剩余任务量"], ["shield", "屏障"], ["vitality", "精力"], ["relax", "放松"]]:
		if values.has(pair[0] + "_before") and values.has(pair[0] + "_after"):
			changes.append("%s %s→%s" % [pair[1], values[pair[0] + "_before"], values[pair[0] + "_after"]])
	if values.has("before") and values.has("after"):
		var resource := str(values.get("resource", "DDL" if kind == "ddl_ticked" else ("阶段" if kind == "phase_changed" else "数值")))
		var name := str({"relax": "放松", "focus": "专注", "synergy": "协同"}.get(resource, UiStyle.label(resource)))
		changes.append("%s %s→%s" % [name, UiStyle.label(str(values.before)), UiStyle.label(str(values.after))])
	if values.has("definition_id") and kind != "card_played":
		changes.append(UiStyle.label(str(values.definition_id)))
	if values.has("focus_cost"):
		changes.append("专注费用 %s · 精力费用 %s" % [values.focus_cost, values.get("vitality_cost", 0)])
	if kind == "card_played" and values.has("definition_id"):
		changes.push_front(UiStyle.label(str(values.definition_id)))
	if values.has("round_index"):
		changes.append("第 %s 回合" % values.round_index)
	if values.has("result"):
		changes.append(str({"won": "胜利", "lost": "失败"}.get(values.result, values.result)))
	if values.has("price"):
		changes.append("支付 %s 金钱" % values.price)
	if values.get("candidate_id") is String and not str(values.candidate_id).is_empty():
		changes.append(UiStyle.label(str(values.candidate_id)))
	if changes.is_empty() and values.has("amount"):
		changes.append("数值 %s" % values.amount)
	if not changes.is_empty():
		text += "\n" + " · ".join(changes)
	return text


func close() -> void:
	if _closing:
		return
	_closing = true
	hide()
	_restore()
	closed.emit()
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
	if not visible or _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif not (get_viewport().gui_get_focus_owner() is LineEdit) and event.keycode in [KEY_M, KEY_D, KEY_L, KEY_G, KEY_F1, KEY_F10, KEY_E, KEY_I, KEY_P, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
			get_viewport().set_input_as_handled()
