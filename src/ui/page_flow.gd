class_name UiFlowPage
extends UiPage

var screen: String = "menu"
var _choices: Dictionary = {}
var _selection_scope: String = ""
var _character: String = ""
var _difficulty: String = ""
var _manifest: String = ""
var _seed: String = ""
var _seed_revision := -1
var _autosave: bool = true
var _settings_loaded: bool = false
var _audio_settings: Dictionary = {}
var _confirm_abandon: bool = false
var _inspector: Control
var _inspect_return_focus: Control
var _inspector_focus_modes: Dictionary = {}


func render(data: Dictionary) -> void:
	_close_inspector()
	view = data.duplicate(true)
	match screen:
		"menu":
			_render_menu()
		"setup":
			_render_setup()
		"map":
			_render_map()
		"reward":
			_render_reward()
		"campaign":
			_render_campaign()
		"shop":
			_render_shop()
		"event":
			_render_event()
		"rest":
			_render_rest()
		"summary":
			_render_summary()
		"settings":
			_render_settings()
		"battle", "battle_entry":
			_render_battle_entry()
		_:
			reset_page("校园生活", "请从主菜单继续当前冒险。")
			add_button(body, "page:menu", "返回主菜单", _ui("menu"))


func _render_menu() -> void:
	reset_page("DDL 战争", "把校园日常，打成自己的牌。")
	add_art(body, "BG_home", Vector2(760, 250))
	add_text(body, "四学年 · 校园卡牌冒险", 24)
	add_text(body, "选择角色，规划四年路线，在作业与休息之间迎接学年挑战。")
	var row: HBoxContainer = add_row(body)
	add_button(row, "menu:new", "开始新一局", _ui("new_run"))
	var resume: Button = add_button(row, "menu:continue", "继续冒险", _ui("continue"))
	resume.disabled = (
		not bool(view.get("has_active_session", false))
		and not bool(view.get("can_continue", false))
	)
	if resume.disabled:
		resume.add_theme_color_override("font_disabled_color", Color("8b938d"))
		var disabled_style := UiStyle.box(Color("dedfd7"))
		resume.add_theme_stylebox_override("disabled", disabled_style)
		resume.tooltip_text = str(view.get("save_error", ""))
		if resume.tooltip_text.is_empty():
			resume.tooltip_text = "还没有可以继续的冒险。"
	add_button(row, "menu:settings", "设置与存档", _ui("settings"))
	if bool(view.get("has_active_session", false)):
		add_text(body, "当前冒险已保留，可以随时继续。", 16)
	if view.get("save_error") != null and not str(view.get("save_error", "")).is_empty():
		add_text(body, "存档暂时不可用：" + str(view.save_error), 16)
		add_text(body, "可在设置中检查备份，或开始新一局；重开会先保留旧存档原件。", 16)
	var profile: Dictionary = _dict(view.get("profile"))
	if not profile.is_empty():
		add_text(
			body,
			(
				"已解锁角色 %d · 已完成冒险 %d"
				% [
					_array(profile.get("unlocked_characters")).size(),
					_array(profile.get("completed_run_ids")).size()
				]
			),
			16
		)


func _render_setup() -> void:
	reset_page("开启校园冒险", "选好角色和难度，再出发。")
	var characters: Array = _array(view.get("characters"))
	var manifests: Array = _array(view.get("manifests"))
	if not manifests.is_empty():
		_manifest = _option_id(manifests[0])
	if _character.is_empty():
		_character = str(view.get("default_character_id", ""))
	if _character.is_empty():
		for entry in characters:
			if not bool(entry.get("locked", false)):
				_character = str(entry.get("id", ""))
				break
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	body.add_child(grid)
	for entry in characters:
		var id: String = str(entry.get("id", ""))
		var panel: VBoxContainer = add_panel(grid)
		add_art(panel, id, Vector2(220, 180))
		add_text(panel, UiStyle.label(id), 22)
		var passive := UiContentText.describe_character_passive(str(entry.get("passive_id", "")))
		if not passive.is_empty():
			add_text(panel, passive, 16)
		var relic_id: String = str(entry.get("starter_relic_id", ""))
		if _manifest == "campus_four_year":
			add_text(panel, "四学年模式：沿途领取饰品，开局无饰品。", 16)
		elif not relic_id.is_empty():
			add_text(panel, "初始饰品：" + UiStyle.label(relic_id), 16)
		var starter_names: Array[String] = []
		for card in _array(entry.get("starter_cards")):
			starter_names.append(UiStyle.label(_candidate_id(card)))
		if not starter_names.is_empty():
			add_text(panel, "起始牌组：" + "、".join(starter_names), 15)
		var button: Button = add_button(
			panel,
			"setup:character:" + id,
			("已选择 · " if id == _character else "选择 · ") + UiStyle.label(id),
			{},
			func() -> void: _select_setup("character", id)
		)
		button.disabled = bool(entry.get("locked", false))
		if button.disabled:
			button.tooltip_text = str(entry.get("reason", "尚未解锁"))
	add_text(body, "难度", 22)
	var difficulties: Array = _array(view.get("difficulties"))
	if _difficulty.is_empty():
		_difficulty = str(view.get("default_difficulty", ""))
	if _difficulty.is_empty() and not difficulties.is_empty():
		_difficulty = _option_id(difficulties[0])
	var difficulty_row: HBoxContainer = add_row(body)
	for difficulty in difficulties:
		var id: String = _option_id(difficulty)
		add_button(
			difficulty_row,
			"setup:difficulty:" + id,
			("● " if id == _difficulty else "○ ") + _difficulty_name(id),
			{},
			func() -> void: _select_setup("difficulty", id)
		)
	if _seed_revision != int(view.get("seed_revision", 0)):
		_seed = str(view.get("default_seed", ""))
		_seed_revision = int(view.get("seed_revision", 0))
	add_text(body, "本局种子", 22)
	var seed_row: HBoxContainer = add_row(body)
	var seed_input := LineEdit.new()
	seed_input.text = _seed
	seed_input.placeholder_text = "输入十进制整数"
	seed_input.custom_minimum_size = Vector2(280, 44)
	seed_input.text_changed.connect(func(value: String) -> void: _seed = value)
	seed_row.add_child(seed_input)
	add_button(seed_row, "setup:seed_random", "随机种子", _ui("random_seed"))
	add_text(body, "相同种子可重现同一局；种子和难度将在开局后锁定。", 15)
	var confirming := bool(view.get("confirm_restart", false))
	if bool(view.get("replaces_run", false)):
		add_text(body, "开始新一局会结束原来的局并替换当前存档；返回可继续原来的局。", 18)
	if bool(view.get("unreadable_save", false)):
		add_text(body, "旧存档无法继续。确认后会先保留旧文件及备份原件，再开始新一局。", 18)
	if confirming:
		add_text(body, "确定结束原来的局，并按以上配置重新开始冒险吗？", 21)
	var footer: HBoxContainer = add_row(body)
	add_button(
		footer,
		"setup:restart_confirm" if confirming else "setup:start",
		"结束旧局并开始" if confirming else "进入校园",
		func() -> Dictionary:
			return _ui(
				"start_run",
				{
					"character_id": _character,
					"difficulty": _difficulty,
					"manifest_id": _manifest,
					"seed": _seed,
					"confirmed": confirming
				}
			)
	)
	if confirming:
		add_button(footer, "setup:restart_cancel", "取消重开", _ui("cancel_restart"))
	add_button(footer, "setup:back", "返回", _ui("menu"))


func _render_map() -> void:
	reset_page("校园路线", "沿着箭头选择下一站，完成本学年的挑战。" if view.has("campaign") else "沿着箭头选择下一站，准备迎接期末。")
	_run_bar(body)
	if view.has("campaign"):
		add_text(body, "大%s · %s｜本图 %s 层，完成第 %s 层后领取饰品" % [["一", "二", "三", "四"][int(view.term)-1], view.get("year_title", ""), view.get("year_layers", 0), "、".join(CampaignMap.MAPS[int(view.term)-1].relic_layers.map(func(value): return str(value)))], 20)
		var c: Dictionary = view.campaign
		add_text(body, "探索 %s/6　方向 %s　履历 %s/6　毕设 %s/5　去向 %s" % [c.exploration, _campaign_label(c.direction), c.resume, c.thesis, _campaign_label(c.destination)], 18)
		add_text(body, "每图末层为学年 Boss；领奖后进入下一学年。实验室与竞赛路线请留意后继和费用。", 17)
	var reachable: Array = _array(view.get("reachable_node_ids"))
	var nodes: Array = _array(view.get("nodes"))
	var completed := 0
	for node in nodes:
		if str(node.get("status", "")) == "completed":
			completed += 1
	add_text(body, "已完成 %s 站 · 下一站由你选择" % completed, 21)
	var next_row := add_row(body)
	for node in nodes:
		var id := str(node.get("node_id", ""))
		if not reachable.has(id):
			continue
		var panel := add_panel(next_row)
		add_text(
			panel, "第 %s 层 · %s" % [node.get("layer", 0), _map_node_title(node)], 22
		)
		add_text(panel, _node_hint(str(node.get("kind", ""))), 17)
		if node.has("subtype"):
			add_text(panel, _campaign_node_hint(node), 17)
		add_button(
			panel,
			"node:" + id,
			"进入 · " + _map_node_title(node),
			_action("enter_node", {"node_id": id})
		)
	if reachable.is_empty():
		add_text(body, "当前站尚未完成，请继续处理当前任务。", 17)
	add_text(body, "完整路线", 22)
	var layers: Dictionary = {}
	for node in nodes:
		var layer: int = int(node.get("layer", 0))
		if not layers.has(layer):
			layers[layer] = []
		layers[layer].append(node)
	var ordered: Array = layers.keys()
	ordered.sort()
	for layer in ordered:
		var row: HBoxContainer = add_row(body)
		var layer_label := add_text(row, "第 %s 层" % layer, 18)
		layer_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		layer_label.custom_minimum_size.x = 68
		for node in layers[layer]:
			var id: String = str(node.get("node_id", ""))
			var panel: VBoxContainer = add_panel(row)
			var status: String = "不可达"
			if str(node.get("status", "")) == "completed":
				status = "已完成"
			elif id == str(view.get("current_node_id", "")):
				status = "当前"
			elif reachable.has(id):
				status = "可进入"
			if reachable.has(id):
				add_text(panel, _map_node_title(node) + " · " + status, 18)
			else:
				add_button(
					panel,
					"node:" + id,
					_map_node_title(node) + " · " + status,
					_action("enter_node", {"node_id": id})
				)
			var next_names: Array[String] = []
			for next_id in _array(node.get("next_ids")):
				for destination in nodes:
					if str(destination.get("node_id", "")) == str(next_id):
						next_names.append(
							(
								"第%s层 %s"
								% [
									destination.get("layer", ""),
								_map_node_title(destination)
								]
							)
						)
			if not next_names.is_empty():
				add_text(panel, "→ " + " / ".join(next_names), 14)
	var footer: HBoxContainer = add_row(body)
	add_button(footer, "map:save", "保存进度", _ui("save"))
	add_button(footer, "map:menu", "主菜单", _ui("menu"))
	add_button(
		footer,
		"map:abandon",
		"放弃本局",
		{},
		func() -> void:
			_confirm_abandon = not _confirm_abandon
			refresh_local()
	)
	if _confirm_abandon:
		add_text(body, "确定放弃本局？此操作会结束当前冒险。", 18)
		add_button(body, "map:abandon_confirm", "确认放弃", _action("abandon_run", {"confirmed": true}))
	_deck_summary(body)


func _render_reward() -> void:
	var offer: Dictionary = _dict(view.get("pending_reward"))
	_scope(str(offer.get("offer_id", "")))
	reset_page("收获时刻", "从本次奖励中选择适合你的卡牌与饰品。")
	_run_bar(body)
	var meta: Dictionary = _dict(offer.get("meta"))
	if int(meta.get("money", 0)) > 0:
		add_text(body, "本次已获得金钱：%s" % meta.money, 20)
	for item in _array(offer.get("items")):
		var item_id: String = str(item.get("item_id", ""))
		var kind: String = str(item.get("kind", "card"))
		var panel: VBoxContainer = add_panel(body)
		add_text(panel, "卡牌奖励" if kind == "card" else "饰品奖励", 23)
		if str(item.get("status", "pending")) != "pending":
			add_text(panel, "已跳过" if str(item.get("status")) == "skipped" else "已领取", 18)
			continue
		var row: HBoxContainer = add_row(panel)
		var candidates: Array = _array(item.get("candidates"))
		var details: Dictionary = _dict(item.get("candidate_details"))
		for candidate in candidates:
			var id: String = _candidate_id(candidate)
			var choice: VBoxContainer = add_panel(row)
			add_art(choice, id, Vector2(192, 144) if kind == "card" else Vector2(120, 110))
			add_text(choice, UiStyle.label(id), 20)
			var detail: Dictionary = _dict(details.get(id))
			var description := (
				UiContentText.describe_card(detail)
				if kind == "card"
				else UiContentText.describe_relic(detail)
			)
			add_text(choice, description, 17)
			add_button(
				choice,
				"reward:%s:pick:%s" % [item_id, id],
				("● " if str(_choices.get(item_id, "")) == id else "选择 ") + UiStyle.label(id),
				{},
				func() -> void: _choose(item_id, id)
			)
		if kind == "relic" and _relics_full():
			_replacement_picker(panel, "reward:" + item_id, item_id + ":replace")
		var buttons: HBoxContainer = add_row(panel)
		add_button(
			buttons,
			"reward:%s:claim" % item_id,
			"领取奖励",
			func() -> Dictionary:
				var payload: Dictionary = {
					"offer_id": str(offer.get("offer_id", "")), "item_id": item_id
				}
				var selected: String = str(_choices.get(item_id, ""))
				if not selected.is_empty():
					payload.candidate_id = selected
				var replacement: String = str(_choices.get(item_id + ":replace", ""))
				if not replacement.is_empty():
					payload.replace_relic_id = replacement
				return _action("claim_reward", payload)
		)
		if bool(item.get("skippable", true)):
			add_button(
				buttons,
				"reward:%s:skip" % item_id,
				"跳过此项",
				_action(
					"skip_reward", {"offer_id": str(offer.get("offer_id", "")), "item_id": item_id}
				)
			)
	add_text(body, "处理完全部奖励后返回地图，点击下一站进入。", 16)
	_flow_navigation("reward")


func _render_campaign() -> void:
	var offer: Dictionary = _dict(view.get("campaign_offer"))
	_scope(str(offer.get("offer_id", "")))
	var kind := str(offer.get("kind", ""))
	reset_page(str({"relic": "学年纪念饰品", "grand": "学年大奖励", "service": "校园服务", "direction": "选择学习方向", "destination": "选择毕业去向", "familiar": "校园熟人"}.get(kind, "学年选择")), "选择完成后继续当前路线；奖励候选已固定，存档不会重新抽取。")
	_run_bar(body)
	if kind in ["direction", "destination"]:
		for id in (CampaignService.DIRECTIONS if kind == "direction" else CampaignService.DESTINATIONS):
			add_button(body, "campaign:" + id, _campaign_label(id), _campaign_action(offer, id))
		return
	if kind in ["relic", "grand"]:
		if kind == "relic":
			add_text(body, "三选一｜重复自动折算25金钱｜满3槽可替换或折算30金钱｜跳过20金钱", 18)
			if _relics_full():
				_replacement_picker(body, "campaign", "campaign:replace")
		else:
			add_text(body, "以下奖励互斥，只能选一项：高阶卡牌 / 升级或移除 / 60金钱与20%精力。", 18)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 14)
		body.add_child(grid)
		for id in _array(offer.get("candidates")):
			var panel := add_panel(grid)
			var detail: Dictionary = _dict(offer.get("details", {}).get(id))
			add_art(panel, str(id), Vector2(192, 144))
			add_text(panel, UiStyle.label(str(id)), 23)
			add_text(panel, UiContentText.describe_relic(detail) if kind == "relic" else UiContentText.describe_card(detail), 18)
			var row := add_row(panel)
			add_button(row, "campaign:claim:" + str(id), "领取" + ("（替换所选饰品）" if kind == "relic" and _relics_full() else ""), func() -> Dictionary:
				var action := _campaign_action(offer, "claim" if kind == "relic" else "card", str(id))
				if kind == "relic" and _choices.has("campaign:replace"):
					action.payload.replace_relic_id = _choices["campaign:replace"]
				return action)
			if kind == "relic" and _relics_full():
				add_button(row, "campaign:convert:" + str(id), "折算金钱", _campaign_action(offer, "convert", str(id)))
	if kind == "grand":
		_campaign_card_choices(offer, false)
		var extra := 20 if (int(view.term) == 1 and int(view.campaign.exploration) >= 6) or (int(view.term) == 4 and int(view.campaign.thesis) >= 4) else 0
		add_button(body, "campaign:resources", "%d金钱，回复%d精力（上限%d）" % [60 + extra, int(floor(int(view.max_vitality) * 0.2)), int(view.max_vitality)], _campaign_action(offer, "resources"))
	elif kind == "service":
		var meta: Dictionary = offer.get("node_meta", {})
		var sub := str(meta.get("subtype", ""))
		add_text(body, str(meta.get("title", "")), 23)
		if sub in ["L", "LAB", "T"]:
			add_text(body, "一次服务费用：%d金钱%s" % [int(offer.service_cost), "与5精力（至少保留1）" if sub == "LAB" else ""], 18)
			_campaign_card_choices(offer, sub == "LAB")
		elif sub == "C":
			add_button(body, "campaign:heal", "回复8精力", _campaign_action(offer, "heal"))
			add_button(body, "campaign:money", "社团活动：15金钱 + 饰品/方向加成", _campaign_action(offer, "money"))
		elif sub == "I":
			add_button(body, "campaign:money", "实习招聘：25金钱 + 饰品/方向加成", _campaign_action(offer, "money"))
		else:
			add_button(body, "campaign:progress", "完成阶段事项，回复4精力", _campaign_action(offer, "progress"))
		if int(view.term) == 2 and int(meta.get("layer", 0)) >= 7 and not bool(view.campaign.direction_changed):
			add_text(body, "可花30金钱更换一次方向（本次服务改为转向）：", 18)
			for id in CampaignService.DIRECTIONS:
				add_button(body, "campaign:direction:" + id, "改为" + _campaign_label(id), _campaign_action(offer, "direction_" + id))
	elif kind == "familiar":
		add_button(body, "campaign:familiar", "向校园熟人咨询，获得10金钱", _campaign_action(offer, "money"))
	add_button(body, "campaign:skip", "放弃（%s金钱）" % ("20" if kind == "relic" else ("30" if kind == "grand" else "0")), _campaign_action(offer, "skip"))
	var navigation := add_row(body)
	add_button(navigation, "campaign:save", "保存进度", _ui("save"))
	add_button(navigation, "campaign:menu", "主菜单", _ui("menu"))


func _campaign_card_choices(offer: Dictionary, upgrade_only: bool) -> void:
	for card in _array(view.get("cards")):
		var row := add_row(body)
		var art := add_art(row, str(card.get("definition_id", "")), Vector2(112, 84))
		art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_text(row, _card_name(card), 18)
		if card.get("upgrade_detail") is Dictionary:
			var upgrade := add_button(row, "campaign:upgrade:" + str(card.card_id), "升级", _campaign_action(offer, "upgrade", str(card.card_id)))
			upgrade.tooltip_text = UiContentText.describe_card(card.upgrade_detail)
		if not upgrade_only:
			add_button(row, "campaign:remove:" + str(card.card_id), "移除", _campaign_action(offer, "remove", str(card.card_id)))


func _campaign_action(offer: Dictionary, option: String, candidate: String = "") -> Dictionary:
	return _action("choose_campaign", {"offer_id": str(offer.get("offer_id", "")), "option_id": option, "candidate_id": candidate})


func _campaign_label(id: String) -> String:
	return str({"": "未选择", "theory": "理论：图书馆费用-10", "engineering": "工程：实验室费用-10", "competition": "竞赛：精英胜利额外10金钱", "practice": "实践：社团/实习额外10金钱", "job": "就业", "exam": "考研", "research": "保研", "abroad": "出国"}.get(id, id))


func _map_node_title(node: Dictionary) -> String:
	return str(node.get("title", _node_name(str(node.get("kind", "")))))


func _campaign_node_hint(node: Dictionary) -> String:
	var sub := str(node.get("subtype", ""))
	return str({"N": "普通战斗 · 标准风险", "EL": "精英战斗 · 高风险 · 稀有奖励", "K": "竞赛精英 · 高风险 · 履历来源", "B": "学年终点 · 胜利后大奖励", "S": "购买/删牌/餐食", "R": "安全 · 回复/升级", "E": "校园事件 · 互斥选项", "L": "图书馆 · 20金钱升级或移除（可减免）", "LAB": "实验室 · 15金钱与5精力升级；注意限定后继", "T": "导师 · 10金钱升级或移除（可减免）", "C": "社团 · 回复8精力或15金钱", "I": "实习招聘 · 25金钱与履历", "ST": "剧情事项 · 毕设进度与4精力"}.get(sub, ""))


func _render_shop() -> void:
	var shop: Dictionary = _dict(view.get("shop"))
	_scope(str(shop.get("shop_id", "")))
	reset_page("校园商店", "买点补给，让下一段路走得更从容。")
	_run_bar(body)
	add_button(body, "shop:leave", "离开商店，返回地图", _leave())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for stock in _array(shop.get("stocks")):
		var stock_id: String = str(stock.get("stock_id", ""))
		var definition_id: String = str(stock.get("definition_id", ""))
		var kind: String = str(stock.get("kind", ""))
		var panel: VBoxContainer = add_panel(grid)
		if kind != "meal":
			add_art(panel, definition_id, Vector2(176, 132) if kind == "card" else Vector2(110, 135))
		add_text(panel, "校园餐食" if kind == "meal" else UiStyle.label(definition_id), 20)
		var detail := _dict(stock.get("detail"))
		if kind == "meal":
			add_text(
				panel,
				(
					"恢复 %s 精力（最多 %s）"
					% [detail.get("heal_amount", "—"), detail.get("base_heal_amount", "—")]
				),
				17
			)
		else:
			add_text(
				panel,
				(
					UiContentText.describe_card(detail)
					if kind == "card"
					else UiContentText.describe_relic(detail)
				),
				17
			)
		add_text(
			panel,
			"金钱 %s%s" % [stock.get("price", 0), " · 已售出" if stock.get("sold", false) else ""],
			17
		)
		if kind == "relic" and _relics_full():
			_replacement_picker(panel, "shop:" + stock_id, stock_id + ":replace")
		add_button(
			panel,
			"shop:buy:" + stock_id,
			"购买",
			func() -> Dictionary:
				var payload: Dictionary = {
					"shop_id": str(shop.get("shop_id", "")), "stock_id": stock_id
				}
				var replacement: String = str(_choices.get(stock_id + ":replace", ""))
				if not replacement.is_empty():
					payload.replace_relic_id = replacement
				return _action("buy_item", payload)
		)
	var removal: Dictionary = _dict(shop.get("removal"))
	var removal_panel: VBoxContainer = add_panel(body)
	add_text(removal_panel, "精简牌组", 23)
	add_text(
		removal_panel,
		(
			"费用 %s 金钱 · 本店已用 %s/%s 次 · 至少保留 %s 张牌"
			% [
				removal.get("price", 0),
				removal.get("used", 0),
				removal.get("max", 1),
				removal.get("minimum_deck_size", 0)
			]
		),
		16
	)
	for card in _array(view.get("cards")):
		var card_id: String = str(card.get("card_id", ""))
		var card_panel := add_panel(removal_panel)
		_card_comparison(card_panel, card, false)
		add_button(
			card_panel,
			"shop:remove:" + card_id,
			"移除 " + _card_name(card),
			_action(
				"remove_card",
				{"shop_id": str(shop.get("shop_id", "")), "card_instance_id": card_id}
			)
		)
	_flow_navigation("shop")


func _render_event() -> void:
	var event: Dictionary = _dict(view.get("event"))
	_scope(str(event.get("event_instance_id", "")))
	reset_page(UiStyle.label(str(event.get("definition_id", ""))), "校园里的小插曲，也会改变这次冒险。")
	_run_bar(body)
	for option in _array(event.get("options")):
		var option_id: String = str(option.get("option_id", ""))
		var panel: VBoxContainer = add_panel(body)
		add_text(panel, _event_option_name(option_id, str(option.get("label_key", ""))), 23)
		add_text(panel, "消耗：" + _cost_text(_dict(option.get("cost"))), 16)
		var effects: Array = _array(option.get("effects"))
		var description: String = UiStyle.describe_effects(effects)
		if not description.is_empty():
			add_text(panel, description, 18)
		var frozen: Dictionary = _dict(option.get("candidates"))
		for index in range(effects.size()):
			var effect: Dictionary = effects[index]
			var op: String = str(effect.get("op", ""))
			var key: String = "%s:%s" % [option_id, index]
			if op in ["upgrade_card", "remove_card"]:
				add_text(panel, "选择一张牌：", 16)
				for card in _array(view.get("cards")):
					var card_id: String = str(card.get("card_id", ""))
					var card_panel := add_panel(panel)
					_card_comparison(card_panel, card, op == "upgrade_card")
					add_button(
						card_panel,
						"event:%s:card:%s" % [option_id, card_id],
						(
							("● " if str(_choices.get(key, "")) == card_id else "○ ")
							+ _card_name(card)
						),
						{},
						func() -> void: _choose(key, card_id)
					)
			elif op == "gain_card" or op == "gain_relic":
				var candidates: Array = _array(frozen.get(str(index)))
				var candidate_row: HBoxContainer = add_row(panel)
				for candidate in candidates:
					var id: String = _candidate_id(candidate)
					var candidate_panel: VBoxContainer = add_panel(candidate_row)
					add_art(candidate_panel, id, Vector2(160, 120) if op == "gain_card" else Vector2(100, 125))
					if op == "gain_card" and not effect.has("card_id") and candidates.size() > 1:
						add_button(
							candidate_panel,
							"event:%s:pick:%s" % [option_id, id],
							(
								("● " if str(_choices.get(key, "")) == id else "○ ")
								+ UiStyle.label(id)
							),
							{},
							func() -> void: _choose(key, id)
						)
					else:
						add_text(candidate_panel, UiStyle.label(id), 17)
				if op == "gain_relic" and _relics_full():
					_replacement_picker(panel, "event:" + option_id, option_id + ":replace")
		add_button(
			panel,
			"event:option:leave" if option_id == "leave" else "event:" + option_id,
			"选择此项",
			func() -> Dictionary: return _event_action(event, option)
		)
	if not str(event.get("resolved_option_id", "")).is_empty():
		add_text(body, "本次事件已处理。", 18)
	add_text(body, "完成事件选择后返回地图，点击下一站进入。", 16)
	_flow_navigation("event")


func _render_rest() -> void:
	var rest: Dictionary = _dict(view.get("rest"))
	_scope(str(view.get("current_node_id", "")))
	reset_page("休整时光", "停一停，选一种方式为接下来的挑战做准备。")
	_run_bar(body)
	var options := _array(rest.get("options"))
	var selected := str(_choices.get("rest:option", "heal"))
	var option_row := add_row(body)
	for option in options:
		var id := str(option.get("option_id", ""))
		add_button(
			option_row,
			"rest:option:" + id,
			("● " if selected == id else "○ ") + _rest_name(id),
			{},
			func() -> void: _choose("rest:option", id)
		)
	for option in _array(rest.get("options")):
		var option_id: String = str(option.get("option_id", ""))
		var panel: VBoxContainer = add_panel(body)
		(panel.get_parent() as Control).visible = option_id == selected
		add_text(panel, _rest_name(option_id), 22)
		if bool(option.get("needs_card", false)):
			var grid := GridContainer.new()
			grid.columns = 2 if size.x >= 700 else 1
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 14)
			panel.add_child(grid)
			for card in _array(view.get("cards")):
				var card_id: String = str(card.get("card_id", ""))
				var card_panel := add_panel(grid)
				_card_comparison(card_panel, card, option_id in ["upgrade", "train"])
				add_button(
					card_panel,
					"rest:take:%s:%s" % [option_id, card_id],
					_card_name(card),
					_action(
						"take_rest",
						{
							"node_id": str(view.get("current_node_id", "")),
							"option_id": option_id,
							"card_instance_id": card_id
						}
					)
				)
		else:
			add_text(
				panel,
				(
					"恢复 %s 精力（最多 %s）"
					% [
						rest.get("effective_heal_amount", rest.get("heal_amount", 0)),
						rest.get("heal_amount", 0)
					]
				),
				18
			)
			add_button(
				panel,
				"rest:take:" + option_id,
				"好好休息",
				_action(
					"take_rest",
					{"node_id": str(view.get("current_node_id", "")), "option_id": option_id}
				)
			)
	if bool(rest.get("used", false)):
		add_text(body, "休整完成，可以继续前进。", 18)
	add_text(body, "完成休整后返回地图，点击下一站进入。", 16)
	_flow_navigation("rest")


func _flow_navigation(prefix: String) -> void:
	var row := add_row(body)
	add_button(row, prefix + ":save", "保存进度", _ui("save"))
	add_button(row, prefix + ":menu", "主菜单", _ui("menu"))


func _render_battle_entry() -> void:
	var node: Dictionary = _dict(view.get("node"))
	reset_page(_node_name(str(node.get("kind", "normal"))), "准备好迎接这次挑战了吗？")
	add_art(body, "BG_classroom", Vector2(760, 240))
	_run_bar(body)
	var battle: Dictionary = _dict(view.get("battle"))
	var encounter_id: String = str(battle.get("encounter_id", node.get("encounter_id", "")))
	if not encounter_id.is_empty():
		add_text(body, UiStyle.label(encounter_id), 23)
	var row: HBoxContainer = add_row(body)
	add_button(row, "battle:start", "开始挑战", _ui("start_battle"))
	add_button(row, "battle:resume", "继续挑战", _ui("resume_battle"))
	add_button(row, "battle:leave", "完成挑战，继续前进", _leave())
	add_button(row, "battle:save", "保存", _ui("save"))
	add_button(row, "battle:menu", "主菜单", _ui("menu"))
	_deck_summary(body)


func _render_summary() -> void:
	var summary: Dictionary = _dict(view.get("terminal_summary"))
	if summary.is_empty():
		summary = _dict(view.get("run_summary"))
	var result: String = str(summary.get("result", view.get("outcome", "")))
	var won: bool = result == "won"
	reset_page(
		("四年冒险完成" if view.has("campaign") else "第一学期完成") if won else ("本局已放弃" if result == "abandoned" else "本局结束"),
		"校园里的每一次选择，都成为了这段旅程的回忆。" if won else "稍作休息，再尝试一条新的校园路线。"
	)
	add_art(body, "BG_success" if won else "BG_failure", Vector2(760, 280))
	if won:
		add_text(body, "你已完成大一至大四的全部地图。毕业去向：" + _campaign_label(str(view.campaign.destination)) if view.has("campaign") else "你已完成历史版本的第一学期切片。第二学期尚未开放；再开一局会重新开始第一学期。", 20)
	add_text(
		body,
		(
			"%s · %s"
			% [
				UiStyle.label(str(summary.get("character_id", view.get("character_id", "")))),
				_difficulty_name(str(summary.get("difficulty", view.get("difficulty", ""))))
			]
		),
		23
	)
	var stats: Dictionary = _dict(summary.get("statistics", summary.get("stats", {})))
	add_text(
		body,
		"完成节点 %s · 完成战斗 %s" % [stats.get("completed_nodes", 0), stats.get("settled_battles", 0)],
		21
	)
	add_text(
		body,
		(
			"精力 %s · 金钱 %s · 牌组 %s 张"
			% [
				stats.get("vitality", view.get("vitality", 0)),
				stats.get("money", view.get("money", 0)),
				stats.get("deck_size", _array(view.get("cards")).size())
			]
		),
		21
	)
	var unlocked: Array = _array(summary.get("unlocked_ids"))
	var commit: Dictionary = _dict(view.get("profile_commit_status"))
	if not unlocked.is_empty():
		if str(commit.get("profile_merge", "")) == "merged":
			add_text(body, "已永久解锁：" + _labels(unlocked), 18)
		else:
			add_text(body, "本局解锁待保存：" + _labels(unlocked), 18)
	if str(commit.get("profile_merge", "")) in ["failed", "pending"]:
		add_text(body, "本局已保存，长期进度待更新。请返回设置重试保存。", 18)
	elif str(commit.get("profile_cleanup", "")) == "failed":
		add_text(body, "长期进度已更新，收尾保存待重试。", 18)
	var row: HBoxContainer = add_row(body)
	add_button(row, "summary:retry", "再开一局", _ui("retry"))
	add_button(row, "summary:menu", "返回主菜单", _ui("menu"))


func _render_settings() -> void:
	if not _settings_loaded:
		_autosave = bool(_dict(view.get("settings")).get("autosave", true))
		_audio_settings = _dict(view.get("settings")).get("audio", {"Master": 100, "Music": 70, "Ambience": 50, "SFX": 80, "UI": 70, "muted": false}).duplicate(true)
		_settings_loaded = true
	reset_page("设置与存档", "管理自动保存，或显式恢复备份中的进度。")
	var panel: VBoxContainer = add_panel(body)
	add_text(panel, "自动保存", 23)
	add_text(panel, "开启后，在每次完整操作完成后保存进度。关闭后请手动保存。", 17)
	var row: HBoxContainer = add_row(panel)
	for enabled in [true, false]:
		add_button(
			row,
			"settings:autosave:" + str(enabled),
			("● " if _autosave == enabled else "○ ") + ("开启" if enabled else "关闭"),
			{},
			func() -> void:
				_autosave = enabled
				refresh_local()
		)
	add_button(
		panel,
		"settings:apply",
		"应用设置",
		func() -> Dictionary: return _ui("save_settings", {"autosave": _autosave, "audio": _audio_settings.duplicate(true)})
	)
	var audio_panel: VBoxContainer = add_panel(body)
	add_text(audio_panel, "音效", 23)
	add_text(audio_panel, "音量与声音开关可即时试听，点击“应用设置”后保存。音乐与环境声尚未配置正式资源。", 17)
	for bus in ["Master", "Music", "Ambience", "SFX", "UI"]:
		var volume_row := add_row(audio_panel)
		var volume_label := add_text(volume_row, str({"Master": "总音量", "Music": "音乐", "Ambience": "环境", "SFX": "效果", "UI": "界面"}[bus]) + " %d%%" % int(_audio_settings.get(bus, 100)), 18)
		volume_label.custom_minimum_size.x = 170
		var slider := HSlider.new()
		slider.name = "Volume" + bus
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = int(_audio_settings.get(bus, 100))
		slider.custom_minimum_size = Vector2(250, 40)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		volume_row.add_child(slider)
		slider.value_changed.connect(func(value: float) -> void:
			_audio_settings[bus] = int(value)
			if audio != null:
				audio.set_bus_volume(bus, value / 100.0)
			volume_label.text = str({"Master": "总音量", "Music": "音乐", "Ambience": "环境", "SFX": "效果", "UI": "界面"}[bus]) + " %d%%" % int(value))
	var audio_row: HBoxContainer = add_row(audio_panel)
	if audio != null:
		for muted in [false, true]:
			add_button(
				audio_row,
				"settings:audio:" + str(muted),
				("● " if bool(_audio_settings.get("muted", false)) == muted else "○ ") + ("静音" if muted else "开启"),
				{},
				func() -> void:
					_audio_settings.muted = muted
					audio.set_muted(muted)
					refresh_local()
			)
	var saves: VBoxContainer = add_panel(body)
	add_text(saves, "冒险进度", 23)
	add_text(saves, "正式存档：" + _save_description(view.get("save_meta")), 17)
	add_text(saves, "备份存档：" + _save_description(view.get("backup_meta")), 17)
	add_button(saves, "settings:save", "手动保存当前进度", _ui("save"))
	var restore: Button = add_button(
		saves, "settings:restore_backup", "恢复备份", _ui("restore_backup")
	)
	restore.disabled = not bool(view.get("can_restore", view.get("backup_meta") != null))
	if restore.disabled:
		restore.tooltip_text = "暂无可恢复的有效备份。"
	if view.has("seed"):
		add_text(saves, "当前种子：%s（开局后锁定）" % str(view.seed), 16)
	if view.has("difficulty"):
		add_text(saves, "当前难度：%s（开局后锁定）" % _difficulty_name(str(view.difficulty)), 16)
	add_button(body, "settings:back", "返回", _ui("back"))


func _event_action(event: Dictionary, option: Dictionary) -> Dictionary:
	var option_id: String = str(option.get("option_id", ""))
	var selections: Array[String] = []
	var effects: Array = _array(option.get("effects"))
	var frozen: Dictionary = _dict(option.get("candidates"))
	for index in range(effects.size()):
		var effect: Dictionary = effects[index]
		var op: String = str(effect.get("op", ""))
		var needs_selection: bool = op in ["upgrade_card", "remove_card"] and not effect.get("all_eligible", false)
		if op == "gain_card" and not effect.has("card_id"):
			needs_selection = _array(frozen.get(str(index))).size() > 1
		if needs_selection:
			var selected: String = str(_choices.get("%s:%s" % [option_id, index], ""))
			if selected.is_empty():
				break
			selections.append(selected)
	var payload: Dictionary = {
		"event_instance_id": str(event.get("event_instance_id", "")),
		"option_id": option_id,
		"selection_ids": selections
	}
	var replacement: String = str(_choices.get(option_id + ":replace", ""))
	if not replacement.is_empty():
		payload.replace_relic_id = replacement
	return _action("choose_event", payload)


func _replacement_picker(parent: Node, uid_prefix: String, choice_key: String) -> void:
	add_text(parent, "饰品槽已满，请选择要替换的饰品：", 16)
	for relic in _array(view.get("relics")):
		var id: String = str(relic.get("relic_id", ""))
		var button := add_button(
			parent,
			uid_prefix + ":replace:" + id,
			(
				("● " if str(_choices.get(choice_key, "")) == id else "○ ")
				+ UiStyle.label(str(relic.get("definition_id", "")))
			),
			{},
			func() -> void: _choose(choice_key, id)
		)
		button.tooltip_text = UiContentText.describe_relic(_dict(relic.get("detail")))
		if view.has("campaign"):
			add_text(parent, button.tooltip_text, 16)


func _run_bar(parent: Node) -> void:
	add_text(
		parent,
		(
			("第 %s 学年　精力 %s/%s　金钱 %s　牌组 %s 张" if view.has("campaign") else "第 %s 学期　精力 %s/%s　金钱 %s　牌组 %s 张")
			% [
				view.get("term", 1),
				view.get("vitality", 0),
				view.get("max_vitality", 0),
				view.get("money", 0),
				view.get("deck_size", _array(view.get("cards")).size())
			]
		),
		20
	)
	var relics: Array[String] = []
	for relic in _array(view.get("relics")):
		relics.append(UiStyle.label(str(relic.get("definition_id", ""))))
	if not relics.is_empty():
		add_text(parent, "携带饰品：" + "、".join(relics), 16)
	var row := add_row(parent)
	add_button(
		row,
		"inspect:deck",
		"查看牌组 · %s 张" % _array(view.get("cards")).size(),
		{},
		func() -> void: _open_inspector("deck")
	)
	add_button(
		row,
		"inspect:relics",
		"查看饰品 · %s 件" % relics.size(),
		{},
		func() -> void: _open_inspector("relics")
	)


func _card_comparison(parent: Node, card: Dictionary, upgrading: bool) -> void:
	var row := add_row(parent)
	var art := add_art(row, str(card.get("definition_id", "")), Vector2(112, 84))
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	add_text(description, _card_name(card), 20)
	add_text(description, "当前：" + UiContentText.describe_card(_dict(card.get("detail"))), 16)
	if upgrading:
		var next_detail := _dict(card.get("upgrade_detail"))
		add_text(
			description,
			(
				"升级后：" + UiContentText.describe_card(next_detail)
				if not next_detail.is_empty()
				else "这张牌没有可用的下一等级。"
			),
			16
		)


func _open_inspector(kind: String) -> void:
	_close_inspector()
	_inspect_return_focus = get_viewport().gui_get_focus_owner()
	for control in find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			_inspector_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	_inspector = Control.new()
	_inspector.name = "CollectionInspector"
	_inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inspector)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.08, 0.09, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_inspector.add_child(margin)
	var panel := add_panel(margin)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := add_row(panel)
	var entries := _array(view.get("cards" if kind == "deck" else "relics"))
	add_text(header, ("我的牌组 · %s 张" if kind == "deck" else "携带饰品 · %s 件") % entries.size(), 26)
	var close := add_button(header, "inspect:close", "关闭 · Esc", {}, _close_inspector)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.grab_focus()
	add_text(panel, "显示整副牌组的当前等级效果；不代表抽牌顺序。" if kind == "deck" else "饰品的触发条件与效果如下。", 16)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if size.x >= 700 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	if entries.is_empty():
		add_text(grid, "暂未携带饰品。" if kind == "relics" else "牌组为空。", 18)
	for entry in entries:
		var item := add_panel(grid)
		var id := str(entry.get("definition_id", ""))
		var row := add_row(item)
		var art := add_art(row, id, Vector2(112, 84) if kind == "deck" else Vector2(70, 70))
		art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_text(row, _card_name(entry) if kind == "deck" else UiStyle.label(id), 21)
		var detail := _dict(entry.get("detail"))
		add_text(
			item,
			(
				UiContentText.describe_card(detail)
				if kind == "deck"
				else UiContentText.describe_relic(detail)
			),
			17
		)


func _close_inspector() -> void:
	if is_instance_valid(_inspector):
		remove_child(_inspector)
		_inspector.queue_free()
	_inspector = null
	_buttons.erase("inspect:close")
	for control in _inspector_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = _inspector_focus_modes[control]
	_inspector_focus_modes.clear()
	if is_instance_valid(_inspect_return_focus) and _inspect_return_focus.is_inside_tree():
		_inspect_return_focus.grab_focus()
	_inspect_return_focus = null


func _input(event: InputEvent) -> void:
	if is_instance_valid(_inspector) and event.is_action_pressed("ui_cancel"):
		_close_inspector()
		get_viewport().set_input_as_handled()


func _deck_summary(parent: Node) -> void:
	var panel: VBoxContainer = add_panel(parent)
	add_text(panel, "我的牌组", 21)
	var names: Array[String] = []
	for card in _array(view.get("cards")):
		names.append(_card_name(card))
	add_text(panel, "、".join(names), 16)


func refresh_local() -> void:
	render(view)
	local_selection_changed.emit(_choices.duplicate(true))


func _choose(key: String, value: String) -> void:
	_choices[key] = value
	refresh_local()


func _select_setup(kind: String, value: String) -> void:
	match kind:
		"character":
			_character = value
		"difficulty":
			_difficulty = value
	refresh_local()


func _scope(value: String) -> void:
	if value != _selection_scope:
		_choices.clear()
		_selection_scope = value


func _relics_full() -> bool:
	return _array(view.get("relics")).size() >= int(view.get("relic_slots", 3))


func _leave() -> Dictionary:
	return _action("leave_node", {"node_id": str(view.get("current_node_id", ""))})


func _ui(type: String, payload: Dictionary = {}) -> Dictionary:
	return _action("ui." + type, payload)


func _action(type: String, payload: Dictionary = {}) -> Dictionary:
	return {"type": type, "payload": payload}


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _candidate_id(value: Variant) -> String:
	return (
		str(value.get("candidate_id", value.get("definition_id", value.get("id", ""))))
		if value is Dictionary
		else str(value)
	)


func _option_id(value: Variant) -> String:
	return str(value.get("id", "")) if value is Dictionary else str(value)


func _card_name(card: Dictionary) -> String:
	return (
		UiStyle.label(str(card.get("definition_id", "")))
		+ (" +%s" % card.upgrade_level if int(card.get("upgrade_level", 0)) > 0 else "")
	)


func _labels(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		names.append(UiStyle.label(str(id)))
	return "、".join(names)


func _node_name(kind: String) -> String:
	return str(
		(
			{
				"normal": "普通作业",
				"elite": "精英作业",
				"boss": "期末大作业",
				"shop": "商店",
				"event": "突发事件",
				"rest": "休息"
			}
			. get(kind, kind)
		)
	)


func _node_hint(kind: String) -> String:
	if view.has("campaign") and kind == "boss":
		return "本学年的最终挑战，共三个阶段；胜利后选择一项学年大奖励。"
	if view.has("campaign") and kind == "shop":
		return "购买卡牌或餐食，也可以精简牌组。饰品来自学年路线奖励。"
	return str(
		(
			{
				"normal": "完成作业，获得卡牌奖励。",
				"elite": "更难的作业挑战，进入前留意精力与牌组。",
				"boss": "第一学期的最后挑战，共有三个阶段。",
				"shop": "购买卡牌、饰品或餐食，也可以精简牌组。",
				"event": "遇见校园事件，选择适合当前状态的行动。",
				"rest": "恢复精力、升级卡牌，或整理负担。"
			}
			. get(kind, "选择后进入这一站。")
		)
	)


func _difficulty_name(id: String) -> String:
	return str(
		{"easy": "轻松", "normal": "标准", "hard": "挑战", "standard": "标准"}.get(id, UiStyle.label(id))
	)


func _rest_name(id: String) -> String:
	return str(
		(
			{
				"heal": "休息 · 恢复精力",
				"upgrade": "复习 · 升级卡牌",
				"train": "训练 · 升级合作牌",
				"remove_burden": "减负 · 移除负担牌"
			}
			. get(id, id)
		)
	)


func _event_option_name(id: String, label_key: String) -> String:
	return str(
		(
			{
				"return_home": "回家看看",
				"travel": "出去旅行",
				"play_games": "打会儿游戏",
				"leave": "暂时离开",
				"consult": "向学长请教",
				"drop": "放下一点基础负担",
				"rest": "好好休息",
				"upgrade_work": "认真复习",
				"return_card": "归还校园卡",
				"service_desk": "前往服务台"
			}
			. get(id, UiStyle.label(label_key if not label_key.is_empty() else id))
		)
	)


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if int(cost.get("money", 0)) > 0:
		parts.append("金钱 %s" % cost.money)
	if int(cost.get("vitality", 0)) > 0:
		parts.append("精力 %s" % cost.vitality)
	return "无" if parts.is_empty() else "、".join(parts)


func _save_description(value: Variant) -> String:
	if not value is Dictionary or value.is_empty():
		return "暂无存档"
	var text: String = "可用"
	if value.has("term"):
		text += " · 第 %s 学期" % value.term
	if value.has("saved_at"):
		text += " · " + str(value.saved_at)
	return text
