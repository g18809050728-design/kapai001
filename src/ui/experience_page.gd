class_name UiExperiencePage
extends UiFlowPage

const MapForecast = preload("res://src/run/route_forecast.gd")
const RouteCanvas = preload("res://src/ui/route_canvas.gd")

var _presentation: Dictionary = {}
var _advanced := false
var _diagnostics := false
var _local_focus := ""
var _layout_size := Vector2.ZERO
var _resize_pending := false
var _map_focus_scope := ""
var _map_overview := false
var _map_run_scope := ""
var _map_detail_scroll := 0
var _settings_status: Label
var _map_preview: PanelContainer
var _map_preview_words: VBoxContainer
var _map_forecast_words: VBoxContainer
var _map_selection_hint: Label
var _room_figure: BattleActorView
var character_motion_enabled := true
var _room_expanded := false
var _room_illustration: CampusRoomIllustration
var _full_map: UiRouteOverlay
var _toolbar: UiRunToolbar
var _map_press_id := ""
var _map_press_origin := Vector2.ZERO
var _map_press_selected := false
var _map_press_double := false
var _map_press_dragged := false
var _map_entry_generation := -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and not view.is_empty() and size != _layout_size and not _resize_pending:
		_resize_pending = true
		_resize_content.call_deferred()


func _resize_content() -> void:
	_resize_pending = false
	if is_inside_tree() and size != _layout_size:
		_layout_size = size
		refresh_local()


func _restore_local_focus(uid: String) -> void:
	if is_inside_tree() and _buttons.has(uid) and is_instance_valid(_buttons[uid]) and _buttons[uid].is_inside_tree():
		_buttons[uid].grab_focus()


func render(data: Dictionary) -> void:
	if is_instance_valid(_toolbar):
		_toolbar.close_menu(false)
	_toolbar = null
	_map_press_id = ""
	var reopen_seed := bool(get_meta("seed_open", false)) and screen == "setup"
	_close_inspector()
	if is_instance_valid(_full_map) and not _full_map.is_queued_for_deletion():
		_full_map.close()
	z_index = 1
	_room_figure = null
	_room_illustration = null
	_room_expanded = false
	var scope := "%s|%s|%s" % [data.get("run_id", ""), data.get("revision", -1), screen]
	if str(get_meta("view_scope", "")) != scope:
		_choices.clear()
	set_meta("view_scope", scope)
	super.render(data)
	var scene := RoomSceneView.new()
	scene.room = screen
	if screen == "event":
		scene.story_background = CampusRoomIllustration.background_texture("E", str(_dict(view.get("event")).get("definition_id", "")))
	elif screen == "campaign":
		var offer := _dict(view.get("campaign_offer"))
		var subtype := "FAMILIAR" if offer.get("kind") == "familiar" else str(_dict(offer.get("node_meta")).get("subtype", ""))
		if offer.get("kind") in ["service", "familiar"]:
			scene.story_background = CampusRoomIllustration.background_texture(subtype)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.z_index = -1
	add_child(scene)
	if screen != "menu" and not is_instance_valid(_toolbar):
		var rail := SpireTopRail.new()
		rail.name = "SharedTopRail"
		rail.size = Vector2(size.x,48)
		rail.z_index = -1
		add_child(rail)
		if header.get_child_count() > 1:
			var heading := header.get_child(1) as Label
			if heading != null:
				heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				heading.add_theme_color_override("font_color",Color("ead09a"))
	if not _local_focus.is_empty() and _buttons.has(_local_focus):
		_restore_local_focus.call_deferred(_local_focus)
	_local_focus = ""
	_layout_regions.call_deferred()
	if reopen_seed:
		_open_inspector("seed")


func _in_region(node: Node, region: Control) -> bool:
	return is_instance_valid(region) and (node == region or region.is_ancestor_of(node))


func _on_paper(node: Node) -> bool:
	var ancestor := node
	while ancestor != null and ancestor != self:
		if ancestor is PanelContainer:
			var skin: StyleBox = ancestor.get_theme_stylebox("panel")
			return skin is StyleBoxFlat and skin.bg_color.get_luminance() > .5
		ancestor = ancestor.get_parent()
	return false


func add_text(parent: Node, value: String, font_size: int = 18, color: Color = UiStyle.INK) -> Label:
	var chrome := _in_region(parent,header) or _in_region(parent,footer)
	var paper := _on_paper(parent)
	var ink := color
	if chrome or not paper:
		ink = Color("bdcac0") if color == UiStyle.MUTED else (UiStyle.CREAM if color == UiStyle.INK else color.lightened(.28))
	var label_node := super.add_text(parent,value,font_size,ink)
	if font_size >= 22:
		label_node.add_theme_font_override("font",UiStyle.title_font())
	if not chrome and not paper:
		label_node.add_theme_color_override("font_shadow_color",Color(0,0,0,.55))
		label_node.add_theme_constant_override("shadow_offset_y",1)
	return label_node


func add_button(parent: Node, uid: String, caption: String, draft: Variant = {}, local_callback: Callable = Callable()) -> Button:
	var button := super.add_button(parent,uid,caption,draft,local_callback)
	var dark := _in_region(parent,header) or _in_region(parent,footer) or not _on_paper(parent)
	var primary := uid.ends_with(":confirm") or uid.ends_with(":claim") or uid in ["map:enter","setup:start","setup:restart_confirm","menu:continue","menu:new","settings:apply"]
	var quiet := uid.ends_with(":back") or uid.ends_with(":menu") or uid.ends_with(":save") or uid in ["flow:help","menu:test","menu:settings","setup:advanced","setup:deck","selection:cancel","map:abandon"]
	UiStyle.button_skin(button,"primary" if primary else ("quiet" if quiet else "secondary"),dark)
	if quiet:
		button.custom_minimum_size.x = clampf(button.get_theme_font("font").get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x+30,94,350)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	elif primary:
		button.custom_minimum_size.x = 224
		if _in_region(parent,footer):
			button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _in_region(parent,header):
		button.custom_minimum_size = Vector2(58,44)
	if _in_region(parent,footer):
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		var text_width := button.get_theme_font("font").get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		button.custom_minimum_size.x = clampf(text_width+40,112,300)
	return button


func add_card(parent: Node, uid: String, id: String, detail: Dictionary, caption: String, picked: bool, callback: Callable, relic: bool = false) -> UiOfferCard:
	var card := super.add_card(parent,uid,id,detail,caption,picked,callback,relic)
	card._caption.add_theme_color_override("font_color",UiStyle.CREAM)
	return card


func refresh_local() -> void:
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focused != null:
		_local_focus = str(focused.get_meta("uid", ""))
	super.refresh_local()


func _grid(parent: Node, columns: int = 3) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = mini(columns, 3 if size.x >= 650 else 2)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 18)
	parent.add_child(grid)
	return grid


func _run_bar(_parent: Node) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = UiRunToolbar.HEIGHT - 4
	header.add_child(spacer)
	header.move_child(spacer, 0)
	_toolbar = UiRunToolbar.new()
	add_child(_toolbar)
	_toolbar.configure(self, {
		"vitality": view.get("vitality", 0), "max_vitality": view.get("max_vitality", 0), "money": view.get("money", 0),
		"journey": str(view.get("year_title", "校园冒险")),
		"relics_uid": "inspect:relics", "relics_count": _array(view.get("relics")).size(), "relics_callback": func(): _open_inspector("relics"),
		"map_uid": "flow:map", "map_callback": _open_full_map,
		"show_map": screen != "map", "map_shortcut_uid": "map:overview" if screen == "map" else "flow:map",
		"deck_uid": "inspect:deck", "deck_count": _array(view.get("cards")).size(), "deck_callback": func(): _open_inspector("deck"),
		"toggle_uid": "flow:options", "close_uid": "flow:close_options", "help_uid": "flow:help", "help_callback": _help,
		"save_uid": screen + ":save", "home_uid": screen + ":menu"
	})
	_toolbar.tooltip_text = str(view.get("map_influence", ""))
	for child in header.get_children():
		if child is Label and child.get_theme_font_size("font_size") < roundi(20*UiStyle.text_scale):
			child.tooltip_text = child.text
			child.visible = false


func _layout_regions() -> void:
	if is_instance_valid(footer):
		for row in footer.get_children():
			if not row is HBoxContainer:
				continue
			for button in row.get_children():
				if button is Button and (str(button.get_meta("uid", "")).ends_with(":confirm") or str(button.get_meta("uid", "")).ends_with(":claim") or button.get_meta("uid", "") in ["map:enter","setup:start","setup:restart_confirm"]):
					row.alignment = BoxContainer.ALIGNMENT_END
					row.move_child(button,row.get_child_count()-1)
	super._layout_regions()
	header.offset_left = 24
	header.offset_right = -24
	footer.offset_left = 24
	footer.offset_right = -24
	_scroll.offset_left = 12
	_scroll.offset_right = -12
	if screen == "menu":
		header.offset_left = size.x*.065
		header.offset_top = size.y*.12
		header.offset_right = -size.x*.54
		header.offset_bottom = header.offset_top+header.get_combined_minimum_size().y
		_scroll.offset_top = header.offset_bottom+26
		_scroll.offset_left = size.x*.065-12
		_scroll.offset_right = -size.x*.59
		_scroll.offset_bottom = -20
	if (screen in ["event", "rest"] or is_instance_valid(_room_illustration)) and not _room_expanded:
		_scroll.offset_left = size.x*.45
		_scroll.offset_right = -size.x*.055
	if is_instance_valid(_room_illustration):
		_room_illustration.visible = not _room_expanded
		_room_illustration.position = Vector2(size.x*.055,_scroll.offset_top+18)
		_room_illustration.size = Vector2(size.x*.35,maxf(100,size.y+_scroll.offset_bottom-_scroll.offset_top-36))
	if is_instance_valid(_room_figure):
		_room_figure.position = Vector2(size.x*.05,_scroll.offset_top+14)
		_room_figure.size = Vector2(size.x*.36,maxf(100,size.y+_scroll.offset_bottom-_scroll.offset_top-24))
	if screen == "setup":
		_scroll.offset_left = size.x*.07
		_scroll.offset_right = -size.x*.55
		if is_instance_valid(_room_figure):
			_room_figure.position.x = size.x*.5
			_room_figure.size.x = size.x*.36
	if screen == "reward" or (screen == "campaign" and (not is_instance_valid(_room_illustration) or _room_expanded)):
		_scroll.offset_left = size.x*.06
		_scroll.offset_right = -size.x*.06
		_fit_reward_cards()
	if screen == "map" and is_instance_valid(_map_preview) and not _map_preview.is_queued_for_deletion():
		var width := 272.0 if size.x < 1100 else 300.0
		_scroll.offset_right = -width-16
		_map_preview.position = Vector2(size.x-width-10,_scroll.offset_top)
		_map_preview.size = Vector2(width,maxf(100,size.y+_scroll.offset_bottom-_scroll.offset_top))


func _fit_reward_cards() -> void:
	var available_width := size.x + _scroll.offset_right - _scroll.offset_left - 24
	var available_height := size.y + _scroll.offset_bottom - _scroll.offset_top - 32
	for grid in body.find_children("*", "GridContainer", true, false):
		if not grid.get_meta("reward_cards", false):
			continue
		var columns := mini(3, grid.get_child_count())
		grid.columns = maxi(1, columns)
		var width := minf(220*UiStyle.text_scale, (available_width-16*(columns-1))/maxi(1,columns))
		for card in grid.get_children():
			if not card is UiOfferCard:
				continue
			var ratio := 1.05 if card._relic else 244.0/168
			var fitted_width := maxf(120, minf(width,(available_height-36*UiStyle.text_scale)/ratio))
			card.custom_minimum_size = Vector2(fitted_width, fitted_width*ratio+36*UiStyle.text_scale)
			card._base_height = card.custom_minimum_size.y
			card._fit_contents()


func _scene_character(id: String) -> void:
	_room_figure = BattleActorView.new()
	_room_figure.configure(id,"player")
	_room_figure.z_index = 0
	add_child(_room_figure)
	_room_figure.set_motion(character_motion_enabled)


func _show_room(subtype: String, title: String, event_id: String = "") -> void:
	_room_illustration = CampusRoomIllustration.new()
	_room_illustration.configure(subtype, title, event_id)
	add_child(_room_illustration)


func _open_full_map() -> void:
	if is_instance_valid(_full_map) and not _full_map.is_queued_for_deletion():
		_full_map.close()
		return
	close_card_preview()
	_close_inspector()
	_full_map = UiRouteOverlay.new()
	add_child(_full_map)
	_full_map.configure(_array(view.get("nodes")), str(view.get("current_node_id", "")), _array(view.get("reachable_node_ids")), str(view.get("year_title", "本学年")))
	if is_instance_valid(_toolbar):
		_toolbar.mark_active("map", true)
	_full_map.closed.connect(func():
		if is_instance_valid(_toolbar):
			_toolbar.mark_active("map", false))


func _event_needs_confirmation(option: Dictionary) -> bool:
	for amount in _dict(option.get("cost")).values():
		if int(amount) > 0:
			return true
	for effect in _array(option.get("effects")):
		if str(effect.get("op", "")) in ["upgrade_card", "remove_card", "gain_card", "gain_relic"]:
			return true
	return false


func _render_menu() -> void:
	reset_page("DDL 战争", "把校园日常，打成自己的牌。")
	_scroll.follow_focus = true
	var title_label := header.get_child(0) as Label
	title_label.add_theme_font_size_override("font_size",roundi(64*UiStyle.text_scale))
	add_text(body,"四学年 · 校园卡牌冒险",16,UiStyle.BRASS)

	var resume := add_button(body,"menu:continue","继续冒险",_ui("continue"))
	resume.disabled = not bool(view.get("has_active_session",false)) and not bool(view.get("can_continue",false))
	if resume.disabled:
		resume.tooltip_text = str(view.get("save_error",""))
		if resume.tooltip_text.is_empty():
			resume.tooltip_text = "还没有可以继续的冒险。"
		add_text(body,resume.tooltip_text,14,UiStyle.MUTED)
	add_button(body,"menu:new","新的四年",_ui("new_run"))
	add_button(body,"menu:compendium","图鉴",_ui("compendium"))
	add_button(body,"menu:test","测试房间",_ui("test_room"))
	add_button(body,"menu:settings","设置与存档",_ui("settings"))
	for uid in ["menu:continue","menu:new","menu:compendium","menu:test","menu:settings"]:
		var option: Button = _buttons[uid]
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.custom_minimum_size = Vector2(220,52)
		option.add_theme_font_override("font",UiStyle.title_font())
		option.add_theme_font_size_override("font_size",roundi(25*UiStyle.text_scale))
		for state in ["normal","hover","pressed","focus","disabled"]:
			option.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		option.add_theme_color_override("font_hover_color",Color("ffe6a0"))
	if bool(view.get("has_active_session",false)):
		add_text(body,"当前冒险已保留。",14,UiStyle.MUTED)
	if not str(view.get("save_error","")).is_empty():
		add_text(body,"存档暂时不可用："+str(view.save_error),14,UiStyle.RED)


func _map_preview_node(node: Dictionary, reachable: Array) -> void:
	if not is_instance_valid(_map_preview_words) or not is_instance_valid(_map_forecast_words):
		return
	for column in [_map_preview_words, _map_forecast_words]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var id := str(node.get("node_id", ""))
	var forecast := MapForecast.describe(_array(view.get("nodes")),id)
	add_text(_map_preview_words,"第 %02d 层  /  %s" % [int(node.get("layer",0)), _map_short_name(node)],13,Color("76522c"))
	var scene_key := str({"normal":"BG_classroom","elite":"BG_classroom","boss":"BG_classroom","rest":"BG_dorm","shop":"BG_shop","event":"BG_campus"}.get(str(node.get("kind","")),"BG_study"))
	var thumbnail := TextureRect.new()
	thumbnail.texture = UiStyle.texture(scene_key)
	thumbnail.custom_minimum_size.y = (48 if UiStyle.text_scale > 1.0 else 64) if size.y < 700 else 86
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_preview_words.add_child(thumbnail)
	var title := add_text(_map_preview_words,_map_node_title(node),18,Color("3d382b"))
	title.add_theme_font_override("font", UiStyle.title_font())
	title.name = "PreviewNodeTitle"
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title.text
	var selected := str(_choices.get("map:node","")) == id
	var status := "✓ 已预选 · 可进入" if selected and reachable.has(id) else ("→ 可进入 · 单击预选" if reachable.has(id) else "○ 仅预览 · 不能进入")
	var status_label := add_text(_map_preview_words,status,14,Color("763c2b") if reachable.has(id) else Color("665d48"))
	status_label.name = "PreviewNodeStatus"
	add_text(_map_forecast_words,_campaign_node_hint(node) if not str(node.get("subtype","")).is_empty() else _node_hint(str(node.get("kind",""))),14,Color("47402f"))
	var text := add_text(_map_forecast_words,str(forecast.text),14,Color("47402f"))
	text.name = "ForecastFullText"
	if not reachable.has(id):
		add_text(_map_forecast_words,"这里只预览路线，确认可达节点后才会前进。",13,Color("665d48"))
	var scroll := _map_forecast_words.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0


func _overview_locate(id: String) -> void:
	_map_overview = false
	refresh_local()
	var canvas := find_child("RouteMap",true,false) as UiRouteCanvas
	if is_instance_valid(canvas):
		_focus_map_after_layout.call_deferred(weakref(canvas),id,_render_generation,_map_focus_scope)


func _flow_navigation(_prefix: String) -> void:
	pass


func _bottom(text: String) -> HBoxContainer:
	add_text(footer, text, 15, UiStyle.MUTED)
	var row := add_row(footer)
	row.alignment = BoxContainer.ALIGNMENT_END
	return row


func _local_button(parent: Node, uid: String, title: String, key: String, value: String) -> Button:
	var selected := not value.is_empty() and str(_choices.get(key, "")) == value
	var button := add_button(parent, uid, ("✓ " if selected and not title.begins_with("✓") else "") + title, {}, func(): _choose(key, value))
	if selected:
		UiStyle.button_skin(button,"selected",true)
	return button


func _choose(key: String, value: String) -> void:
	if key == "map:node" and screen == "map":
		_select_map_node(value)
		return
	if key in ["campaign:deck_mode", "campaign:category"] and str(_choices.get(key, "")) != value:
		for field in ["campaign:option", "campaign:target", "campaign:replace"]:
			_choices.erase(field)
		if key == "campaign:category":
			_choices.erase("campaign:deck_mode")
	super._choose(key, value)


func add_panel(parent: Node) -> VBoxContainer:
	var column := super.add_panel(parent)
	var skin := UiStyle.surface(Color("20323f"),Color("5c6a6f"),4)
	skin.bg_color.a = .93
	column.get_parent().add_theme_stylebox_override("panel",skin)
	return column


func _choice_panel(parent: Node, selected: bool) -> VBoxContainer:
	var column := add_panel(parent)
	var style := UiStyle.surface(Color("344d5b") if selected else Color("243947"),UiStyle.BRASS if selected else Color("607581"))
	style.border_width_left = 4 if selected else 1
	column.get_parent().add_theme_stylebox_override("panel", style)
	return column


func _cancel(parent: Node, key: String, title: String = "取消预选") -> void:
	_local_button(parent, "selection:cancel", title, key, "")


func _render_reward() -> void:
	var offer := _dict(view.get("pending_reward"))
	_scope(str(offer.get("offer_id", "")))
	reset_page("选择你的收获", "悬停或键盘聚焦查看卡文 · 点击预选 · 底部确认领取")
	_run_bar(header)
	var pending: Array = _array(offer.get("items")).filter(func(item): return item.get("status", "pending") == "pending")
	var money := int(_dict(offer.get("meta")).get("money", 0))
	if pending.is_empty():
		add_text(body, "奖励已处理完成。", 22)
		return
	var item: Dictionary = pending[0]
	var id := str(item.item_id)
	var relic: bool = item.get("kind", "card") == "relic"
	add_text(header, "已获得金钱 %d · 待处理 %d 项 · %s" % [money, pending.size(), "饰品奖励" if relic else "卡牌奖励"], 15)
	var grid := _grid(body)
	grid.set_meta("reward_cards", true)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var details := _dict(item.get("candidate_details"))
	for candidate in _array(item.get("candidates")):
		var cid := _candidate_id(candidate)
		add_card(grid, "reward:%s:pick:%s" % [id, cid], cid, _dict(details.get(cid)), UiStyle.label(cid), _choices.get(id, "") == cid, func(): _choose(id, cid), relic)
	var selected := str(_choices.get(id, ""))
	if relic and _relics_full():
		_replacement_picker(body, "reward:" + id, id + ":replace")
	var skipping: bool = _choices.get(id + ":skip", "") == "yes"
	var summary := "已选：" + UiStyle.label(selected) if not selected.is_empty() else "请选择一个候选；查看说明不会领取奖励。"
	if relic and _relics_full() and not selected.is_empty():
		var replacement := str(_choices.get(id + ":replace", ""))
		summary += " · 装备槽已满，请向下选择替换对象" if replacement.is_empty() else " · 将失去：" + _relic_name(replacement)
	var row := _bottom("确认跳过这项奖励？" if skipping else summary)
	if skipping:
		add_button(row, "reward:%s:skip_confirm" % id, "确认跳过", _action("skip_reward", {"offer_id": offer.get("offer_id", ""), "item_id": id}))
		_cancel(row, id + ":skip", "继续选牌")
	else:
		var payload := {"offer_id": offer.get("offer_id", ""), "item_id": id, "candidate_id": selected}
		if not str(_choices.get(id + ":replace", "")).is_empty():
			payload.replace_relic_id = _choices[id + ":replace"]
		var confirm := add_button(row, "reward:%s:claim" % id, "领取这件饰品" if relic else "领取这张卡", _action("claim_reward", payload))
		if selected.is_empty() or (relic and _relics_full() and not payload.has("replace_relic_id")):
			confirm.disabled = true
			confirm.tooltip_text = "请先选择要替换的已装备饰品" if not selected.is_empty() else "请先预选奖励"
		_cancel(row, id)
		if item.get("skippable", true):
			_local_button(row, "reward:%s:skip" % id, "跳过此项", id + ":skip", "yes")


func _render_campaign() -> void:
	var offer := _dict(view.get("campaign_offer"))
	_scope(str(offer.get("offer_id", "")))
	var kind := str(offer.get("kind", ""))
	var title := str(_dict(offer.get("node_meta")).get("title","校园服务")) if kind == "service" else str({"grand": "学年大奖励", "relic": "学年纪念饰品", "direction": "选择学习方向", "destination": "选择毕业去向", "familiar": "校园熟人"}.get(kind, "学年选择"))
	var story_room := kind in ["service", "familiar"]
	reset_page("" if story_room else title, "" if story_room else "候选已固定 · 查看和返回不会消耗奖励")
	_run_bar(header)
	if story_room:
		var heading := add_text(body, title, 28, UiStyle.BRASS)
		heading.name = "EventTitle"
	var category := str(_choices.get("campaign:category", ""))
	if kind == "grand":
		if category.is_empty():
			var grid := _grid(body)
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for entry in [["cards", "获得高阶卡牌", "从固定的三个候选中选择一张"], ["deck", "升级或移除", "调整牌组，选择具体的一张实例"], ["resources", "获得资源", _quote(offer, "resources")]]:
				var panel := _choice_panel(grid, false)
				add_text(panel, str(entry[1]), 22)
				add_text(panel, str(entry[2]), 17)
				_local_button(panel, "campaign:category:" + str(entry[0]), "查看此类", "campaign:category", str(entry[0]))
			_local_button(body, "campaign:skip", "放弃奖励 · 获得30金钱", "campaign:category", "skip")
		else:
			var categories := add_row(header)
			for entry in [["cards", "获得卡牌"], ["deck", "调整牌组"], ["resources", "获得资源"], ["skip", "放弃 · +30金钱"]]:
				_local_button(categories, "campaign:skip" if entry[0] == "skip" else "campaign:category:" + str(entry[0]), str(entry[1]), "campaign:category", str(entry[0]))
		if category.is_empty():
			_bottom("本次只能选择一项 · 确认前可比较")
			return
		if category in ["resources", "skip"]:
			var panel := _choice_panel(body, true)
			add_art(panel, "campus_meal" if category == "resources" else "BG_campus", Vector2(220, 130))
			add_text(panel, "已预选：" + ("获得资源" if category == "resources" else "放弃奖励"), 22)
			add_text(panel, _quote(offer, category), 18)
	if kind == "grand" and category == "cards":
		_candidates(offer, false)
	elif kind == "relic":
		_candidates(offer, true)
	elif kind == "grand" and category == "deck":
		_campaign_deck(offer, false)
	elif kind == "service":
		var meta := _dict(offer.get("node_meta"))
		_room_expanded = not str(_choices.get("campaign:deck_mode", "")).is_empty()
		_show_room(str(meta.get("subtype", "E")),str(meta.get("title", "校园服务")))
		if not _room_expanded:
			var story := add_text(body,CampusRoomIllustration.narrative(str(meta.get("subtype", "E"))),17)
			story.name = "EventNarrative"
		if meta.get("subtype", "") in ["L", "LAB", "T"]:
			if not _room_expanded:
				add_text(body,"服务费用：%d 金钱%s" % [int(offer.get("service_cost",0))," + 5 精力（至少保留1）" if meta.get("subtype") == "LAB" else ""],16,UiStyle.BRASS)
			_campaign_deck(offer, meta.get("subtype", "") == "LAB")
		else:
			for option in ["heal", "money", "progress"]:
				var quote := _preview_quote(offer, option)
				if quote.get("ok", false):
					var label := str({"heal":"和伙伴休息片刻","money":"参与活动 / 实践","progress":"整理毕设进度"}[option])
					var action_button := add_button(body,"campaign:"+option,label+"\n"+_quote(offer,option),_campaign_action(offer,option,""))
					UiStyle.story_choice(action_button)
		if int(view.get("term", 1)) == 2 and int(meta.get("layer", 0)) >= 7 and not bool(view.get("campaign", {}).get("direction_changed", false)):
			add_text(body, "更换一次方向 · 支付30金钱", 18)
			for id in CampaignService.DIRECTIONS:
				_local_button(body, "campaign:direction:" + id, _campaign_label(id), "campaign:option", "direction_" + id)
	elif kind in ["direction", "destination"]:
		var compact_choices := size.y < 600 and UiStyle.text_scale <= 1.0
		if compact_choices and kind == "direction":
			add_text(header, str(_preview_quote(offer, CampaignService.DIRECTIONS[0]).get("consequence", "")), 13, UiStyle.MUTED)
		var grid := _grid(body, 2)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if compact_choices:
			grid.add_theme_constant_override("v_separation", 10)
		for id in (CampaignService.DIRECTIONS if kind == "direction" else CampaignService.DESTINATIONS):
			var panel := _choice_panel(grid, _choices.get("campaign:option", "") == id)
			if compact_choices:
				panel.add_theme_constant_override("separation", 4)
				var style := panel.get_parent().get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.content_margin_top = 6
				style.content_margin_bottom = 6
				style.content_margin_left = 10
				style.content_margin_right = 10
				panel.get_parent().add_theme_stylebox_override("panel", style)
			var content := add_row(panel)
			var artwork := str({"theory": "R3-P02-03", "engineering": "R3-P01-27", "competition": "R3-P03-19", "practice": "R3-P04-10", "job": "R3-P04-30", "exam": "BG_study", "research": "R3-P02-01", "abroad": "BG_campus"}.get(id, "BG_campus"))
			var resource_slot := "map.destination." + str(id)
			if UiStyle.texture(resource_slot) != null:
				artwork = resource_slot
			var art := add_art(content, artwork, Vector2(84, 52) if compact_choices else Vector2(138, 112))
			art.set_meta("resource_slot", resource_slot)
			art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var words := VBoxContainer.new()
			words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.add_child(words)
			add_text(words, _campaign_label(id), 17 if compact_choices else 19)
			if not compact_choices or kind != "direction":
				add_text(words, str(_preview_quote(offer, id).get("consequence", "")), 12 if compact_choices else 14)
			var pick := _local_button(panel, "campaign:" + id, "✓ 已预选" if _choices.get("campaign:option", "") == id else "预选此项", "campaign:option", id)
			if compact_choices:
				pick.custom_minimum_size.y = 30
				pick.add_theme_font_size_override("font_size", 14)
	elif kind == "familiar":
		_show_room("FAMILIAR","校园熟人")
		var story := add_text(body,CampusRoomIllustration.narrative("FAMILIAR"),17)
		story.name = "EventNarrative"
		var action_button := add_button(body,"campaign:familiar","和熟人聊一聊\n"+_quote(offer,"money"),_campaign_action(offer,"money",""))
		UiStyle.story_choice(action_button)
	if kind in ["service","familiar"] and not _room_expanded and str(_choices.get("campaign:option", "")).is_empty():
		var exit_row := _bottom("行动收益已列明 · 点击行动完成本次活动")
		if kind == "service" and _dict(offer.get("node_meta")).get("subtype") in ["L","LAB","T"]:
			(footer.get_child(0) as Label).text = "选择卡牌，比较前后效果，再确认服务"
		add_button(exit_row,"campaign:skip","离开这里",_campaign_action(offer,"skip",""))
		return
	var option := str(_choices.get("campaign:option", ""))
	var target := str(_choices.get("campaign:target", ""))
	if kind == "grand" and category in ["resources", "skip"]:
		option = category
	var quote := _preview_quote(offer, option, target, str(_choices.get("campaign:replace", "")))
	var summary := _quote(offer, option, target, str(_choices.get("campaign:replace", ""))) if not option.is_empty() else "请选择对象或行动"
	if kind == "relic" and option == "claim" and quote.get("ok", false) and int(quote.get("money_delta", 0)) > 0:
		summary = "重复饰品，将折算：" + summary
	var row := _bottom(summary)
	var action := _campaign_action(offer, option, target)
	if _choices.has("campaign:replace"):
		action.payload.replace_relic_id = _choices["campaign:replace"]
	var confirm := add_button(row, "campaign:confirm", str({"card": "领取此卡", "claim": "确认领取 / 替换", "convert": "确认折算", "upgrade": "升级此卡", "remove": "移除此卡", "skip": "确认放弃", "resources": "领取资源"}.get(option, "确认选择")), action)
	confirm.disabled = option.is_empty() or not quote.get("ok", false)
	if kind == "grand":
		add_button(row, "campaign:back", "返回类别", {}, func(): _choices.clear(); refresh_local())
	else:
		if kind == "relic":
			add_button(row, "selection:cancel", "返回饰品候选", {}, func(): _choices.erase("campaign:target"); _choices.erase("campaign:option"); _choices.erase("campaign:replace"); refresh_local())
			if not target.is_empty() and _relics_full():
				_local_button(row, "campaign:convert:" + target, "主动折算 · " + _quote(offer, "convert", target), "campaign:option", "convert")
		else:
			_cancel(row, "campaign:option")
		if kind not in ["direction", "destination"]:
			_local_button(row, "campaign:skip", "跳过 · %s金钱" % ("20" if kind == "relic" else "0"), "campaign:option", "skip")


func _candidates(offer: Dictionary, relic: bool) -> void:
	var target := str(_choices.get("campaign:target", ""))
	var grid := _grid(body)
	grid.set_meta("reward_cards", true)
	for value in _array(offer.get("candidates")):
		var id := str(value)
		add_card(grid, "campaign:claim:" + id, id, _dict(offer.get("details", {}).get(id)), UiStyle.label(id), _choices.get("campaign:target", "") == id, func():
			_choices["campaign:option"] = "claim" if relic else "card"
			_choices["campaign:target"] = id
			_choices.erase("campaign:skip")
			refresh_local(), relic)
	if relic:
		add_text(body, "携带 %d/%d 件饰品；预选后比较实际装备槽。" % [_array(view.get("relics")).size(), int(view.get("relic_slots", 3))], 15)
		if not target.is_empty():
			_replacement_picker(body, "campaign", "campaign:replace")


func _replacement_picker(parent: Node, uid_prefix: String, choice_key: String) -> void:
	add_text(parent, "%d个装备槽 · 选择替换后失去的旧效果" % int(view.get("relic_slots", 3)) if _relics_full() else "当前装备槽 · 领取后保留已有饰品", 17)
	var grid := _grid(parent)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var relics := _array(view.get("relics"))
	for index in int(view.get("relic_slots", 3)):
		var panel := add_panel(grid)
		panel.add_theme_constant_override("separation", 4)
		var style := UiStyle.box(Color("253947"))
		for side in ["left", "right", "top", "bottom"]:
			style.set("content_margin_" + side, 4)
		panel.get_parent().add_theme_stylebox_override("panel", style)
		var relic: Dictionary = {}
		for entry in relics:
			if int(entry.get("slot", relics.find(entry))) == index:
				relic = entry
		if relic.is_empty():
			add_text(panel, "空槽 %d" % (index + 1), 18)
			continue
		var id := str(relic.relic_id)
		add_art(panel, str(relic.definition_id), Vector2(90, 64))
		add_text(panel, "装备槽 %d · %s" % [int(relic.get("slot", index)) + 1, "将被替换" if _choices.get(choice_key, "") == id else "已装备"], 14)
		add_text(panel, UiStyle.label(str(relic.definition_id)), 16)
		add_text(panel, UiContentText.describe_relic(_dict(relic.get("detail"))), 14)
		add_button(panel, uid_prefix + ":inspect:" + id, "查看完整饰品", {}, func(): _open_reference("relics", id))
		if _relics_full():
			_local_button(panel, uid_prefix + ":replace:" + id, "✓ 将失去此效果" if _choices.get(choice_key, "") == id else "替换这一槽", choice_key, id)


func _relic_name(instance_id: String) -> String:
	for relic in _array(view.get("relics")):
		if str(relic.get("relic_id", "")) == instance_id:
			return UiStyle.label(str(relic.get("definition_id", "")))
	return "所选饰品"


func _campaign_deck(offer: Dictionary, upgrade_only: bool) -> void:
	var option := str(_choices.get("campaign:deck_mode", ""))
	var row := add_row(body)
	var upgrade := _local_button(row, "campaign:mode:upgrade", "升级一张牌", "campaign:deck_mode", "upgrade")
	if offer.get("kind") == "service":
		upgrade.text += "\n查看当前牌组，比较升级效果"
		UiStyle.story_choice(upgrade)
	if not upgrade_only:
		var remove := _local_button(row, "campaign:mode:remove", "移除一张牌", "campaign:deck_mode", "remove")
		if offer.get("kind") == "service":
			remove.text += "\n选择一张实例，整理牌组"
			UiStyle.story_choice(remove)
	if option.is_empty():
		return
	_local_button(row, "campaign:mode:back", "返回行动", "campaign:deck_mode", "")
	_target_grid(body, "campaign", option, "campaign:target", func(card):
		_choices["campaign:target"] = str(card.card_id)
		_choices["campaign:option"] = option
		refresh_local())
	if not str(_choices.get("campaign:target", "")).is_empty():
		_selected_comparison("campaign:target", option == "upgrade")


func _target_grid(parent: Node, prefix: String, mode: String, key: String, callback: Callable) -> void:
	var grid := _grid(parent)
	var cards := _array(view.get("cards"))
	for index in cards.size():
		var card: Dictionary = cards[index]
		var id := str(card.card_id)
		var button := add_card(grid, prefix + ":" + mode + ":" + id, str(card.definition_id), _dict(card.get("detail")), _card_name(card) + " · 第%d张" % (index + 1), _choices.get(key, "") == id, func(): callback.call(card))
		if mode == "upgrade" and not card.get("upgrade_detail") is Dictionary:
			button.tooltip_text = "已达最高等级；可查看当前卡文。"
	if cards.is_empty():
		add_text(grid, "没有可用目标。", 20)


func _selected_comparison(key: String, upgrading: bool) -> void:
	for card in _array(view.get("cards")):
		if str(card.card_id) == str(_choices.get(key, "")):
			var panel := add_panel(body)
			_card_comparison(panel, card, upgrading)
			if not upgrading:
				add_text(panel, "移除后牌组 %d 张。确认前可以取消。" % (_array(view.get("cards")).size() - 1), 17)


func _preview_quote(offer: Dictionary, option: String, target: String = "", replacement: String = "") -> Dictionary:
	return _dict(offer.get("previews", {}).get("%s|%s|%s" % [option, target, replacement]))


func _quote(offer: Dictionary, option: String, target: String = "", replacement: String = "") -> String:
	var quote := _preview_quote(offer, option, target, replacement)
	if not quote.get("ok", false):
		var reason := str({"run.campaign.replacement.required": "请选择要替换的旧饰品", "run.campaign.resources.insufficient": "金钱或精力不足（实验室须保留至少1精力）", "run.campaign.upgrade.invalid": "这张卡已达最高等级", "run.campaign.deck.minimum": "牌组不能少于5张", "run.campaign.candidate.invalid": "请选择候选", "run.campaign.convert.requires_full": "饰品槽未满，只能领取"}.get(quote.get("error_key", ""), "请预选行动和具体对象"))
		return "不可确认：" + reason
	var label := UiStyle.label(target)
	for card in _array(view.get("cards")):
		if card.card_id == target:
			label = _card_name(card)
	var value := label + " · " if not target.is_empty() else ""
	value += "金钱 %+d · 精力 %+d" % [int(quote.get("money_delta", 0)), int(quote.get("vitality_delta", 0))]
	if not replacement.is_empty():
		for relic in _array(view.get("relics")):
			if relic.relic_id == replacement:
				value += " · 失去 " + UiStyle.label(str(relic.definition_id))
	return value


func _render_map() -> void:
	var current_id := str(view.get("current_node_id", ""))
	var nodes: Array = _array(view.get("nodes")).filter(func(node): return int(node.get("term", view.get("term", 1))) == int(view.get("term", 1)))
	var node_ids: Array = nodes.map(func(node): return str(node.node_id))
	var reachable: Array = _array(view.get("reachable_node_ids")).filter(func(id): return node_ids.has(str(id)))
	var run_scope := "%s|%s" % [view.get("run_id", ""), view.get("term", 1)]
	if run_scope != _map_run_scope:
		_map_overview = false
		_map_detail_scroll = 0
		_choices.erase("map:node")
		_map_run_scope = run_scope
	var current_title := "起点"
	for node in nodes:
		if str(node.get("node_id", "")) == current_id:
			current_title = _map_node_title(node)
			break
	var compact_map := size.x < 1100 and UiStyle.text_scale >= 1.25
	reset_page("校园路线 · " + str(view.get("year_title", "")), "", compact_map)
	var map_title: Label = header.get_child(0)
	if compact_map:
		map_title.add_theme_font_size_override("font_size", roundi(21 * UiStyle.text_scale))
	map_title.tooltip_text = str(view.get("map_influence", ""))
	_run_bar(header)
	if not compact_map and not str(view.get("map_influence", "")).is_empty():
		add_text(header, str(view.get("map_influence", "")), 14, UiStyle.MUTED)
	var selected := str(_choices.get("map:node", ""))
	var forecast := MapForecast.describe(nodes, selected)
	if not _map_overview:
		var legend := add_text(body, "◆ 当前　✓ 已过　断圈可入　淡墨不可达　· 红圈预选 / 朱线预览后3层", 12 if compact_map else 14, UiStyle.MUTED)
		legend.tooltip_text = "当前：%s · %d 个相邻后继可入\n%s" % [current_title, reachable.size(), view.get("map_influence", "")]
	if nodes.is_empty():
		add_text(body, "本学年地图尚未生成。确认方向或毕业去向后再查看；未来学年不会提前展示。", 18)
	if _map_overview and not nodes.is_empty():
		add_text(body, "本学年全图 · 当前：%s · 圈记可入 · 朱线预览后3层" % current_title, 14)
		var overview := RouteCanvas.new()
		overview.name = "MapOverview"
		overview.overview = true
		overview.detailed_overview = true
		overview.configure(nodes, reachable, current_id, selected)
		overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overview.node_inspected.connect(_overview_locate)
		body.add_child(overview)
		overview.arrange.call_deferred()
		_fit_map_overview.call_deferred(weakref(overview), _render_generation)
	var canvas := RouteCanvas.new()
	canvas.name = "RouteMap"
	canvas.configure(nodes, reachable, current_id, selected)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	var forward: Array = []
	for root_id in ([current_id] if node_ids.has(current_id) else reachable):
		for id in MapForecast.describe(nodes, str(root_id), nodes.size()).node_ids:
			if not forward.has(id):
				forward.append(id)
	var description := "选择任意节点查看路线；只有相邻可入节点能够进入。"
	var node_generation := _render_generation
	for node in nodes:
		var id := str(node.node_id)
		var current := id == current_id
		var status := "当前" if current else ("已过" if node.get("status", "") == "completed" else ("可入" if reachable.has(id) else ("后续" if forward.has(id) else "不可达")))
		var button := add_button(canvas, "node:" + id, "", {}, func(): _choose("map:node", id))
		button.set_script(RouteCanvas.NodeStamp)
		button.set_meta("node_id", id)
		button.gui_input.connect(_map_node_input.bind(id,node_generation))
		button.size_flags_horizontal = 0
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
		var subtype := str(node.get("subtype", ""))
		if subtype.is_empty():
			subtype = str({"normal": "N", "elite": "EL", "boss": "B", "shop": "S", "rest": "R", "event": "E"}.get(str(node.get("kind", "")), "E"))
		button.call("configure", subtype, _map_short_name(node), status, forecast.node_ids.has(id), canvas.node_textures.get(id))
		button.toggle_mode = true
		button.set_pressed_no_signal(id == selected)
		button.set_meta("current_node", current)
		button.tooltip_text = "第%s层 · %s · %s\n%s\n%s" % [node.layer, _map_node_title(node), status, _node_hint(str(node.kind)), _campaign_node_hint(node)]
		button.tooltip_text += "\n首次点击预选 · 再次点击或双击进入" if reachable.has(id) else "\n点击查看路线"
		if id == selected:
			description = "已选：%s · %s · 第%s层" % [_map_node_title(node), status, node.layer]
			if str(node.get("kind", "")) == "elite":
				description += " · 高风险"
	canvas.arrange.call_deferred()
	if not _map_overview and node_ids.has(selected) and _local_focus == "node:" + selected:
		_ensure_map_selection_visible.call_deferred(selected, _render_generation)
	var scope := "%s|%s|%s|%s|%s|%s" % [view.get("run_id", ""), view.get("term", 0), current_id, view.get("revision", -1), size, UiStyle.text_scale]
	if scope != _map_focus_scope:
		var focus_id := str(reachable[0]) if not reachable.is_empty() else current_id
		if not focus_id.is_empty():
			_focus_map_after_layout.call_deferred(weakref(canvas), focus_id, _render_generation, scope)
	_map_preview = UiMapPaper.new()
	_map_preview.name = "MapNodePreview"
	_map_preview.cool = true
	add_child(_map_preview)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation",10)
	_map_preview.add_child(preview_column)
	_map_preview_words = VBoxContainer.new()
	_map_preview_words.name = "MapNodeSummary"
	_map_preview_words.add_theme_constant_override("separation",6)
	preview_column.add_child(_map_preview_words)
	preview_column.add_child(HSeparator.new())
	var preview_scroll := ScrollContainer.new()
	preview_scroll.name = "RouteForecast"
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(preview_scroll)
	_map_forecast_words = VBoxContainer.new()
	_map_forecast_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_forecast_words.add_theme_constant_override("separation",10)
	preview_scroll.add_child(_map_forecast_words)
	var preview_id := selected if node_ids.has(selected) else (str(reachable[0]) if not reachable.is_empty() else current_id)
	for node in nodes:
		if str(node.node_id) == preview_id:
			_map_preview_node(node,reachable)
		var node_button: Button = _buttons.get("node:"+str(node.node_id))
		if node_button != null:
			node_button.mouse_entered.connect(func(): _map_preview_node(node,reachable))
			node_button.focus_entered.connect(func(): _map_preview_node(node,reachable))
	_layout_regions.call_deferred()

	var row := _bottom(description + "  ·  再次点击已选节点进入 / 可双击")
	_map_selection_hint = footer.get_child(0) as Label
	# Selection text cannot resize the footer and shift the node under a second click.
	_map_selection_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_map_selection_hint.clip_text = true
	_map_selection_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_selection_hint.tooltip_text = _map_selection_hint.text
	var enter := add_button(row, "map:enter", "进入此节点", func(): return _action("enter_node", {"node_id": str(_choices.get("map:node", ""))}))
	enter.disabled = not node_ids.has(selected) or not reachable.has(selected)
	if enter.disabled:
		enter.tooltip_text = "请先选择当前位置直接相连的真实可入节点。"
	add_button(row, "map:current", "定位当前" if compact_map else "回到当前位置", {}, func(): _focus_map(canvas, current_id if not current_id.is_empty() else str(reachable[0]) if not reachable.is_empty() else ""))
	var overview_button := add_button(row, "map:overview", "收起全图" if _map_overview else "全图概览", {}, _toggle_map_overview)
	overview_button.tooltip_text = "切换本页全图概览 · M"
	add_button(row, "map:abandon", "放弃本局", {}, func(): _confirm_abandon = not _confirm_abandon; refresh_local())
	if _confirm_abandon:
		add_button(add_row(footer), "map:abandon_confirm", "确认放弃本局", _action("abandon_run", {"confirmed": true}))


func _select_map_node(id: String) -> void:
	var nodes: Array = _array(view.get("nodes")).filter(func(node): return int(node.get("term", view.get("term", 1))) == int(view.get("term", 1)))
	var selected_node: Dictionary = {}
	for node in nodes:
		if str(node.node_id) == id:
			selected_node = node
			break
	if selected_node.is_empty():
		return
	_choices["map:node"] = id
	var reachable := _array(view.get("reachable_node_ids"))
	var forecast := MapForecast.describe(nodes, id)
	# Keep native buttons, focus, scroll and input capture intact between clicks.
	for node in nodes:
		var button: Button = _buttons.get("node:" + str(node.node_id))
		if is_instance_valid(button):
			button.set_pressed_no_signal(str(node.node_id) == id)
			button.set("forecast", forecast.node_ids.has(str(node.node_id)))
			button.queue_redraw()
	for canvas_name in ["RouteMap", "MapOverview"]:
		var canvas := find_child(canvas_name, true, false) as UiRouteCanvas
		if is_instance_valid(canvas):
			canvas.select_node(id)
	_map_preview_node(selected_node, reachable)
	var button: Button = _buttons.get("node:" + id)
	var status := str(button.get("map_status")) if is_instance_valid(button) else ""
	_map_selection_hint.text = "已选：%s · %s · 第%s层%s  ·  再次点击此节点进入 / 可双击" % [_map_node_title(selected_node), status, selected_node.layer, " · 高风险" if str(selected_node.kind) == "elite" else ""]
	_map_selection_hint.tooltip_text = _map_selection_hint.text
	var enter: Button = _buttons.get("map:enter")
	enter.disabled = not reachable.has(id)
	enter.tooltip_text = "确认前往预选节点；也可再次点击此节点或双击进入。" if reachable.has(id) else "这里只预览路线；请选择当前位置直接相连的可入节点。"
	local_selection_changed.emit(_choices.duplicate(true))


func _map_node_input(event: InputEvent, id: String, generation: int) -> void:
	if not is_inside_tree() or screen != "map" or generation != _render_generation or _map_entry_generation == generation:
		return
	var button: Button = _buttons.get("node:"+id)
	if not is_instance_valid(button) or button.disabled:
		return
	if event is InputEventMouseMotion and _map_press_id == id:
		_map_press_dragged = _map_press_dragged or event.global_position.distance_to(_map_press_origin) > 8
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	button.accept_event()
	if event.pressed:
		_map_press_id = id
		_map_press_origin = event.global_position
		_map_press_selected = str(_choices.get("map:node", "")) == id
		_map_press_double = event.double_click
		_map_press_dragged = false
		button.grab_focus()
		return
	if _map_press_id != id:
		return
	_map_press_id = ""
	if _map_press_dragged or not Rect2(Vector2.ZERO, button.size).has_point(event.position):
		return
	var enter := (_map_press_selected or _map_press_double) and _array(view.get("reachable_node_ids")).has(id)
	_choose("map:node", id)
	if enter:
		# Reuse the fixed CTA's preview, current draft and shell revision gate.
		_map_entry_generation = generation
		if not press("map:enter"):
			_map_entry_generation = -1


func _map_short_name(node: Dictionary) -> String:
	var subtype := str(node.get("subtype", ""))
	return str({"N": "战斗", "EL": "精英", "K": "竞赛", "B": "首领", "S": "商店", "R": "休息", "E": "事件", "L": "图书", "LAB": "实验", "T": "导师", "C": "社团", "I": "实习", "ST": "毕设"}.get(subtype, {"normal": "战斗", "elite": "精英", "boss": "首领", "shop": "商店", "rest": "休息", "event": "事件"}.get(str(node.get("kind", "")), "节点")))


func _toggle_map_overview() -> void:
	if not _map_overview:
		_map_detail_scroll = _scroll.scroll_vertical
	_map_overview = not _map_overview
	refresh_local()
	_scroll_position.y = 0 if _map_overview else _map_detail_scroll
	_scroll.scroll_vertical = _scroll_position.y


func _fit_map_overview(canvas_ref: WeakRef, generation: int, frames_left: int = 4) -> void:
	var canvas := canvas_ref.get_ref() as UiRouteCanvas
	if not is_inside_tree() or not is_instance_valid(canvas) or generation != _render_generation:
		return
	if frames_left > 0 or _scroll_restore_pending:
		get_tree().create_timer(0).timeout.connect(_fit_map_overview.bind(canvas_ref, generation, maxi(0, frames_left - 1)), CONNECT_ONE_SHOT)
		return
	canvas.overview_height = maxf(56, _scroll.get_global_rect().end.y - canvas.global_position.y - 12)
	canvas.custom_minimum_size.y = canvas.overview_height


func _ensure_map_selection_visible(id: String, generation: int, frames_left: int = 4) -> void:
	if not is_inside_tree() or generation != _render_generation:
		return
	if frames_left > 0 or _scroll_restore_pending:
		get_tree().create_timer(0).timeout.connect(_ensure_map_selection_visible.bind(id, generation, maxi(0, frames_left - 1)), CONNECT_ONE_SHOT)
		return
	if _buttons.has("node:" + id) and is_instance_valid(_buttons["node:" + id]) and _buttons["node:" + id].has_focus():
		var button: Control = _buttons["node:" + id]
		_scroll.ensure_control_visible(button)
		# Scroll offsets are integers while scaled button geometry can end on .5.
		var viewport_rect := _scroll.get_global_rect()
		var button_rect := button.get_global_rect()
		if button_rect.end.y > viewport_rect.end.y:
			_scroll.scroll_vertical += ceili(button_rect.end.y - viewport_rect.end.y)
		elif button_rect.position.y < viewport_rect.position.y:
			_scroll.scroll_vertical -= ceili(viewport_rect.position.y - button_rect.position.y)
		_scroll_position.y = _scroll.scroll_vertical


func _focus_map(canvas: UiRouteCanvas, id: String) -> void:
	if is_instance_valid(canvas) and canvas.positions.has(id):
		var center: Vector2 = canvas.global_position + canvas.positions[id]
		_scroll.scroll_vertical = maxi(0, roundi(_scroll.scroll_vertical + center.y - _scroll.get_global_rect().get_center().y))
		_scroll_position.y = _scroll.scroll_vertical


func _focus_map_after_layout(canvas_ref: WeakRef, id: String, generation: int, scope: String, frames_left: int = 2) -> void:
	var canvas := canvas_ref.get_ref() as UiRouteCanvas
	if not is_inside_tree() or not is_instance_valid(canvas) or generation != _render_generation:
		return
	if frames_left > 0 or _scroll_restore_pending:
		get_tree().create_timer(0).timeout.connect(_focus_map_after_layout.bind(canvas_ref, id, generation, scope, maxi(0, frames_left - 1)), CONNECT_ONE_SHOT)
		return
	_focus_map(canvas, id)
	_map_focus_scope = scope


func _render_shop() -> void:
	var shop := _dict(view.get("shop"))
	_scope(str(shop.get("shop_id", "")))
	reset_page("校园商店", "价格直接可见 · 点击商品预选 · 购买后继续浏览")
	_run_bar(header)
	var removing: bool = _choices.get("shop:mode", "") == "remove"
	var selected := str(_choices.get("shop:stock", ""))
	var summary := "请选择商品或移除服务。"
	var action := {}
	if removing:
		var removal := _dict(shop.get("removal"))
		add_text(header, "移除费用 %s · 已用 %s/%s 次 · 至少保留 %s 张" % [removal.get("price", 0), removal.get("used", 0), removal.get("max", 1), removal.get("minimum_deck_size", 0)], 16)
		_target_or_comparison("shop", "remove", "shop:card")
		summary = "支付 %s 金钱 · 余额 %d · 移除后 %d 张牌" % [removal.get("price", 0), int(view.get("money", 0)) - int(removal.get("price", 0)), _array(view.get("cards")).size() - 1]
		action = _action("remove_card", {"shop_id": shop.get("shop_id", ""), "card_instance_id": _choices.get("shop:card", "")})
	else:
		body.alignment = BoxContainer.ALIGNMENT_CENTER
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var tableau := VBoxContainer.new()
		tableau.name = "ShopTableau"
		tableau.add_theme_constant_override("separation",12)
		body.add_child(tableau)
		var cards_row := add_row(tableau)
		cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var supplies_row := add_row(tableau)
		supplies_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var stocks := _array(shop.get("stocks"))
		for stock_index in stocks.size():
			var stock: Dictionary = stocks[stock_index]
			var id := str(stock.stock_id)
			var kind := str(stock.kind)
			var panel := add_panel(cards_row if kind == "card" else supplies_row)
			panel.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			panel.get_parent().add_theme_stylebox_override("panel",StyleBoxEmpty.new())
			panel.add_theme_constant_override("separation",5)
			var status := "已售罄" if stock.get("sold", false) else ("金钱不足" if int(stock.price) > int(view.get("money", 0)) else "可购买")
			var price := add_text(panel, "%s 金钱\n%s" % [stock.price, status], 14, UiStyle.RED if status != "可购买" else UiStyle.BRASS)
			price.name = "StockPrice_" + id.validate_node_name()
			price.add_theme_color_override("font_color",UiStyle.RED.lightened(.3) if status != "可购买" else UiStyle.CREAM)
			var price_skin := UiStyle.surface(Color("263943"), Color("7e704f"), 3)
			price_skin.set_content_margin_all(4)
			price_skin.shadow_size = 0
			price.add_theme_stylebox_override("normal", price_skin)
			price.tooltip_text = "%s 金钱 · %s" % [stock.price, status]
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if kind == "meal":
				var meal_row := add_row(panel)
				add_art(meal_row, "campus_meal", Vector2(84, 76))
				var meal_info := VBoxContainer.new()
				meal_info.custom_minimum_size.x = 162 * UiStyle.text_scale
				meal_row.add_child(meal_info)
				_local_button(meal_info, "shop:pick:" + id, "校园餐食\n实际回复 %s 精力" % stock.get("detail", {}).get("heal_amount", 0), "shop:stock", id)
				price.reparent(meal_info)
			else:
				var stock_card := add_card(panel, "shop:pick:" + id, str(stock.definition_id), _dict(stock.get("detail")), UiStyle.label(str(stock.definition_id)), selected == id, func(): _choose("shop:stock", id), kind == "relic")
				stock_card._caption.add_theme_color_override("font_color",UiStyle.CREAM)
				var width := (148.0 if size.x >= 1100 else 126.0)*minf(UiStyle.text_scale,1.25)
				stock_card.custom_minimum_size.x = width
				stock_card._base_height = width*(1.0 if kind == "relic" else 244.0/168)+24
				stock_card.custom_minimum_size.y = stock_card._base_height
				stock_card._fit_contents()
				panel.move_child(price,panel.get_child_count()-1)
			if selected == id:
				summary = "%s · 支付%s · 余额%d" % ["校园餐食" if kind == "meal" else UiStyle.label(str(stock.definition_id)), stock.price, int(view.get("money", 0)) - int(stock.price)]
				if kind == "meal":
					summary += " · 实际回复 %s 精力" % stock.get("detail", {}).get("heal_amount", 0)
				action = _action("buy_item", {"shop_id": shop.get("shop_id", ""), "stock_id": id})
				if kind == "relic" and _relics_full():
					_replacement_picker(body, "shop:" + id, id + ":replace")
					if _choices.has(id + ":replace"):
						action.payload.replace_relic_id = _choices[id + ":replace"]
	var row := _bottom(summary)
	if not action.is_empty():
		add_button(row, "shop:confirm", "移除这张卡" if removing else "购买所选商品", action)
	_local_button(row, "shop:removal", "返回货架" if removing else "移除卡牌服务", "shop:mode", "" if removing else "remove")
	add_button(row, "shop:leave", "离开商店", _leave())


func _render_event() -> void:
	var event := _dict(view.get("event"))
	var event_id := str(event.get("definition_id", ""))
	_scope(str(event.get("event_instance_id", "")))
	reset_page("")
	_run_bar(header)
	var selected := str(_choices.get("event:option", ""))
	_room_expanded = not selected.is_empty()
	if not _room_expanded:
		_show_room("E",UiStyle.label(event_id),event_id)
	if selected.is_empty():
		var title := add_text(body,UiStyle.label(event_id),28,UiStyle.BRASS)
		title.name = "EventTitle"
		var story := add_text(body,CampusRoomIllustration.narrative("E",event_id),16)
		story.name = "EventNarrative"
		for option in _array(event.get("options")):
			var caption := CampusRoomIllustration.option_title(event_id,str(option.option_id),_event_option_name(str(option.option_id),str(option.get("label_key",""))))
			var effects_text := UiStyle.describe_effects(_array(option.get("effects")))
			caption += "\n消耗："+_cost_text(_dict(option.get("cost")))+(" · "+effects_text if not effects_text.is_empty() else " · 继续当前路线")
			var blocking := _event_blocking_text(option)
			if not blocking.is_empty():
				caption += "\n不可用："+blocking
			var uid := "event:option:leave" if option.option_id == "leave" else "event:"+str(option.option_id)
			var pick: Button
			if _event_needs_confirmation(option):
				pick = _local_button(body,uid,caption,"event:option",str(option.option_id))
			else:
				pick = add_button(body,uid,caption,_event_action(event,option))
			pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
			pick.custom_minimum_size.y = 74*UiStyle.text_scale
			pick.disabled = not option.get("enabled",true)
			if pick.disabled:
				pick.tooltip_text = blocking
			UiStyle.story_choice(pick)
		_bottom("点击行动执行 · 需要选牌或支付的行动先查看详情")
		return

	for option in _array(event.get("options")):
		if str(option.option_id) != selected:
			continue
		add_text(header, CampusRoomIllustration.option_title(event_id,selected,_event_option_name(selected, str(option.get("label_key", "")))), 18)
		var effects := _array(option.get("effects"))
		for index in effects.size():
			var effect: Dictionary = effects[index]
			var op := str(effect.get("op", ""))
			var key := "%s:%s" % [selected, index]
			if op in ["upgrade_card", "remove_card"]:
				if op == "upgrade_card" and effect.get("all_eligible", false):
					var eligible := _array(option.get("eligible_card_ids"))
					add_text(body, "将自动升级 %d 张工作牌" % eligible.size(), 19)
					for card in _array(view.get("cards")):
						if eligible.has(str(card.get("card_id", ""))):
							_card_comparison(body, card, true)
				else:
					var mode := "upgrade" if op == "upgrade_card" else "remove"
					_target_or_comparison("event:" + selected, mode, key)
			elif op in ["gain_card", "gain_relic"]:
				var grid := _grid(body)
				for candidate in _array(option.get("candidates", {}).get(str(index))):
					var id := _candidate_id(candidate)
					add_card(grid, "event:%s:pick:%s" % [selected, id], id, _dict(option.get("candidate_details", {}).get(id)), UiStyle.label(id), _choices.get(key, "") == id, func(): _choose(key, id), op == "gain_relic")
				if op == "gain_relic" and _relics_full():
					_replacement_picker(body, "event:" + selected, selected + ":replace")
		var row := _bottom("消耗：" + _cost_text(_dict(option.get("cost"))) + " · " + UiStyle.describe_effects(effects))
		add_button(row, "event:confirm", "确认此行动", _event_action(event, option))
		_cancel(row, "event:option", "返回所有选项")


func _event_blocking_text(option: Dictionary) -> String:
	var reasons: Array[String] = []
	for item in _array(option.get("blocking")):
		var code := str(item.get("code", ""))
		var reason := str({"INSUFFICIENT_RESOURCE":"资源不足，行动后需至少保留1精力", "INVALID_TARGET":"当前牌组没有符合条件的目标", "ALREADY_RESOLVED":"本次事件已经完成"}.get(code,"当前条件不满足"))
		if not reasons.has(reason):
			reasons.append(reason)
	return "；".join(reasons)


func _render_rest() -> void:
	var rest := _dict(view.get("rest"))
	_scope(str(view.get("current_node_id", "")))
	reset_page("休整时光", "点击恢复即可休息 · 升级与移除先选牌")
	_run_bar(header)
	var selected := str(_choices.get("rest:option", ""))
	_room_expanded = selected in ["upgrade","remove"]
	if not _room_expanded:
		_show_room("R","宿舍休息")
		add_text(body,"精力 %s / %s" % [view.get("vitality",0),view.get("max_vitality",0)],23)
	var options := body
	for option in _array(rest.get("options")):
		var caption := _rest_name(str(option.option_id))+"\n"
		caption += "实际回复 %s 精力" % rest.get("effective_heal_amount",rest.get("heal_amount",0)) if not option.get("needs_card",false) else "查看牌组，比较后确认一张实例"
		var pick: Button
		if option.get("needs_card",false):
			pick = _local_button(options,"rest:option:"+str(option.option_id),caption,"rest:option",str(option.option_id))
		else:
			pick = add_button(options,"rest:option:"+str(option.option_id),caption,_action("take_rest",{"node_id":view.get("current_node_id",""),"option_id":option.option_id}))
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.custom_minimum_size.y = 80*UiStyle.text_scale
		for state in ["normal","hover","pressed","disabled","focus"]:
			var skin := pick.get_theme_stylebox(state).duplicate() as StyleBox
			skin.set_content_margin(SIDE_LEFT,52)
			pick.add_theme_stylebox_override(state,skin)
		var glyph := Control.new()
		glyph.position = Vector2(16,26)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph_kind := "heart" if not option.get("needs_card",false) else "book"
		glyph.draw.connect(func(): EffectGlyph.paint(glyph,glyph_kind,Vector2(12,12),11,UiStyle.BRASS))
		pick.add_child(glyph)
		pick.disabled = not option.get("enabled",true)
		if pick.disabled:
			pick.tooltip_text = "没有合法目标，或本节点已使用。"
	var action := {}
	var summary := "请选择一种休整方式。"
	for option in _array(rest.get("options")):
		if str(option.option_id) != selected:
			continue
		var payload := {"node_id": view.get("current_node_id", ""), "option_id": selected}
		if option.get("needs_card", false):
			_target_or_comparison("rest", "upgrade" if selected == "upgrade" else "remove", "rest:card")
			payload.card_instance_id = _choices.get("rest:card", "")
			summary = "升级所选实例 · 确认前可取消"
		else:
			summary = "实际回复 %s 精力 · 当前 %s/%s" % [rest.get("effective_heal_amount", rest.get("heal_amount", 0)), view.get("vitality", 0), view.get("max_vitality", 0)]
			add_text(body, summary, 24)
		action = _action("take_rest", payload)
	var row := _bottom(summary)
	if not action.is_empty():
		add_button(row, "rest:confirm", "确认休整", action)
	if not selected.is_empty():
		_cancel(row, "rest:option")


func _target_or_comparison(prefix: String, mode: String, key: String) -> void:
	_target_grid(body, prefix, mode, key, func(card): _choose(key, str(card.card_id)))
	if not str(_choices.get(key, "")).is_empty():
		_selected_comparison(key, mode == "upgrade")


func _render_setup() -> void:
	# Use the existing configuration/old-run replacement semantics, with one hero in focus.
	var characters := _array(view.get("characters"))
	var manifests := _array(view.get("manifests"))
	if not manifests.is_empty():
		_manifest = _option_id(manifests[0])
	if _character.is_empty():
		_character = str(view.get("default_character_id", "P01"))
	var difficulties := _array(view.get("difficulties"))
	if _difficulty.is_empty() and not difficulties.is_empty():
		_difficulty = str(view.get("default_difficulty", _option_id(difficulties[0])))
	reset_page("开启校园冒险", "大一至大四 · 选择你的角色")
	_scene_character(_character)
	var tabs := add_row(footer)
	for character in characters:
		var id := str(character.id)
		var button := add_button(tabs, "setup:character:" + id, ("✓ " if _character == id else "") + UiStyle.label(id).split("·")[0], {}, func(): _select_setup("character", id))
		button.icon = UiStyle.character_portrait(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",34)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.custom_minimum_size.x = button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x+78
		button.disabled = bool(character.get("locked", false))
		button.tooltip_text = str(character.get("reason", ""))
		UiStyle.button_skin(button,"primary" if _character == id else "secondary",true)
	for character in characters:
		if str(character.id) != _character:
			continue
		var info := add_panel(body)
		info.get_parent().add_theme_stylebox_override("panel",UiStyle.surface(Color(UiStyle.NIGHT,.78),Color(UiStyle.BRASS,.4)))
		add_text(info,"人物  /  " + str(characters.find(character)+1).pad_zeros(2),12,UiStyle.MUTED)
		add_text(info, UiStyle.label(_character), 32)
		add_text(info,str({"P01":"策略铺垫 → 工作连携 → 取回策略","P02":"开题 → 编排章节 → 发表论文","P03":"叠加不同负面 → 触发复合反应","P04":"伙伴协作 → 积攒协同 → 团队爆发"}.get(_character,"")),19,UiStyle.GREEN.darkened(.3))
		add_text(info, UiContentText.describe_character_passive(str(character.get("passive_id", ""))), 17)
		add_text(info, "开局无饰品 · 12张起始牌 · 沿四张学年地图前进", 16)
		add_button(info, "setup:deck", "查看起始牌组", {}, func(): _setup_deck(character))
	if _seed_revision != int(view.get("seed_revision", 0)):
		_seed = str(view.get("default_seed", ""))
		_seed_revision = int(view.get("seed_revision", 0))
	var difficulty_row := add_row(footer)
	difficulty_row.name = "SetupConfiguration"
	add_text(difficulty_row,"冒险难度",14,UiStyle.MUTED)
	for difficulty in difficulties:
		var id := _option_id(difficulty)
		var pick := add_button(difficulty_row, "setup:difficulty:" + id, ("✓ " if _difficulty == id else "") + _difficulty_name(id), {}, func(): _select_setup("difficulty", id))
		pick.tooltip_text = DifficultyRules.description(_dict(view.get("difficulty_details",{}).get(id)))
		UiStyle.button_skin(pick,"primary" if _difficulty == id else "secondary",true)
	add_button(difficulty_row,"setup:advanced","高级设置",{},func(): _open_inspector("seed"))
	add_text(footer,DifficultyRules.description(_dict(view.get("difficulty_details",{}).get(_difficulty))),14,UiStyle.MUTED).name = "DifficultyEffects"
	var confirming := bool(view.get("confirm_restart", false))
	var row := _bottom(("确认结束旧局并替换当前存档？" if confirming else "人物：" + UiStyle.label(_character) + " · " + _difficulty_name(_difficulty)))
	add_button(row, "setup:restart_confirm" if confirming else "setup:start", "结束旧局并开始" if confirming else "开始四年冒险", func(): return _ui("start_run", {"character_id": _character, "difficulty": _difficulty, "manifest_id": _manifest, "seed": _seed, "confirmed": confirming}))
	if confirming:
		add_button(row, "setup:restart_cancel", "取消重开", _ui("cancel_restart"))
	add_button(row, "setup:back", "返回", _ui("menu"))


func _setup_deck(character: Dictionary) -> void:
	var saved: Variant = view.get("cards")
	view.cards = _array(character.get("starter_details"))
	_open_inspector("deck")
	view.cards = saved


func _render_settings() -> void:
	super._render_settings()
	# Move the apply/back controls to a fixed action area.
	var actions := add_row(footer)
	for uid in ["settings:apply", "settings:back"]:
		var button: Control = _buttons[uid]
		button.reparent(actions)
	_buttons["settings:restore_backup"].get_parent().get_parent().visible = _diagnostics
	add_button(header, "settings:diagnostics", "收起存档诊断" if _diagnostics else "查看存档诊断 / 恢复备份", {}, func(): _diagnostics = not _diagnostics; refresh_local())
	_presentation = _dict(view.get("settings")).get("presentation", {"text_scale": 100, "reduced_motion": false, "animation_speed": 1}).duplicate(true) if _presentation.is_empty() else _presentation
	var panel := add_panel(body)
	body.move_child(panel.get_parent(), 0)
	add_text(panel, "文字与动态", 23)
	var applied := _dict(view.get("settings")).get("presentation", _presentation) as Dictionary
	add_text(panel, "当前生效：" + _presentation_summary(applied), 16, UiStyle.MUTED)
	var sizes := _setting_row(panel, "字号")
	for value in [100, 125, 150]:
		add_button(sizes, "settings:text:" + str(value), ("✓ " if _presentation.text_scale == value else "") + "%d%%" % value, {}, func(): _presentation.text_scale = value; refresh_local())
	var motion := _setting_row(panel, "动态")
	for value in [false, true]:
		add_button(motion, "settings:motion:" + str(value), "减少动态" if value else "标准动态", {}, func(): _presentation.reduced_motion = value; refresh_local())
	var speed := _setting_row(panel, "倍速")
	for value in [0, 1, 2, 4]:
		add_button(speed, "settings:speed:" + str(value), "动画关闭" if value == 0 else "动画 ×%d" % value, {}, func(): _presentation.animation_speed = value; refresh_local())
	if bool(_presentation.reduced_motion):
		add_text(panel, "已选减少动态：应用后动画关闭，倍速偏好仍保留。", 15, UiStyle.MUTED)
	for value in [100, 125, 150]:
		_mark_setting("settings:text:" + str(value), int(_presentation.text_scale) == value)
	for value in [false, true]:
		_mark_setting("settings:motion:" + str(value), bool(_presentation.reduced_motion) == value)
		_mark_setting("settings:autosave:" + str(value), _autosave == value)
		_mark_setting("settings:audio:" + str(value), bool(_audio_settings.get("muted", false)) == value)
	for value in [0, 1, 2, 4]:
		_mark_setting("settings:speed:" + str(value), int(_presentation.animation_speed) == value)
	_settings_status = add_text(footer, "", 15)
	footer.move_child(_settings_status, 0)
	_update_settings_status()
	for slider in body.find_children("Volume*", "HSlider", true, false):
		slider.value_changed.connect(func(_value): _update_settings_status())
	_drafts["settings:apply"] = func(): return _ui("save_settings", {"autosave": _autosave, "audio": _audio_settings.duplicate(true), "presentation": _presentation.duplicate(true)})


func _setting_row(parent: Node, title: String) -> HBoxContainer:
	var row := add_row(parent)
	var label := add_text(row, title, 16)
	label.custom_minimum_size.x = 48
	label.size_flags_horizontal = Control.SIZE_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


func _mark_setting(uid: String, selected: bool) -> void:
	if not _buttons.has(uid):
		return
	var button: Button = _buttons[uid]
	button.text = button.text.trim_prefix("● ").trim_prefix("○ ").trim_prefix("✓ ")
	button.toggle_mode = true
	button.set_pressed_no_signal(selected)
	button.set_meta("setting_selected", selected)
	if selected:
		button.text = "✓ " + button.text + " · 已选"
	UiStyle.button_skin(button,"selected" if selected else "secondary",true)


func _presentation_summary(value: Dictionary) -> String:
	var speed := int(value.get("animation_speed", 1))
	var motion := bool(value.get("reduced_motion", false))
	var animation := "动画关闭（减少动态）" if motion else ("动画关闭" if speed == 0 else "动画 ×%d" % speed)
	return "字号 %d%% · %s · %s" % [int(value.get("text_scale", 100)), "减少动态" if motion else "标准动态", animation]


func _update_settings_status() -> void:
	var applied := _dict(view.get("settings"))
	var changed := _autosave != bool(applied.get("autosave", true)) or _audio_settings != _dict(applied.get("audio")) or _presentation != _dict(applied.get("presentation"))
	_settings_status.text = ("尚未应用：点击“应用设置”保存修改。" if changed else "已生效") + " · 已保存：自动保存%s · 声音%s" % ["开启" if bool(applied.get("autosave", true)) else "关闭", "静音" if bool(_dict(applied.get("audio")).get("muted", false)) else "开启"]
	_settings_status.add_theme_color_override("font_color", UiStyle.RED if changed else UiStyle.MUTED)


func _render_summary() -> void:
	super._render_summary()
	var summary := _dict(view.get("terminal_summary"))
	if summary.is_empty():
		summary = _dict(view.get("run_summary"))
	var reasons := {"deadline_expired": "DDL 已到期，仍有未完成任务", "vitality_depleted": "精力耗尽", "four_years_completed": "四学年已完成", "abandoned": "你主动结束了本局"}
	add_text(header, str(reasons.get(summary.get("reason", ""), "本次冒险已结束")), 21, UiStyle.RED if summary.get("result", "") == "lost" else UiStyle.INK)
	for uid in ["summary:retry", "summary:menu"]:
		_buttons[uid].reparent(footer)
	for label in body.find_children("*", "Label", true, false):
		if label.text.contains("完成战斗"):
			label.text = label.text.replace("完成战斗", "已结算战斗")


func _open_seed_settings() -> void:
	_close_inspector()
	_inspect_return_focus = get_viewport().gui_get_focus_owner()
	for control in find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			_inspector_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	_inspector = Control.new()
	_inspector.name = "SeedSettings"
	_inspector.z_index = 200
	_inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inspector)
	var shade := ColorRect.new()
	shade.color = Color(.02,.04,.06,.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_inspector())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "SeedSettingsPanel"
	panel.custom_minimum_size.x = minf(680,size.x-64)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",UiStyle.surface(UiStyle.NIGHT,UiStyle.BRASS))
	center.add_child(panel)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation",18)
	panel.add_child(words)
	var heading := add_row(words)
	var title := add_text(heading,"高级设置 · 本局种子",24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := add_button(heading,"inspect:close","完成 · Esc",{},_close_inspector)
	close.autowrap_mode = TextServer.AUTOWRAP_OFF
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 136
	add_text(words,"相同种子与选择可重现冒险；开始后不能修改。关闭后保留当前输入。",16)
	var input := LineEdit.new()
	input.name = "RunSeedInput"
	input.text = _seed
	input.placeholder_text = "十进制整数种子"
	input.custom_minimum_size.y = 48
	input.add_theme_font_size_override("font_size",roundi(18*UiStyle.text_scale))
	input.text_changed.connect(func(value): _seed = value)
	words.add_child(input)
	var actions := add_row(words)
	actions.alignment = BoxContainer.ALIGNMENT_END
	add_button(actions,"setup:seed_random","重新生成种子",_ui("random_seed"))
	set_meta("seed_open",true)
	_focus_seed.call_deferred(weakref(input),_render_generation)


func _open_inspector(kind: String) -> void:
	close_card_preview()
	if kind == "seed":
		_open_seed_settings()
		return
	if kind in ["relics", "help", "rules", "log", "info"]:
		_open_reference(kind)
		return
	super._open_inspector(kind)
	_inspector.z_index = 200
	if is_instance_valid(_toolbar):
		_toolbar.mark_active("deck" if kind == "deck" else "relics", kind in ["deck", "relics"])
	if kind != "deck":
		return
	var grid: GridContainer = _inspector.find_children("*", "GridContainer", true, false)[0]
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = maxi(2,mini(5,int((size.x-90)/(194*UiStyle.text_scale+18))))
	var cards := _array(view.get("cards"))
	for index in cards.size():
		var entry: Dictionary = cards[index]
		var card := add_card(grid, "inspect:card:" + str(entry.get("card_id", index)), str(entry.get("definition_id", "")), _dict(entry.get("detail")), _card_name(entry) + " · 第%d张" % (index + 1), false, func(): pass)
		card.pressed.connect(func(): _preview_card = card; _show_card_preview(true))
	var search := LineEdit.new()
	search.placeholder_text = "查找名称 / 类型 / 费用1 / 已升级 / 未升级"
	search.custom_minimum_size.y = 42
	grid.get_parent().get_parent().add_child(search)
	search.text_changed.connect(func(value):
		for child in grid.get_children():
			var searchable: String = child.text + " " + UiStyle.label(str(child.detail.get("type", ""))) + " 费用" + str(child.detail.get("cost", 0)) + (" 已升级" if int(child.detail.get("upgrade_level", 0)) > 0 else " 未升级")
			child.visible = value.is_empty() or searchable.contains(value))
	var sorting := add_row(search.get_parent())
	for key in ["name", "cost", "type"]:
		add_button(sorting, "inspect:sort:" + key, "按" + str({"name": "名称", "cost": "费用", "type": "类型"}[key]) + "排序", {}, func():
			var entries := grid.get_children()
			entries.sort_custom(func(a, b):
				if key == "cost":
					return int(a.detail.get("cost", 0)) < int(b.detail.get("cost", 0))
				return str(a.text if key == "name" else a.detail.get("type", "")) < str(b.text if key == "name" else b.detail.get("type", "")))
			for index in entries.size():
				grid.move_child(entries[index], index))


func _close_inspector() -> void:
	if is_instance_valid(_reference):
		_reference.close()
	if is_instance_valid(_toolbar):
		_toolbar.mark_active("deck", false)
		_toolbar.mark_active("relics", false)
	set_meta("seed_open", false)
	close_card_preview()
	super._close_inspector()
	for uid in _buttons.keys():
		if str(uid).begins_with("inspect:card:") or str(uid).begins_with("inspect:sort:"):
			_buttons.erase(uid)


func _focus_seed(field: WeakRef, generation: int) -> void:
	var input: LineEdit = field.get_ref()
	if generation == _render_generation and is_instance_valid(input) and input.is_inside_tree() and not input.is_queued_for_deletion():
		input.grab_focus()


func _help() -> void:
	_open_reference("rules")


func _open_reference(kind: String, relic_id: String = "") -> void:
	if is_instance_valid(_inspector) and not is_instance_valid(_reference):
		_close_inspector()
	_inspector = open_reference("rules" if kind == "help" else kind, relic_id)
	_buttons["inspect:close"] = _reference._close
	if is_instance_valid(_toolbar):
		_toolbar.mark_active("relics", kind == "relics")
	_reference.closed.connect(func():
		_inspector = null
		_buttons.erase("inspect:close")
		if is_instance_valid(_toolbar): _toolbar.mark_active("relics", false))


func _input(event: InputEvent) -> void:
	if is_instance_valid(_reference) and _reference.visible:
		return
	if is_instance_valid(_toolbar) and _toolbar.route_input(event):
		return
	if is_instance_valid(_full_map) and _full_map.visible:
		return
	if is_instance_valid(_toolbar) and not is_instance_valid(_inspector) and event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.keycode == KEY_F10:
			press("flow:options")
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_D, KEY_G, KEY_F1, KEY_L]:
			press("inspect:deck" if event.keycode == KEY_D else ("flow:log" if event.keycode == KEY_L else "flow:help"))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and not is_instance_valid(_inspector) and not _array(view.get("nodes")).is_empty():
		if screen == "map":
			press("map:overview")
		else:
			_open_full_map()
		get_viewport().set_input_as_handled()
		return
	if _preview_pinned and event is InputEventMouseButton and not _card_preview.get_global_rect().has_point(get_global_mouse_position()):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I and is_instance_valid(_preview_card):
			_show_card_preview(true)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(_card_preview):
				close_card_preview()
			elif is_instance_valid(_inspector):
				_close_inspector()
			else:
				_choices.clear()
				refresh_local()
			get_viewport().set_input_as_handled()
			return
	super._input(event)
