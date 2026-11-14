extends RefCounted

var failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	var density: RefCounted = load("res://tests/suites/test_annual_map_generator_density.gd").new()
	density.helpers = load("res://tests/suites/test_annual_map_generator.gd").new()
	density.expected_version = 3
	density._test_properties(AnnualMapGenerator)
	density._test_variation(AnnualMapGenerator)
	failures.append_array(density.failures)
	for year in range(1, 5):
		for index in 100:
			var map := AnnualMapGenerator.generate(year, "v3-choices-%d" % index)
			_check(not map.is_empty(), "map exists")
			if map.is_empty():
				continue
			var nodes := {}
			for node in map.nodes:
				nodes[node.key] = node
			for fork in map.nodes:
				if fork.layer == 1 or fork.next.size() != 2:
					continue
				var left := str(fork.next[0])
				var right := str(fork.next[1])
				var differences := 0
				var early := false
				var corrupt := map.duplicate(true)
				while left != right and nodes[left].next.size() == 1 and nodes[right].next.size() == 1:
					var a: Dictionary = nodes[left]
					var b: Dictionary = nodes[right]
					var same: bool = a.kind == b.kind and (a.kind != "rest" or a.subtype == b.subtype)
					differences += int(not same)
					early = early or (not same and a.layer <= fork.layer + 3)
					for changed in corrupt.nodes:
						if changed.key == right:
							changed.kind = a.kind
							changed.subtype = a.subtype
					left = nodes[left].next[0]
					right = nodes[right].next[0]
				_check(differences >= 2 and early, "each detour has two real category differences, visible within three stops")
				_check(not AnnualMapGenerator.validate(corrupt).is_empty(), "equivalent copied detour is rejected")
			for version in [1, 2]:
				var legacy: GDScript = load("res://src/run/annual_map_generator_v%d.gd" % version)
				var original: Dictionary = legacy.generate(year, "v3-choices-%d" % index)
				_check(AnnualMapGenerator.generate(year, "v3-choices-%d" % index, {}, version) == original, "legacy dispatch preserves every old node")
				_check(AnnualMapGenerator.validate(original) == legacy.validate(original), "legacy validation is unchanged")
	var directory := OS.get_environment("CAMPUS_MAP_EVIDENCE_OUT")
	if directory.is_empty():
		directory = "user://map-property-evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory + "/v3"))
	var file := FileAccess.open(directory + "/v3/property-inputs.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 3, "cases": density.evidence, "branch_checks": _checks, "failures": failures}, "\t"))
	print("MAP_V3_CASES=800 BRANCH_COMPAT_CHECKS=%d FAILURES=%d" % [_checks, failures.size()])
	return failures


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		failures.append("map v3: " + message)
