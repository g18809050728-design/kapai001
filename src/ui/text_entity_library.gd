class_name TextEntityLibrary
extends RefCounted

## Entity-first view over the flat text overrides. A field can own several
## override UIDs (for example a glossary name and its shared label); saving a
## field writes the same text to every UID and reset clears all of them.

const TYPE_ORDER := ["cards", "relics", "characters", "stories", "glossary", "monsters", "tutorial", "terms"]
const TYPE_NAMES := {
	"cards": "卡牌",
	"relics": "饰品",
	"characters": "人物",
	"stories": "剧情",
	"glossary": "词条",
	"monsters": "怪物",
	"tutorial": "教程",
	"terms": "其他",
}
const MONSTER_KIND_NAMES := {
	"normal": "普通",
	"elite": "精英",
	"boss": "首领",
	"auxiliary": "附属",
}
const OWNER_NAMES := {"C": "公共", "P01": "林序", "P02": "许知微", "P03": "沈见章", "P04": "唐以宁", "T": "衍生"}
const CARD_TYPE_NAMES := {
	"work": "作业",
	"strategy": "策略",
	"cooperation": "合作",
	"scene": "场景",
	"ability": "能力",
	"burden": "负担",
}
const RARITY_NAMES := {
	"basic": "初始",
	"common": "普通",
	"advanced": "进阶",
	"rare": "稀有",
	"uncommon": "少见",
	"starter": "初始",
	"white": "白色",
	"blue": "蓝色",
	"purple": "紫色",
	"gold": "金色",
}
const STORY_CATEGORIES := ["事件", "房间"]


static func build(catalog: ContentDB = null) -> GameResult:
	var db: ContentDB = catalog
	if db == null:
		db = ContentDB.new(TextLibrary.ROOT)
		var loaded := db.load(TextLibrary.MANIFEST)
		if not loaded.ok:
			return loaded
	if db.get_info() == null:
		return GameResult.failure(ApiError.new(&"CONTENT_INVALID", "text.entities.catalog.unavailable"))
	var flat := TextLibrary.build(db)
	if not flat.ok:
		return flat
	var entries: Array = flat.data.entries
	var by_uid: Dictionary = {}
	for entry in entries:
		by_uid[str(entry.uid)] = entry
	var assigned: Dictionary = {}
	var entities: Array[Dictionary] = []
	_add_cards(entities, by_uid, assigned, db)
	_add_relics(entities, by_uid, assigned, db)
	_add_characters(entities, by_uid, assigned, db)
	_add_stories(entities, by_uid, assigned, db)
	_add_glossary(entities, by_uid, assigned)
	_add_monsters(entities, by_uid, assigned, db)
	_add_tutorials(entities, by_uid, assigned)
	_add_terms(entities, by_uid, assigned)
	for entity in entities:
		entity["search"] = _entity_search(entity)
	entities.sort_custom(_entity_before)
	var counts: Dictionary = {"all": entities.size()}
	var field_count := 0
	var uid_count := 0
	var seen_uids: Dictionary = {}
	for entity in entities:
		counts[entity.type] = int(counts.get(entity.type, 0)) + 1
		for field in entity.fields:
			field_count += 1
			for uid in field.uids:
				if not seen_uids.has(uid):
					seen_uids[uid] = true
					uid_count += 1
	return GameResult.success(
		{
			"manifest_id": db.get_info().id,
			"content_hash": db.get_info().content_hash,
			"entities": entities,
			"counts": counts,
			"field_count": field_count,
			"uid_count": uid_count,
			"source_uid_count": entries.size(),
		}
	)


static func _add_cards(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary,
	catalog: ContentDB
) -> void:
	for id in catalog.get_candidates({"kind": "card"}):
		var result := catalog.get_definition("card", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var owner := str(definition.get("owner", "T"))
		var card_type := str(definition.get("type", ""))
		var rarity := str(definition.get("rarity", "common"))
		var entity := _entity(
			"card:" + str(id),
			"cards",
			"卡牌",
			_raw_label(str(id)),
			"%s · %s · %s · %s" % [
				str(id),
				str(OWNER_NAMES.get(owner, owner)),
				str(CARD_TYPE_NAMES.get(card_type, card_type)),
				str(RARITY_NAMES.get(rarity, rarity)),
			],
			{
				"owner": owner,
				"card_type": card_type,
				"rarity": rarity,
			},
			"卡牌名称与说明；考试面沿用基础/升级说明。只改显示文字。"
		)
		var name_entry: Variant = by_uid.get("label:" + str(id))
		if name_entry is Dictionary:
			entity.fields.append(
				_field(
					entity.id + ":name",
					"名称",
					["label:" + str(id)],
					str(name_entry.default),
					str(name_entry.source),
					"所有引用该卡牌 ID 的位置。",
					false,
					by_uid
				)
			)
			assigned["label:" + str(id)] = true
		for level in [0, 1]:
			for surface in ["detail", "battle", "battle_glossary"]:
				var uid := "card:%s:%d:%s" % [id, level, surface]
				var entry: Variant = by_uid.get(uid)
				if not entry is Dictionary:
					continue
				var suffix := str(
					{"detail": "说明", "battle": "战斗说明", "battle_glossary": "名词解释"}.get(surface, surface)
				)
				var label := ("升级" if level > 0 else "基础") + suffix
				entity.fields.append(
					_field(
						entity.id + ":%s_%d" % [surface, level],
						label,
						[uid],
						str(entry.default),
						str(entry.source),
						str(entry.note),
						true,
						by_uid
					)
				)
				assigned[uid] = true
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_relics(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary,
	catalog: ContentDB
) -> void:
	for id in catalog.get_candidates({"kind": "relic"}):
		var result := catalog.get_definition("relic", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var rarity := str(definition.get("rarity", "common"))
		var entity := _entity(
			"relic:" + str(id),
			"relics",
			"饰品",
			_raw_label(str(id)),
			"%s · %s · %s" % [str(id), str(RARITY_NAMES.get(rarity, rarity)), str(definition.get("availability", ""))],
			{"rarity": rarity},
			"饰品名称与说明；只改显示文字。"
		)
		_add_named_field(entity, by_uid, assigned, "label:" + str(id), "name", "名称", false, "所有引用该饰品 ID 的位置。")
		_add_named_field(entity, by_uid, assigned, "relic:" + str(id), "description", "说明", true, "饰品详情与提示中的说明。")
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_characters(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary,
	catalog: ContentDB
) -> void:
	for id in catalog.get_candidates({"kind": "character"}):
		var result := catalog.get_definition("character", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var passive_id := str(definition.get("passive", {}).get("id", ""))
		var entity := _entity(
			"character:" + str(id),
			"characters",
			"人物",
			_raw_label(str(id)),
			"%s · 人物" % str(id),
			{},
			"人物名称与被动说明；不改变触发条件或数值。"
		)
		_add_named_field(entity, by_uid, assigned, "label:" + str(id), "name", "名称", false, "选角、战斗和档案中的名称。")
		if not passive_id.is_empty():
			_add_named_field(
				entity,
				by_uid,
				assigned,
				"passive:" + passive_id,
				"passive",
				"被动说明",
				true,
				"人物被动说明；不改变触发条件或数值。"
			)
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_stories(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary,
	catalog: ContentDB
) -> void:
	var stories: Dictionary = CampusRoomIllustration.STORIES.data
	var event_stories: Dictionary = stories.get("events", {})
	for id in catalog.get_candidates({"kind": "event"}):
		var result := catalog.get_definition("event", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var story: Dictionary = event_stories.get(str(id), {})
		var entity := _entity(
			"story:events." + str(id),
			"stories",
			"事件",
			_raw_label(str(id)),
			"%s · 事件 · 第 %s 学年" % [str(id), "/".join(definition.get("terms", []).map(func(value): return str(value)))],
			{"story_kind": "事件", "terms": definition.get("terms", []).duplicate()},
			"事件标题、地点、叙述与所有选项标题；费用和效果仍由规则生成。"
		)
		var title_uids: Array[String] = []
		if by_uid.has("story:events.%s.title" % id):
			title_uids.append("story:events.%s.title" % id)
		if by_uid.has("label:" + str(id)):
			title_uids.append("label:" + str(id))
		if not title_uids.is_empty():
			_add_alias_field(
				entity,
				title_uids,
				"title",
				"事件标题",
				false,
				"事件页标题与剧情标题；保存时同步两个入口。",
				by_uid,
				assigned
			)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"story:events.%s.location" % id,
			"location",
			"地点",
			false,
			"事件插图中的地点文字。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"story:events.%s.narrative" % id,
			"narrative",
			"叙述",
			true,
			"事件主叙述；保留换行。"
		)
		var option_fields: Dictionary = {}
		for option in definition.get("options", []):
			var option_id := str(option.get("option_id", ""))
			if option_id.is_empty():
				continue
			var uid := "story:events.%s.option_titles.%s" % [id, option_id]
			var entry: Variant = by_uid.get(uid)
			var default_text: String = (
				str(entry.default)
				if entry is Dictionary
				else EventText.option_name(option_id, str(option.get("label_key", "")))
			)
			var source := (
				str(entry.source)
				if entry is Dictionary
				else "data/four_year/definitions/events.json"
			)
			var field := _field(
				entity.id + ":option_" + option_id,
				"选项 · " + default_text,
				[uid],
				default_text,
				source,
				"事件选项标题；只改显示文字，费用与效果不变。",
				false,
				by_uid
			)
			entity.fields.append(field)
			option_fields[option_id] = true
			assigned[uid] = true
		var story_options: Dictionary = story.get("option_titles", {})
		for option_id in story_options:
			if option_fields.has(str(option_id)):
				continue
			_add_named_field(
				entity,
				by_uid,
				assigned,
				"story:events.%s.option_titles.%s" % [id, option_id],
				"option_" + str(option_id),
				"选项 · " + str(story_options[option_id]),
				false,
				"事件选项标题；只改显示文字。"
			)
		if not entity.fields.is_empty():
			entities.append(entity)
	var room_stories: Dictionary = stories.get("rooms", {})
	for story_id in room_stories:
		var story: Dictionary = room_stories[story_id]
		if not story is Dictionary:
			continue
		var entity := _entity(
			"story:rooms." + str(story_id),
			"stories",
			"房间",
			str(story.get("title", story_id)),
			"%s · 房间" % str(story_id),
			{"story_kind": "房间"},
			"房间标题、地点与叙述；只改显示文字。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"story:rooms.%s.title" % story_id,
			"title",
			"标题",
			false,
			"房间标题。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"story:rooms.%s.location" % story_id,
			"location",
			"地点",
			false,
			"房间插图中的地点文字。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"story:rooms.%s.narrative" % story_id,
			"narrative",
			"叙述",
			true,
			"房间主叙述；保留换行。"
		)
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_glossary(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary
) -> void:
	for key in UiGlossary.ENTRIES:
		var source_entry: Dictionary = UiGlossary.ENTRIES[key]
		var entity := _entity(
			"glossary:" + str(key),
			"glossary",
			"词条",
			str(source_entry.get("name", key)),
			str(source_entry.get("type", "")),
			{"glossary_type": str(source_entry.get("type", ""))},
			"规则帮助/名词解释；名称与共享标签同步。"
		)
		var name_uids: Array[String] = []
		if by_uid.has("glossary:%s.name" % key):
			name_uids.append("glossary:%s.name" % key)
		if by_uid.has("label:" + str(key)):
			name_uids.append("label:" + str(key))
		if not name_uids.is_empty():
			_add_alias_field(
				entity,
				name_uids,
				"name",
				"名称",
				false,
				"词条名称与同名共享标签；保存时同步。",
				by_uid,
				assigned
			)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"glossary:%s.type" % key,
			"type",
			"分类",
			false,
			"词条分类。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"glossary:%s.short" % key,
			"short",
			"短说明",
			false,
			"规则帮助列表中的短说明。"
		)
		_add_named_field(
			entity,
			by_uid,
			assigned,
			"glossary:%s.body" % key,
			"body",
			"详细说明",
			true,
			"规则帮助详情中的完整说明。"
		)
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_monsters(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary,
	catalog: ContentDB
) -> void:
	for id in catalog.get_candidates({"kind": "task"}):
		var result := catalog.get_definition("task", id)
		if not result.ok:
			continue
		var definition: Dictionary = result.data
		var kind := str(definition.get("kind", "normal"))
		var terms: Array = definition.get("terms", [])
		var phases: Array = definition.get("phases", [])
		var phase_count: int = phases.size()
		var years := "/".join(terms.map(func(value): return str(value))) if not terms.is_empty() else "未记录"
		var year_text := ("第 %s 学年" % years) if not terms.is_empty() else "学年未记录"
		var entity := _entity(
			"monster:" + str(id),
			"monsters",
			str(MONSTER_KIND_NAMES.get(kind, kind)),
			_raw_label(str(id)),
			"%s · %s · %s · %d 阶段" % [
				str(id),
				str(MONSTER_KIND_NAMES.get(kind, kind)),
				year_text,
				phase_count,
			],
			{"kind": kind, "terms": terms.duplicate(), "phase_count": phase_count},
			"怪物名称、阶段名与意图名；数值、压力、阶段规则仍由规则生成。"
		)
		var name_uid := "label:" + str(id)
		var name_entry: Variant = by_uid.get(name_uid)
		entity.fields.append(
			_field(
				entity.id + ":name",
				"名称",
				[name_uid],
				str(name_entry.default) if name_entry is Dictionary else _raw_label(str(id)),
				str(name_entry.source) if name_entry is Dictionary else "data/four_year/definitions/tasks.json",
				"战斗、图鉴与提示中的怪物名称。",
				false,
				by_uid
			)
		)
		assigned[name_uid] = true
		var seen: Dictionary = {}
		var phase_index := 0
		for phase in phases:
			var phase_name_key := str(phase.get("name_key", ""))
			if not phase_name_key.is_empty():
				var phase_uid := "label:" + phase_name_key
				var phase_entry: Variant = by_uid.get(phase_uid)
				if phase_entry is Dictionary and not seen.has(phase_uid):
					entity.fields.append(
						_field(
							entity.id + ":phase_%d" % phase_index,
							"阶段 · " + str(phase_entry.default),
							[phase_uid],
							str(phase_entry.default),
							str(phase_entry.source),
							"怪物阶段名称；只改显示文字。",
							false,
							by_uid
						)
					)
					seen[phase_uid] = true
					assigned[phase_uid] = true
			phase_index += 1
		var intent_index := 0
		for phase in phases:
			for intent in phase.get("intents", []):
				var text_key := str(intent.get("text_key", ""))
				if text_key.is_empty():
					continue
				var intent_uid := "label:" + text_key
				var intent_entry: Variant = by_uid.get(intent_uid)
				if not intent_entry is Dictionary or seen.has(intent_uid):
					continue
				entity.fields.append(
					_field(
						entity.id + ":intent_%d" % intent_index,
						"意图 · " + str(intent_entry.default),
						[intent_uid],
						str(intent_entry.default),
						str(intent_entry.source),
						"怪物意图名称；只改显示文字，不改变压力、屏障或负面数值。",
						false,
						by_uid
					)
				)
				seen[intent_uid] = true
				assigned[intent_uid] = true
				intent_index += 1
		entities.append(entity)


static func _add_tutorials(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary
) -> void:
	var pages: Array = UiTutorialContent.entity_pages()
	for index in pages.size():
		var page: Dictionary = pages[index]
		var page_id := str(page.get("id", ""))
		if page_id.is_empty():
			continue
		var title_uid := UiTutorialContent.page_uid(page_id, "title")
		var title_entry: Variant = by_uid.get(title_uid)
		var title := str(title_entry.default) if title_entry is Dictionary else str(page.get("title", ""))
		var kind_label := UiTutorialContent.page_kind_label(page)
		var entity := _entity(
			"tutorial:" + page_id,
			"tutorial",
			kind_label,
			title,
			"%d / %d 页 · %s" % [index + 1, pages.size(), kind_label],
			{"tutorial_kind": kind_label, "page": index + 1},
			"新手教程显示文字；只改文案，不改变触发、指示位置或规则。"
		)
		_add_named_field(
			entity, by_uid, assigned, UiTutorialContent.page_uid(page_id, "chapter"),
			"chapter", "章节", false, "教程页眉中的章节名。"
		)
		_add_named_field(
			entity, by_uid, assigned, title_uid,
			"title", "标题", false, "教程页标题。"
		)
		_add_named_field(
			entity, by_uid, assigned, UiTutorialContent.page_uid(page_id, "body"),
			"body", "正文", true, "教程标题下的一句说明。"
		)
		var bullets: Array = page.get("bullets", [])
		for bullet_index in bullets.size():
			var bullet_label := "词条 %d" % (bullet_index + 1)
			_add_named_field(
				entity, by_uid, assigned,
				UiTutorialContent.bullet_uid(page_id, bullet_index, "term"),
				"bullet_%d_term" % bullet_index,
				bullet_label + " · 名词",
				false,
				"教程词条左侧的名词。"
			)
			_add_named_field(
				entity, by_uid, assigned,
				UiTutorialContent.bullet_uid(page_id, bullet_index, "text"),
				"bullet_%d_text" % bullet_index,
				bullet_label + " · 说明",
				false,
				"教程词条右侧的短说明。"
			)
		if page.has("next"):
			_add_named_field(
				entity, by_uid, assigned, UiTutorialContent.page_uid(page_id, "next"),
				"next", "末页按钮", false, "最后一页的主按钮文字。"
			)
		if not entity.fields.is_empty():
			entities.append(entity)


static func _add_terms(
	entities: Array[Dictionary],
	by_uid: Dictionary,
	assigned: Dictionary
) -> void:
	for uid in by_uid:
		if assigned.has(uid):
			continue
		var entry: Dictionary = by_uid[uid]
		var entity_id: String = (
			"term:" + uid.trim_prefix("label:")
			if str(uid).begins_with("label:")
			else "other:" + str(uid)
		)
		var entity := _entity(
			entity_id,
			"terms",
			str(entry.get("category", "其他")),
			str(entry.title),
			"%s · %s" % [str(entry.get("category", "其他")), str(uid)],
			{"label_category": str(entry.get("category", "其他"))},
			"未归属到五类主实体的名称/术语；保留以便继续编辑。"
		)
		entity.fields.append(
			_field(
				entity.id + ":text",
				"名称" if str(entry.group) == "names" else "文本",
				[uid],
				str(entry.default),
				str(entry.source),
				str(entry.note),
				false,
				by_uid
			)
		)
		assigned[uid] = true
		entities.append(entity)


static func _add_named_field(
	entity: Dictionary,
	by_uid: Dictionary,
	assigned: Dictionary,
	uid: String,
	local_key: String,
	label: String,
	multiline: bool,
	note: String
) -> void:
	if not by_uid.has(uid):
		return
	var entry: Dictionary = by_uid[uid]
	entity.fields.append(
		_field(
			entity.id + ":" + local_key,
			label,
			[uid],
			str(entry.default),
			str(entry.source),
			note,
			multiline,
			by_uid
		)
	)
	assigned[uid] = true


static func _add_alias_field(
	entity: Dictionary,
	uids: Array,
	local_key: String,
	label: String,
	multiline: bool,
	note: String,
	by_uid: Dictionary,
	assigned: Dictionary
) -> void:
	var defaults: Dictionary = {}
	var first: Dictionary = {}
	for uid in uids:
		if not by_uid.has(uid):
			continue
		var entry: Dictionary = by_uid[uid]
		defaults[uid] = str(entry.default)
		if first.is_empty():
			first = entry
		assigned[uid] = true
	if first.is_empty():
		return
	entity.fields.append(
		_field(
			entity.id + ":" + local_key,
			label,
			uids,
			str(first.default),
			str(first.source),
			note,
			multiline,
			by_uid,
			defaults
		)
	)


static func _field(
	key: String,
	label: String,
	uids: Array,
	default_text: String,
	source: String,
	note: String,
	multiline: bool,
	by_uid: Dictionary,
	uid_defaults: Dictionary = {}
) -> Dictionary:
	var defaults := uid_defaults.duplicate(true)
	if defaults.is_empty():
		for uid in uids:
			if by_uid.has(uid):
				defaults[uid] = str(by_uid[uid].default)
	return {
		"key": key,
		"label": label,
		"uids": uids,
		"default": default_text,
		"uid_defaults": defaults,
		"source": source,
		"note": note,
		"multiline": multiline,
	}


static func _entity(
	id: String,
	type: String,
	category: String,
	title: String,
	subtitle: String,
	meta: Dictionary,
	note: String
) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"type_label": str(TYPE_NAMES.get(type, type)),
		"category": category,
		"title": title,
		"subtitle": subtitle,
		"meta": meta,
		"note": note,
		"fields": [],
		"search": "",
	}


static func _entity_search(entity: Dictionary) -> String:
	var parts: PackedStringArray = [
		str(entity.title),
		str(entity.id),
		str(entity.subtitle),
		str(entity.category),
		str(entity.type_label),
	]
	for field in entity.fields:
		parts.append(str(field.label))
		parts.append(str(field.default))
		for uid in field.uids:
			parts.append(str(uid))
	return " ".join(parts).to_lower()


static func _entity_before(a: Dictionary, b: Dictionary) -> bool:
	var left_type := TYPE_ORDER.find(str(a.type))
	var right_type := TYPE_ORDER.find(str(b.type))
	if left_type != right_type:
		return left_type < right_type
	if str(a.type) == "tutorial" and str(b.type) == "tutorial":
		return int(a.meta.get("page", 0)) < int(b.meta.get("page", 0))
	if str(a.category) != str(b.category):
		return str(a.category) < str(b.category)
	if str(a.title) != str(b.title):
		return str(a.title) < str(b.title)
	return str(a.id) < str(b.id)


static func _raw_label(id: String) -> String:
	var labels: Dictionary = UiStyle.LABELS.data.get("labels", {})
	return str(labels.get(id, id))
