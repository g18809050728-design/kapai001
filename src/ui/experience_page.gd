class_name UiExperiencePage
extends UiFlowPage

var _presentation: Dictionary = {}
var _advanced := false
var _diagnostics := false
var _local_focus := ""
var _layout_size := Vector2.ZERO
var _resize_pending := false
var _map_focus_scope := ""


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
	var scope := "%s|%s|%s" % [data.get("run_id", ""), data.get("revision", -1), screen]
	if str(get_meta("view_scope", "")) != scope:
		_choices.clear()
	set_meta("view_scope", scope)
	super.render(data)
	if not _local_focus.is_empty() and _buttons.has(_local_focus):
		_restore_local_focus.call_deferred(_local_focus)
	_local_focus = ""


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
	var row := add_row(header)
	add_button(row, "inspect:deck", "牌组 · %d" % _array(view.get("cards")).size(), {}, func(): _open_inspector("deck"))
	add_button(row, "inspect:relics", "饰品 · %d" % _array(view.get("relics")).size(), {}, func(): _open_inspector("relics"))
	add_button(row, screen + ":save", "保存", _ui("save"))
	add_button(row, screen + ":menu", "暂停 / 菜单", _ui("menu"))
	add_button(row, "flow:help", "规则帮助", {}, _help)


func _flow_navigation(_prefix: String) -> void:
	pass


func _bottom(text: String) -> HBoxContainer:
	add_text(footer, text, 15, UiStyle.MUTED)
	return add_row(footer)


func _local_button(parent: Node, uid: String, title: String, key: String, value: String) -> Button:
	var selected := not value.is_empty() and str(_choices.get(key, "")) == value
	var button := add_button(parent, uid, ("✓ " if selected and not title.begins_with("✓") else "") + title, {}, func(): _choose(key, value))
	if selected:
		var style := UiStyle.box(Color("e6ecdf"))
		style.border_color = UiStyle.GOLD
		style.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", style)
	return button


func _choose(key: String, value: String) -> void:
	if key in ["campaign:deck_mode", "campaign:category"] and str(_choices.get(key, "")) != value:
		for field in ["campaign:option", "campaign:target", "campaign:replace"]:
			_choices.erase(field)
		if key == "campaign:category":
			_choices.erase("campaign:deck_mode")
	super._choose(key, value)


func _choice_panel(parent: Node, selected: bool) -> VBoxContainer:
	var column := add_panel(parent)
	var style := UiStyle.box(Color("f3f2e6") if selected else Color("fffbef"))
	style.border_color = UiStyle.GOLD if selected else Color("c0cbbd")
	style.set_border_width_all(2)
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
	var row := _bottom("确认跳过这项奖励？" if skipping else ("已选：" + UiStyle.label(selected) if not selected.is_empty() else "请选择一个候选；查看说明不会领取奖励。"))
	if skipping:
		add_button(row, "reward:%s:skip_confirm" % id, "确认跳过", _action("skip_reward", {"offer_id": offer.get("offer_id", ""), "item_id": id}))
		_cancel(row, id + ":skip", "继续选牌")
	else:
		var payload := {"offer_id": offer.get("offer_id", ""), "item_id": id, "candidate_id": selected}
		if not str(_choices.get(id + ":replace", "")).is_empty():
			payload.replace_relic_id = _choices[id + ":replace"]
		var confirm := add_button(row, "reward:%s:claim" % id, "领取这件饰品" if relic else "领取这张卡", _action("claim_reward", payload))
		if selected.is_empty():
			confirm.disabled = true
		_cancel(row, id)
		if item.get("skippable", true):
			_local_button(row, "reward:%s:skip" % id, "跳过此项", id + ":skip", "yes")


func _render_campaign() -> void:
	var offer := _dict(view.get("campaign_offer"))
	_scope(str(offer.get("offer_id", "")))
	var kind := str(offer.get("kind", ""))
	reset_page(str({"grand": "学年大奖励", "relic": "学年纪念饰品", "direction": "选择学习方向", "destination": "选择毕业去向", "service": "校园服务", "familiar": "校园熟人"}.get(kind, "学年选择")), "候选已固定 · 查看和返回不会消耗奖励")
	_run_bar(header)
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
		add_text(header, str(meta.get("title", "")), 16)
		if meta.get("subtype", "") in ["L", "LAB", "T"]:
			_campaign_deck(offer, meta.get("subtype", "") == "LAB")
		else:
			var row := add_row(body)
			for option in ["heal", "money", "progress"]:
				var quote := _preview_quote(offer, option)
				if quote.get("ok", false):
					_local_button(row, "campaign:" + option, _quote(offer, option), "campaign:option", option)
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
			var art := add_art(content, artwork, Vector2(84, 52) if compact_choices else Vector2(138, 112))
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
		_local_button(body, "campaign:familiar", "咨询校园熟人 · 获得10金钱", "campaign:option", "money")
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
	for value in _array(offer.get("candidates")):
		var id := str(value)
		add_card(grid, "campaign:claim:" + id, id, _dict(offer.get("details", {}).get(id)), UiStyle.label(id), _choices.get("campaign:target", "") == id, func():
			_choices["campaign:option"] = "claim" if relic else "card"
			_choices["campaign:target"] = id
			_choices.erase("campaign:skip")
			refresh_local(), relic)
	if relic:
		add_text(body, "携带 %d/3 件饰品；预选后查看三个装备槽。" % _array(view.get("relics")).size(), 15)
		if not target.is_empty():
			_replacement_picker(body, "campaign", "campaign:replace")


func _replacement_picker(parent: Node, uid_prefix: String, choice_key: String) -> void:
	add_text(parent, "三个装备槽 · 选择替换后失去的旧效果" if _relics_full() else "当前装备槽 · 领取后保留已有饰品", 17)
	var grid := _grid(parent)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var relics := _array(view.get("relics"))
	for index in 3:
		var panel := add_panel(grid)
		panel.add_theme_constant_override("separation", 4)
		var style := UiStyle.box(Color("fffbef"))
		for side in ["left", "right", "top", "bottom"]:
			style.set("content_margin_" + side, 4)
		panel.get_parent().add_theme_stylebox_override("panel", style)
		if index >= relics.size():
			add_text(panel, "空槽 %d" % (index + 1), 18)
			continue
		var relic: Dictionary = relics[index]
		var id := str(relic.relic_id)
		add_text(panel, UiStyle.label(str(relic.definition_id)), 16)
		add_text(panel, UiContentText.describe_relic(_dict(relic.get("detail"))), 14)
		if _relics_full():
			_local_button(panel, uid_prefix + ":replace:" + id, "✓ 将失去此效果" if _choices.get(choice_key, "") == id else "替换这一槽", choice_key, id)


func _campaign_deck(offer: Dictionary, upgrade_only: bool) -> void:
	var option := str(_choices.get("campaign:deck_mode", ""))
	var row := add_row(body)
	_local_button(row, "campaign:mode:upgrade", "升级一张牌", "campaign:deck_mode", "upgrade")
	if not upgrade_only:
		_local_button(row, "campaign:mode:remove", "移除一张牌", "campaign:deck_mode", "remove")
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
	reset_page("校园路线 · " + str(view.get("year_title", "")), "✓ 已完成　◆ 当前　○ 可进入　· 不可达 · 连接线对应真实路线")
	_run_bar(header)
	var nodes := _array(view.get("nodes"))
	var reachable := _array(view.get("reachable_node_ids"))
	var selected := str(_choices.get("map:node", ""))
	var canvas := UiRouteCanvas.new()
	canvas.configure(nodes, reachable, str(view.get("current_node_id", "")))
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	var description := "选择可达节点，查看预告后进入。"
	for node in nodes:
		var id := str(node.node_id)
		var current := id == str(view.get("current_node_id", ""))
		var status := "◆" if current else ("✓" if node.status == "completed" else ("○" if reachable.has(id) else "·"))
		var caption := _map_node_title(node)
		if bool(node.get("preview_random", false)):
			caption = "精英战斗 · 随机遭遇" if node.kind == "elite" else "普通战斗 · 随机校园任务"
		var button := _local_button(canvas, "node:" + id, "%s %s\n第%s层" % [status, caption, node.layer], "map:node", id)
		button.set_meta("node_id", id)
		button.size_flags_horizontal = 0
		button.custom_minimum_size = Vector2(176, 64)
		button.size = Vector2(176, 64)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := UiStyle.box(Color("334f53") if current else (Color("e4eddf") if reachable.has(id) else Color("efeee4")))
			style.border_color = UiStyle.GOLD if id == selected or state == "focus" else (UiStyle.GREEN if reachable.has(id) else Color("b8c3b5"))
			style.set_border_width_all(3 if id == selected or current else 1)
			button.add_theme_stylebox_override(state, style)
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color, UiStyle.PAPER if current else UiStyle.INK)
		button.set_meta("current_node", current)
		button.tooltip_text = _node_hint(str(node.kind)) + "\n" + _campaign_node_hint(node)
		if id == selected:
			description = caption + " · " + button.tooltip_text.replace("\n", " ")
	canvas.arrange.call_deferred()
	var scope := "%s|%s|%s|%s" % [view.get("run_id", ""), view.get("term", 0), view.get("current_node_id", ""), view.get("revision", -1)]
	if scope != _map_focus_scope and not reachable.is_empty():
		_focus_map_after_layout.call_deferred(weakref(canvas), str(reachable[0]), _render_generation, scope)
	var row := _bottom(description)
	var enter := add_button(row, "map:enter", "进入此节点", _action("enter_node", {"node_id": selected}))
	enter.disabled = not reachable.has(selected)
	add_button(row, "map:current", "回到当前位置", {}, func(): _focus_map(canvas, str(view.get("current_node_id", "")) if not str(view.get("current_node_id", "")).is_empty() else str(reachable[0]) if not reachable.is_empty() else ""))
	add_button(row, "map:abandon", "放弃本局", {}, func(): _confirm_abandon = not _confirm_abandon; refresh_local())
	if _confirm_abandon:
		add_button(row, "map:abandon_confirm", "确认放弃本局", _action("abandon_run", {"confirmed": true}))


func _focus_map(canvas: UiRouteCanvas, id: String) -> void:
	if is_instance_valid(canvas) and canvas.positions.has(id):
		var center: Vector2 = canvas.global_position + canvas.positions[id]
		_scroll.scroll_vertical = maxi(0, roundi(_scroll.scroll_vertical + center.y - _scroll.get_global_rect().get_center().y))
		_scroll_position.y = _scroll.scroll_vertical


func _focus_map_after_layout(canvas_ref: WeakRef, id: String, generation: int, scope: String, frames_left: int = 4) -> void:
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
		var grid := _grid(body)
		for stock in _array(shop.get("stocks")):
			var id := str(stock.stock_id)
			var panel := add_panel(grid)
			var kind := str(stock.kind)
			var status := "已售罄" if stock.get("sold", false) else ("金钱不足" if int(stock.price) > int(view.get("money", 0)) else "可购买")
			add_text(panel, "%s 金钱 · %s" % [stock.price, status], 17, UiStyle.RED if status != "可购买" else UiStyle.INK)
			if kind == "meal":
				add_art(panel, "campus_meal", Vector2(184, 144))
				_local_button(panel, "shop:pick:" + id, "校园餐食\n实际回复 %s 精力" % stock.get("detail", {}).get("heal_amount", 0), "shop:stock", id)
			else:
				add_card(panel, "shop:pick:" + id, str(stock.definition_id), _dict(stock.get("detail")), UiStyle.label(str(stock.definition_id)), selected == id, func(): _choose("shop:stock", id), kind == "relic")
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
	_scope(str(event.get("event_instance_id", "")))
	reset_page(UiStyle.label(str(event.get("definition_id", ""))), "先查看所有行动；预选后再选择所需目标")
	_run_bar(header)
	var selected := str(_choices.get("event:option", ""))
	for option in _array(event.get("options")):
		var panel := _choice_panel(body, selected == str(option.option_id))
		add_text(panel, _event_option_name(str(option.option_id), str(option.get("label_key", ""))), 20)
		add_text(panel, "消耗：" + _cost_text(_dict(option.get("cost"))) + "\n" + UiStyle.describe_effects(_array(option.get("effects"))), 16)
		var pick := _local_button(panel, "event:option:leave" if option.option_id == "leave" else "event:" + str(option.option_id), "预选此项" if option.get("enabled", true) else "不可用", "event:option", str(option.option_id))
		pick.disabled = not option.get("enabled", true)
		if pick.disabled:
			add_text(panel, "资源不足、没有合法目标或此事件已完成。", 15, UiStyle.RED)
	if selected.is_empty():
		_bottom("请选择一项行动。查看目标后仍可返回。")
		return
	for option in _array(event.get("options")):
		if str(option.option_id) != selected:
			continue
		add_text(header, _event_option_name(selected, str(option.get("label_key", ""))), 18)
		var effects := _array(option.get("effects"))
		for index in effects.size():
			var effect: Dictionary = effects[index]
			var op := str(effect.get("op", ""))
			var key := "%s:%s" % [selected, index]
			if op in ["upgrade_card", "remove_card"]:
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


func _render_rest() -> void:
	var rest := _dict(view.get("rest"))
	_scope(str(view.get("current_node_id", "")))
	reset_page("休整时光", "选择行动后查看结果，确认一次完成")
	_run_bar(header)
	var selected := str(_choices.get("rest:option", ""))
	var options := add_row(body)
	for option in _array(rest.get("options")):
		var pick := _local_button(options, "rest:option:" + str(option.option_id), _rest_name(str(option.option_id)), "rest:option", str(option.option_id))
		pick.disabled = not option.get("enabled", true)
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
			add_art(body, "BG_dorm", Vector2(360, 180))
			add_text(body, summary, 24)
		action = _action("take_rest", payload)
	var row := _bottom(summary)
	if not action.is_empty():
		add_button(row, "rest:confirm", "确认休整", action)
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
	var tabs := add_row(header)
	for character in characters:
		var id := str(character.id)
		var button := add_button(tabs, "setup:character:" + id, ("✓ " if _character == id else "") + UiStyle.label(id).split("·")[0], {}, func(): _select_setup("character", id))
		button.disabled = bool(character.get("locked", false))
		button.tooltip_text = str(character.get("reason", ""))
	for character in characters:
		if str(character.id) != _character:
			continue
		var row := add_row(body)
		var portrait := add_art(row, _character, Vector2(190, 210))
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		add_text(info, UiStyle.label(_character), 24)
		add_text(info, UiContentText.describe_character_passive(str(character.get("passive_id", ""))), 17)
		add_text(info, "开局无饰品 · 12张起始牌 · 沿四张学年地图前进", 16)
		add_button(info, "setup:deck", "查看起始牌组", {}, func(): _setup_deck(character))
	if _seed_revision != int(view.get("seed_revision", 0)):
		_seed = str(view.get("default_seed", ""))
		_seed_revision = int(view.get("seed_revision", 0))
	add_button(body, "setup:advanced", "收起种子设置" if _advanced else "高级设置 · 种子", {}, func(): _advanced = not _advanced; refresh_local())
	if _advanced:
		var seed_row := add_row(body)
		var seed_input := LineEdit.new()
		seed_input.text = _seed
		seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seed_input.custom_minimum_size.y = 44
		seed_input.text_changed.connect(func(value): _seed = value)
		seed_row.add_child(seed_input)
		add_button(seed_row, "setup:seed_random", "随机种子", _ui("random_seed"))
	var difficulty_row := add_row(footer)
	for difficulty in difficulties:
		var id := _option_id(difficulty)
		add_button(difficulty_row, "setup:difficulty:" + id, ("✓ " if _difficulty == id else "") + _difficulty_name(id), {}, func(): _select_setup("difficulty", id))
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
	var sizes := add_row(panel)
	for value in [100, 125, 150]:
		add_button(sizes, "settings:text:" + str(value), ("✓ " if _presentation.text_scale == value else "") + "%d%%" % value, {}, func(): _presentation.text_scale = value; refresh_local())
	var motion := add_row(panel)
	for value in [false, true]:
		add_button(motion, "settings:motion:" + str(value), "减少动态" if value else "标准动态", {}, func(): _presentation.reduced_motion = value; refresh_local())
	var speed := add_row(panel)
	for value in [0, 1, 2, 4]:
		add_button(speed, "settings:speed:" + str(value), "动画关闭" if value == 0 else "动画 ×%d" % value, {}, func(): _presentation.animation_speed = value; refresh_local())
	_drafts["settings:apply"] = func(): return _ui("save_settings", {"autosave": _autosave, "audio": _audio_settings.duplicate(true), "presentation": _presentation.duplicate(true)})


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


func _open_inspector(kind: String) -> void:
	close_card_preview()
	super._open_inspector(kind)
	if kind != "deck":
		return
	var grid: GridContainer = _inspector.find_children("*", "GridContainer", true, false)[0]
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = 3 if size.x >= 750 else 2
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
	close_card_preview()
	super._close_inspector()
	for uid in _buttons.keys():
		if str(uid).begins_with("inspect:card:") or str(uid).begins_with("inspect:sort:"):
			_buttons.erase(uid)


func _help() -> void:
	_open_inspector("help")
	# Inspector supplies focus isolation and the fixed close action.
	var grid: GridContainer = _inspector.find_children("*", "GridContainer", true, false)[0]
	var labels := _inspector.find_children("*", "Label", true, false)
	labels[0].text = "规则帮助"
	labels[1].text = "先了解胜负与资源，再按需查阅卡牌。"
	for child in grid.get_children():
		child.queue_free()
	grid.columns = 1
	add_text(grid, "完成全部任务才能获胜；阶段完成后可能出现下一阶段。\n精力降为0或DDL到期且仍有任务时失败。\n专注用于支付卡牌费用；放松抵挡压力。\nDDL是剩余完整轮末次数，按规则书的轮末时序结算。\n连携：前牌策略→本牌工作。\n效果内强制待选必须完成；此时不能保存半条效果。\n悬停/聚焦看说明，I固定详情，Esc关闭详情或取消本地预选。", 18)


func _input(event: InputEvent) -> void:
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
