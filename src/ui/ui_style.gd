class_name UiStyle
extends RefCounted

const PAPER := Color("f4eedf")
const INK := Color("243e4a")
const MUTED := Color("637871")
const GREEN := Color("78978e")
const GOLD := Color("dda957")
const RED := Color("bd6b64")
const LABELS = preload("res://src/ui/ui_labels.json")
static var _textures: Dictionary = {}
static var text_scale := 1.0
static var reduced_motion := false


static func label(id: String) -> String:
	var rarities := {"basic": "初始", "common": "普通", "advanced": "进阶", "rare": "稀有", "uncommon": "少见", "starter": "初始"}
	if rarities.has(id):
		return rarities[id]
	if id == "ability":
		return "能力"
	var labels: Dictionary = LABELS.data.get("labels", {})
	if labels.has(id):
		return str(labels[id])
	if id.begins_with("run_"):
		return "我方" if id.ends_with("|p1") else "当前战斗"
	var key := id
	if key.contains("."):
		var parts := key.split(".")
		if parts.size() >= 2:
			key = parts[1]
	if labels.has(key.to_upper()):
		key = key.to_upper()
	return str(labels.get(key, key))


static func texture(id: String) -> Texture2D:
	var key := str(LABELS.data.get("aliases", {}).get(id, id))
	if _textures.has(key):
		return _textures[key]
	var path := str(LABELS.data.get("textures", {}).get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var value := load(path) as Texture2D
	_textures[key] = value
	return value


static func describe_effects(effects: Array) -> String:
	var phrases: PackedStringArray = []
	for effect in effects:
		if not effect is Dictionary:
			continue
		var op := str(effect.get("op", ""))
		var amount := describe_amount(effect.get("amount", effect.get("stacks", "")))
		var names := {
			"complete": "完成量",
			"relax": "放松",
			"draw": "抽牌",
			"discard": "弃牌",
			"heal": "恢复精力",
			"gain_money": "获得金钱",
			"gain_focus": "专注",
			"pay_vitality": "支付精力",
			"remove_card": "移除卡牌",
			"upgrade_card": "升级卡牌",
			"gain_card": "获得卡牌",
			"gain_relic": "获得饰品",
			"retain": "保留",
			"exhaust": "消耗",
			"advance_ddl": "推进 DDL",
			"delay_ddl": "延后 DDL",
			"summon": "召唤同学",
			"set_scene": "切换场景",
			"cleanse": "移除负面状态",
			"gain_status": "获得状态",
			"apply_status": "施加状态",
			"summon_unit": "召唤",
			"establish_scene": "建立场景",
			"retain_hand_card": "选择手牌保留",
			"recall_from_discard": "从弃牌堆取回手牌",
			"remove_status": "移除状态",
			"lose_vitality": "失去精力",
			"reduce_relax": "减少放松",
			"reduce_focus": "减少专注",
			"reduce_max_vitality": "降低精力上限",
			"restore_max_vitality": "恢复精力上限",
			"random_discard": "随机弃牌",
			"summon_task": "新增任务",
			"restore_work": "恢复任务量",
			"pressure": "施加压力",
			"paper_open": "开题",
			"paper_progress": "论文进度",
			"paper_citation": "引用",
			"paper_modifier": "论文修正",
			"paper_amplify": "增幅",
			"paper_publish": "发表",
			"chapter_deploy": "部署章节",
			"chapter_run": "运行章节",
			"chapter_return": "收回章节",
			"swap_chapter_slots": "交换章节",
			"copy_chapter_to_hand": "复印章节",
			"change_topic": "换题",
			"spend_citation": "消耗引用",
			"generate_card": "生成卡牌",
			"publication_cost_discount": "发表减费",
			"gain_synergy": "获得协同",
			"spend_synergy": "消耗协同",
			"spend_synergy_up_to": "消耗协同",
			"spend_all_synergy": "消耗全部协同",
			"summon_partner": "召入伙伴",
			"partner_heal": "伙伴治疗",
			"partner_retreat": "伙伴撤回",
			"partner_extra_action": "伙伴额外行动",
			"cost_discount_next": "下张减费",
			"work_bonus_next": "下张加值",
			"retrieve": "取回卡牌",
			"exhaust_other": "消耗其他卡牌",
			"remove_shield": "移除护盾",
			"arm_erosion_on_next_draws": "下次抽取施加剧侵蚀",
			"extend_timed_debuffs": "延长限时负面",
			"trigger_erosion": "触发侵蚀",
			"trigger_induced": "触发诱发",
			"shuffle_draw": "洗牌",
			"search_draw_for_type": "检索卡牌",
			"add_work_bonus": "下张工作完成量加值",
			"status_complete": "状态完成量",
			"modify_erosion_window": "侵蚀结算窗口（当前引擎尚未应用数值修正）"
		}
		var phrase := str(names.get(op, op))
		if bool(effect.get("up_to", false)):
			phrase += "至多"
		if effect.has("status"):
			phrase += "·" + label(str(effect.status))
		elif effect.get("category") == "negative":
			phrase += "·负面状态"
		for key in ["unit", "unit_id", "scene", "scene_id", "card", "card_id", "relic_id", "task"]:
			if effect.has(key):
				phrase += "·" + label(str(effect[key]))
		if not amount.is_empty():
			phrase += " " + amount
		if effect.has("per_discarded"):
			phrase += "（每弃一张牌额外抽 %s 张）" % effect.per_discarded
		for pair in [["vitality_bonus", "额外精力"], ["cooperation_bonus", "额外合作值"]]:
			if effect.has(pair[0]):
				phrase += "（%s +%s）" % [pair[1], effect[pair[0]]]
		if effect.has("target"):
			phrase += (
				"（%s）"
				% {"player": "我方", "task": "所选任务", "all_tasks": "所有任务", "self": "自身", "one": "一位伙伴", "all": "全体", "earliest_task": "最早任务", "other_task": "另一个任务"}.get(
					str(effect.target), label(str(effect.target))
				)
			)
		var bonus: Dictionary = effect.get("bonus_if", {})
		if not bonus.is_empty():
			var condition := ""
			if bonus.has("played_definition"):
				condition = "本回合打出过" + label(str(bonus.played_definition))
			elif bonus.has("status"):
				condition = "拥有至少 %s 层%s" % [bonus.get("min_stacks", 1), label(str(bonus.status))]
			elif bonus.has("ddl_lte"):
				condition = "DDL 不超过 %s" % bonus.ddl_lte
			phrase += "（%s时额外 +%s）" % [condition, bonus.get("amount", 0)]
		if effect.has("condition"):
			var condition_text := describe_condition(effect.condition)
			if not condition_text.is_empty():
				phrase += "（需：%s）" % condition_text
		var effect_limit := str(effect.get("limit", ""))
		if effect_limit in ["once_per_turn", "twice_per_turn", "three_per_turn"]:
			phrase += "（%s）" % {"once_per_turn": "每回合一次", "twice_per_turn": "每回合两次", "three_per_turn": "每回合三次"}[effect_limit]
		phrase += _describe_effect_details(effect)
		phrases.append(phrase)
	return " / ".join(phrases)


static func _describe_effect_details(effect: Dictionary) -> String:
	var details: PackedStringArray = []
	var op := str(effect.get("op", ""))
	var bonus: Dictionary = effect.get("bonus", {})
	if not bonus.is_empty():
		details.append("%s时额外 +%s" % [describe_condition(bonus.get("condition", {})), bonus.get("amount", 0)])
	for entry in [["per_link_work", "本次连携工作次数", 3], ["per_partner", "在场伙伴数量", 3], ["per_other_chapter", "本窗口其他已运行章节数量", 2], ["per_debuff_kind", "目标负面种类数", 6]]:
		if effect.has(entry[0]):
			details.append("按%s每个额外 +%s，至多计 %s 个%s" % [entry[1], effect[entry[0]], effect.get("cap", entry[2]), "，每个目标分别计算" if bool(effect.get("per_target", false)) else ""])
	if effect.has("per_spent"):
		details.append("本次每消耗 1 协同额外 +%s" % effect.per_spent)
	if op == "retrieve":
		details.append("从弃牌堆取回本角色卡牌到手牌")
		if effect.has("card_kind"):
			details.append("仅%s牌" % label(str(effect.card_kind)))
		if bool(effect.get("permanent_only", false)):
			details.append("仅永久牌")
		if effect.has("base_cost_min"):
			details.append("基础费用至少 %s" % effect.base_cost_min)
	if op == "search_draw_for_type":
		details.append("取回抽牌堆首张章节到手牌，随后洗切抽牌堆；没有章节则抽 1 张；满手转入弃牌堆")
	if op == "chapter_return":
		details.append("按槽位顺序撤入弃牌堆")
		if effect.has("modifier_per_chapter"):
			details.append("每收回 1 章，论文修正 %+d" % int(effect.modifier_per_chapter))
	if op == "change_topic":
		details.append("若有已用牌名，移除最早记录，论文修正 %+d" % int(effect.get("modifier", -1)))
	if op == "cost_discount_next":
		details.append("用于下一张基础费用至少 %s 的卡牌" % effect.get("min_base_cost", 2))
	if op == "summon_partner":
		for entry in [["vitality", "入场精力"], ["max_vitality", "精力上限"], ["cooperation", "合作值"]]:
			if effect.has(entry[0]):
				details.append("%s %s" % [entry[1], effect[entry[0]]])
	if op == "generate_card":
		details.append("加入手牌，满手转入弃牌堆" if effect.get("zone", "hand") == "hand" else "加入弃牌堆")
	if op == "extend_timed_debuffs":
		details.append("仅延长已有易伤、虚弱、脆化，各自上限 3")
	if op == "trigger_erosion":
		details.append("按当前侵蚀层数额外结算一次" + ("，不衰减" if not bool(effect.get("decay", true)) else "，随后衰减 1 层"))
	if op == "paper_citation":
		details.append("上限 5；第 3/4/5 层额外支付 1/2/3 专注，不足时改抽 1 张")
	if op == "summon_task":
		details.append("数量 %s" % effect.get("count", 1))
	if op == "spend_synergy_up_to":
		details.append("最多消耗所示数量，协同为 0 也执行后续")
	if op == "spend_all_synergy":
		details.append("协同为 0 也执行后续")
	if op == "spend_synergy" and bool(effect.get("optional", false)):
		details.append("足够时自动消耗；不足时跳过此项及其后续收益")
	if effect.has("then"):
		details.append("随后：" + describe_effects(effect.then))
	if effect.has("if_spent"):
		details.append("成功消耗后：" + describe_effects(effect.if_spent))
	if effect.has("after"):
		details.append("最后：" + describe_effects(effect.after))
	return "" if details.is_empty() else "（" + "；".join(details) + "）"


static func describe_amount(value: Variant) -> String:
	if not value is Dictionary:
		return str(value)
	var op := str(value.get("op", ""))
	var names := {"source_stacks": "所选源任务的%s层数" % label(str(value.get("status", ""))), "synergy": "当前协同", "paper_progress": "论文进度", "citation": "引用层数", "modifier": "论文修正", "consumed_synergy": "本次消耗的协同"}
	var text := str(names.get(op, "按当前状态计算"))
	if value.has("cap"):
		text += "（最多 %s）" % value.cap
	if value.has("multiplier"):
		text += " × %s" % value.multiplier
	if value.has("bonus"):
		text += "，再 +%s" % value.bonus
	return text


static func describe_conditions(conditions: Array) -> String:
	var parts: PackedStringArray = []
	for condition in conditions:
		var text := describe_condition(condition)
		if not text.is_empty():
			parts.append(text)
	return "、".join(parts)


static func describe_condition(condition: Variant) -> String:
	if not condition is Dictionary:
		return ""
	if condition.has("all"):
		return describe_conditions(condition.all)
	if condition.has("any"):
		var options: PackedStringArray = []
		for item in condition.any:
			options.append(describe_condition(item))
		return " 或 ".join(options)
	var kind := str(condition.get("kind", ""))
	var value: Variant = condition.get("value", "")
	var names := {
		"link": "连携：前一张为策略、本张为工作",
		"link_work_resolved": "连携工作结算后",
		"paper_progress_gained": "获得论文进度后",
		"paper_name_turn_unused": "本回合尚未使用该牌名",
		"two_tasks": "至少有两个任务",
		"prev_card_type_is": "前牌为%s" % label(str(condition.get("value", ""))),
		"hand_other_min": "其他手牌至少%s张" % condition.get("value", 1),
		"no_strategy_played_turn": "本回合尚未打出策略",
		"instance_plays_battle": "本实例本场已使用至少%s次" % condition.get("min", 1),
		"instance_played_before": "本实例本场使用过",
		"previous_strategy_plays_min": "前一策略实例已使用至少%s次" % condition.get("value", 1),
		"retrieved_strategy_this_turn": "本回合被动已取回策略",
		"paid_citation_focus_this_turn": "本回合为引用支付过专注",
		"base_cost_min": "基础费用至少%s" % condition.get("value", 0),
		"card_discarded_this_effect": "本次效果已弃牌",
		"passive_retrieve_success": "被动成功取回后",
		"target_status_kinds": "目标负面种类至少%s、至多%s" % [condition.get("min", 0), condition.get("max", 6)],
		"target_has_any_timed_debuff": "目标有易伤、虚弱或脆化",
		"target_has_induced": "目标有诱发",
		"target_had_induced_at_play_start": "出牌开始时目标有诱发",
		"any_task_has_induced": "存在带诱发的任务",
		"any_task_debuff_kinds_min": "某任务有至少%s种负面" % condition.get("value", 1),
		"erosion_applied_events_min": "本回合已成功施加侵蚀至少%s次" % condition.get("value", 1),
		"first_induced_trigger": "本回合首次诱发触发",
		"compound_reaction_success": "复合反应成功后",
		"prepare_window": "准备阶段",
		"paper_open": "已开题",
		"paper_closed": "未开题",
		"paper_name_unused": "本篇未用牌名",
		"paper_name_used": "本篇已用牌名",
		"paper_progress_min": "论文进度≥%s" % value,
		"chapter_count_min": "章节≥%s" % value,
		"other_chapter_ran_window": "本轮有其他章节运行",
		"citation_min": "引用≥%s" % value,
		"synergy_min": "协同≥%s" % value,
		"synergy_is_zero": "协同为 0",
		"partner_count_min": "伙伴≥%s" % value,
		"no_partner": "无伙伴",
		"ddl_lte": "DDL≤%s" % value,
		"independent_exam": "独立作答",
		"fixed_exam_room": "固定考场",
		"first_cooperation_resolved": "本回合首张合作牌",
		"played_type_count_turn": "本回合已打出%s牌至少%s张" % [label(str(condition.get("card_type", ""))), condition.get("min", condition.get("value", 1))],
		"target_has_status": "目标有%s" % label(str(condition.get("status", "状态"))),
		"target_still_alive": "目标仍存活",
		"healed_partner_turn": "本回合治疗过伙伴",
		"summoned_partner_turn": "本回合召入过伙伴"
	}
	return str(names.get(kind, ""))


static func error_text(error: ApiError) -> String:
	if error == null:
		return ""
	var names := {
		"INSUFFICIENT_RESOURCE": "资源不足",
		"INSUFFICIENT_FOCUS": "专注不足",
		"INSUFFICIENT_VITALITY": "精力不足",
		"INVALID_TARGET": "请检查目标或候选",
		"CHOICE_PENDING": "请先完成当前选择",
		"WRONG_PHASE": "当前阶段不可执行",
		"RUN_ACTIVE": "请先继续或结束已有学期",
		"RUN_NOT_FOUND": "尚未开始学期",
		"SAVE_NOT_FOUND": "暂无存档",
		"SAVE_CORRUPT": "存档损坏，可检查备份",
		"VERSION_MISMATCH": "存档与当前游戏版本不兼容",
		"SAVE_IO_ERROR": "保存失败，请重试",
		"STALE_STATE": "界面已过期，请重新选择",
		"UNPLAYABLE": "此牌不可主动打出"
	}
	var reason := str(names.get(String(error.code), "当前操作不可用"))
	var details := {
		"error.play.paper_name_used_turn": "本回合此牌名已使用",
		"error.play.requirement_invalid": "未满足使用条件",
		"error.play.citation_insufficient": "引用不足",
		"error.play.no_chapter_replace": "无法选择撤下的章节",
		"error.play.no_recall_target": "弃牌堆没有可取回的卡牌",
		"error.play.no_exhaust_target": "没有可消耗的卡牌",
		"error.battle.v3_card_limit": "本回合使用次数已达上限",
		"error.battle.choice_pending": "请先完成当前选择",
		"error.battle.no_pending_choice": "当前没有待选效果",
		"error.battle.choice_id_invalid": "选择已失效，请重新操作"
	}
	var detail := str(details.get(str(error.message_key), ""))
	return detail if not detail.is_empty() else reason


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"]
	)
	theme.default_font = font
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("84918b"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := box(Color("e3e9df") if state == "normal" else Color("cbdacf"))
		if state == "disabled":
			style.bg_color = Color("e8e5db")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = GOLD
			style.set_border_width_all(2)
		theme.set_stylebox(state, "Button", style)
	theme.set_stylebox("panel", "PanelContainer", box(Color("fffbf1")))
	theme.set_stylebox("normal", "LineEdit", box(Color("ffffff")))
	theme.set_color("font_color", "LineEdit", INK)
	return theme


static func box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
