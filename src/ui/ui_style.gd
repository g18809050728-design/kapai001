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
			"pressure": "施加压力"
		}
		var phrase := str(names.get(op, op))
		if bool(effect.get("up_to", false)):
			phrase += "至多"
		if effect.has("status"):
			phrase += "·" + label(str(effect.status))
		elif effect.get("category") == "negative":
			phrase += "·负面状态"
		for key in ["unit", "unit_id", "scene", "scene_id", "card_id", "relic_id"]:
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
		phrases.append(phrase)
	return " / ".join(phrases)


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
	return "%s · %s\n%s" % [reason, error.code, error.message_key]


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
