class_name CompendiumView
extends RefCounted

## A definition snapshot. Never receives a live session, run, RNG, or save store.
static func build(catalog: ContentDB, include_all_cards: bool = false) -> GameResult:
	var info := catalog.get_info()
	if info == null:
		return GameResult.failure(ApiError.new(&"CONTENT_INVALID", "compendium.catalog.unavailable"))
	var ruleset := catalog.get_definition("ruleset", info.ruleset_id)
	if not ruleset.ok:
		return ruleset
	var status_rules: Dictionary = ruleset.data.get("statuses", {})
	var cards: Array[Dictionary] = []
	var monsters: Array[Dictionary] = []
	var resolver := BattleCardRules.new(catalog)
	var overlay: TestOverlay = catalog.overlay if catalog is TestContent else null
	var card_ids := catalog.get_candidates({"kind": "card"})
	if include_all_cards:
		for id in info.enabled.get("card", []):
			if not card_ids.has(str(id)):
				card_ids.append(str(id))
		card_ids.sort()
	for id in card_ids:
		var definition := catalog.get_definition("card", id)
		if not definition.ok:
			return definition
		var entry := {"id": id, "definition": definition.data, "variants": []}
		var has_upgrade: bool = not definition.data.get("upgrade", {}).is_empty()
		var upgradable := bool(definition.data.get("flags", {}).get("upgradable", has_upgrade))
		var levels := [0, 1] if upgradable and (overlay == null or has_upgrade) else [0]
		var exam: Dictionary = definition.data.get("exam", {})
		for exam_mode in [false, true] if not exam.is_empty() else [false]:
			for level in levels:
				var state := BattleState.new({"card_by_id": {id: {"definition_id": id, "upgrade_level": level}}})
				if exam_mode:
					state.exam_flags.assign([str(exam.get("condition", ""))])
				var resolved := resolver.resolve_face(state, id)
				if not resolved.ok:
					return resolved
				var face: Dictionary = resolved.data
				face.related_units = {}
				face.related_scenes = {}
				_attach_related(catalog, resolved.data.duplicate(true), face)
				entry.variants.append({"level": level, "exam": exam_mode, "face": face, "test_override": _overrides(overlay, "card", id)})
		cards.append(entry)
	var encounters: Array[Dictionary] = []
	for id in catalog.get_candidates({"kind": "encounter"}):
		encounters.append(catalog.get_definition("encounter", id).data)
	# A grouped normal encounter draws from the normal solo pool for the current year.
	var solo_years := {}
	for encounter in encounters:
		if encounter.get("kind") != "normal" or encounter.has("spawn"):
			continue
		for member in encounter.get("members", []):
			if not solo_years.has(member):
				solo_years[member] = []
			for year in encounter.get("terms", []):
				if int(year) in [1, 2, 3, 4] and not solo_years[member].has(year):
					solo_years[member].append(year)
	var by_id: Dictionary = {}
	for id in catalog.get_candidates({"kind": "task"}):
		var definition: Dictionary = catalog.get_definition("task", id).data
		var entry := {"id": id, "definition": definition, "sources": [], "parents": [], "terms": [], "status_rules": status_rules.duplicate(true)}
		for encounter in encounters:
			if not encounter.get("members", []).has(id):
				continue
			var years: Array = encounter.get("terms", []).filter(func(year): return int(year) in [1, 2, 3, 4])
			if encounter.has("spawn"):
				years = years.filter(func(year): return solo_years.get(id, []).has(year))
				if years.is_empty():
					continue
			var source := encounter.duplicate(true)
			source.terms = years
			entry.sources.append(source)
			for year in years:
				if not entry.terms.has(year):
					entry.terms.append(year)
		by_id[id] = entry
		monsters.append(entry)
	for entry in monsters:
		for phase in entry.definition.get("phases", []):
			for intent in phase.get("intents", []):
				for spec in intent.get("summon_tasks", []):
					_add_parent(by_id, str(spec.get("task", "")), entry.id, "summon")
				_add_parent(by_id, str(intent.get("transform_task", {}).get("task", "")), entry.id, "transform")
		for effect in entry.definition.get("on_complete_effects", []):
			if effect.get("op") == "summon_task":
				_add_parent(by_id, str(effect.get("task", "")), entry.id, "on_complete")
	# Propagate only year labels, including chained transforms; finite sets converge.
	for _pass in monsters.size():
		var changed := false
		for entry in monsters:
			for parent in entry.parents:
				for term in by_id[parent.id].terms:
					if not entry.terms.has(term):
						entry.terms.append(term)
						changed = true
		if not changed:
			break
	for entry in monsters:
		entry.terms.sort()
	var relics: Array[Dictionary] = []
	for id in catalog.get_candidates({"kind": "relic"}):
		var definition: Dictionary = catalog.get_definition("relic", id).data
		var year := int(definition.get("campaign", {}).get("year", 0))
		var terms := [year] if year > 0 else ([3, 4] if definition.get("rarity", "") == "gold" else [1, 2, 3, 4])
		relics.append({"id": id, "definition": definition, "terms": terms, "test_override": _overrides(overlay, "relic", id)})
	relics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return GameResult.success({"relics": relics, "manifest_id": info.id, "content_hash": info.content_hash, "cards": cards, "monsters": monsters})


static func _overrides(overlay: TestOverlay, kind: String, id: String) -> bool:
	return overlay != null and (overlay.definitions.get(kind, {}).has(id) or overlay.fields.get(kind, {}).has(id))


static func _attach_related(catalog: ContentDB, value: Variant, face: Dictionary) -> void:
	if value is Array:
		for item in value:
			_attach_related(catalog, item, face)
	elif value is Dictionary:
		for pair in [["unit", "related_units"], ["scene", "related_scenes"]]:
			var id := str(value.get(pair[0], ""))
			if not id.is_empty():
				var related := catalog.get_definition(pair[0], id)
				if related.ok:
					face[pair[1]][id] = related.data
		for item in value.values():
			_attach_related(catalog, item, face)


static func _add_parent(by_id: Dictionary, child: String, parent: String, kind: String) -> void:
	if by_id.has(child) and child != parent:
		var link := {"id": parent, "kind": kind}
		if not by_id[child].parents.has(link):
			by_id[child].parents.append(link)
