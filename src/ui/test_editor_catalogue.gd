extends RefCounted

const YEARS := {"1": "大一", "2": "大二", "3": "大三", "4": "大四"}
const CARD_TYPES := {"work": "作业", "strategy": "策略", "cooperation": "合作", "scene": "场景", "ability": "能力", "burden": "负担"}
const CARD_RARITY := {"basic": "初始", "common": "普通", "advanced": "进阶", "rare": "稀有", "token": "衍生"}
const TARGETS := {"player": "主角", "task": "敌怪", "unit": "伙伴"}
const UNIT_ROLES := {"guard": "护卫", "support": "支援", "cooperation": "合作"}
const SCENE_TYPES := {"prepare_effects": "准备效果", "prepare_random": "随机效果", "modifiers": "持续修正"}
const FILTERS := {
	"cards": [
		["owner", "人物", CompendiumText.OWNER_NAMES], ["type", "牌型", CARD_TYPES],
		["rarity", "稀有度", CARD_RARITY], ["cost", "专注", {"0": "0", "1": "1", "2": "2", "3+": "3 及以上"}],
	],
	"tasks": [["kind", "类别", CompendiumText.KIND_NAMES], ["year", "学年", YEARS]],
	"encounters": [["kind", "类别", CompendiumText.KIND_NAMES], ["year", "学年", YEARS], ["formation", "编组", {"fixed": "固定", "random": "随机"}]],
	"units": [["role", "职责", UNIT_ROLES]],
	"relics": [["owner", "归属", CompendiumText.OWNER_NAMES], ["rarity", "品质", CompendiumText.RELIC_RARITY_NAMES], ["year", "学年", YEARS]],
	"statuses": [["target", "目标", TARGETS], ["group", "类别", {"negative": "负面", "other": "其他状态"}]],
	"scenes": [["type", "类别", SCENE_TYPES]],
}
const GLYPHS := {"cards": "work", "tasks": "pressure", "encounters": "pressure", "units": "partner", "relics": "stamp", "statuses": "status", "scenes": "scene"}


static func build(options: Dictionary) -> Dictionary:
	var reference: Dictionary = options.get("reference", {})
	var references := {}
	for group in ["cards", "monsters", "relics"]:
		for entry in reference.get(group, []):
			references[entry.id] = entry
	var catalogue := {}
	for kind in FILTERS:
		var entries: Array[Dictionary] = []
		for option in options.get(kind, []):
			entries.append(_entry(kind, option, references.get(option.id, {}), options.ruleset))
		catalogue[kind] = entries
	return catalogue


static func matches(entry: Dictionary, query: String, filters: Dictionary) -> bool:
	var search: String = entry.search
	for word in query.to_lower().replace("　", " ").strip_edges().split(" ", false):
		if not search.contains(word):
			return false
	for key in filters:
		if not str(filters[key]).is_empty() and not entry.facets.get(key, []).has(filters[key]):
			return false
	return true


static func _entry(kind: String, option: Dictionary, reference: Dictionary, rules: Dictionary) -> Dictionary:
	var id: String = option.id
	var definition: Dictionary = option.definition
	var title := name_of(definition, id)
	var art := id
	var glyph: String = GLYPHS[kind]
	var facets := {}
	var details := PackedStringArray()
	var summary := ""
	var meta := ""
	match kind:
		"cards":
			var entry := {"id": id, "definition": definition}
			var cost := int(option.cost)
			facets = {"owner": [CompendiumText.owner(entry)], "type": [str(option.type)], "rarity": [str(option.rarity)], "cost": [str(cost) if cost < 3 else "3+"]}
			meta = "%s 专注" % cost
			var variants: Array = reference.get("variants", [{"level": 0, "exam": false, "face": definition}])
			for variant in variants:
				var face: Dictionary = variant.face
				if summary.is_empty():
					summary = UiContentText.card_summary(face)
				details.append(CompendiumText.variant_name(variant) + "\n" + UiContentText.describe_card_default(face))
		"tasks":
			var task := reference if not reference.is_empty() else {"id": id, "definition": definition, "status_rules": rules.get("statuses", {})}
			facets = {"kind": [option.kind], "year": _year_keys(task.get("terms", []))}
			if not definition.get("victory_required", true):
				facets.kind.append("auxiliary")
			for section in CompendiumText.monster_sections(task):
				details.append(section.title + "\n" + section.text)
			var traits := TaskIntentText.traits(definition)
			var phases: Array = definition.get("phases", [])
			var intents: Array = phases[0].get("intents", []) if not phases.is_empty() else []
			if not traits.is_empty():
				summary = str(traits[0])
			elif not intents.is_empty():
				summary = TaskIntentText.describe(intents[0], {}, rules.get("statuses", {}))
			meta = "基础未完成量 %s" % option.work_max
		"encounters":
			var members: Array = option.members
			if not members.is_empty():
				art = str(members[0]) if not definition.has("spawn") else ""
			facets = {"kind": [option.kind], "year": _year_keys(definition.get("terms", [])), "formation": ["random" if definition.has("spawn") else "fixed"]}
			meta = "基础 DDL %s" % option.base_ddl
			var member_names: PackedStringArray = []
			for member in members:
				member_names.append("%s（%s）" % [UiStyle.label(str(member)), str(member)])
			summary = ("候选成员 " if definition.has("spawn") else "成员 ") + "、".join(member_names)
			details.append(summary)
			if not definition.get("exam_flags", []).is_empty():
				details.append("考试条件 " + "、".join(definition.exam_flags.map(func(flag): return UiStyle.label(str(flag)))))
		"units":
			var roles: Array = ["cooperation"]
			if definition.get("guard", false):
				roles.append("guard")
			if definition.get("support", {}).get("kind", "none") != "none":
				roles.append("support")
			facets = {"role": roles}
			var lines := UiContentText.unit_details(definition)
			meta = lines[0] if not lines.is_empty() else ""
			for index in range(1, lines.size()):
				details.append(lines[index])
		"relics":
			var entry := {"id": id, "definition": definition}
			facets = {"owner": [CompendiumText.relic_group(entry)], "rarity": [str(option.rarity)], "year": _year_keys(reference.get("terms", []))}
			summary = UiContentText.describe_relic_default(definition)
			details.append(summary)
		"statuses":
			art = ""
			glyph = BattleStatusSlot.GLYPHS.get(id, "status")
			var negative := id in BattleStatusSlot.NEGATIVES
			facets = {"target": [option.target], "group": ["negative" if negative else "other"]}
			title = UiGlossary.label(id) if UiGlossary.ENTRIES.has(id) else title
			if UiGlossary.ENTRIES.has(id):
				var glossary: Dictionary = UiGlossary.ENTRIES[id]
				summary = TextOverrides.text("glossary:" + id + ".short", glossary.short)
				details.append(summary)
				details.append(TextOverrides.text("glossary:" + id + ".body", glossary.body))
			var numeric_key := str(definition.get("numeric_rule_key", id))
			var values: Dictionary = rules.get("statuses", {}).get(numeric_key, {})
			if values.has("cap"):
				details.append("层数上限 %s" % values.cap)
		"scenes":
			facets = {"type": SCENE_TYPES.keys().filter(func(key): return definition.has(key))}
			details.append_array(UiContentText.scene_details(definition))
	var tags := PackedStringArray()
	for filter in FILTERS[kind]:
		var labels: Dictionary = filter[2]
		for value in facets.get(filter[0], []):
			var label := str(labels.get(value, UiStyle.label(str(value))))
			if not label.is_empty() and filter[0] != "cost":
				tags.append(label)
	if not meta.is_empty():
		tags.append(meta)
	var full := "\n\n".join(details).strip_edges()
	if summary.strip_edges().is_empty():
		summary = full.split("\n", false, 1)[0] if not full.is_empty() else ""
	return {
		"id": id, "title": title, "art": art, "glyph": glyph, "tags": " · ".join(tags),
		"summary": summary.strip_edges(), "details": full, "facets": facets,
		"search": " ".join([id, title, option.name_key, " ".join(tags), summary, full]).to_lower(),
	}


static func name_of(definition: Dictionary, id: String) -> String:
	var label := UiStyle.label(id)
	var name_key := str(definition.get("name_key", id))
	var from_key := UiStyle.label(name_key)
	return from_key if from_key != name_key or label == id or not name_key.contains(".") else label


static func _year_keys(terms: Array) -> Array:
	var years: Array = []
	for term in terms:
		var key := str(int(term))
		if YEARS.has(key) and not years.has(key):
			years.append(key)
	return years
