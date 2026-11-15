class_name CompendiumText
extends RefCounted

const KIND_NAMES := {"normal": "普通", "elite": "精英", "boss": "首领", "auxiliary": "附属"}
const OWNER_NAMES := {"C": "公共", "P01": "林序", "P02": "许知微", "P03": "沈见章", "P04": "唐以宁", "T": "衍生"}
const TYPE_NAMES := {"work": "作业", "strategy": "策略", "cooperation": "合作", "scene": "场景", "ability": "能力", "burden": "负担"}
const PHASE_NAMES := {"main": "主阶段", "big_project": "大作业", "choice_questions": "选择题", "code": "代码实现", "coding": "编码", "defense": "答辩", "demo": "演示", "documentation": "文档", "essay_questions": "论述题", "extra_requirement_1": "追加需求一", "extra_requirement_2": "追加需求二", "fill_blank": "填空题", "followup": "追问", "independent_answer": "独立作答", "integrate": "整合", "interrogation": "质询", "interview_round": "面试", "materials_review": "材料复核", "modeling": "建模", "paper": "论文", "paperwork": "材料整理", "requirements": "需求梳理", "retake": "补考", "retake_defense": "补考答辩", "retake_written": "补考笔试", "score_review": "成绩复核", "self_intro": "自我介绍", "split": "任务拆分", "test_run": "试运行", "written_test": "笔试"}


static func title(entry: Dictionary, monster: bool = false) -> String:
	if monster:
		return UiStyle.label(str(entry.definition.get("name_key", entry.id)))
	return UiStyle.label(str(entry.id)).split("：")[0]


static func owner(entry: Dictionary) -> String:
	if not bool(entry.definition.get("permanent", true)):
		return "T"
	return str(entry.definition.get("owner", "T"))


static func kind(entry: Dictionary) -> String:
	var text := str(KIND_NAMES.get(entry.definition.get("kind", "normal"), "普通"))
	if not bool(entry.definition.get("victory_required", true)):
		text += " · 附属"
	return text


static func rarity(entry: Dictionary) -> String:
	var value := str(entry.definition.get("rarity", "common"))
	return "衍生" if value == "token" else UiStyle.label(value)


static func years(terms: Array) -> String:
	var result: PackedStringArray = []
	for term in terms:
		result.append("大" + ["一", "二", "三", "四"][clampi(int(term) - 1, 0, 3)])
	return " / ".join(result)


static func card_text(variant: Dictionary) -> String:
	var face: Dictionary = variant.face
	var text := UiContentText.describe_card(face)
	var keyword_help := UiContentText.keyword_help(face)
	if not keyword_help.is_empty():
		text += "\n\n名词解释\n" + keyword_help
	if not bool(face.get("permanent", true)):
		text += "\n\n战斗衍生牌：由对应机制生成，不属于永久起始牌组或普通授牌卡池。"
	if not bool(face.get("flags", {}).get("upgradable", true)):
		text += "\n不可通过常规升级服务升级。"
	if variant.get("exam", false):
		text += "\n\n当前为考试替代面，只在对应考试标签生效时使用。"
	return text


static func variant_name(variant: Dictionary) -> String:
	return ("考试 · " if variant.get("exam", false) else "") + ("升级" if int(variant.level) > 0 else "基础")


static func monster_sections(entry: Dictionary) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var definition: Dictionary = entry.definition
	var mechanics: PackedStringArray = []
	if not bool(definition.get("victory_required", true)):
		mechanics.append("附属任务：不要求完成它即可满足该场战斗的任务完成条件。")
	for field in ["shield_persistent", "self_copy_every_round", "taunt"]:
		if definition.get(field, false):
			mechanics.append(str({"shield_persistent": "持久屏障：屏障不按普通任务的回合规则清除。", "self_copy_every_round": "每回合复制：生成一个同种任务。", "taunt": "嘲讽：存活时限制其他任务作为出牌目标。"}[field]))
	for field in ["draw_reduction", "first_card_cost_bonus", "discard_on_first_card", "max_vitality_reduction"]:
		if int(definition.get(field, 0)) > 0:
			mechanics.append(str({"draw_reduction": "在场时，准备阶段抽牌减少 %s 张。", "first_card_cost_bonus": "在场时，每回合首张牌的专注费用增加 %s。", "discard_on_first_card": "在场时，每回合首张牌触发弃牌 %s 张。", "max_vitality_reduction": "在场时，每次我方准备阶段精力上限减少 %s（最低为1）。"}[field]) % definition[field])
	if not definition.get("on_complete_effects", []).is_empty():
		mechanics.append("完成后：" + UiStyle.describe_effects(definition.on_complete_effects))
	if not mechanics.is_empty():
		sections.append({"title": "特殊机制", "text": "\n".join(mechanics)})
	var phases: Array = definition.get("phases", [])
	for index in phases.size():
		var phase: Dictionary = phases[index]
		var phase_title := UiStyle.label(str(phase.name_key)) if phase.has("name_key") else str(PHASE_NAMES.get(phase.get("phase_key", ""), "任务阶段"))
		var lines: PackedStringArray = []
		lines.append("基础工作量 %s" % phase.get("work_max", 0))
		lines.append("意图按下列顺序循环。" if phase.get("intent_loop", "cycle") == "cycle" else "按顺序执行后，重复最后一个意图。")
		for step in phase.get("intents", []).size():
			var intent: Dictionary = phase.intents[step]
			var intent_name := UiStyle.label(str(intent.get("text_key", "意图")))
			lines.append("\n%s. %s\n%s" % [step + 1, intent_name, intent_text(intent)])
		sections.append({"title": "阶段 %s / %s · %s" % [index + 1, phases.size(), phase_title], "text": "\n".join(lines)})
	var sources: PackedStringArray = []
	for source in entry.get("sources", []):
		var source_text := "%s · %s · 基础DDL %s" % [UiStyle.label(str(source.get("name_key", source.id))), years(source.get("terms", [])), source.get("base_ddl", 0)]
		if not source.get("exam_flags", []).is_empty():
			source_text += " · 考试"
		sources.append(source_text)
	for parent in entry.get("parents", []):
		sources.append(str({"summon": "由 %s 召唤", "transform": "由 %s 转化", "on_complete": "%s 完成后生成"}.get(parent.kind, "来自 %s")) % UiStyle.label(str(parent.id)))
	sections.append({"title": "出现来源", "text": "\n".join(sources) if not sources.is_empty() else "正式内容目录收录；未配置直接遭遇。"})
	return sections


static func intent_text(intent: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in ["pressure", "shield", "work_restore", "player_gain_focus", "player_reduce_focus", "ddl_bonus"]:
		if intent.has(key):
			parts.append(str({"pressure": "基础压力 %s", "shield": "屏障 %s", "work_restore": "恢复工作量 %s", "player_gain_focus": "我方专注 +%s", "player_reduce_focus": "我方专注 -%s", "ddl_bonus": "DDL +%s"}[key]) % intent[key])
	if int(intent.get("pressure_times", 1)) > 1:
		parts.append("压力结算 %s 次" % intent.pressure_times)
	if intent.get("pressure_all", false):
		parts.append("压力作用于全体")
	if int(intent.get("pressure_per_unit", 0)) > 0:
		parts.append("每位在场伙伴增加压力 %s%s" % [intent.pressure_per_unit, "（最多增加 %s）" % intent.pressure_per_unit_cap if intent.has("pressure_per_unit_cap") else ""])
	if int(intent.get("pressure_per_vitality", 0)) > 0:
		parts.append("我方每 %s 精力增加压力 %s" % [intent.get("pressure_vitality_step", 10), intent.pressure_per_vitality])
	if int(intent.get("pressure_when_shield", 0)) > 0:
		parts.append("有屏障时压力 +%s" % intent.pressure_when_shield)
	for key in ["pressure_has_unit_mult", "pressure_no_unit_mult"]:
		if intent.has(key):
			parts.append(("有伙伴时压力 ×%s%%" if key == "pressure_has_unit_mult" else "无伙伴时压力 ×%s%%") % intent[key])
	for card_type in intent.get("pressure_per_card_type", {}):
		parts.append("本场每打出一张%s，压力 +%s" % [TYPE_NAMES.get(card_type, card_type), intent.pressure_per_card_type[card_type]])
	if intent.has("gain_status"):
		var status: Dictionary = intent.gain_status
		parts.append("%s获得%s %s层" % ["我方" if status.get("target", "player") == "player" else "自身", UiStyle.label(str(status.get("status", ""))), status.get("stacks", 1)])
	if intent.has("add_card"):
		var card: Dictionary = intent.add_card
		parts.append("向%s加入 %s ×%s" % [{"draw": "抽牌堆", "discard": "弃牌堆", "hand": "手牌"}.get(card.get("zone", "discard"), card.get("zone", "")), UiStyle.label(str(card.get("card", ""))), card.get("count", 1)])
	for spec in intent.get("summon_tasks", []):
		parts.append("召唤 %s ×%s（每场战斗一次）" % [UiStyle.label(str(spec.get("task", ""))), spec.get("count", 1)])
	if intent.has("transform_task"):
		parts.append("转化为 " + UiStyle.label(str(intent.transform_task.get("task", ""))))
	if intent.get("self_destruct", false):
		parts.append("执行后自行退场")
	return "；".join(parts) if not parts.is_empty() else "无额外数值效果"
