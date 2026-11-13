class_name CampaignProgression
extends RefCounted

const MAP_VERSION := 2
const SUPPORTED_MAP_VERSIONS := [1, 2]
const COUNTERS := ["research", "competition", "internship", "community"]
const MAP_FIELDS := {"root_seed": TYPE_STRING, "map_version": TYPE_INT, "years": TYPE_ARRAY, "summaries": TYPE_ARRAY}


static func enabled(run: RunState) -> bool:
	return CampaignService.enabled(run) and int(run.campaign.get("version", 1)) == 2


static func initialize(run: RunState, seed: String) -> GameResult:
	run.campaign = CampaignService.initial()
	run.campaign.merge({"version": 2, "root_seed": seed, "map_version": MAP_VERSION, "years": [], "summaries": []}, true)
	return ensure_year(run)


static func ensure_year(run: RunState) -> GameResult:
	if not enabled(run):
		return GameResult.success(true)
	if run.campaign.years.size() >= run.term:
		return GameResult.success(true)
	if run.campaign.years.size() != run.term - 1:
		return _error("run.map.generation_order")
	if run.campaign.pending.get("kind", "") in ["direction", "destination"]:
		return GameResult.success(true)
	var version: int = run.campaign.map_version
	if version not in SUPPORTED_MAP_VERSIONS:
		return _error("run.map.unsupported_version")
	var profile := _profile(run.campaign, run.term)
	var seed := _year_seed(run.campaign.root_seed, run.term, profile, version)
	var generator: GDScript = load("res://src/run/annual_map_generator.gd")
	var map: Dictionary = generator.generate(run.term, seed, profile, version)
	var issues: Array[String] = generator.validate(map)
	if not issues.is_empty():
		return GameResult.failure(ApiError.new(GameConstants.ERROR_CONTENT_INVALID, "run.map.generation_invalid", {"issues": issues}))
	run.campaign.years.append(map.duplicate(true))
	run.nodes.append_array(_nodes(map, run.run_id))
	return GameResult.success(true)


static func complete_year(run: RunState) -> void:
	if not enabled(run) or run.campaign.summaries.size() >= run.term:
		return
	run.campaign.summaries.append(_summarize(run, run.term))


static func _summarize(run: RunState, year: int) -> Dictionary:
	var summary := {"year": year, "research": 0, "competition": 0, "internship": 0, "community": 0}
	for node in run.nodes:
		if node.term != year or node.status != "completed":
			continue
		var subtype := str(metadata(run, node.node_id).get("subtype", ""))
		if node.kind == "rest" and subtype != "R":
			var used: bool = run.campaign.history.any(func(record): return record.offer_id == node.node_id + "|service" and record.option_id in ["upgrade", "remove", "heal", "money", "progress"])
			if not used:
				continue
		var counter := str({"LAB": "research", "T": "research", "ST": "research", "K": "competition", "I": "internship", "C": "community"}.get(subtype, ""))
		if not counter.is_empty():
			summary[counter] = mini(6, int(summary[counter]) + 1)
	return summary


static func metadata(run: RunState, node_id: String) -> Dictionary:
	if enabled(run):
		var key := node_id.get_slice("|", 1)
		for map in run.campaign.years:
			for item in map.nodes:
				if item.key == key:
					return item.duplicate(true)
		return {}
	return CampaignMap.metadata(node_id)


static func year_info(run: RunState, year: int) -> Dictionary:
	if enabled(run):
		return run.campaign.years[year - 1].duplicate(true) if year > 0 and year <= run.campaign.years.size() else {}
	return CampaignMap.MAPS[year - 1].duplicate(true)


static func expected_nodes(run: RunState) -> Array[RunNodeState]:
	var nodes: Array[RunNodeState] = []
	for map in run.campaign.get("years", []):
		nodes.append_array(_nodes(map, run.run_id))
	return nodes


static func influence(run: RunState) -> String:
	if not enabled(run):
		return ""
	if run.campaign.years.size() < run.term:
		return "确认方向或毕业去向后，将根据种子与已完成经历生成本学年地图。"
	var profile: Dictionary = run.campaign.years[run.term - 1].profile
	if run.term == 1:
		return "种子已生成本学年路线；不同选择积累的经历，将有限影响下一学年的机会。"
	var parts: Array[String] = []
	for key in COUNTERS:
		if int(profile.get(key, 0)) > 0:
			parts.append("%s%d" % [{"research": "科研", "competition": "竞赛", "internship": "实践", "community": "社群"}[key], profile[key]])
	return "上学年经历：%s。相关机会有所增加，其他方向仍可选择。" % ("、".join(parts) if not parts.is_empty() else "均衡探索")


static func validate_campaign(data: Dictionary, issues: Array[String]) -> void:
	if data.get("map_version") not in SUPPORTED_MAP_VERSIONS or not str(data.get("root_seed", "")).is_valid_int():
		issues.append("campaign map version/seed invalid")
		return
	var years: Array = data.get("years", [])
	var summaries: Array = data.get("summaries", [])
	if years.is_empty() or years.size() > 4 or summaries.size() > years.size():
		issues.append("campaign annual record count invalid")
		return
	for index in summaries.size():
		var start := issues.size()
		RunCodec.shape(summaries[index], {"year": TYPE_INT, "research": TYPE_INT, "competition": TYPE_INT, "internship": TYPE_INT, "community": TYPE_INT}, "campaign.summaries[]", issues)
		if issues.size() != start:
			return
		if summaries[index].year != index + 1:
			issues.append("campaign summaries are out of order")
		for counter in COUNTERS:
			if summaries[index][counter] < 0 or summaries[index][counter] > 6:
				issues.append("campaign summary counter outside bounds")
	var generator: GDScript = load("res://src/run/annual_map_generator.gd")
	for index in years.size():
		if not years[index] is Dictionary:
			issues.append("campaign year must be an object")
			return
		var map: Dictionary = years[index]
		var found: Array[String] = generator.validate(map)
		if not found.is_empty():
			issues.append_array(found)
			return
		var year := index + 1
		var profile := _profile(data, year)
		var version: int = data.map_version
		var seed := _year_seed(data.root_seed, year, profile, version)
		if map.version != version or map.year != year or map.seed != seed or map.profile != profile:
			issues.append("campaign generated map input mismatch")
		elif generator.generate(year, seed, profile, version) != map:
			issues.append("campaign generated map differs from frozen generation")


static func validate(run: RunState, issues: Array[String]) -> void:
	var count: int = run.campaign.years.size()
	var waiting: bool = run.campaign.pending.get("kind", "") in ["direction", "destination"]
	if count != run.term - (1 if waiting else 0):
		issues.append("campaign generated years disagree with current year")
	var finished_current: bool = run.campaign.summaries.size() == run.term
	if finished_current and (run.term != 4 or run.outcome != "won"):
		issues.append("campaign current year was summarized too early")
	elif run.campaign.summaries.size() != run.term - (0 if finished_current else 1):
		issues.append("campaign completed year summaries missing")
	for summary in run.campaign.summaries:
		if summary != _summarize(run, int(summary.year)):
			issues.append("campaign summary disagrees with completed experiences")
		var bosses := run.nodes.filter(func(node): return node.term == summary.year and node.kind == "boss")
		if bosses.size() != 1 or bosses[0].status != "completed":
			issues.append("campaign summarized year has no completed boss")
		elif not run.campaign.history.any(func(record): return record.offer_id == bosses[0].node_id + "|grand"):
			issues.append("campaign summarized year has no resolved grand reward")
	_validate_decisions(run, issues)


static func _validate_decisions(run: RunState, issues: Array[String]) -> void:
	var initial_direction := ""
	var active_direction := ""
	var destination := ""
	var changes := 0
	for record in run.campaign.history:
		if str(record.offer_id).ends_with("|direction"):
			if record.offer_id != run.run_id + "|direction" or record.option_id not in CampaignService.DIRECTIONS:
				issues.append("campaign initial direction history invalid")
			initial_direction = str(record.option_id)
			active_direction = initial_direction
		elif str(record.option_id).begins_with("direction_"):
			var node := run.find_node(str(record.offer_id).trim_suffix("|service"))
			var direction := str(record.option_id).trim_prefix("direction_")
			if initial_direction.is_empty() or node == null or node.term != 2 or node.layer < 7 or node.kind != "rest" or direction not in CampaignService.DIRECTIONS:
				issues.append("campaign direction change history invalid")
			active_direction = direction
			changes += 1
		elif str(record.offer_id).ends_with("|destination"):
			if record.offer_id != run.run_id + "|destination" or record.option_id not in CampaignService.DESTINATIONS:
				issues.append("campaign destination history invalid")
			destination = str(record.option_id)
	var pending_kind := str(run.campaign.pending.get("kind", ""))
	var direction_due := run.term >= 2 and pending_kind != "direction"
	var destination_due := run.term == 4 and pending_kind != "destination"
	if (not initial_direction.is_empty()) != direction_due or active_direction != run.campaign.direction:
		issues.append("campaign direction disagrees with decision history/year")
	if changes > 1 or (changes == 1) != bool(run.campaign.direction_changed):
		issues.append("campaign direction-change flag disagrees with history")
	if (not destination.is_empty()) != destination_due or destination != run.campaign.destination:
		issues.append("campaign destination disagrees with decision history/year")
	if pending_kind in ["direction", "destination"]:
		var current := run.find_node(run.current_node_id)
		if run.term != (2 if pending_kind == "direction" else 4) or current == null or current.term != run.term - 1 or current.kind != "boss" or current.status != "completed":
			issues.append("campaign decision is not at the expected annual boundary")


static func _profile(data: Dictionary, year: int) -> Dictionary:
	var profile := {"research": 0, "competition": 0, "internship": 0, "community": 0, "direction": "", "destination": ""}
	if year > 1 and data.summaries.size() >= year - 1:
		var previous: Dictionary = data.summaries[year - 2]
		for counter in COUNTERS:
			profile[counter] = previous[counter]
	# Replay explicit decisions rather than trusting saved generation inputs.
	# A year-two direction change only affects the following years.
	for record in data.history:
		if year >= 2 and str(record.offer_id).ends_with("|direction"):
			profile.direction = record.option_id
		if year >= 3 and str(record.option_id).begins_with("direction_"):
			profile.direction = str(record.option_id).trim_prefix("direction_")
		if year == 4 and str(record.offer_id).ends_with("|destination"):
			profile.destination = record.option_id
	return profile


static func _year_seed(root_seed: String, year: int, profile: Dictionary, version: int = MAP_VERSION) -> String:
	return ("annual-map-v%d|%s|%d|%s" % [version, root_seed, year, SnapshotCodec.canonical_json(profile)]).sha256_text()


static func _nodes(map: Dictionary, run_id: String) -> Array[RunNodeState]:
	var nodes: Array[RunNodeState] = []
	for item in map.nodes:
		var next_ids: Array[String] = []
		for key in item.next:
			next_ids.append(run_id + "|" + key)
		nodes.append(RunNodeState.create({"node_id": run_id + "|" + item.key, "term": map.year, "layer": item.layer, "kind": item.kind, "next_ids": next_ids}))
	return nodes


static func _error(key: String) -> GameResult:
	return GameResult.failure(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, key))
