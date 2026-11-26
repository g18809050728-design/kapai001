class_name TaskIntentText
extends RefCounted

const TAUNT := "嘲讽：受嘲讽限制的单体卡牌只能选中有嘲讽的任务。"
const CARD_ZONES := {"draw": "抽牌堆", "discard": "弃牌堆", "hand": "手牌"}
const CARD_TYPES := {"work": "工作牌", "strategy": "策略牌", "cooperation": "合作牌", "scene": "场景牌", "ability": "能力牌", "burden": "负担牌"}
const FOCUS_REDUCTION := "玩家当轮剩余专注扣除 %d 点，最低为 0。"
const FOCUS_GAIN := "玩家当轮剩余专注增加 %d 点，最多加到专注上限。"
const FOCUS_TIMING := "专注在玩家行动结束后增减。下一轮准备时会重新计算专注，剩余专注不会带入下一轮。"
const VITALITY_REDUCTION := "玩家精力上限降低 %d 点（最低为 1），当前精力若超过新上限，也会降到新上限。"
const SUMMON_LIMIT := "每个任务实例本场只能触发一次意图召唤。"
const SUMMON_USED := "此任务实例本场已用过意图召唤。"
const SELF_DESTRUCT := "结算压力后自身退场。"
const WORK_RESTORE := "自身未完成量增加 %d 点，最多回到本阶段上限。"
const DDL_BONUS := "剩余 DDL 增加 %d，之后仍会结算本轮正常倒计时。"
const PASSIVE_EFFECTS := {
	"draw_reduction": ["基础抽牌减少", "draw", "−", "在场时，玩家每轮基础抽牌少 %d 张（最低为 0 张）。"],
	"first_card_cost_bonus": ["首张牌加费", "focus", "+", "在场时，玩家每轮打出的第一张牌增加 %d 点专注费用。"],
	"discard_on_first_card": ["首张牌触发弃牌", "discard", "−", "在场时，玩家每轮打出第一张牌时，从其余手牌随机弃掉至多 %d 张，然后结算打出的牌。"],
	"max_vitality_reduction": ["精力上限持续降低", "heart", "−", "在场时，玩家每轮准备时精力上限累计降低 %d 点（最低为 1）。当前精力若超过新上限，会降到新上限。"],
}
const INTENT_VALUE_EFFECTS := {
	"player_reduce_focus": ["扣除剩余专注", "focus", "−", FOCUS_REDUCTION],
	"player_gain_focus": ["补充剩余专注", "focus", "+", FOCUS_GAIN],
	"player_reduce_max_vitality": ["精力上限降低", "heart", "−", VITALITY_REDUCTION],
	"work_restore": ["恢复未完成量", "work", "+", WORK_RESTORE],
	"ddl_bonus": ["增加 DDL", "clock", "+", DDL_BONUS],
}
const INTENT_STATUS_GLYPHS := {
	"anxiety": "anxiety", "procrastination": "clock", "drowsiness": "drowsiness",
	"work_boost": "work", "brainstorm": "focus", "confusion": "status",
	"attack_immunity": "relax",
}


static func summary(intent: Dictionary, task: Dictionary = {}, limit: int = 2) -> String:
	if task.get("intent_waiting", false):
		return "本轮不行动"
	var parts := _effects(intent, task, true)
	if parts.is_empty():
		return "待揭示" if intent.is_empty() else "无行动效果"
	if parts.size() <= limit:
		return " · ".join(parts)
	return " · ".join(parts.slice(0, limit)) + "…"


static func hud_caption(task: Dictionary, font: Font, pixels: int, width: float) -> String:
	var intent: Dictionary = task.get("intent_snapshot", {})
	var caption := summary(intent, task)
	if _fits(caption, font, pixels, width) or task.get("intent_waiting", false):
		return caption
	var lines := _effects(intent, task, true)
	var narrow := _effects(intent, task, true, true)
	var visible := mini(lines.size(), 2)
	for index in visible:
		var suffix := "…" if index == 1 and lines.size() > 2 else ""
		lines[index] += suffix
		if not _fits(lines[index], font, pixels, width):
			lines[index] = narrow[index] + suffix
		if not suffix.is_empty() and not _fits(lines[index], font, pixels, width):
			lines[index] = narrow[index]
	return "\n".join(lines.slice(0, visible))


static func _fits(text: String, font: Font, pixels: int, width: float) -> bool:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x <= width


static func describe(intent: Dictionary, task: Dictionary = {}, status_rules: Dictionary = {}) -> String:
	if task.get("intent_waiting", false):
		return "本轮不行动。下一轮开始后可行动。"
	var lines := _effects(intent, task, false)
	if lines.is_empty():
		return "待揭示。" if intent.is_empty() else "本次意图无行动效果。"
	if _has_pressure(intent, task):
		lines.append_array(_pressure_conditions(intent))
		if task.has("effective_pressure"):
			lines.append("已计入预告的敌方技能。前面的攻击、护卫离场或其他效果会改变结算时的数值。")
	var status: Dictionary = intent.get("gain_status", {})
	if not status.is_empty():
		var explanation := _status_explanation(str(status.get("status", "")), status_rules)
		if not explanation.is_empty():
			lines.append(explanation)
	if intent.has("player_gain_focus") or intent.has("player_reduce_focus"):
		lines.append(FOCUS_TIMING)
	return "\n".join(lines)


static func sequence_rule(phase: Dictionary) -> String:
	if phase.get("intents", []).size() <= 1:
		return "每轮使用同一个意图。"
	if phase.get("intent_loop", "cycle") == "clamp":
		return "每轮末切换到下一个意图，到最后一个后停留。"
	return "每轮末切换到下一个意图，最后一个之后回到第一个。"


static func traits(definition: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry in _trait_entries(definition):
		lines.append(entry.body)
	return lines


static func mechanics(task: Dictionary, status_rules: Dictionary) -> Array[Dictionary]:
	var definition: Dictionary = task.get("traits", {}).duplicate()
	definition.taunt = task.get("taunting", false)
	var entries := _trait_entries(definition)
	var phase: Dictionary = task.get("intent_phase", {})
	if phase.get("intent_loop", "cycle") == "clamp" and phase.get("intents", []).size() > 1:
		entries.append(_mechanic("intent_clamp", "意图递进", "next", "阶段规则", sequence_rule(phase)))
	if not task.get("intent_waiting", false):
		entries.append_array(_intent_entries(task, status_rules))
	return entries


static func _trait_entries(definition: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not definition.get("victory_required", true):
		entries.append(_mechanic("optional_task", "附属任务", "link", "胜利条件", "附属任务：完成所有胜利必需任务即可获胜，即使它仍在场。"))
	if definition.get("taunt", false):
		entries.append(_mechanic("taunt", "嘲讽", "taunt", "在场效果", TAUNT))
	if definition.get("shield_persistent", false):
		entries.append(_mechanic("shield_persistent", "保留屏障", "relax", "在场效果",
			"保留屏障：任务准备时保留剩余屏障，本轮获得的屏障会叠加。进入下一轮时，屏障重新按新意图赋值。"))
	if definition.get("self_copy_every_round", false):
		var interval := int(definition.get("self_copy_interval", 1))
		var timing := "每轮开始时" if interval == 1 else "每当新轮次是 %d 的倍数时" % interval
		entries.append(_mechanic("self_copy", "复制自身", "copy", "在场效果",
			"复制：%s，每个在场的同种任务各生成 1 个复制体。复制体以原型首阶段基础未完成量的 %d%% 为基准，按来源任务强度调整并向上取整，当轮就能行动。"
			% [timing, definition.get("self_copy_work_percent", 100)]))
	for field in PASSIVE_EFFECTS:
		var amount := int(definition.get(field, 0))
		if amount > 0:
			var info: Array = PASSIVE_EFFECTS[field]
			entries.append(_mechanic(field, info[0], info[1], "在场效果", str(info[3]) % amount, "%s%d" % [info[2], amount]))
	var completion := _completion_entry(definition.get("on_complete_effects", []))
	if not completion.is_empty():
		entries.append(completion)
	return entries


static func _completion_entry(effects: Array) -> Dictionary:
	if effects.is_empty():
		return {}
	var descriptions: PackedStringArray = []
	for effect in effects:
		var description := _completion_effect(effect)
		if not description.is_empty():
			descriptions.append(description)
	if descriptions.is_empty():
		return {}
	var body := "完成最终阶段时，" + "\n".join(descriptions)
	if effects.size() > 1:
		return _mechanic("completion", "结课联动", "link", "完成时", body)
	var effect: Dictionary = effects[0]
	match str(effect.get("op", "")):
		"gain_focus":
			return _mechanic("completion", "结课返还专注", "focus", "完成时", body, "+%d" % effect.amount)
		"restore_max_vitality":
			return _mechanic("completion", "结课恢复精力上限", "heart", "完成时", body)
		"summon_task":
			return _mechanic("completion", "结课召唤", "summon", "完成时", body, "×%d" % effect.get("count", 1))
		"pressure":
			return _mechanic("completion_pressure_0", "结课反击", "pressure", "完成时", body, effect.amount)
	return _mechanic("completion", "结课效果", "work", "完成时", body)


static func _intent_entries(task: Dictionary, status_rules: Dictionary) -> Array[Dictionary]:
	var intent: Dictionary = task.get("intent_snapshot", {})
	var entries: Array[Dictionary] = []
	for field in INTENT_VALUE_EFFECTS:
		var amount := int(intent.get(field, 0))
		if amount <= 0:
			continue
		var info: Array = INTENT_VALUE_EFFECTS[field]
		var body := "结束回合后，" + (str(info[3]) % amount)
		if info[1] == "focus":
			body += "\n下一轮准备时会重新计算专注。"
		entries.append(_mechanic(field, info[0], info[1], "本轮意图", body, "%s%d" % [info[2], amount]))
	if intent.has("gain_status"):
		entries.append(_status_entry(intent.gain_status, status_rules))
	if intent.has("add_card"):
		var card: Dictionary = intent.add_card
		var burden: bool = task.get("intent_adds_burden", false)
		entries.append(_mechanic("add_burden" if burden else "add_card", "加入负担牌" if burden else "加入卡牌",
			"discard" if burden else "draw", "本轮意图", "结束回合后，" + _add_card_description(card), "+%d" % card.get("count", 1)))
	if not intent.get("summon_tasks", []).is_empty():
		entries.append(_summon_entry(intent.summon_tasks, task.get("intent_summon_used", false)))
	if intent.has("transform_task"):
		entries.append(_mechanic("transform_task", "转化任务", "next", "本轮意图", _transform_description(intent.transform_task)))
	if intent.get("self_destruct", false):
		entries.append(_mechanic("self_destruct", "自行退场", "break", "本轮意图", SELF_DESTRUCT))
	if _has_pressure(intent, task):
		var pressure := _pressure_entry(intent)
		if not pressure.is_empty():
			entries.append(pressure)
	return entries


static func _status_entry(status: Dictionary, rules: Dictionary) -> Dictionary:
	var id := str(status.get("status", ""))
	var target := str(status.get("target", "player"))
	var harmful := id in ["anxiety", "procrastination", "drowsiness"]
	var title := "施加" if harmful else "玩家获得"
	var key := ("inflict_" if harmful else "grant_") + id
	if target == "task":
		title = "自身获得"
		key = "gain_" + id
	var body := "结束回合后，" + _status_effect(status, false, false)
	var explanation := _status_explanation(id, rules)
	if not explanation.is_empty():
		body += "\n" + explanation
	var count := ("×%d" if id == "attack_immunity" else "+%d") % status.get("stacks", 1)
	return _mechanic(key, title + UiStyle.label(id), INTENT_STATUS_GLYPHS.get(id, "status"), "本轮意图", body, count)


static func _summon_entry(specs: Array, used: bool) -> Dictionary:
	if used:
		return _mechanic("summon_tasks", "召唤已用", "summon", "本轮意图", SUMMON_USED)
	var lines: PackedStringArray = []
	var total := 0
	for spec in specs:
		total += int(spec.get("count", 1))
		lines.append(_summon_effect(spec, false, false))
	lines.append(SUMMON_LIMIT)
	return _mechanic("summon_tasks", "召唤任务", "summon", "本轮意图", "\n".join(lines), "×%d" % total)


static func _pressure_entry(intent: Dictionary) -> Dictionary:
	var times := int(intent.get("pressure_times", 1))
	var all: bool = intent.get("pressure_all", false)
	var conditions := _pressure_conditions(intent)
	if not all and times <= 1 and conditions.is_empty():
		return {}
	var titles: PackedStringArray = []
	if all:
		titles.append("全体")
		conditions.insert(0, "每段压力由玩家和所有在场伙伴各自承受。护卫只代受单体压力。")
	if times > 1:
		titles.append("多段")
		conditions.insert(0, "依次结算 %d 段压力，每段结算时重新检查承受目标。" % times)
	if titles.is_empty():
		titles.append("条件")
	return _mechanic("special_pressure", "".join(titles) + "压力", "pressure", "本轮意图", "\n".join(conditions), "×%d" % times if times > 1 else "")


static func _mechanic(key: String, title: String, glyph: String, timing: String, body: String, count: Variant = "") -> Dictionary:
	return {"key": key, "title": title, "glyph": glyph, "mechanic": timing, "body": body, "count": count}


static func _effects(intent: Dictionary, task: Dictionary, compact: bool, narrow: bool = false) -> PackedStringArray:
	var parts: PackedStringArray = []
	var pressure_line := ""
	if _has_pressure(intent, task):
		var pressure := int(task.get("effective_pressure", intent.get("pressure", 0)))
		var times := int(intent.get("pressure_times", 1))
		var all: bool = intent.get("pressure_all", false)
		var amount := str(pressure)
		if times > 1:
			amount = ("%d×%d" if narrow else "%d × %d 段") % [pressure, times]
		if compact:
			var prefix := "全体压力 " if all else "压力 "
			if narrow:
				prefix = "全体 " if all else "压力 "
			parts.append(prefix.strip_edges() + amount if narrow else prefix + amount)
		else:
			var target := "玩家和所有在场伙伴各承受" if all else "施加"
			var hits := "%d 段，每段 %d 点压力" % [times, pressure] if times > 1 else "%d 点压力" % pressure
			var basis := "预计值" if task.has("effective_pressure") else "基础值"
			var guard := "护卫只代受单体压力。" if all else "每段由最早入场的在场护卫代受。没有护卫时由玩家承受。"
			pressure_line = "%s %s（%s）。%s" % [target, hits, basis, guard]
	if intent.has("shield"):
		var shield := int(task.get("intent_shield_gain", intent.shield))
		var qualifier := "预计" if task.has("intent_shield_gain") else "基础值"
		parts.append(("%s +%d" % ["屏障" if narrow else "自身屏障", shield]) if compact else "自身获得 %d 点屏障（%s）。迷惑会增加、脆化会减少新获得的屏障。" % [shield, qualifier])
	if intent.has("player_gain_focus"):
		var focus := int(intent.player_gain_focus)
		parts.append("%s +%d" % ["专注" if narrow else "剩余专注", focus] if compact else FOCUS_GAIN % focus)
	if intent.has("player_reduce_focus"):
		var focus := int(intent.player_reduce_focus)
		parts.append("%s −%d" % ["专注" if narrow else "剩余专注", focus] if compact else FOCUS_REDUCTION % focus)
	if intent.has("player_reduce_max_vitality"):
		var amount := int(intent.player_reduce_max_vitality)
		parts.append(("精力上限−%d" if narrow else "精力上限 −%d") % amount if compact else VITALITY_REDUCTION % amount)
	if intent.has("work_restore"):
		var amount := int(intent.work_restore)
		parts.append("未完成量 +%d" % amount if compact else WORK_RESTORE % amount)
	if intent.has("gain_status"):
		parts.append(_status_effect(intent.gain_status, compact, narrow))
	if intent.has("add_card"):
		var card: Dictionary = intent.add_card
		if compact:
			var zone := str(card.get("zone", "discard"))
			var destination := str(CARD_ZONES.get(zone, zone))
			var count := int(card.get("count", 1))
			var title := UiStyle.label(str(card.get("card", "")))
			parts.append("%s +%d 张" % [destination, count] if narrow else "%s加入 %s ×%d" % [destination, title, count])
		else:
			parts.append(_add_card_description(card))
	if intent.has("ddl_bonus"):
		var amount := int(intent.ddl_bonus)
		parts.append("DDL +%d" % amount if compact else DDL_BONUS % amount)
	if not pressure_line.is_empty():
		parts.append(pressure_line)
	if intent.get("self_destruct", false):
		if compact:
			parts.insert(int(_has_pressure(intent, task)), "自行退场")
		else:
			parts.append(SELF_DESTRUCT)
	if intent.has("transform_task"):
		var title := UiStyle.label(str(intent.transform_task.get("task", "")))
		parts.append(("转化" if narrow else "转化为" + title) if compact else _transform_description(intent.transform_task))
	if not intent.get("summon_tasks", []).is_empty():
		if task.get("intent_summon_used", false):
			parts.append("召唤已用" if compact else SUMMON_USED)
		else:
			var position := int(_has_pressure(intent, task))
			for spec in intent.summon_tasks:
				var text := _summon_effect(spec, compact, narrow)
				if compact:
					parts.insert(position, text)
					position += 1
				else:
					parts.append(text)
			if not compact:
				parts.append(SUMMON_LIMIT)
	return parts


static func _has_pressure(intent: Dictionary, task: Dictionary) -> bool:
	return intent.has("pressure") or int(task.get("effective_pressure", 0)) > 0


static func _add_card_description(card: Dictionary) -> String:
	var zone := str(card.get("zone", "discard"))
	var overflow := "，手牌满时放入弃牌堆" if zone == "hand" else ""
	return "向玩家的%s加入 %d 张「%s」%s。" % [CARD_ZONES.get(zone, zone), card.get("count", 1), UiStyle.label(str(card.get("card", ""))), overflow]


static func _transform_description(spec: Dictionary) -> String:
	var title := UiStyle.label(str(spec.get("task", "")))
	return "压力阶段后转化为「%s」，清除原状态，未完成量最多保留到新阶段上限，并从下一轮行动。" % title


static func _pressure_conditions(intent: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	if intent.has("pressure_per_unit"):
		var cap := "（最多增加 %d 点）" % intent.pressure_per_unit_cap if intent.has("pressure_per_unit_cap") else ""
		lines.append("结算时每有 1 名在场伙伴，每段压力增加 %d 点%s。" % [intent.pressure_per_unit, cap])
	if intent.has("pressure_per_vitality"):
		lines.append("结算时玩家的当前精力每满 %d 点，每段压力增加 %d 点。" % [intent.get("pressure_vitality_step", 10), intent.pressure_per_vitality])
	if intent.has("pressure_when_shield"):
		lines.append("结算压力时若任务自身仍有屏障，每段压力增加 %d 点。普通屏障在任务准备时清空。" % intent.pressure_when_shield)
	for key in ["pressure_has_unit_mult", "pressure_no_unit_mult"]:
		if intent.has(key):
			var condition := "有伙伴在场" if key == "pressure_has_unit_mult" else "没有伙伴在场"
			lines.append("结算时%s，每段压力按 %d%% 计算（向上取整）。" % [condition, intent[key]])
	for type in intent.get("pressure_per_card_type", {}):
		lines.append("本场战斗每打出 1 张%s，每段压力增加 %d 点。" % [CARD_TYPES.get(type, type), intent.pressure_per_card_type[type]])
	return lines


static func _status_effect(status: Dictionary, compact: bool, narrow: bool) -> String:
	var id := str(status.get("status", ""))
	var target := "自身" if status.get("target", "player") == "task" else "玩家"
	var name := UiStyle.label(id)
	var stacks := int(status.get("stacks", 1))
	var effect := "%s获得 %d 层%s" % [target, stacks, name]
	if id == "attack_immunity":
		return "%s攻击免疫 ×%d" % ["" if narrow else "自身", stacks] if compact else "自身获得 %d 次攻击免疫。每次抵消一整张工作牌对自身的直接完成量，包括同一张牌的多段完成量。侵蚀等自动完成量仍然生效。" % stacks
	if compact:
		return "%s+%d" % [name, stacks] if narrow else effect
	return effect + "。"


static func _status_explanation(id: String, rules: Dictionary) -> String:
	var rule: Dictionary = rules.get(id, {})
	var text := str({
		"anxiety": "下一轮准备时，每层少获得 1 点基础专注。",
		"procrastination": "下一次基础抽牌时，每层少抽 1 张。",
		"drowsiness": "下一次玩家行动中，每张工作牌的第一段完成量每层减少 %d 点。" % rule.get("completion_penalty_per_stack", 1),
		"work_boost": "本场战斗中，每张工作牌第一段的完成量每层增加 %d 点。" % rule.get("completion_per_stack", 1),
		"brainstorm": "该任务每层增加 %d 点压力，本次压力也受影响。" % rule.get("pressure_per_stack", 1),
		"confusion": "该任务每次新获得屏障时，每层额外增加 %d 点。若本次也获得屏障，先获得屏障再叠迷惑。" % rule.get("shield_per_stack", 1),
	}.get(id, ""))
	if not text.is_empty() and int(rule.get("cap", 0)) > 0:
		text += "最多叠加 %d 层。" % rule.cap
	return text


static func _summon_effect(spec: Dictionary, compact: bool, narrow: bool) -> String:
	var title := UiStyle.label(str(spec.get("task", "")))
	var count := int(spec.get("count", 1))
	var taunt := "，带嘲讽" if spec.get("taunt", false) else ""
	if compact:
		if narrow:
			return "召唤嘲讽" if spec.get("taunt", false) and count == 1 else "召唤×%d" % count
		return "召唤 %s ×%d%s" % [title, count, taunt]
	return "压力阶段后召唤 %d 个「%s」%s，初始未完成量取原型首阶段基础未完成量的 %d%%，按来源任务强度调整并向上取整。召唤物从下一轮行动。" % [count, title, taunt, spec.get("work_percent", 100)]


static func _completion_effect(effect: Dictionary) -> String:
	var amount := int(effect.get("amount", 0))
	match str(effect.get("op", "")):
		"gain_focus":
			return "玩家立即获得 %d 点专注，最多加到专注上限。" % amount
		"complete":
			if effect.get("target") == "other_tasks":
				return "对其他每个在场任务施加 %d 点完成量，先扣屏障。" % amount
		"reduce_shield":
			if effect.get("target") == "other_tasks":
				return "其他每个在场任务的屏障再减少 %d 点，最低为 0。" % amount
		"restore_max_vitality":
			return "玩家精力上限恢复最多 %d 点，至多回到开战时的上限。当前精力保持原值。" % amount
		"pressure":
			if effect.get("target") == "all":
				return "玩家和所有在场伙伴各承受 %d 点压力。" % amount
		"summon_task":
			return "召唤 %d 个「%s」，它们从下一轮行动。" % [effect.get("count", 1), UiStyle.label(str(effect.get("task", "")))]
	return UiStyle.describe_effects([effect])
