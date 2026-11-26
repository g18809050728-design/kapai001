class_name CompendiumText
extends RefCounted

const RELIC_RARITY_NAMES := {"white": "白色", "blue": "蓝色", "purple": "紫色", "gold": "金色"}
const KIND_NAMES := {"normal": "普通", "elite": "精英", "boss": "首领", "auxiliary": "附属"}
const OWNER_NAMES := {"C": "公共", "P01": "林序", "P02": "许知微", "P03": "沈见章", "P04": "唐以宁", "T": "衍生"}
const PHASE_NAMES := {"main": "主阶段", "big_project": "大作业", "choice_questions": "选择题", "code": "代码实现", "coding": "编码", "defense": "答辩", "demo": "演示", "documentation": "文档", "essay_questions": "论述题", "extra_requirement_1": "追加需求一", "extra_requirement_2": "追加需求二", "fill_blank": "填空题", "followup": "追问", "independent_answer": "独立作答", "integrate": "整合", "interrogation": "质询", "interview_round": "面试", "materials_review": "材料复核", "modeling": "建模", "paper": "论文", "paperwork": "材料整理", "requirements": "需求梳理", "retake": "补考", "retake_defense": "补考答辩", "retake_written": "补考笔试", "score_review": "成绩复核", "self_intro": "自我介绍", "split": "任务拆分", "test_run": "试运行", "written_test": "笔试"}


static func title(entry: Dictionary, monster: bool = false) -> String:
	if monster:
		return UiStyle.label(str(entry.definition.get("name_key", entry.id)))
	var id: String = entry.id
	var name := UiStyle.label(id)
	if name == id:
		name = UiStyle.label(str(entry.definition.get("name_key", id)))
	return name.split("：")[0]


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
	if RELIC_RARITY_NAMES.has(value):
		return RELIC_RARITY_NAMES[value]
	return "衍生" if value == "token" else UiStyle.label(value)


static func years(terms: Array) -> String:
	var result: PackedStringArray = []
	var labels := ["大一", "大二", "大三", "大四"]
	for term in terms:
		var index := int(term) - 1
		if index >= 0 and index < labels.size() and not result.has(labels[index]):
			result.append(labels[index])
	return " / ".join(result)


static func card_text(variant: Dictionary) -> String:
	var face: Dictionary = variant.face
	var text := UiContentText.describe_card_default(face) if variant.get("test_override", false) else UiContentText.describe_card(face)
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


static func relic_group(entry: Dictionary) -> String:
	return str(entry.definition.get("rx", {}).get("owner", "C"))


static func relic_text(entry: Dictionary) -> String:
	return UiContentText.describe_relic_default(entry.definition) if entry.get("test_override", false) else UiContentText.describe_relic(entry.definition)


static func relic_group_text(entry: Dictionary) -> String:
	var group := relic_group(entry)
	return "通用" if group == "C" else str(OWNER_NAMES.get(group, group)) + "专属"


static func relic_source(entry: Dictionary) -> String:
	var result := "地图学年饰品奖励 · " + years(entry.terms)
	if entry.id == "RX-C22":
		result += "。仅当前学年仍可到达独立作答或固定考场时出现。"
	elif entry.id == "RX-P04-12":
		result += "。仅唐以宁且本学年仍可到达独立作答时出现。"
	elif relic_group(entry) != "C":
		result += "。只进入对应角色的奖励池。"
	return result


static func monster_sections(entry: Dictionary) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var definition: Dictionary = entry.definition
	var status_rules: Dictionary = entry.get("status_rules", {})
	var mechanics := TaskIntentText.traits(definition)
	if not mechanics.is_empty():
		sections.append({"title": "特殊机制", "text": "\n".join(mechanics)})
	var phases: Array = definition.get("phases", [])
	for index in phases.size():
		var phase: Dictionary = phases[index]
		var phase_title := UiStyle.label(str(phase.name_key)) if phase.has("name_key") else str(PHASE_NAMES.get(phase.get("phase_key", ""), "任务阶段"))
		var lines: PackedStringArray = []
		lines.append("基础未完成量 %s" % phase.get("work_max", 0))
		for step in phase.get("intents", []).size():
			var intent: Dictionary = phase.intents[step]
			var intent_name := UiStyle.label(str(intent.get("text_key", "意图")))
			lines.append("\n%s. %s\n%s" % [step + 1, intent_name, TaskIntentText.describe(intent, {}, status_rules)])
		lines.append("\n" + TaskIntentText.sequence_rule(phase))
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
