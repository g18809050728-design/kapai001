class_name AnnualMapGenerator
extends RefCounted
## Pure annual map generation. Identity is local to the year; no RunState or global RNG is used.

const VERSION := 2
const LEGACY := preload("res://src/run/annual_map_generator_v1.gd")
const YEAR_LAYERS := [12, 12, 14, 14]
const YEAR_TITLES := ["适应与基础", "分流与专业", "履历与实践", "毕设与毕业去向"]
const MAP_FIELDS := ["version", "year", "title", "layers", "relic_layers", "seed", "profile", "nodes"]
const NODE_FIELDS := ["key", "year", "layer", "kind", "subtype", "title", "next", "column"]
const EXPERIENCE_FIELDS := ["research", "competition", "internship", "community"]
const PROFILE_FIELDS := ["research", "competition", "internship", "community", "direction", "destination"]
const KINDS := {"N": "normal", "E": "event", "S": "shop", "EL": "elite", "K": "elite",
	"R": "rest", "L": "rest", "LAB": "rest", "C": "rest", "T": "rest", "I": "rest",
	"ST": "rest", "B": "boss"}
const NORMAL_TITLES := [
	["课后习题", "英语小作文", "C语言练习", "实验预习", "基础课程作业"],
	["专业课作业", "课程设计", "实验报告", "文献综述", "专业基础实践"],
	["项目阶段报告", "实习周报", "科研文献", "团队项目", "履历整理"],
	["毕设文献", "毕业课程实践", "论文初稿", "求职材料", "毕业设计"]]
const EVENT_TITLES := [
	["社团招新", "室友夜谈", "校园探索"], ["专业分流宣讲", "竞赛报名", "方向交流"],
	["科研项目招募", "企业开放日", "团队经验交流"], ["导师约谈", "毕业规划", "论文投稿"]]
const ELITE_TITLES := ["随堂测验", "课程设计检查", "项目冲刺", "毕业项目检查"]
const COMPETITION_TITLES := ["新生学科挑战", "学科竞赛", "创新竞赛", "毕业创新竞赛"]
const SHOP_TITLES := ["校园商店", "教材商店", "项目补给站", "打印店"]
const BOSS_TITLES := ["大一学年综合考核", "大二专业综合考核", "大三履历综合考核", "毕业答辩"]
const SERVICE_TITLES := {
	"L": ["图书馆导读", "专业文献研读", "科研文献讨论", "毕设文献研读"],
	"LAB": ["实验室体验", "实验室", "科研组会", "毕设实验室"],
	"T": ["学业导师", "导师交流", "导师项目", "毕设导师"],
	"I": ["职业体验", "实习体验", "实习", "招聘会"],
	"C": ["社团活动", "社团换届", "社群协作", "毕业社群"],
	"ST": ["学业规划", "方向规划", "履历规划", "毕设中期检查"]}
const DESTINATION_CHALLENGES := {"job": "求职终审", "exam": "升学综合考核",
	"research": "科研项目评审", "abroad": "海外申请评审"}


static func generate(year: int, seed: String, profile: Dictionary = {}, version: int = VERSION) -> Dictionary:
	if version == 1:
		return LEGACY.generate(year, seed, profile)
	if version != VERSION or year < 1 or year > 4:
		return {}
	var normalized := _normalize_profile(profile)
	# Topology and schedule streams never depend on experiences or content draws.
	var topology_rng := _random(year, seed, "topology", [])
	var content_rng := _random(year, seed, "content", normalized.values())
	var layers: int = YEAR_LAYERS[year - 1]
	var detours := _detours(layers, topology_rng)
	var safe_lane := topology_rng.randi_range(0, 2)
	var side_columns := [topology_rng.randi_range(0, 1) * 2, 4 + topology_rng.randi_range(0, 1) * 2]
	var schedules: Array[Dictionary] = []
	for lane in 3:
		schedules.append(_lane_schedule(year, lane, safe_lane, _random(year, seed, "schedule-lane-%d" % lane, [])))
	var nodes: Array = [_node(year, 1, 0, 3, "N", content_rng, normalized)]
	for layer in range(2, layers):
		for lane in 3:
			var subtype := _resolve_subtype(schedules[lane][layer], content_rng, normalized)
			nodes.append(_node(year, layer, lane, 1 + lane * 2, subtype, content_rng, normalized))
			if lane == 1:
				continue
			var side := 0 if lane == 0 else 1
			var detour: Dictionary = detours[side]
			if layer > detour.fork and layer < detour.merge:
				# Detours inherit their main lane's exact category at every layer.
				# Service opportunities may differ without changing a complete route's budget.
				var side_subtype := subtype
				if subtype in ["L", "LAB", "T", "I", "C"]:
					side_subtype = _service_subtype(content_rng, normalized)
				nodes.append(_node(year, layer, 3 + side, side_columns[side], side_subtype, content_rng, normalized))
	nodes.append(_node(year, layers, 0, 3, "B", content_rng, normalized))
	for node in nodes:
		var layer: int = node.layer
		if layer == layers:
			continue
		if layer == 1:
			node.next = [_key(year, 2, 0), _key(year, 2, 1), _key(year, 2, 2)]
			continue
		var slot := int(String(node.key).get_slice("s", 1))
		var lane := slot if slot < 3 else (0 if slot == 3 else 2)
		var target_slot := slot
		if lane != 1:
			var side := 0 if lane == 0 else 1
			var detour: Dictionary = detours[side]
			if slot >= 3 and layer + 1 == detour.merge:
				target_slot = lane
			node.next = [_key(year, layer + 1, 0 if layer + 1 == layers else target_slot)]
			if slot < 3 and layer == detour.fork:
				node.next.append(_key(year, layer + 1, 3 + side))
		else:
			node.next = [_key(year, layer + 1, 0 if layer + 1 == layers else target_slot)]
	var map := {"version": VERSION, "year": year, "title": YEAR_TITLES[year - 1],
		"layers": layers, "relic_layers": [3, 9] if year <= 2 else [3, 10],
		"seed": seed, "profile": normalized, "nodes": nodes}
	var issues := validate(map)
	if not issues.is_empty():
		push_error("Generated annual map rejected: " + "; ".join(issues))
		return {}
	return map


static func _detours(layers: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	# One branch spans at least half the middle layers; the other lasts at least three.
	# Sampling the longer side and both fork/merge points varies actual edges across seeds.
	var wide_layers := ceili((layers - 2) / 2.0)
	var long_side := rng.randi_range(0, 1)
	var detours: Array[Dictionary] = []
	for side in 2:
		var length := wide_layers if side == long_side else 3
		var fork := rng.randi_range(2, layers - length - 2)
		var merge := rng.randi_range(fork + length + 1, layers - 1)
		detours.append({"fork": fork, "merge": merge})
	return detours


static func validate(map: Dictionary) -> Array[String]:
	if typeof(map.get("version")) == TYPE_INT and map.version == 1:
		return LEGACY.validate(map)
	var issues: Array[String] = []
	if not _exact_fields(map, MAP_FIELDS):
		issues.append("map fields must exactly match the annual map schema")
		return issues
	for field in ["version", "year", "layers"]:
		if typeof(map[field]) != TYPE_INT:
			issues.append("map.%s must be an integer" % field)
	for field in ["title", "seed"]:
		if typeof(map[field]) != TYPE_STRING:
			issues.append("map.%s must be a string" % field)
	if typeof(map.profile) != TYPE_DICTIONARY or typeof(map.nodes) != TYPE_ARRAY or typeof(map.relic_layers) != TYPE_ARRAY:
		issues.append("map profile/nodes/relic_layers containers are invalid")
	if not issues.is_empty():
		return issues
	if map.version != VERSION or map.year < 1 or map.year > 4:
		issues.append("unsupported annual map version or year")
		return issues
	var year: int = map.year
	var layers: int = YEAR_LAYERS[year - 1]
	if map.layers != layers or map.title.strip_edges().is_empty():
		issues.append("annual layers/title are invalid")
	var relics: Array = [3, 9] if year <= 2 else [3, 10]
	if map.relic_layers != relics:
		issues.append("annual relic checkpoints are invalid")
	for layer in map.relic_layers:
		if typeof(layer) != TYPE_INT:
			issues.append("relic checkpoint must be an integer")
	if not _exact_fields(map.profile, PROFILE_FIELDS):
		issues.append("profile fields must exactly match the normalized schema")
	else:
		for field in EXPERIENCE_FIELDS:
			if typeof(map.profile[field]) != TYPE_INT or map.profile[field] < 0 or map.profile[field] > 6:
				issues.append("profile.%s must be an integer in 0..6" % field)
		for field in ["direction", "destination"]:
			if typeof(map.profile[field]) != TYPE_STRING:
				issues.append("profile.%s must be a string" % field)
	if map.nodes.size() < 2 or map.nodes.size() > 5 * (layers - 2) + 2:
		issues.append("annual node count is outside the route width budget")
		return issues
	var nodes := {}
	var by_layer := {}
	for node in map.nodes:
		if typeof(node) != TYPE_DICTIONARY or not _exact_fields(node, NODE_FIELDS):
			issues.append("node fields must exactly match the annual node schema")
			continue
		var typed := true
		for field in ["year", "layer", "column"]:
			if typeof(node[field]) != TYPE_INT:
				issues.append("node.%s must be an integer" % field)
				typed = false
		for field in ["key", "kind", "subtype", "title"]:
			if typeof(node[field]) != TYPE_STRING:
				issues.append("node.%s must be a string" % field)
				typed = false
		if typeof(node.next) != TYPE_ARRAY:
			issues.append("node.next must be an array")
			typed = false
		if not typed:
			continue
		if node.year != year or node.layer < 1 or node.layer > layers or node.column < 0 or node.column > 6:
			issues.append("node year/layer/column is out of range")
		var pattern := RegEx.create_from_string("^y%dl%d[sc][0-9]+$" % [year, node.layer])
		if pattern.search(node.key) == null:
			issues.append("node key must encode its year and layer")
		if String(node.key).contains("c") and node.key != "y%dl%dc%d" % [year, node.layer, node.column]:
			issues.append("column key must encode its column")
		if not KINDS.has(node.subtype) or node.kind != KINDS.get(node.subtype):
			issues.append("node subtype and runtime kind disagree")
		if node.title.strip_edges().is_empty():
			issues.append("node title must not be blank")
		if nodes.has(node.key):
			issues.append("duplicate node key")
		nodes[node.key] = node
		if not by_layer.has(node.layer):
			by_layer[node.layer] = []
		for other in by_layer[node.layer]:
			if other.column == node.column:
				issues.append("two nodes occupy the same layer/column")
		by_layer[node.layer].append(node)
	if not issues.is_empty():
		return issues
	var wide_layers := 0
	for layer in range(1, layers + 1):
		var width: int = by_layer.get(layer, []).size()
		if (layer in [1, layers] and width != 1) or (layer not in [1, layers] and (width < 3 or width > 5)):
			issues.append("each middle layer needs 3..5 routes and the endpoints need one node")
		if layer not in [1, layers] and width >= 4:
			wide_layers += 1
	if 2 * wide_layers < layers - 2:
		issues.append("at least half the middle layers need four or five routes")
	if not issues.is_empty():
		return issues
	var start: Dictionary = by_layer[1][0]
	var boss: Dictionary = by_layer[layers][0]
	if start.subtype != "N" or boss.subtype != "B":
		issues.append("the endpoints must be a normal starter and a terminal boss")
	var forks := 0
	for node in map.nodes:
		if node.layer == layers - 1 and node.subtype != "R":
			issues.append("every route needs recovery immediately before the boss")
		if node.kind == "elite" and node.layer < 3:
			issues.append("elite/competition nodes cannot appear in the initial two layers")
		if (node.kind == "boss") != (node.layer == layers):
			issues.append("only the last layer may contain the boss")
		if node.layer == 1 and node.next.size() != 3:
			issues.append("the starter needs exactly three entrances")
		if (node.layer > 1 and node.next.size() > 2) or (node.layer < layers and node.next.is_empty()) or (node.layer == layers and not node.next.is_empty()):
			issues.append("ordinary nodes need 1..2 successors and the boss needs none")
		if node.layer > 1 and node.next.size() == 2:
			forks += 1
		var targets := {}
		for target in node.next:
			if typeof(target) != TYPE_STRING or not nodes.has(target):
				issues.append("successor must be an existing year-local node key")
				continue
			if targets.has(target):
				issues.append("duplicate successor")
			targets[target] = true
			if nodes[target].layer != node.layer + 1:
				issues.append("edges must connect adjacent layers")
			if node.kind == "elite" and nodes[target].kind == "elite":
				issues.append("consecutive elite/competition nodes are forbidden")
	if not issues.is_empty():
		return issues
	if forks < 2:
		issues.append("at least two sustained side branches are required")
	var reached := _nearby(nodes, start.key, layers)
	if reached.size() != nodes.size():
		issues.append("every candidate must be reachable from the starter")
	var from_start := {start.key: 1}
	var stats := {}
	for layer in range(1, layers + 1):
		for node in by_layer[layer]:
			for target in node.next:
				from_start[target] = int(from_start.get(target, 0)) + int(from_start.get(node.key, 0))
	for layer in range(layers, 0, -1):
		for node in by_layer[layer]:
			var current := {"ways": 1 if node.key == boss.key else 0,
				"shops": 0, "rests": 0, "recovery": 0, "normal": 0, "elite": 0,
				"thesis": 0, "late_service": 0, "safe": node.kind != "elite"}
			if not node.next.is_empty():
				current.safe = false
				for field in ["shops", "rests", "recovery", "normal", "thesis", "late_service"]:
					current[field] = layers + 1
				for target in node.next:
					var child: Dictionary = stats[target]
					current.ways += child.ways
					current.safe = current.safe or child.safe
					for field in ["shops", "rests", "recovery", "normal", "thesis", "late_service"]:
						current[field] = mini(current[field], child[field])
					current.elite = maxi(current.elite, child.elite)
				current.safe = current.safe and node.kind != "elite"
			current.shops += int(node.kind == "shop")
			current.rests += int(node.kind == "rest")
			current.recovery += int(node.subtype == "R")
			current.normal += int(node.kind == "normal")
			current.elite += int(node.kind == "elite")
			current.thesis += int(node.subtype == "ST")
			current.late_service += int(node.layer >= 7 and node.kind == "rest" and node.subtype != "R")
			stats[node.key] = current
	var budget: Dictionary = stats[start.key]
	if budget.shops < 1 or budget.rests < 2 or budget.recovery < 2:
		issues.append("every route needs a shop and at least two actual recovery opportunities")
	if budget.normal < [4, 3, 3, 2][year - 1] or budget.elite > [1, 2, 3, 3][year - 1]:
		issues.append("annual combat/risk budget exceeded")
	if year == 4 and budget.thesis < 2:
		issues.append("every final-year route needs at least two ST services")
	if year == 2 and budget.late_service < 1:
		issues.append("every year-two route needs a late service for changing direction")
	if not budget.safe:
		issues.append("an elite/competition free complete route is required")
	for node in map.nodes:
		if stats[node.key].ways == 0:
			issues.append("every candidate must lead to the boss")
		if node.key not in [start.key, boss.key] and int(from_start.get(node.key, 0)) * stats[node.key].ways == budget.ways:
			issues.append("only the starter and boss may be universal chokepoints")
		if node.next.size() >= 2:
			for left_index in node.next.size():
				for right_index in range(left_index + 1, node.next.size()):
					var left := _nearby(nodes, node.next[left_index], node.layer + 3)
					var right := _nearby(nodes, node.next[right_index], node.layer + 3)
					for key in left:
						if right.has(key):
							issues.append("forks must retain three independent nodes before merging")
							break
	issues.append_array(_validate_route_multisets(by_layer, start, layers, year))
	return issues


static func _validate_route_multisets(by_layer: Dictionary, start: Dictionary, layers: int, year: int) -> Array[String]:
	var stats := {}
	for layer in range(layers, 0, -1):
		for node in by_layer[layer]:
			var counts := {"combat": int(node.kind in ["normal", "elite"]),
				"event": int(node.kind == "event"), "shop": int(node.kind == "shop"),
				"rest": int(node.kind == "rest"), "recovery": int(node.subtype == "R"),
				"thesis": int(node.subtype == "ST")}
			var minimum := counts.duplicate()
			var maximum := counts.duplicate()
			var risks := {}
			if node.next.is_empty():
				risks[int(node.kind == "elite")] = true
			else:
				for field in counts:
					minimum[field] = layers + 1
					maximum[field] = 0
				for target in node.next:
					var child: Dictionary = stats[target]
					for field in counts:
						minimum[field] = mini(minimum[field], counts[field] + child.minimum[field])
						maximum[field] = maxi(maximum[field], counts[field] + child.maximum[field])
					for risk in child.risks:
						risks[int(risk) + int(node.kind == "elite")] = true
			stats[node.key] = {"minimum": minimum, "maximum": maximum, "risks": risks}
	var expected := {"combat": [5, 5, 6, 5][year - 1], "event": 1, "shop": 1,
		"rest": [4, 4, 5, 6][year - 1], "recovery": 2, "thesis": 2 if year == 4 else 0}
	var result: Array[String] = []
	var budget: Dictionary = stats[start.key]
	for field in expected:
		if budget.minimum[field] != expected[field] or budget.maximum[field] != expected[field]:
			result.append("every route must retain the original %s content multiset" % field)
	for risk in budget.risks:
		if risk not in [0, [1, 2, 3, 3][year - 1]]:
			result.append("every route must retain the safe or risky annual budget")
	return result


static func _normalize_profile(profile: Dictionary) -> Dictionary:
	var normalized := {}
	for field in EXPERIENCE_FIELDS:
		var value: Variant = profile.get(field, 0)
		normalized[field] = 0
		if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value)):
			normalized[field] = int(clamp(value, 0, 6))
	for field in ["direction", "destination"]:
		var value: Variant = profile.get(field, "")
		normalized[field] = value if typeof(value) == TYPE_STRING else ""
	return normalized


static func _random(year: int, seed: String, scope: String, preferences: Array) -> RandomNumberGenerator:
	var source := RandomNumberGenerator.new()
	# SHA-256 disperses nearby textual seeds before seeding the local PCG generator.
	var identity := JSON.stringify([VERSION, year, seed, scope, preferences])
	source.seed = identity.sha256_text().substr(0, 15).hex_to_int()
	return source


static func _lane_schedule(year: int, lane: int, safe_lane: int, rng: RandomNumberGenerator) -> Dictionary:
	var layers: int = YEAR_LAYERS[year - 1]
	var schedule := {layers - 1: "R"}
	var risk_count: int = 0 if lane == safe_lane else [1, 2, 3, 3][year - 1]
	# Sampling one parity group leaves a non-risk layer between every pair of elites.
	var risk_candidates: Array = []
	var parity := rng.randi_range(0, 1)
	for layer in range(3, layers - 1):
		if layer % 2 == parity:
			risk_candidates.append(layer)
	_shuffle(risk_candidates, rng)
	for index in risk_count:
		schedule[risk_candidates[index]] = "risk"
	# Each lane keeps its content multiset while the seed determines the positions.
	# Final-year shared trial budget: replace one N with a second ST on every lane.
	var pool: Array = ["S", "R", "E", "research" if lane == 0 else "I", "C" if lane == 0 else "service"]
	if year == 3:
		pool.append("service")
	elif year == 4:
		pool.append_array(["ST", "ST"])
	var normal_count: int = [4, 4, 5, 4][year - 1] - risk_count
	for index in normal_count:
		pool.append("N")
	if year == 2:
		# Preserve an actual service after layer six on every route, including side detours.
		var late_positions: Array = []
		for layer in range(7, layers - 1):
			if not schedule.has(layer):
				late_positions.append(layer)
		var service_index := rng.randi_range(3, 4)
		var position: int = late_positions[rng.randi_range(0, late_positions.size() - 1)]
		schedule[position] = pool[service_index]
		pool.remove_at(service_index)
	_shuffle(pool, rng)
	for layer in range(2, layers - 1):
		if not schedule.has(layer):
			schedule[layer] = pool.pop_back()
	return schedule


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value


static func _resolve_subtype(token: String, rng: RandomNumberGenerator, profile: Dictionary) -> String:
	if token == "research":
		return _research_subtype(rng, profile)
	if token == "service":
		return _service_subtype(rng, profile)
	if token == "risk":
		var competition_weight: int = 3 + profile.competition
		if profile.direction == "competition":
			competition_weight += 18
		return "K" if rng.randi_range(1, 7 + competition_weight) <= competition_weight else "EL"
	return token


static func _service_subtype(rng: RandomNumberGenerator, profile: Dictionary) -> String:
	var weights: Array[int] = [6 + profile.research, 6 + profile.internship, 6 + profile.community]
	match profile.direction:
		"theory", "engineering": weights[0] += 18
		"practice": weights[1] += 18
	match profile.destination:
		"research", "exam": weights[0] += 24
		"job": weights[1] += 24
		"abroad":
			weights[0] += 12
			weights[2] += 24
	var draw := rng.randi_range(1, weights[0] + weights[1] + weights[2])
	if draw <= weights[0]:
		return _research_subtype(rng, profile)
	return "I" if draw <= weights[0] + weights[1] else "C"


static func _research_subtype(rng: RandomNumberGenerator, profile: Dictionary) -> String:
	var choices: Array[String] = ["L", "LAB", "T"]
	if profile.direction == "theory" or profile.destination == "exam":
		choices.append_array(["L", "L", "L"])
	elif profile.direction == "engineering":
		choices.append_array(["LAB", "LAB", "LAB"])
	elif profile.destination == "research":
		choices.append_array(["LAB", "T", "T"])
	return choices[rng.randi_range(0, choices.size() - 1)]


static func _node(year: int, layer: int, slot: int, column: int, subtype: String,
		rng: RandomNumberGenerator, profile: Dictionary) -> Dictionary:
	var title := ""
	match subtype:
		"N": title = NORMAL_TITLES[year - 1][rng.randi_range(0, NORMAL_TITLES[year - 1].size() - 1)]
		"E": title = EVENT_TITLES[year - 1][rng.randi_range(0, EVENT_TITLES[year - 1].size() - 1)]
		"EL": title = ELITE_TITLES[year - 1]
		"K": title = COMPETITION_TITLES[year - 1]
		"S": title = SHOP_TITLES[year - 1]
		"R": title = "宿舍休息" if year == 1 else "学年休整"
		"B":
			title = BOSS_TITLES[year - 1]
			if year == 4 and DESTINATION_CHALLENGES.has(profile.destination):
				title += "与" + DESTINATION_CHALLENGES[profile.destination]
		_:
			title = SERVICE_TITLES[subtype][year - 1]
			if year == 4 and subtype == "L" and profile.destination == "exam":
				title = "考研专题自习"
			elif year == 4 and subtype == "I" and profile.destination == "abroad":
				title = "海外实践交流"
	return {"key": _key(year, layer, slot), "year": year, "layer": layer,
		"kind": KINDS[subtype], "subtype": subtype, "title": title, "next": [], "column": column}


static func _key(year: int, layer: int, slot: int) -> String:
	return "y%dl%ds%d" % [year, layer, slot]


static func _exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


static func _nearby(nodes: Dictionary, key: String, last_layer: int) -> Dictionary:
	var found := {}
	var pending: Array = [key]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if found.has(current) or nodes[current].layer > last_layer:
			continue
		found[current] = true
		pending.append_array(nodes[current].next)
	return found
