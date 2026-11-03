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


static func label(id: String) -> String:
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
		var amount := str(effect.get("amount", effect.get("stacks", "")))
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
			"search_draw_for_type": "检索卡牌"
		}
		var phrase := str(names.get(op, op))
		if bool(effect.get("up_to", false)):
			phrase += "至多"
		if effect.has("status"):
			phrase += "·" + label(str(effect.status))
		elif effect.get("category") == "negative":
			phrase += "·负面状态"
		for key in ["unit", "unit_id", "scene", "scene_id", "card", "card_id", "relic_id"]:
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
				% {"player": "我方", "task": "所选任务", "all_tasks": "所有任务", "self": "自身"}.get(
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
		if str(effect.get("limit", "")) == "once_per_turn":
			phrase += "（每回合一次）"
		phrases.append(phrase)
	return " / ".join(phrases)


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
		return describe_conditions(condition.any)
	var kind := str(condition.get("kind", ""))
	var value: Variant = condition.get("value", "")
	var names := {
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
		"played_type_count_turn": "本回合已打出类型牌",
		"target_has_status": "目标有状态",
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
