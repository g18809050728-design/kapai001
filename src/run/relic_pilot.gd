class_name RelicPilot
extends RefCounted
## Explicitly versioned, opt-in extension of the four-year campaign.

const MANIFEST := "campus_four_year_relic_pilot"
const VERSION := "campus_four_year_relic_pilot.v2"
const LEGACY_VERSION := "campus_four_year_relic_pilot.v1"
const BASE := "campus_four_year"
const ROSTER := "campus_four_year_relics"
const ROSTER_VERSION := "campus_four_year_relics.v2"
const LEGACY_ROSTER_VERSION := "campus_four_year_relics.v1"
const FULL_DEFINITIONS := preload("res://data/four_year/relic_roster/definitions.json")
const DEFINITIONS := preload("res://data/four_year/relic_pilot/definitions.json")
const IDS := [
	"RX-C01", "RX-C02", "RX-C05", "RX-C09", "RX-C17", "RX-C23", "RX-C26", "RX-C28",
	"RX-P01-01", "RX-P01-05", "RX-P01-09", "RX-P01-15",
	"RX-P02-01", "RX-P02-02", "RX-P02-07", "RX-P02-15",
	"RX-P03-01", "RX-P03-05", "RX-P03-09", "RX-P03-16",
	"RX-P04-01", "RX-P04-06", "RX-P04-08", "RX-P04-11",
]
const RUN_LIMITS := {"RX-C26": 2, "RX-C28": 3}
const QUALITY := ["white", "blue", "purple", "gold"]
const WEIGHTS := [[65, 30, 5, 0], [50, 35, 15, 0], [35, 40, 20, 5], [25, 40, 25, 10]]


static func expanded(manifest_id: String) -> bool:
	return manifest_id in [MANIFEST, ROSTER]


static func legacy_version(manifest_id: String) -> String:
	match manifest_id:
		MANIFEST: return LEGACY_VERSION
		ROSTER: return LEGACY_ROSTER_VERSION
	return ""


static func is_retired(id: String) -> bool:
	return id.length() == 7 and id.begins_with("FY_Y") and id[4] in ["1", "2", "3", "4"] and id[5] == "_" and id[6] in ["1", "2", "3", "4"]


static func is_rx(id: String) -> bool:
	if not id.begins_with("RX-"):
		return false
	var group := id.get_slice("-", 1)
	var suffix := id.right(2)
	if not suffix.is_valid_int() or "%02d" % int(suffix) != suffix:
		return false
	if group.begins_with("C"):
		return id == "RX-C" + suffix and int(suffix) in range(1, 41)
	return group in ["P01", "P02", "P03", "P04"] and id == "RX-" + group + "-" + suffix and int(suffix) in range(1, 17)


static func owns_definition(id: String, character: String) -> bool:
	return not id.begins_with("RX-") or (is_rx(id) and (id.begins_with("RX-C") or id.begins_with("RX-" + character + "-")))


static func display_name(id: String) -> String:
	for row in FULL_DEFINITIONS.data:
		if row.id == id:
			return str(row.name_key)
	return id


static func is_candidate(definition: Dictionary, character: String, year: int, full: bool = false, legacy_pool: bool = false) -> bool:
	var id := str(definition.get("id", ""))
	var quality := QUALITY.find(definition.get("rarity"))
	if definition.get("availability") != "drop" or quality < 0 or year < 1 or year > 4:
		return false
	if id.begins_with("RX-"):
		return WEIGHTS[year - 1][quality] > 0 and definition.has("rx") and owns_definition(id, character) and (full or (id in IDS and definition.rarity != "gold"))
	# Only used to validate already-frozen rewards from the old catalogs.
	return legacy_pool and is_retired(id) and int(definition.get("campaign", {}).get("year", 0)) == year and (WEIGHTS[year - 1][quality] > 0 or (full and quality == 3))


static func _future_exam_flags(run: RunState, catalog: ContentDB) -> Dictionary:
	var source := run.find_node(run.current_node_id)
	var queue: Array[String] = source.next_ids.duplicate() if source != null else run.reachable_node_ids()
	var seen := {}
	var flags := {}
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		var node := run.find_node(id)
		if node == null or node.term != run.term or node.status != "pending":
			continue
		queue.append_array(node.next_ids)
		var choices: Array = []
		if node.kind == "elite":
			var subtype: String = CampaignProgression.metadata(run, id).subtype
			choices = ["E02" if subtype == "K" else ["Q01", "E01", "E03", "E05"][run.term - 1]]
		elif node.kind == "boss" and run.term < 4:
			choices = ["FY_B%d" % run.term]
		elif node.kind == "boss" and run.term == 4:
			var target := str(run.campaign.destination)
			choices = ["FY_ROUTE_" + target, "FY_FINAL_deferred"]
		elif node.kind == "normal":
			choices = catalog.get_candidates({"kind": "encounter", "terms": run.term}).filter(func(enc): return catalog.get_definition("encounter", enc).data.kind == "normal")
		for enc in choices:
			var definition := catalog.get_definition("encounter", enc)
			if definition.ok:
				for flag in definition.data.get("exam_flags", []):
					flags[flag] = true
	return flags


static func candidates(run: RunState, catalog: ContentDB, rng: RandomSource) -> GameResult:
	var groups := {"common": [], "own": []}
	var by_id := {}
	var owned := {}
	var taken: Array[String] = []
	var used_gold := false
	var full := run.manifest_id == ROSTER
	var exam := _future_exam_flags(run, catalog) if full else {}
	for slot in run.relics:
		owned[str(slot.definition_id)] = true
	for id in catalog.get_candidates({"kind": "relic", "availability": "drop"}):
		var definition: Dictionary = catalog.get_definition("relic", id).data
		if not is_candidate(definition, run.character_id, run.term, full):
			continue
		if full and ((id == "RX-C22" and not (exam.has("fixed_exam_room") or exam.has("independent_answer"))) or (id == "RX-P04-12" and not exam.has("independent_answer"))):
			continue
		var group := "common" if definition.rx.owner == "C" else "own"
		groups[group].append(id)
		by_id[id] = definition
	var mixed: Array = groups.common + groups.own
	# Prioritize an unowned alternative before offering an equipped duplicate.
	for tiers in [[groups.common], [groups.own, groups.common], [mixed]]:
		var pool: Array[String] = []
		for allow_owned in [false, true]:
			for tier in tiers:
				for id: String in tier:
					if id not in taken and (allow_owned or not owned.has(id)) and (not used_gold or by_id[id].rarity != "gold"):
						pool.append(id)
				if not pool.is_empty():
					break
			if not pool.is_empty():
				break
		if pool.is_empty():
			continue
		pool.sort()
		var weights := {}
		var total := 0
		var available: Array[String] = []
		for q in QUALITY.size():
			var rarity: String = QUALITY[q]
			if pool.any(func(id): return str(by_id[id].rarity) == rarity):
				available.append(rarity)
				weights[rarity] = WEIGHTS[run.term - 1][q]
				total += int(weights[rarity])
		var rarity: String = available[0]
		if available.size() > 1:
			var rolled := rng.draw_int("reward", 1, total)
			if not rolled.ok:
				return rolled
			var cursor := int(rolled.data)
			for q in available:
				cursor -= int(weights[q])
				if cursor <= 0:
					rarity = q
					break
		var matching := pool.filter(func(id): return str(by_id[id].rarity) == rarity)
		var draw := rng.draw_int("reward", 0, matching.size() - 1)
		if not draw.ok:
			return draw
		taken.append(str(matching[draw.data]))
		used_gold = used_gold or rarity == "gold"
	return GameResult.success(taken)


static func remaining(run: RunState, id: String) -> int:
	return int(RUN_LIMITS.get(id, 0)) - int(run.campaign.get("rx_uses", {}).get(id, 0))


static func can_trigger(run: RunState, id: String) -> bool:
	return expanded(run.manifest_id) and remaining(run, id) > 0 and run.relics.any(func(slot): return slot.definition_id == id)


static func consume(run: RunState, id: String) -> void:
	var uses: Dictionary = run.campaign.rx_uses
	uses[id] = int(uses.get(id, 0)) + 1


static func rest_bonus(run: RunState, node_id: String, before: int, after: int) -> int:
	if after <= before or after >= run.max_vitality or not can_trigger(run, "RX-C26"):
		return 0
	return mini(4, run.max_vitality - after) if CampaignProgression.metadata(run, node_id).get("subtype") == "R" else 0
