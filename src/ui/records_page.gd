extends UiPage

signal history_requested(token: String, offset: int, match_id: String)

const MUTED := Color("becac8")
const LINE := Color("516773")
const REASONS := {"deadline_expired": "DDL 已到期", "vitality_depleted": "精力耗尽", "battle_lost": "战斗失败", "first_term_completed": "第一学期已完成", "four_years_completed": "四学年已完成", "graduated": "已毕业", "player_abandoned": "主动结束冒险", "replaced_by_new_run": "重开结束旧局", "abandoned": "主动结束冒险"}
const ROOM_NAMES := {"normal": "战斗", "elite": "精英", "boss": "首领", "shop": "商店", "rest": "休息", "event": "事件"}
const ROUTE_STATES := {"cleared": "已通过", "battle_won": "战斗胜利", "battle_lost": "战斗失败", "stopped": "在此结束"}

var _source := "initial"
var _records: Array = []
var _stats: Dictionary = {}
var _selected: Dictionary = {}
var _section := "route"
var _detail: Variant
var _list_error := ""
var _detail_error := ""
var _sync_message := ""
var _pending := ""
var _sequence := 0
var _offset := 0
var _next_offset := -1
var _list_scroll := 0
var _return_uid := ""
var _compact := false
var _layout_pending := false


func render(data: Dictionary) -> void:
	view = data
	var state := str(data.get("account_state", ""))
	if state != _source:
		_source = state
		_records = []
		_stats = {}
		_sync_message = ""
		_selected = {}
		_pending = ""
		_list_error = ""
		_list_scroll = 0
		_next_offset = -1
		if not _source.is_empty():
			_request()
	if _source.is_empty():
		_records = data.get("records", [])
		_stats = _local_stats(_records)
		_list_error = str(data.get("records_error", ""))
	view.records = _records
	_draw_page()


func _request(offset: int = 0, match_id: String = "") -> void:
	_sequence += 1
	_pending = "%d:%d" % [get_instance_id(), _sequence]
	_offset = offset
	var token := _pending
	_emit_request.call_deferred(token, offset, match_id)


func _emit_request(token: String, offset: int, id: String) -> void:
	if is_inside_tree() and token == _pending:
		history_requested.emit(token, offset, id)


func receive_records(token: String, result: Dictionary) -> void:
	if token != _pending or not is_inside_tree():
		return
	_pending = ""
	if _selected.is_empty():
		_list_error = str(result.get("error", ""))
		if _list_error.is_empty():
			var messages := PackedStringArray()
			if result.get("recovery_pending", false):
				messages.append("有旧局待完成结算")
			if int(result.get("pending_sync", 0)) > 0:
				messages.append("%d 局尚未同步" % int(result.pending_sync))
			if int(result.get("blocked_sync", 0)) > 0:
				messages.append("%d 局同步失败" % int(result.blocked_sync))
			_sync_message = " · ".join(messages)
			if _offset == 0:
				_records = []
				_stats = result.get("stats", {})
			else:
				_list_scroll = _scroll.scroll_vertical
			var existing := {}
			for row in _records:
				existing[row.match_id] = true
			for row in result.get("items", []):
				if not existing.has(row.match_id):
					existing[row.match_id] = true
					_records.append(row)
			_next_offset = int(result.next_offset) if result.get("next_offset") != null else -1
			view.records = _records
	else:
		_detail_error = str(result.get("error", ""))
		_detail = result.get("detail")
	_draw_page()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and not view.is_empty() and not _layout_pending:
		_layout_pending = true
		_resize.call_deferred()


func _resize() -> void:
	_layout_pending = false
	if not is_inside_tree() or _compact == _is_compact():
		return
	if _selected.is_empty():
		_list_scroll = _scroll.scroll_vertical
	_draw_page()


func _is_compact() -> bool:
	return UiStyle.web_touch or size.y < 550 or size.x < 760


func _draw_page() -> void:
	_compact = _is_compact()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_drafts.clear()
	var scene := RoomSceneView.new()
	scene.room = "settings"
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene)
	var shade := ColorRect.new()
	shade.color = Color("0c1821", .91)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := 13 if _compact else clampi(roundi(size.x * .085), 34, 160)
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, side)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8 if _compact else 27)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5 if _compact else 13)
	margin.add_child(column)
	var header_row := add_row(column)
	var detail_open := not _selected.is_empty()
	var title := _text(header_row, _character(_selected) if detail_open else "游戏记录", 23 if _compact else 38, UiStyle.CREAM, true)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not detail_open and not _compact:
		var scope := _text(header_row, _scope_text(), 15, MUTED)
		scope.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		scope.size_flags_horizontal = Control.SIZE_SHRINK_END
	var back := add_button(header_row, "records:back", ("返回列表" if detail_open else ("主菜单" if _compact else "返回主菜单")), {}, _back)
	_style_action(back)
	if detail_open:
		_detail_bar(column)
	else:
		_list_heading(column)
	_scroll = MobileScroll.TapScroll.new()
	_scroll.name = "RecordScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = not UiStyle.web_touch
	column.add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6 if _compact else 10)
	_scroll.add_child(body)
	if detail_open:
		_draw_detail()
	else:
		_draw_list()
		_scroll.set_deferred("scroll_vertical", _list_scroll)
		var focus: Control = _buttons.get(_return_uid, back)
		_return_uid = ""
		if not UiStyle.web_touch:
			focus.grab_focus()
	if detail_open and not UiStyle.web_touch:
		var tab: Control = _buttons.get("records:tab:" + _section, back)
		tab.grab_focus()


func _scope_text() -> String:
	if _source == "ready":
		return "账号战绩"
	return "本次游客登录" if _source == "guest" else "本地战绩"


func _list_heading(parent: Node) -> void:
	var row := add_row(parent)
	var scope := _scope_text() if _compact else "过往对局"
	var label := _text(row, scope, 13 if _compact else 17, UiStyle.TERM_HIGHLIGHT)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not _stats.is_empty():
		var caption := "结算 %d　胜利 %d" % [_stats.settled, _stats.wins]
		if int(_stats.furthest) > 0:
			caption += "　最远第 %d 学年" % _stats.furthest
		var stats := _text(row, caption, 12 if _compact else 15, MUTED)
		stats.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _source == "ready":
		var refresh_button := add_button(row, "records:refresh", "刷新", {}, func():
			_list_scroll = 0
			_list_error = ""
			_request()
			_draw_page())
		_style_action(refresh_button, true)
		refresh_button.disabled = not _pending.is_empty()
	parent.add_child(HSeparator.new())


func _local_stats(rows: Array) -> Dictionary:
	var stats := {"settled": 0, "wins": 0, "furthest": 0}
	for record in rows:
		stats.settled += 0 if str(record.get("result", "")).is_empty() else 1
		stats.wins += 1 if record.get("result") == "won" else 0
		stats.furthest = maxi(stats.furthest, int(record.get("term", 0)))
	return stats


func _draw_list() -> void:
	if not _sync_message.is_empty():
		_text(body, _sync_message, 14, UiStyle.TERM_HIGHLIGHT)
	for index in _records.size():
		_record_row(_records[index], index)
	if not _list_error.is_empty():
		_text(body, _list_error, 16, UiStyle.CREAM)
		if not _source.is_empty():
			var retry := add_button(body, "records:retry", "重试", {}, func(): _request(_offset); _draw_page())
			_style_action(retry)
	elif not _pending.is_empty():
		_text(body, "正在读取对局…", 16, MUTED)
	elif _records.is_empty():
		_text(body, "暂无对局记录", 21, UiStyle.CREAM, true)
		_text(body, "开始一局冒险后可在这里查看战绩。", 15, MUTED)
	elif _next_offset >= 0:
		var more := add_button(body, "records:more", "加载更多", {}, func():
			_list_scroll = _scroll.scroll_vertical
			_request(_next_offset)
			_draw_page())
		_style_action(more)


func _record_row(record: Dictionary, index: int) -> void:
	var uid := "records:open:%d" % index
	var scroller := _scroll as MobileScroll.TapScroll
	var button := add_button(body, uid, "", {}, func():
		if scroller.allows_activation():
			_open_record(record, uid))
	button.accessibility_name = "%s，%s，查看详情" % [_character(record), _outcome(record)]
	button.custom_minimum_size = Vector2(0, 66 + 16 * (UiStyle.text_scale - 1.0) if _compact else 92)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.button_skin(button, "secondary", true)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + edge, 11 if _compact else 20)
	button.add_child(pad)
	var row := add_row(pad)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var id := str(record.get("character_id", ""))
	var portrait := _portrait(id, 48 if _compact else 79)
	row.add_child(portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	_text(words, _character(record), 17 if _compact else 23, UiStyle.CREAM, true)
	_text(words, _metadata(record), 12 if _compact else 15, MUTED)
	var stats := _settlement_stats(record, record.get("detail"))
	if not stats.is_empty() and (stats.has("vitality") or stats.has("money")):
		var resources := add_row(row)
		resources.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		resources.alignment = BoxContainer.ALIGNMENT_END
		resources.add_theme_constant_override("separation", 16 if _compact else 30)
		resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resource_stat(resources, "剩余精力", _vitality_text(stats), Color("f2b0a3"), false)
		_resource_stat(resources, "金币", _stat_value(stats, "money"), UiStyle.TERM_HIGHLIGHT, false)
	var outcome := VBoxContainer.new()
	outcome.alignment = BoxContainer.ALIGNMENT_CENTER
	outcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(outcome)
	_text(outcome, _outcome(record) + "  ›", 15 if _compact else 19, _outcome_ink(record))
	if int(record.get("term", 0)) > 0:
		_text(outcome, "第 %d 学年" % int(record.term), 12 if _compact else 15, MUTED)


func _open_record(record: Dictionary, uid: String) -> void:
	_list_scroll = _scroll.scroll_vertical
	_return_uid = uid
	_selected = record
	_section = "route"
	_detail_error = ""
	_detail = record.get("detail")
	_pending = ""
	if not _source.is_empty() and record.get("has_detail", false):
		_request(0, str(record.match_id))
	_draw_page()


func _detail_bar(parent: Node) -> void:
	var year := int(_selected.get("term", 0))
	var progress := "第 %d 学年" % year if year > 0 else ""
	var pieces := [_outcome(_selected), progress, str(REASONS.get(_selected.get("reason", ""), ""))]
	var ending := str(_selected.get("ending_id", ""))
	if not ending.is_empty():
		var title := UiStyle.label("ending." + ending + ".name")
		if title != ending:
			pieces.append(title)
	var summary := _text(parent, " · ".join(pieces.filter(func(item): return not item.is_empty())), 13 if _compact else 17, _outcome_ink(_selected))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stats := _settlement_stats(_selected, _detail)
	if not stats.is_empty():
		var resource_line := _detail_row(parent)
		resource_line.add_theme_constant_override("separation", 7 if _compact else 18)
		_resource_stat(resource_line, "剩余精力", _vitality_text(stats), Color("f2b0a3"))
		_resource_stat(resource_line, "金币", _stat_value(stats, "money"), UiStyle.TERM_HIGHLIGHT)
		_resource_stat(resource_line, "完成节点", _stat_value(stats, "completed_nodes"), UiStyle.CREAM)
		_resource_stat(resource_line, "已结算战斗", _stat_value(stats, "settled_battles"), UiStyle.CREAM)
	if _detail is Dictionary:
		var tabs := add_row(parent)
		for item in [["route", "闯关路线"], ["cards", "牌组 · %d" % _detail.cards.size()], ["relics", "饰品 · %d" % _detail.relics.size()]]:
			var key: String = item[0]
			var button := add_button(tabs, "records:tab:" + key, item[1], {}, func(): _section = key; _draw_page())
			_style_action(button)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiStyle.button_skin(button, "primary" if key == _section else "quiet", true)
	parent.add_child(HSeparator.new())


func _settlement_stats(record: Dictionary, detail: Variant) -> Dictionary:
	var stats: Dictionary = record.get("statistics", {}).duplicate()
	var resources: Dictionary = record.get("resources", {})
	stats.merge(resources, true)
	if detail is Dictionary:
		for field in ["vitality", "max_vitality", "money"]:
			if detail.has(field):
				stats[field] = detail[field]
		var completed := 0
		var settled := 0
		for node in detail.get("route", []):
			if node.status == "cleared":
				completed += 1
			if node.kind in ["normal", "elite", "boss"] and node.status in ["cleared", "battle_won", "battle_lost"]:
				settled += 1
		stats["completed_nodes"] = detail.get("completed_nodes", completed)
		stats["settled_battles"] = detail.get("settled_battles", settled)
	return stats


func _stat_value(stats: Dictionary, key: String) -> String:
	return "%d" % int(stats[key]) if stats.get(key) != null else "—"


func _vitality_text(stats: Dictionary) -> String:
	if stats.get("vitality") == null:
		return "—"
	var value := _stat_value(stats, "vitality")
	if stats.get("max_vitality") != null:
		value += " / " + _stat_value(stats, "max_vitality")
	return value


func _resource_stat(parent: Node, caption: String, value: String, ink: Color, expanded: bool = true) -> void:
	var stat := VBoxContainer.new()
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.alignment = BoxContainer.ALIGNMENT_CENTER
	stat.add_theme_constant_override("separation", 1)
	stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expanded else Control.SIZE_SHRINK_CENTER
	if not expanded:
		stat.custom_minimum_size.x = 48
	parent.add_child(stat)
	_text(stat, caption, 12 if _compact else 14, MUTED)
	var number := _text(stat, value, (18 if expanded else 15) if _compact else (24 if expanded else 18), ink)
	number.name = "Value"


func _draw_detail() -> void:
	if not _detail_error.is_empty():
		_text(body, _detail_error, 16, UiStyle.CREAM)
		var retry := add_button(body, "records:retry", "重试", {}, func(): _detail_error = ""; _request(0, str(_selected.match_id)); _draw_page())
		_style_action(retry)
	elif not _pending.is_empty():
		_text(body, "正在读取对局详情…", 16, MUTED)
	elif not _detail is Dictionary:
		_text(body, "结算后可查看本局详情。" if str(_selected.get("result", "")).is_empty() else "这场对局只保留了结算摘要。", 16, MUTED)
	else:
		match _section:
			"cards": _deck()
			"relics": _relics()
			_: _route()


func _route() -> void:
	if _detail.route.is_empty():
		_text(body, "本局尚未进入地图节点。", 16, UiStyle.CREAM)
	var previous := 0
	for node in _detail.route:
		var term := int(node.term)
		if term != previous:
			_text(body, "第 %d 学年" % term, 17 if _compact else 23, UiStyle.TERM_HIGHLIGHT, true)
			previous = term
		var row := _detail_row(body)
		var kind := str(ROOM_NAMES.get(node.kind, node.kind))
		var id := str(node.get("event_id", ""))
		if id.is_empty():
			id = str(node.get("encounter_id", ""))
		var name := UiStyle.label(("event." if not str(node.get("event_id", "")).is_empty() else "encounter.") + id + ".name")
		var caption := "%02d　%s" % [int(node.layer), kind]
		if not id.is_empty() and name != id:
			caption += " · " + name
		_text(row, caption, 15, UiStyle.CREAM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var status := _text(row, str(ROUTE_STATES.get(node.status, "")), 13, Color("edab95") if node.status == "battle_lost" else MUTED)
		status.size_flags_horizontal = Control.SIZE_SHRINK_END


func _deck() -> void:
	var grouped := {}
	for card in _detail.cards:
		var key := "%s:%d" % [card.definition_id, int(card.upgrade_level)]
		if not grouped.has(key):
			grouped[key] = {"id": str(card.definition_id), "upgrade": int(card.upgrade_level), "count": 0}
		grouped[key].count += 1
	if grouped.is_empty():
		_text(body, "结算时牌组为空。", 16, MUTED)
	var grid := GridContainer.new()
	grid.columns = 2 if _compact else 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for entry in grouped.values():
		var row := _detail_row(grid)
		_item_art(row, entry.id, true)
		var text := UiStyle.label(entry.id) + (" +%d" % entry.upgrade if entry.upgrade > 0 else "")
		_text(row, text, 15 if _compact else 18, UiStyle.CREAM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var count := _text(row, "×%d" % entry.count, 14, UiStyle.TERM_HIGHLIGHT)
		count.size_flags_horizontal = Control.SIZE_SHRINK_END


func _relics() -> void:
	if _detail.relics.is_empty():
		_text(body, "结算时未携带饰品。", 16, MUTED)
	for entry in _detail.relics:
		var row := _detail_row(body)
		_item_art(row, str(entry.definition_id), false)
		_text(row, UiStyle.label(str(entry.definition_id)), 17, UiStyle.CREAM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var slot := _text(row, "装备槽 %d" % (int(entry.slot) + 1), 14, UiStyle.TERM_HIGHLIGHT)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_END


func _detail_row(parent: Node) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := UiStyle.surface(Color("233944"), LINE, 5)
	fill.set_content_margin_all(7 if _compact else 11)
	fill.shadow_size = 0
	panel.add_theme_stylebox_override("panel", fill)
	parent.add_child(panel)
	return add_row(panel)


func _item_art(row: Node, id: String, is_card: bool) -> void:
	var image := TextureRect.new()
	image.texture = UiStyle.texture(id)
	if image.texture == null:
		image.texture = UiNavIcon.texture("deck" if is_card else "relics")
	image.custom_minimum_size = Vector2(49, 37) if _compact else Vector2(76, 53)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(image)


func _portrait(character: String, width: int) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.custom_minimum_size.x = width
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := CharacterArt.texture_path(character, true)
	if not art.is_empty() and ResourceLoader.exists(art):
		portrait.texture = load(art)
	return portrait


func _metadata(record: Dictionary) -> String:
	var difficulty := str({"relaxed": "轻松", "normal": "标准", "hard": "困难"}.get(record.get("difficulty", ""), ""))
	var date := str(record.get("finished_at", record.get("started_at", "")))
	if record.get("finished_at") == null:
		date = str(record.get("started_at", ""))
	if record.get("source", "") == "imported":
		date = ""
	var calendar := date.left(10)
	if date.length() >= 19:
		var timestamp := Time.get_unix_time_from_datetime_string(date.left(19).replace(" ", "T"))
		calendar = Time.get_date_string_from_unix_time(int(timestamp) + 8 * 3600)
	var fields := [difficulty, calendar]
	return " · ".join(fields.filter(func(item): return not item.is_empty()))


func _character(record: Dictionary) -> String:
	var id := str(record.get("character_id", ""))
	return UiStyle.label(id) if not id.is_empty() else "冒险记录"


func _outcome(record: Dictionary) -> String:
	return str({"won": "胜利", "lost": "失败", "abandoned": "已放弃"}.get(record.get("result", ""), "进行中"))


func _outcome_ink(record: Dictionary) -> Color:
	return Color("edab95") if record.get("result", "") == "lost" else UiStyle.TERM_HIGHLIGHT


func _text(parent: Node, caption: String, pixels: int, ink: Color, title_font: bool = false) -> Label:
	var text := add_text(parent, caption, pixels, ink)
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if title_font:
		text.add_theme_font_override("font", UiStyle.title_font())
	return text


func _style_action(button: Button, quiet: bool = false) -> void:
	UiStyle.button_skin(button, "quiet" if quiet else "secondary", true)
	button.custom_minimum_size = Vector2(68 if _compact else 120, 44 if _compact else 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_font_size_override("font_size", roundi((14 if _compact else 16) * UiStyle.text_scale))
	button.autowrap_mode = TextServer.AUTOWRAP_OFF


func _back() -> void:
	if _selected.is_empty():
		action_requested.emit({"type": "ui.records_back", "payload": {}})
	else:
		_selected = {}
		_pending = ""
		_draw_page()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
