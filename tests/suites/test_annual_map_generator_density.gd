extends RefCounted

var failures: Array[String] = []
var evidence: Array = []
var helpers: RefCounted


func run() -> Array[String]:
	var generator: GDScript = load("res://src/run/annual_map_generator.gd")
	_check(generator != null and generator.can_instantiate(), "density generator loads")
	if generator == null or not generator.can_instantiate():
		return failures
	_check(generator.VERSION == 2, "new annual maps default to generation version 2")
	if generator.VERSION != 2:
		return failures
	helpers = load("res://tests/suites/test_annual_map_generator.gd").new()
	# Run the same identity and opportunity assertions for both algorithm versions.
	helpers._test_identity(generator)
	helpers._test_profiles(generator)
	failures.append_array(helpers.failures)
	_test_dispatch(generator)
	_test_properties(generator)
	_test_variation(generator)
	_test_fork_boundary(generator)
	_test_rejection(generator)
	var directory := "res://artifacts/verification/adaptive-maps-20261113/density-generator-worker-v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output := FileAccess.open(directory + "/property-inputs.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"generator_version": 2, "cases": evidence}, "\t"))
	else:
		_check(false, "density property evidence can be written")
	print("DENSITY_GENERATOR_PROPERTY_CASES=%d FAILURES=%d" % [evidence.size(), failures.size()])
	return failures


func _test_dispatch(generator: GDScript) -> void:
	var legacy: GDScript = load("res://src/run/annual_map_generator_v1.gd")
	for year in range(1, 5):
		for index in 12:
			var profile := {"research": index % 7, "direction": "engineering", "destination": "exam"}
			var map_seed := "legacy-replay-%d" % index
			var original: Dictionary = legacy.generate(year, map_seed, profile)
			_check(generator.generate(year, map_seed, profile, 1) == original, "version 1 dispatch preserves full original maps")
			_check(generator.validate(original) == legacy.validate(original), "version 1 validation dispatch preserves original behavior")
			var current: Dictionary = generator.generate(year, map_seed, profile)
			_check(current == generator.generate(year, map_seed, profile, 2), "explicit version 2 equals default generation")
			_check(not legacy.validate(current).is_empty(), "legacy validator does not accept version 2")
	for version in [-1, 0, 3, 999]:
		_check(generator.generate(1, "unsupported", {}, version).is_empty(), "unsupported generator version is rejected")
		var bad: Dictionary = generator.generate(1, "unsupported")
		bad.version = version
		_check(not generator.validate(bad).is_empty(), "unsupported map version is rejected")
	_check(not generator.validate({}).is_empty(), "version dispatch rejects missing schema")
	var broken: Dictionary = generator.generate(1, "legacy-corrupt", {}, 1)
	broken.nodes[0].next.clear()
	_check(generator.validate(broken) == legacy.validate(broken), "legacy corruption still uses exact original validation")


func _test_properties(generator: GDScript) -> void:
	for year in range(1, 5):
		for index in 100:
			var map_seed := "density-property-%03d" % index
			var profile := {"research": index % 7, "competition": (index + 2) % 7,
				"internship": (index + 4) % 7, "community": (index + 6) % 7,
				"direction": ["", "theory", "engineering", "practice", "competition"][index % 5],
				"destination": ["", "job", "exam", "research", "abroad"][index % 5]}
			var map: Dictionary = generator.generate(year, map_seed, profile)
			var context := "density year=%d seed=%s" % [year, map_seed]
			_check(not map.is_empty(), context + ": generated map")
			if map.is_empty():
				continue
			_check(map == generator.generate(year, map_seed, profile), context + ": full deterministic replay")
			_check(generator.validate(map).is_empty(), context + ": generated map validates")
			var summary := _inspect(map, context)
			var neutral: Dictionary = generator.generate(year, map_seed)
			_check(helpers._signature(neutral) == helpers._signature(map), context + ": profile does not change topology")
			_check(helpers._risk_budget(neutral) == helpers._risk_budget(map), context + ": profile does not change budget or layer order")
			evidence.append({"year": year, "seed": map_seed, "profile": profile,
				"nodes": map.nodes.size(), "topology": helpers._signature(map), "summary": summary})


func _inspect(map: Dictionary, context: String) -> Dictionary:
	_check(map.version == 2 and map.layers == [12, 12, 14, 14][map.year - 1], context + ": version and annual length")
	_check(helpers._exact_fields(map, helpers.MAP_FIELDS), context + ": exact map schema")
	_check(helpers._exact_fields(map.profile, helpers.PROFILE_FIELDS), context + ": exact profile schema")
	_check(map.relic_layers == ([3, 9] if map.year <= 2 else [3, 10]), context + ": two original relic layers")
	var nodes: Dictionary = helpers._index(map)
	var by_layer := {}
	var forks := 0
	for node in map.nodes:
		_check(helpers._exact_fields(node, helpers.NODE_FIELDS), context + ": exact node schema")
		_check(node.year == map.year and node.kind == helpers.KINDS.get(node.subtype), context + ": runtime subtype semantics")
		_check(not node.title.is_empty(), context + ": readable content title")
		if not by_layer.has(node.layer):
			by_layer[node.layer] = []
		_check(not by_layer[node.layer].has(node.column) and node.column >= 0 and node.column <= 6, context + ": unique bounded columns")
		by_layer[node.layer].append(node.column)
		_check(node.next.size() <= (3 if node.layer == 1 else 2), context + ": entrance and ordinary degree limits")
		for target in node.next:
			_check(nodes.has(target) and nodes[target].layer == node.layer + 1, context + ": adjacent existing successors")
			_check(node.kind != "elite" or nodes[target].kind != "elite", context + ": nonconsecutive risks")
		if node.layer == map.layers - 1:
			_check(node.subtype == "R", context + ": actual recovery immediately before boss")
		if node.kind == "elite":
			_check(node.layer >= 3 and node.layer < map.layers - 1, context + ": bounded risk layers")
		if node.next.size() >= 2:
			if node.layer > 1:
				forks += 1
			for left_index in node.next.size():
				for right_index in range(left_index + 1, node.next.size()):
					var left: Dictionary = helpers._nearby(nodes, node.next[left_index], node.layer + 3)
					var right: Dictionary = helpers._nearby(nodes, node.next[right_index], node.layer + 3)
					for key in left:
						_check(not right.has(key), context + ": all fork arms retain three independent nodes")
		for other in map.nodes:
			if other.layer != node.layer or other.column <= node.column:
				continue
			for target in node.next:
				for other_target in other.next:
					_check(nodes[target].column <= nodes[other_target].column, context + ": no crossing edges")
	var wide_layers := 0
	for layer in range(2, map.layers):
		var width: int = by_layer[layer].size()
		_check(width >= 3 and width <= 5, context + ": middle width 3..5")
		wide_layers += int(width >= 4)
		for lane in 3:
			var key := "y%dl%ds%d" % [map.year, layer, lane]
			_check(nodes.has(key) and nodes[key].column == 1 + lane * 2, context + ": three sustained central main lanes")
	_check(2 * wide_layers >= map.layers - 2, context + ": at least half of middle layers have 4..5 nodes")
	_check(forks >= 2, context + ": at least two sustained side branches")
	_check(by_layer[1].size() == 1 and map.nodes[0].subtype == "N" and map.nodes[0].next.size() == 3, context + ": three initial entrances")
	_check(by_layer[map.layers].size() == 1 and map.nodes[-1].subtype == "B" and map.nodes[-1].next.is_empty(), context + ": single terminal boss")
	var paths: Array = helpers._paths(nodes, map.nodes[0].key)
	var common: Array = paths[0].duplicate()
	var visited := {}
	var safe := false
	var budgets := {}
	for path in paths:
		var counts := {"normal": 0, "elite": 0, "event": 0, "shop": 0, "rest": 0, "boss": 0, "R": 0, "ST": 0, "late_service": 0}
		for key in common.duplicate():
			if not path.has(key):
				common.erase(key)
		for key in path:
			var node: Dictionary = nodes[key]
			visited[key] = true
			counts[node.kind] += 1
			counts.R += int(node.subtype == "R")
			counts.ST += int(node.subtype == "ST")
			counts.late_service += int(node.layer >= 7 and node.kind == "rest" and node.subtype != "R")
		_check(path.size() == map.layers and path[-1] == map.nodes[-1].key, context + ": complete annual path")
		_check(counts.normal + counts.elite == [5, 5, 6, 5][map.year - 1], context + ": exact original combat multiset")
		_check(counts.elite in [0, [1, 2, 3, 3][map.year - 1]], context + ": exact safe or risky budget")
		_check(counts.normal >= [4, 3, 3, 2][map.year - 1], context + ": normal combat floor")
		_check(counts.event == 1 and counts.shop == 1 and counts.boss == 1 and counts.R == 2, context + ": exact event/shop/boss/recovery multiset")
		_check(counts.rest == [4, 4, 5, 6][map.year - 1] and counts.ST == (2 if map.year == 4 else 0), context + ": exact service and thesis multiset")
		_check(map.year != 2 or counts.late_service >= 1, context + ": late direction service on every year-two path")
		safe = safe or counts.elite == 0
		budgets[JSON.stringify(counts)] = true
	_check(safe and common.size() == 2, context + ": safe route and no universal middle chokepoints")
	_check(visited.size() == nodes.size(), context + ": every candidate lies on a full path")
	return {"wide_layers": wide_layers, "forks": forks, "paths": paths.size(), "budgets": budgets.keys()}


func _test_variation(generator: GDScript) -> void:
	for year in range(1, 5):
		var topologies := {}
		var widths := {}
		var positions: Array = [{}, {}, {}]
		for index in 30:
			var map: Dictionary = generator.generate(year, "density-variation-%d" % index)
			topologies[helpers._signature(map)] = true
			var counts := {}
			for node in map.nodes:
				counts[node.layer] = counts.get(node.layer, 0) + 1
				for lane in 3:
					if node.key.ends_with("s%d" % lane) and node.layer > 1 and node.kind == "shop":
						positions[lane][node.layer] = true
			widths[JSON.stringify(counts)] = true
		_check(topologies.size() >= 15 and widths.size() >= 12, "year %d: seeds vary actual branching and width, not only column decoration" % year)
		for lane in 3:
			_check(positions[lane].size() >= 5, "year %d lane %d: shop layer varies across seeds" % [year, lane])
		print("DENSITY_GENERATOR_VARIATION year=%d topologies=%d widths=%d shop_layers=%s" % [year, topologies.size(), widths.size(), JSON.stringify(positions)])


func _test_fork_boundary(generator: GDScript) -> void:
	var fixture := {}
	# Keep a long left branch so reducing the right branch changes only disjointness.
	for index in 30:
		var candidate: Dictionary = generator.generate(1, "density-fork-boundary-%d" % index)
		var left_length: int = candidate.nodes.filter(func(node: Dictionary): return node.key.ends_with("s3")).size()
		if 2 * left_length >= candidate.layers - 2:
			fixture = candidate
			break
	_check(not fixture.is_empty(), "density fork fixture retains the independent wide-layer budget")
	if fixture.is_empty():
		return
	fixture.nodes = fixture.nodes.filter(func(node: Dictionary): return not node.key.ends_with("s4"))
	for node in fixture.nodes:
		if node.key.ends_with("s2"):
			node.next = ["y1l%ds%d" % [node.layer + 1, 0 if node.layer + 1 == fixture.layers else 2]]
	for length in [3, 1, 2]:
		var map := fixture.duplicate(true)
		for node in fixture.nodes:
			if node.layer == 3 and node.key.ends_with("s2"):
				for parent in map.nodes:
					if parent.key == node.key:
						parent.next.append("y1l4s4")
			if node.layer >= 4 and node.layer < 4 + length and node.key.ends_with("s2"):
				var side: Dictionary = node.duplicate(true)
				side.key = "y1l%ds4" % node.layer
				side.column = 6
				side.next = ["y1l%ds%d" % [node.layer + 1, 2 if node.layer == 3 + length else 4]]
				map.nodes.append(side)
		var issues: Array[String] = generator.validate(map)
		if length == 3:
			_check(issues.is_empty(), "density accepts exactly three independent branch nodes")
		else:
			_check(issues.size() == 1 and issues[0].contains("three independent"),
				"density rejects a %d-node branch specifically for early merging" % length)


func _test_rejection(generator: GDScript) -> void:
	var good: Dictionary = generator.generate(4, "density-corruption")
	for field in helpers.MAP_FIELDS:
		var bad := good.duplicate(true)
		bad.erase(field)
		_reject(generator, bad, "missing map field " + field)
	for field in helpers.NODE_FIELDS:
		var bad := good.duplicate(true)
		bad.nodes[0].erase(field)
		_reject(generator, bad, "missing node field " + field)
	for field in ["version", "year", "layers"]:
		var bad := good.duplicate(true)
		bad[field] = float(bad[field])
		_reject(generator, bad, "float " + field)
	for label in ["extra_map", "extra_node", "extra_profile", "column_collision", "unknown_subtype", "duplicate_edge", "four_entrances", "two_entrances", "wrong_width", "extra_shop", "lost_event", "lost_ST", "lost_recovery", "short_fork"]:
		var bad := good.duplicate(true)
		match label:
			"extra_map": bad.extra = true
			"extra_node": bad.nodes[0].extra = true
			"extra_profile": bad.profile.extra = true
			"column_collision": bad.nodes[2].column = bad.nodes[1].column
			"unknown_subtype": bad.nodes[0].subtype = "UNKNOWN"
			"duplicate_edge": bad.nodes[0].next[1] = bad.nodes[0].next[0]
			"four_entrances": bad.nodes[0].next.append(bad.nodes[0].next[0])
			"two_entrances": bad.nodes[0].next.pop_back()
			"wrong_width":
				bad.nodes = bad.nodes.filter(func(node: Dictionary): return not node.key.ends_with("s1"))
				bad.nodes[0].next.remove_at(1)
			"short_fork":
				for node in bad.nodes:
					if node.layer > 1 and node.next.size() == 2:
						var side_key: String = node.next[1]
						for side in bad.nodes:
							if side.key == side_key:
								var main: Dictionary = helpers._index(bad)[node.next[0]]
								side.next = main.next.duplicate()
						break
			_:
				for node in bad.nodes:
					if label == "extra_shop" and node.kind == "event":
						node.subtype = "S"
						node.kind = "shop"
					if label == "lost_event" and node.kind == "event":
						node.subtype = "N"
						node.kind = "normal"
					if label == "lost_ST" and node.subtype == "ST": node.subtype = "I"
					if label == "lost_recovery" and node.subtype == "R": node.subtype = "LAB"
		_reject(generator, bad, label)
	var no_late: Dictionary = generator.generate(2, "density-late-direction")
	for node in no_late.nodes:
		if node.layer >= 7 and node.kind == "rest" and node.subtype != "R": node.subtype = "R"
	_reject(generator, no_late, "no late year-two service")


func _reject(generator: GDScript, map: Dictionary, label: String) -> void:
	_check(not generator.validate(map).is_empty(), "density corruption rejected: " + label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
