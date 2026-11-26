class_name TextLibrary
extends RefCounted

## Read-only inventory of display text used by the game. Entries never contain
## live run/session state; the editor stores only uid -> replacement strings.

const MANIFEST := RelicPilot.ROSTER
const ROOT := "res://data/four_year"
const CATEGORY_ORDER := [
	"人物", "卡牌", "任务 / 怪物", "饰品", "伙伴", "事件", "状态 / 术语",
	"场景 / 房间", "背景", "界面提示", "其他"
]


static func build(catalog: ContentDB = null) -> GameResult:
	var db: ContentDB = catalog
	if db == null:
		db = ContentDB.new(ROOT)
		var loaded := db.load(MANIFEST)
		if not loaded.ok:
			return loaded
	if db.get_info() == null:
		return GameResult.failure(ApiError.new(&"CONTENT_INVALID", "text.library.catalog.unavailable"))
	var entries: Array[Dictionary] = []
	_add_labels(entries, db)
	_add_stories(entries)
	_add_glossary(entries)
	var catalogue := CompendiumView.build(db)
	if not catalogue.ok:
		return catalogue
	_add_card_descriptions(entries, catalogue.data)
	_add_relic_descriptions(entries, db)
	_add_passive_descriptions(entries, db)
	entries.sort_custom(_entry_before)
	var counts := {"all": entries.size(), "names": 0, "descriptions": 0, "story": 0, "glossary": 0}
	for entry in entries:
		counts[entry.group] = int(counts.get(entry.group, 0)) + 1
	return GameResult.success(
		{
			"manifest_id": db.get_info().id,
			"content_hash": db.get_info().content_hash,
			"entries": entries,
			"counts": counts,
		}
	)


static func _add_labels(entries: Array[Dictionary], catalog: ContentDB) -> void:
	var labels: Dictionary = UiStyle.LABELS.data.get("labels", {})
	for key in labels:
		if RelicPilot.is_retired(str(key)) and not catalog.get_definition("relic", str(key)).ok:
			continue
		var value := str(labels[key])
		entries.append(
			_entry(
				"label:" + str(key),
				"names",
				_label_category(str(key)),
				str(key),
				value,
				value,
				"src/ui/ui_labels.json",
				"名称与术语；所有引用该 ID 的位置同步显示。"
			)
		)
	for id in catalog.get_candidates({"kind": "relic"}):
		if RelicPilot.is_rx(id) and not labels.has(id):
			var definition: Dictionary = catalog.get_definition("relic", id).data
			entries.append(_entry("label:" + id, "names", "饰品", id, definition.name_key,
				definition.name_key, _relic_source(catalog, id), "饰品名称；只影响显示文字。"))
	# UiStyle.label has a few built-in display words that never existed in the
	# JSON label table. Expose them so "any label text" is editable too.
	var builtins := {
		"basic": "初始",
		"common": "普通",
		"advanced": "进阶",
		"rare": "稀有",
		"uncommon": "少见",
		"starter": "初始",
		"ability": "能力",
	}
	for key in builtins:
		if labels.has(key):
			continue
		entries.append(
			_entry(
				"label:" + str(key),
				"names",
				"其他",
				str(key),
				str(builtins[key]),
				str(builtins[key]),
				"src/ui/ui_style.gd",
				"内置显示词条；只影响显示文字。"
			)
		)


static func _add_stories(entries: Array[Dictionary]) -> void:
	var sources: Dictionary = CampusRoomIllustration.STORIES.data
	for group in ["events", "rooms"]:
		var stories: Dictionary = sources.get(group, {})
		for story_id in stories:
			var story: Dictionary = stories[story_id]
			if not story is Dictionary:
				continue
			var title := str(story.get("title", story_id))
			var category := "事件" if group == "events" else "房间"
			for field in ["title", "location", "narrative"]:
				if not story.get(field) is String:
					continue
				var suffix: String = {"title": "标题", "location": "地点", "narrative": "叙述"}[field]
				entries.append(
					_entry(
						"story:%s.%s.%s" % [group, story_id, field],
						"story",
						category,
						str(story_id),
						"%s · %s" % [title, suffix],
						str(story[field]),
						"src/ui/room_stories.json",
						"主菜单/事件页中的剧情文本；只影响显示文字。"
					)
				)
			var option_titles: Dictionary = story.get("option_titles", {})
			for option in option_titles:
				entries.append(
					_entry(
						"story:%s.%s.option_titles.%s" % [group, story_id, option],
						"story",
						category,
						str(story_id),
						"%s · 选项「%s」" % [title, str(option_titles[option])],
						str(option_titles[option]),
						"src/ui/room_stories.json",
						"事件选项标题；只影响显示文字。"
					)
				)


static func _add_glossary(entries: Array[Dictionary]) -> void:
	var glossary: Dictionary = UiGlossary.ENTRIES
	for key in glossary:
		var entry: Dictionary = glossary[key]
		var name := str(entry.get("name", key))
		for field in ["name", "type", "short", "body"]:
			if not entry.get(field) is String:
				continue
			var suffix: String = {"name": "名称", "type": "分类", "short": "短说明", "body": "详细说明"}[field]
			entries.append(
				_entry(
					"glossary:%s.%s" % [key, field],
					"glossary",
					"词条",
					str(key),
					"%s · %s" % [name, suffix],
					str(entry[field]),
					"src/ui/ui_glossary.gd",
					"规则帮助/名词解释；只影响显示文字。"
				)
			)


static func _add_card_descriptions(entries: Array[Dictionary], catalogue: Dictionary) -> void:
	for card in catalogue.get("cards", []):
		var name := _raw_label(str(card.id))
		for variant in card.get("variants", []):
			if bool(variant.get("exam", false)):
				continue
			var level := int(variant.get("level", 0))
			var face: Dictionary = variant.get("face", {})
			var suffix := "升级" if level > 0 else "基础"
			entries.append(
				_entry(
					"card:%s:%d:detail" % [card.id, level],
					"descriptions",
					"卡牌",
					str(card.id),
					"%s · %s说明" % [name, suffix],
					UiContentText.describe_card_default(face),
					"data/four_year/definitions/cards.json",
					"图鉴、牌组与奖励中的完整卡牌说明；不改变效果、费用或规则。"
				)
			)
			entries.append(
				_entry(
					"card:%s:%d:battle" % [card.id, level],
					"descriptions",
					"卡牌",
					str(card.id),
					"%s · %s战斗说明" % [name, suffix],
					UiContentText.describe_battle_card_default(face),
					"data/four_year/definitions/cards.json",
					"战斗内逐步说明；不改变结算顺序、数值或规则。"
				)
			)


static func _add_relic_descriptions(entries: Array[Dictionary], catalog: ContentDB) -> void:
	for id in catalog.get_candidates({"kind": "relic"}):
		var result := catalog.get_definition("relic", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		entries.append(
			_entry(
				"relic:" + str(id),
				"descriptions",
				"饰品",
				str(id),
				str(definition.name_key) + " · 说明",
				UiContentText.describe_relic_default(definition),
				_relic_source(catalog, id),
				"饰品详情与提示中的说明；只影响显示文字。"
			)
		)


static func _relic_source(catalog: ContentDB, id: String) -> String:
	if not RelicPilot.is_rx(id):
		return "data/four_year/definitions/relics.json"
	return "data/four_year/%s/definitions.json" % ("relic_pilot" if catalog.get_info().id == RelicPilot.MANIFEST else "relic_roster")


static func _add_passive_descriptions(entries: Array[Dictionary], catalog: ContentDB) -> void:
	for id in catalog.get_candidates({"kind": "character"}):
		var result := catalog.get_definition("character", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var passive: Dictionary = definition.get("passive", {})
		var passive_id := str(passive.get("id", ""))
		if passive_id.is_empty():
			continue
		entries.append(
			_entry(
				"passive:" + passive_id,
				"descriptions",
				"人物",
				str(id),
				_raw_label(str(id)) + " · 被动说明",
				UiContentText.describe_character_passive_default(passive_id),
				"data/four_year/definitions/characters.json",
				"人物被动说明；不改变触发条件或数值。"
			)
		)


static func _entry(
	uid: String,
	group: String,
	category: String,
	id: String,
	title: String,
	text: String,
	source: String,
	note: String
) -> Dictionary:
	return {
		"uid": uid,
		"group": group,
		"category": category,
		"id": id,
		"title": title,
		"default": TextOverrides.default_text(uid, text),
		"source": source,
		"note": note,
	}


static func _raw_label(id: String) -> String:
	var labels: Dictionary = UiStyle.LABELS.data.get("labels", {})
	return str(labels.get(id, id))


static func _label_category(key: String) -> String:
	if key.begins_with("character.") or (key.begins_with("P0") and key.length() <= 3):
		return "人物"
	if key.begins_with("unit.") or (key.begins_with("F0") and key.length() <= 3):
		return "伙伴"
	if key.begins_with("FY_Y"):
		return "饰品"
	if key.begins_with("R3-") or key.begins_with("K") or key.begins_with("X"):
		return "卡牌"
	if key.begins_with("task.") or key.begins_with("encounter."):
		return "任务 / 怪物"
	if key.begins_with("N") or key.begins_with("Q0") or key.begins_with("B0") or key.begins_with("E0"):
		return "任务 / 怪物"
	if key.begins_with("FY_B") or key.begins_with("FY_ROUTE") or key.begins_with("NR"):
		return "任务 / 怪物"
	if key.begins_with("A") and key.length() == 3 and key.substr(1).is_valid_int():
		return "饰品"
	if key.begins_with("event.") or (key.begins_with("V") and key.length() <= 3):
		return "事件"
	if key.begins_with("scene.") or key in ["L", "L01", "L02", "L03", "LAB", "T", "C", "I", "ST", "FAMILIAR"]:
		return "场景 / 房间"
	if key.begins_with("status.") or key in [
		"inspiration", "anxiety", "procrastination", "drowsiness",
		"guard", "erosion", "induced", "brittle", "feebleness", "weakness", "vulnerability",
		"focus", "vitality", "relax", "ddl", "synergy", "paper_open", "paper_progress",
		"paper_citation", "paper_modifier", "paper_amplify", "paper_publish", "retrieve",
		"exhaust", "retain", "chapter_deploy", "chapter_run", "chapter_return",
		"swap_chapter_slots", "copy_chapter_to_hand", "change_topic", "gain_synergy",
		"spend_synergy", "summon_partner", "partner_extra_action", "partner_heal",
		"partner_retreat", "complete", "shield", "pressure", "negative"
	]:
		return "状态 / 术语"
	if key.begins_with("BG_"):
		return "背景"
	if key.begins_with("choice."):
		return "界面提示"
	return "其他"


static func _entry_before(a: Dictionary, b: Dictionary) -> bool:
	var group_rank := {"names": 0, "descriptions": 1, "story": 2, "glossary": 3}
	var left_group := int(group_rank.get(a.get("group", ""), 9))
	var right_group := int(group_rank.get(b.get("group", ""), 9))
	if left_group != right_group:
		return left_group < right_group
	var left_category := CATEGORY_ORDER.find(str(a.get("category", "")))
	var right_category := CATEGORY_ORDER.find(str(b.get("category", "")))
	if left_category < 0:
		left_category = CATEGORY_ORDER.size()
	if right_category < 0:
		right_category = CATEGORY_ORDER.size()
	if left_category != right_category:
		return left_category < right_category
	if str(a.get("title", "")) != str(b.get("title", "")):
		return str(a.get("title", "")) < str(b.get("title", ""))
	return str(a.get("uid", "")) < str(b.get("uid", ""))
