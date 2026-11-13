extends RefCounted

const MAP_FIELDS := ["version", "year", "title", "layers", "relic_layers", "seed", "profile", "nodes"]
const NODE_FIELDS := ["key", "year", "layer", "kind", "subtype", "title", "next", "column"]
const PROFILE_FIELDS := ["research", "competition", "internship", "community", "direction", "destination"]
const KINDS := {"N": "normal", "E": "event", "S": "shop", "EL": "elite", "K": "elite",
	"R": "rest", "L": "rest", "LAB": "rest", "C": "rest", "T": "rest", "I": "rest",
	"ST": "rest", "B": "boss"}

var failures: Array[String] = []
var evidence: Array = []
var placement_evidence: Array = []


func run() -> Array[String]:
	var generator: GDScript = load("res://src/run/annual_map_generator_v1.gd")
	_check(generator != null and generator.can_instantiate(), "generator script loads")
	if generator == null or not generator.can_instantiate():
		return failures
	_test_identity(generator)
	_test_properties(generator)
	_test_first_year_budgets(generator)
	_test_variation(generator)
	_test_profiles(generator)
	_test_layer_schedules(generator)
	_test_route_service_guarantees(generator)
	_test_fork_boundary(generator)
	_test_rejection(generator)
	var density_suite: RefCounted = load("res://tests/suites/test_annual_map_generator_density.gd").new()
	failures.append_array(density_suite.run())
	var directory := "res://artifacts/verification/adaptive-maps-20261113/density-generator-worker"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output := FileAccess.open(directory + "/property-inputs.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"generator_version": 1, "cases": evidence,
			"placement_variation": placement_evidence}, "\t"))
	else:
		_check(false, "property evidence can be written")
	print("GENERATOR_PROPERTY_CASES=%d FAILURES=%d" % [evidence.size(), failures.size()])
	return failures


func run_placement_checks() -> Array[String]:
	var generator: GDScript = load("res://src/run/annual_map_generator_v1.gd")
	_test_layer_schedules(generator)
	_test_route_service_guarantees(generator)
	return failures


func _test_identity(generator: GDScript) -> void:
	var profile := {"research": 3, "competition": 1, "internship": 2, "community": 0,
		"direction": "engineering", "destination": "job"}
	var before := profile.duplicate(true)
	var first: Dictionary = generator.generate(3, "独立种子|annual", profile)
	seed(918273)
	var expected := randi()
	seed(918273)
	var replay: Dictionary = generator.generate(3, "独立种子|annual", profile)
	_check(randi() == expected, "generation leaves global RNG unchanged")
	_check(first == replay, "same inputs reproduce the complete map")
	_check(profile == before, "generation leaves the supplied profile unchanged")
	profile.run_id = "a"
	_check(generator.generate(3, "独立种子|annual", profile) == first, "run_id is ignored")
	profile.run_id = "b"
	_check(generator.generate(3, "独立种子|annual", profile) == first, "run_id never changes identity")
	var normalized: Dictionary = generator.generate(2, "normalize", {
		"research": 90, "competition": -1, "internship": 2.9, "community": "bad",
		"direction": "theory", "destination": null, "ignored": true}).profile
	_check(normalized == {"research": 6, "competition": 0, "internship": 2,
		"community": 0, "direction": "theory", "destination": ""}, "profile is clamped, typed and stripped")
	_check(generator.generate(2, "normalize", normalized).profile == normalized, "normalization is idempotent")
	_check(generator.generate(0, "invalid").is_empty(), "year zero is rejected")
	_check(generator.generate(5, "invalid").is_empty(), "year five is rejected")
	_check(generator.validate(generator.generate(1, "")).is_empty(), "empty string is a valid deterministic seed")
	var frozen := first.duplicate(true)
	generator.validate(first)
	_check(first == frozen, "validation leaves its input unchanged")
	replay.nodes[0].next.clear()
	_check(generator.generate(3, "独立种子|annual", before) == frozen, "returned maps share no mutable state")


func _test_properties(generator: GDScript) -> void:
	for year in range(1, 5):
		for index in 100:
			var map_seed := "property-%03d" % index
			var profile := {"research": index % 7, "competition": (index + 2) % 7,
				"internship": (index + 4) % 7, "community": (index + 6) % 7,
				"direction": ["", "theory", "engineering", "practice"][index % 4],
				"destination": ["", "job", "exam", "research", "abroad"][index % 5]}
			var map: Dictionary = generator.generate(year, map_seed, profile)
			var issues: Array[String] = generator.validate(map)
			var context := "year=%d seed=%s" % [year, map_seed]
			_check(issues.is_empty(), context + ": " + "; ".join(issues))
			_check(map == generator.generate(year, map_seed, profile), context + ": deterministic replay")
			var result := _inspect(map, context)
			evidence.append({"year": year, "seed": map_seed, "profile": profile,
				"topology": _signature(map), "nodes": map.nodes.size(), "routes": result,
				"validation_issues": issues})


func _inspect(map: Dictionary, context: String) -> Array:
	_check(_exact_fields(map, MAP_FIELDS), context + ": exact map fields")
	_check(map.version == 1 and map.layers == [12, 12, 14, 14][map.year - 1], context + ": annual version/length")
	_check(_exact_fields(map.profile, PROFILE_FIELDS), context + ": exact normalized profile fields")
	_check(map.relic_layers == ([3, 9] if map.year <= 2 else [3, 10]), context + ": two fixed relic checkpoints")
	_check(map.year != 1 or map.nodes.size() > 20, context + ": first year has long route candidates")
	var nodes := _index(map)
	var starts: Array = []
	var bosses: Array = []
	var layers := {}
	var key_pattern := RegEx.create_from_string("^y%d+l[0-9]+[sc][0-9]+$" % map.year)
	for node in map.nodes:
		_check(_exact_fields(node, NODE_FIELDS), context + ": exact node fields")
		_check(node.year == map.year and key_pattern.search(node.key) != null, context + ": year local stable key")
		_check(typeof(node.column) == TYPE_INT and node.column >= 0 and node.column <= 6, context + ": integer columns")
		_check(node.kind == KINDS.get(node.subtype, "unknown"), context + ": runtime subtype semantics")
		_check(node.next.size() <= 2, context + ": maximum outdegree two")
		_check(not node.title.is_empty(), context + ": useful title")
		if not layers.has(node.layer):
			layers[node.layer] = []
		_check(not layers[node.layer].has(node.column), context + ": no column collisions")
		layers[node.layer].append(node.column)
		if node.layer == 1:
			starts.append(node)
		if node.layer == map.layers - 1:
			_check(node.subtype == "R", context + ": recovery immediately before the boss")
		if node.kind == "elite":
			_check(node.layer >= 3 and node.layer < map.layers - 1, context + ": risk stays out of the initial and final rest layers")
		if node.kind == "boss":
			bosses.append(node)
		for target in node.next:
			_check(nodes.has(target), context + ": successor exists")
			if nodes.has(target):
				_check(nodes[target].layer == node.layer + 1, context + ": adjacent edges")
				_check(node.kind != "elite" or nodes[target].kind != "elite", context + ": no consecutive elites")
		if node.next.size() == 2:
			var left := _nearby(nodes, node.next[0], node.layer + 3)
			var right := _nearby(nodes, node.next[1], node.layer + 3)
			for key in left:
				_check(not right.has(key), context + ": fork retains three independent nodes")
	_check(starts.size() == 1 and starts[0].subtype == "N", context + ": single normal starter")
	_check(bosses.size() == 1 and bosses[0].layer == map.layers and bosses[0].next.is_empty(), context + ": single terminal boss")
	for layer in range(2, map.layers):
		_check(layers[layer].size() >= 2 and layers[layer].size() <= 4, context + ": 2-4 simultaneous routes")
	var paths := _paths(nodes, starts[0].key)
	var visited := {}
	var common := {}
	var safe := false
	var budgets: Array = []
	for key in paths[0]:
		common[key] = true
	for path in paths:
		var counts := {"normal": 0, "event": 0, "shop": 0, "rest": 0, "elite": 0, "boss": 0,
			"R": 0, "ST": 0, "late_service": 0}
		for key in common.keys():
			if not path.has(key):
				common.erase(key)
		for key in path:
			visited[key] = true
			counts[nodes[key].kind] += 1
			if nodes[key].subtype == "R":
				counts.R += 1
			if nodes[key].subtype == "ST":
				counts.ST += 1
			if nodes[key].kind == "rest" and nodes[key].subtype != "R" and nodes[key].layer >= 7:
				counts.late_service += 1
		_check(path.size() == map.layers and path[-1] == bosses[0].key, context + ": full start to boss route")
		_check(counts.shop >= 1 and counts.rest >= 2 and counts.R >= 2, context + ": route shop and actual recovery budget")
		_check(counts.elite <= [1, 2, 3, 3][map.year - 1], context + ": bounded annual risk")
		_check(counts.normal >= [4, 3, 3, 2][map.year - 1], context + ": annual combat floor")
		_check(counts.elite in [0, [1, 2, 3, 3][map.year - 1]], context + ": shuffled routes retain the safe or risky lane budget")
		_check(counts.normal + counts.elite == [5, 5, 6, 5][map.year - 1], context + ": scheduling preserves the annual combat multiset")
		_check(counts.event == 1 and counts.shop == 1 and counts.boss == 1 and counts.R == 2,
			context + ": main lanes and side branches retain event, shop, boss and recovery counts")
		_check(counts.rest == [4, 4, 5, 6][map.year - 1] and counts.ST == (2 if map.year == 4 else 0),
			context + ": scheduling preserves the annual service multiset with two final-year ST services")
		_check(map.year != 2 or counts.late_service >= 1, context + ": each year two route retains a late change-direction service")
		_check(map.year != 4 or counts.ST >= 2, context + ": each final year route has two ST opportunities without paid research services")
		if counts.elite == 0:
			safe = true
		budgets.append(counts)
	_check(visited.size() == nodes.size(), context + ": every node lies on a full route")
	_check(common.size() == 2 and common.has(starts[0].key) and common.has(bosses[0].key), context + ": only start and boss are universal")
	_check(safe, context + ": elite and competition free route")
	return budgets


func _test_variation(generator: GDScript) -> void:
	for year in range(1, 5):
		var signatures := {}
		var widths := {}
		for index in 30:
			var map: Dictionary = generator.generate(year, "variation-%d" % index)
			signatures[_signature(map)] = true
			var counts := {}
			for node in map.nodes:
				counts[node.layer] = counts.get(node.layer, 0) + 1
			widths[JSON.stringify(counts)] = true
		_check(signatures.size() >= 15 and widths.size() >= 12, "year %d: 30 seeds change actual branching/edges" % year)
		print("GENERATOR_TOPOLOGY_VARIATION year=%d seeds=30 signatures=%d widths=%d" % [year, signatures.size(), widths.size()])


func _test_first_year_budgets(generator: GDScript) -> void:
	var expected := {}
	for index in 100:
		var map: Dictionary = generator.generate(1, "budget-%d" % index)
		var nodes := _index(map)
		var budgets := {}
		for path in _paths(nodes, map.nodes[0].key):
			var counts := {"normal": 0, "elite": 0, "rest": 0, "shop": 0, "event": 0, "boss": 0}
			for key in path:
				counts[nodes[key].kind] += 1
			budgets[JSON.stringify(counts)] = true
		if index == 0:
			expected = budgets
		_check(budgets == expected, "all first year seeds share the same route budget bounds")
	print("GENERATOR_FIRST_YEAR_BUDGETS seeds=100 signatures=%d" % expected.size())


func _test_layer_schedules(generator: GDScript) -> void:
	for year in range(1, 5):
		var observed: Array = [{"shop": {}, "recovery": {}, "service": {}, "risk": {}},
			{"shop": {}, "recovery": {}, "service": {}, "risk": {}}]
		var independent := 0
		for index in 30:
			var map: Dictionary = generator.generate(year, "placement-%d" % index)
			var orders: Array = [[], []]
			for lane in 2:
				var positions := {"shop": [], "recovery": [], "service": [], "risk": []}
				for node in map.nodes:
					if not node.key.ends_with("s%d" % lane) or node.layer <= 1 or node.layer >= map.layers - 1:
						continue
					var category := "battle"
					if node.kind == "shop": category = "shop"
					elif node.subtype == "R": category = "recovery"
					elif node.kind == "rest": category = "service"
					elif node.kind == "event": category = "event"
					orders[lane].append(category)
					if positions.has(category): positions[category].append(node.layer)
					if node.kind == "elite": positions.risk.append(node.layer)
				for category in positions:
					observed[lane][category][JSON.stringify(positions[category])] = true
				if positions.risk.size() > 1:
					for layer in positions.risk:
						_check(layer % 2 == positions.risk[0] % 2, "risk samples one nonadjacent parity group")
			if orders[0] != orders[1]: independent += 1
		_check(independent >= 20, "year %d: main lanes independently arrange non-risk categories" % year)
		var counts: Array = []
		for lane in 2:
			var summary := {}
			for category in observed[lane]:
				summary[category] = observed[lane][category].size()
				_check(summary[category] >= 5, "year %d lane %d: %s positions vary across seeds" % [year, lane, category])
			counts.append(summary)
		placement_evidence.append({"year": year, "seeds": 30, "distinct_positions": counts,
			"independent_main_lane_orders": independent})
		print("GENERATOR_LAYER_VARIATION year=%d independent=%d counts=%s" % [year, independent, JSON.stringify(counts)])


func _test_route_service_guarantees(generator: GDScript) -> void:
	var map: Dictionary = generator.generate(4, "thesis-budget", {"destination": "job"})
	var nodes := _index(map)
	for path in _paths(nodes, map.nodes[0].key):
		var thesis := 0
		for key in path:
			thesis += int(nodes[key].subtype == "ST")
		_check(thesis == 2, "final year common budget has exactly two free ST services on every route")
	var insufficient := map.duplicate(true)
	for node in insufficient.nodes:
		if node.subtype == "ST" and int(String(node.key).get_slice("s", 1)) % 2 == 0:
			node.subtype = "I"
	_check(generator.validate(insufficient).any(func(issue: String): return issue.contains("two ST")),
		"ST on another lane cannot satisfy the final year route budget")
	var bypass_found := false
	for index in 30:
		var branch_map: Dictionary = generator.generate(4, "thesis-side-%d" % index)
		for node in branch_map.nodes:
			if node.subtype == "ST" and int(String(node.key).get_slice("s", 1)) >= 2:
				node.subtype = "I"
				bypass_found = true
				break
		if bypass_found:
			_check(generator.validate(branch_map).any(func(issue: String): return issue.contains("two ST")),
				"a side branch may not bypass a mandatory ST opportunity")
			break
	_check(bypass_found, "a generated side branch exercises the ST route guarantee")
	var no_late_service: Dictionary = generator.generate(2, "late-direction")
	for node in no_late_service.nodes:
		if node.kind == "rest" and node.subtype != "R" and node.layer >= 7:
			node.subtype = "R"
	_check(generator.validate(no_late_service).any(func(issue: String): return issue.contains("late service")),
		"year two rejects routes without a change-direction service in the second half")
	var no_final_recovery: Dictionary = generator.generate(1, "last-rest")
	for node in no_final_recovery.nodes:
		if node.layer == no_final_recovery.layers - 1:
			node.subtype = "I"
	_check(generator.validate(no_final_recovery).any(func(issue: String): return issue.contains("before the boss")),
		"the final recovery layer cannot be replaced by a paid or career service")


func _test_profiles(generator: GDScript) -> void:
	var totals := {}
	for theme in ["research", "competition", "internship", "community"]:
		var base_score := 0
		var biased_score := 0
		for index in 40:
			var map_seed := "bias-%d" % index
			var profile := {theme: 6}
			var neutral: Dictionary = generator.generate(3, map_seed)
			var biased: Dictionary = generator.generate(3, map_seed, profile)
			base_score += _theme_score(neutral, theme)
			biased_score += _theme_score(biased, theme)
			_check(generator.validate(biased).is_empty(), theme + ": valid biased routes")
			_check(_risk_budget(neutral) == _risk_budget(biased), theme + ": experience does not increase combat/risk budgets")
			_check(_has_alternatives(biased), theme + ": alternatives remain selectable")
		totals[theme] = {"base": base_score, "biased": biased_score}
		_check(biased_score > base_score, theme + ": completed experience measurably influences opportunities")
	for direction in ["theory", "engineering", "practice", "competition"]:
		var map: Dictionary = generator.generate(2, "direction-choice", {"direction": direction})
		_check(_has_alternatives(map), "chosen direction retains alternative services")
		var target_type: String = {"theory": "L", "engineering": "LAB", "practice": "I", "competition": "K"}[direction]
		var neutral_count := 0
		var direction_count := 0
		for index in 40:
			var map_seed := "explicit-%d" % index
			neutral_count += _subtype_count(generator.generate(2, map_seed), target_type)
			# A deliberate choice still matters in the presence of a competing experience history.
			var opposing_history := {"direction": direction, "community": 6}
			direction_count += _subtype_count(generator.generate(2, map_seed, opposing_history), target_type)
		_check(direction_count > neutral_count, direction + ": explicit direction increases corresponding opportunities")
	var destinations := {}
	for destination in ["job", "exam", "research", "abroad"]:
		var map: Dictionary = generator.generate(4, "destination-choice", {"destination": destination})
		destinations[JSON.stringify(map.nodes)] = true
		_check(map.nodes[-1].title.contains("毕业"), "all destinations retain the shared graduation requirement")
		_check(_has_alternatives(map), "chosen destination retains alternative services")
		var theme: String = {"job": "internship", "exam": "research", "research": "research", "abroad": "community"}[destination]
		var neutral_score := 0
		var destination_score := 0
		for index in 40:
			var map_seed := "explicit-%d" % index
			neutral_score += _theme_score(generator.generate(4, map_seed), theme)
			destination_score += _theme_score(generator.generate(4, map_seed, {"destination": destination}), theme)
		_check(destination_score > neutral_score, destination + ": destination changes services along the route")
	_check(destinations.size() == 4, "four destinations produce distinct opportunities and final challenge labels")
	print("GENERATOR_PROFILE_INFLUENCE=" + JSON.stringify(totals))


func _test_fork_boundary(generator: GDScript) -> void:
	var fixture: Dictionary = generator.generate(1, "fork-boundary")
	fixture.nodes = fixture.nodes.filter(func(node: Dictionary): return int(String(node.key).get_slice("s", 1)) < 2)
	for node in fixture.nodes:
		if node.layer > 1 and node.layer < fixture.layers:
			var slot := int(String(node.key).get_slice("s", 1))
			node.next = ["y1l%ds%d" % [node.layer + 1, 0 if node.layer + 1 == fixture.layers else slot]]
	_check(generator.validate(fixture).is_empty(), "a valid persistent two lane fixture is accepted")
	var long_branch := _with_detour(fixture, 3)
	_check(generator.validate(long_branch).is_empty(), "exactly three independent nodes before merge are accepted")
	for length in [1, 2]:
		var short_branch := _with_detour(fixture, length)
		var issues: Array[String] = generator.validate(short_branch)
		_check(issues.size() == 1 and issues[0].contains("three independent"), "otherwise valid short forks fail specifically the disjointness constraint")
	var one_route_without_shop := fixture.duplicate(true)
	for node in one_route_without_shop.nodes:
		if node.kind == "shop" and node.key.ends_with("s0"):
			node.kind = "normal"
			node.subtype = "N"
	_check(generator.validate(one_route_without_shop).any(func(issue: String): return issue.contains("every route needs")), "shops on another route cannot satisfy a route's budget")
	var one_route_without_recovery := fixture.duplicate(true)
	for node in one_route_without_recovery.nodes:
		if node.subtype == "R" and node.layer < fixture.layers - 1 and node.key.ends_with("s0"):
			node.subtype = "LAB"
	_check(generator.validate(one_route_without_recovery).any(func(issue: String): return issue.contains("recovery")), "paid services do not substitute for actual recovery")


func _with_detour(fixture: Dictionary, length: int) -> Dictionary:
	var map := fixture.duplicate(true)
	for node in fixture.nodes:
		if node.layer == 3 and node.key.ends_with("s0"):
			for parent in map.nodes:
				if parent.key == node.key:
					parent.next.append("y1l4s2")
		if node.layer >= 4 and node.layer < 4 + length and node.key.ends_with("s0"):
			var side: Dictionary = node.duplicate(true)
			side.key = "y1l%ds2" % node.layer
			side.column = 2
			side.next = ["y1l%ds%d" % [node.layer + 1, 0 if node.layer == 3 + length else 2]]
			map.nodes.append(side)
	return map


func _test_rejection(generator: GDScript) -> void:
	var good: Dictionary = generator.generate(1, "corruption")
	_reject(generator, {}, "empty map")
	for field in MAP_FIELDS:
		var bad := good.duplicate(true)
		bad.erase(field)
		_reject(generator, bad, "missing map field " + field)
	for field in NODE_FIELDS:
		var bad := good.duplicate(true)
		bad.nodes[0].erase(field)
		_reject(generator, bad, "missing node field " + field)
	for field in ["version", "year", "layers"]:
		var bad := good.duplicate(true)
		bad[field] = float(bad[field])
		_reject(generator, bad, "float " + field)
	var cases := ["extra_map", "extra_node", "extra_profile", "bad_version", "wrong_year", "wrong_layers",
		"bad_profile", "wrong_direction_type", "wrong_seed", "bad_relics", "nonarray_nodes", "nondict_node",
		"duplicate_key", "wrong_key_layer", "wrong_node_year", "column_range", "column_float", "column_collision",
		"wrong_kind", "unknown_subtype", "empty_title", "missing_target", "cross_year", "skip_layer",
		"nonarray_next", "nonstr_next", "duplicate_edge", "third_edge", "no_edge", "boss_edge",
		"no_shops", "no_recovery", "no_safe_route", "consecutive_elites", "orphan", "short_fork"]
	for label in cases:
		var bad := good.duplicate(true)
		match label:
			"extra_map": bad.extra = true
			"extra_node": bad.nodes[0].extra = true
			"extra_profile": bad.profile.extra = true
			"bad_version": bad.version = 2
			"wrong_year": bad.year = 7
			"wrong_layers": bad.layers = 14
			"bad_profile": bad.profile.research = 7
			"wrong_direction_type": bad.profile.direction = 1
			"wrong_seed": bad.seed = 42
			"bad_relics": bad.relic_layers = [3, 3]
			"nonarray_nodes": bad.nodes = {}
			"nondict_node": bad.nodes[1] = "node"
			"duplicate_key": bad.nodes.append(bad.nodes[0].duplicate(true))
			"wrong_key_layer": bad.nodes[0].key = "y1l2s9"
			"wrong_node_year": bad.nodes[0].year = 2
			"column_range": bad.nodes[0].column = 7
			"column_float": bad.nodes[0].column = 3.0
			"column_collision": bad.nodes[2].column = bad.nodes[1].column
			"wrong_kind": bad.nodes[0].kind = "rest"
			"unknown_subtype": bad.nodes[0].subtype = "SCRIPT"
			"empty_title": bad.nodes[0].title = ""
			"missing_target": bad.nodes[0].next[0] = "y1l2s99"
			"cross_year": bad.nodes[0].next[0] = "y2l2s0"
			"skip_layer": bad.nodes[0].next[0] = bad.nodes[3].key
			"nonarray_next": bad.nodes[0].next = {}
			"nonstr_next": bad.nodes[0].next[0] = 4
			"duplicate_edge": bad.nodes[0].next[1] = bad.nodes[0].next[0]
			"third_edge": bad.nodes[0].next.append(bad.nodes[3].key)
			"no_edge": bad.nodes[1].next = []
			"boss_edge": bad.nodes[-1].next = [bad.nodes[0].key]
			"orphan": bad.nodes[0].next.remove_at(1)
			"short_fork":
				for node in bad.nodes:
					if node.layer == 2:
						node.next = [bad.nodes[3].key]
			_:
				for node in bad.nodes:
					if (label == "no_shops" and node.kind == "shop") or (label == "no_recovery" and node.subtype == "R"):
						node.subtype = "N"
						node.kind = "normal"
					if (label == "no_safe_route" and node.layer == 4) or (label == "consecutive_elites" and node.layer in [4, 5]):
						node.subtype = "EL"
						node.kind = "elite"
		_reject(generator, bad, label)
	print("GENERATOR_CORRUPTION_CASES=%d" % (cases.size() + MAP_FIELDS.size() + NODE_FIELDS.size() + 4))


func _reject(generator: GDScript, map: Dictionary, label: String) -> void:
	_check(not generator.validate(map).is_empty(), "corrupted map rejected: " + label)


func _theme_score(map: Dictionary, theme: String) -> int:
	var types: Array = {"research": ["LAB", "L", "T"], "competition": ["K"],
		"internship": ["I"], "community": ["C"]}[theme]
	var score := 0
	for node in map.nodes:
		if node.subtype in types:
			score += 1
	return score


func _subtype_count(map: Dictionary, subtype: String) -> int:
	return map.nodes.filter(func(node: Dictionary): return node.subtype == subtype).size()


func _has_alternatives(map: Dictionary) -> bool:
	return _theme_score(map, "research") > 0 and _theme_score(map, "internship") > 0 and _theme_score(map, "community") > 0


func _risk_budget(map: Dictionary) -> Dictionary:
	var result := {}
	for node in map.nodes:
		# Side branches can alter candidate counts; each route's combat categories must stay fixed.
		result[str(node.layer) + ":" + str(node.key).get_slice("s", 1)] = node.kind
	return result


func _index(map: Dictionary) -> Dictionary:
	var result := {}
	for node in map.nodes:
		result[node.key] = node
	return result


func _paths(nodes: Dictionary, key: String) -> Array:
	if nodes[key].next.is_empty():
		return [[key]]
	var result: Array = []
	for target in nodes[key].next:
		for suffix in _paths(nodes, target):
			var path: Array = [key]
			path.append_array(suffix)
			result.append(path)
	return result


func _nearby(nodes: Dictionary, key: String, last_layer: int) -> Dictionary:
	var found := {}
	var pending: Array = [key]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if found.has(current) or nodes[current].layer > last_layer:
			continue
		found[current] = true
		pending.append_array(nodes[current].next)
	return found


func _signature(map: Dictionary) -> String:
	# Contains edges and identities only: renaming titles or moving columns cannot satisfy variation.
	var parts: Array[String] = []
	for node in map.nodes:
		parts.append(node.key + ">" + ",".join(node.next))
	return "|".join(parts)


func _exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
