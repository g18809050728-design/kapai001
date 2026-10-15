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
			"apply_status": "施加状态"
		}
		var phrase := str(names.get(op, op))
		if effect.has("status"):
			phrase += "·" + label(str(effect.status))
		if effect.has("unit_id"):
			phrase += "·" + label(str(effect.unit_id))
		if effect.has("scene_id"):
			phrase += "·" + label(str(effect.scene_id))
		if not amount.is_empty():
			phrase += " " + amount
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
