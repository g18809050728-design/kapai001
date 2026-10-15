extends SceneTree

const CONTENT_DB = preload("res://src/content/content_db.gd")

var _db = CONTENT_DB.new()


func _initialize() -> void:
	var cards_path := "res://artifacts/g2-build/staging/cards/cards.json"
	var cards: Variant = _read_json(cards_path)
	if typeof(cards) != TYPE_ARRAY:
		push_error("cards.json must contain an array")
		quit(1)
		return

	var failures := 0
	var definitions := _load_production_definitions()
	var manifest: Dictionary = _read_json("res://data/manifests/campus_mvp.json")
	var enabled: Dictionary = manifest.get("enabled", {}).duplicate(true)
	enabled["card"] = enabled.get("card", []).duplicate()
	for dependency_kind in ["unit", "scene"]:
		enabled[dependency_kind] = enabled.get(dependency_kind, []).duplicate()
		for dependency_id in (["F01", "F02", "F03", "F04"] if dependency_kind == "unit" else ["L01", "L02", "L03"]):
			enabled[dependency_kind].append(dependency_id)
	var card_rows: Array = _read_json("res://data/definitions/cards.json")
	var card_by_id: Dictionary = {}
	for card in card_rows:
		if typeof(card) == TYPE_DICTIONARY:
			card_by_id[str(card.get("id", ""))] = card

	var staged_ids: Array[String] = []
	var staged_by_id: Dictionary = {}
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY or typeof(card.get("id")) != TYPE_STRING:
			push_error("cards.json contains an invalid record")
			failures += 1
			continue
		var id: String = card.id
		if card_by_id.has(id):
			push_error("staging card duplicates enabled definition: %s" % id)
			failures += 1
			continue
		card_by_id[id] = _db._normalize_json_numbers(card)
		staged_ids.append(id)
		staged_by_id[id] = card_by_id[id]
		enabled.card.append(id)

	for id in staged_ids:
		var own_issues: Array[String] = []
		var definition: Dictionary = staged_by_id[id] as Dictionary
		_db._validate_definition_file("card", [definition], own_issues)
		if own_issues.is_empty():
			print("SCHEMA_OK card/%s" % id)
		else:
			for issue in own_issues:
				push_error("SCHEMA_FAIL card/%s: %s" % [id, issue])
			failures += 1
	definitions["card"].merge(staged_by_id)
	for dependency_kind in ["unit", "scene"]:
		var staged_dependencies: Array = _load_staged_entity_definitions(dependency_kind)
		var normalized_dependencies: Dictionary = {}
		for dependency in staged_dependencies:
			if typeof(dependency) == TYPE_DICTIONARY and typeof(dependency.get("id")) == TYPE_STRING:
				normalized_dependencies[dependency.id] = dependency
		definitions[dependency_kind].merge(normalized_dependencies)

	var package_manifest := manifest.duplicate(true)
	package_manifest.id = "test_cards_staging"
	package_manifest.enabled = enabled
	var probe_root := ProjectSettings.globalize_path(
		"res://.godot/g2_cards_staging_probe_%d" % Time.get_ticks_usec()
	)
	if not _write_isolated_package(probe_root, package_manifest, card_by_id):
		push_error("could not create isolated test package")
		quit(1)
		return

	var closure_failures := 0
	for id in staged_ids:
		var issues: Array[String] = []
		_db._validate_references_recursive("card", staged_by_id[id], id, enabled, definitions, issues)
		if issues.is_empty():
			print("REFERENCE_CLOSURE_OK card/%s" % id)
		else:
			closure_failures += 1
			for issue in issues:
				print("REFERENCE_CLOSURE_BLOCKED card/%s: %s" % [id, issue])

	var isolated_db = CONTENT_DB.new(probe_root, true)
	var loaded: GameResult = isolated_db.load("test_cards_staging")
	if loaded.ok:
		print("CARD_PACKAGE_LOAD_OK test_cards_staging")
	else:
		print("CARD_PACKAGE_LOAD_REJECTED test_cards_staging")
		print(JSON.stringify(loaded.error.to_dictionary()))
	if closure_failures > 0:
		print("CARD_REFERENCE_CLOSURE_BLOCKERS=%d" % closure_failures)
	if failures > 0:
		print("CARD_SCHEMA_PROBE=failed definitions=%d failures=%d" % [staged_ids.size(), failures])
		quit(1)
		return
	print("CARD_SCHEMA_PROBE=passed definitions=%d" % staged_ids.size())
	quit(0)


func _load_production_definitions() -> Dictionary:
	var output := {}
	for kind in ["character", "card", "relic", "task", "encounter", "unit", "scene", "event", "status", "ruleset"]:
		var rows: Variant = _read_json("res://data/definitions/%s.json" % CONTENT_DB.FILE_NAMES[kind])
		var issues: Array[String] = []
		output[kind] = _db._validate_definition_file(kind, rows, issues)
		if not issues.is_empty():
			push_error("production %s definitions failed schema: %s" % [kind, issues])
	return output


func _write_isolated_package(root: String, manifest: Dictionary, cards: Dictionary) -> bool:
	var absolute_root := ProjectSettings.globalize_path(root)
	for directory in ["definitions", "manifests"]:
		if DirAccess.make_dir_recursive_absolute("%s/%s" % [absolute_root, directory]) != OK:
			return false
	for kind in ["character", "card", "relic", "task", "encounter", "unit", "scene", "event", "status", "ruleset"]:
		var file_name: String = CONTENT_DB.FILE_NAMES[kind]
		var rows: Array = _read_json("res://data/definitions/%s.json" % file_name)
		if kind == "card":
			rows = cards.values()
		elif kind in ["unit", "scene"]:
			rows = _load_staged_entity_definitions(kind)
		if not _write_text("%s/definitions/%s.json" % [root, file_name], JSON.stringify(rows)):
			return false
	if not _write_text("%s/manifests/test_cards_staging.json" % root, JSON.stringify(manifest)):
		return false
	return true


func _load_staged_entity_definitions(kind: String) -> Array:
	var rows: Array = []
	for id in (["F01", "F02", "F03", "F04"] if kind == "unit" else ["L01", "L02", "L03"]):
		var envelope: Variant = _read_json("res://artifacts/g2-build/staging/entities/definitions/%s_%s.json" % [kind, id])
		if typeof(envelope) == TYPE_DICTIONARY and envelope.has("definition"):
			rows.append(envelope.definition)
	return rows


func _read_json(path: String) -> Variant:
	var parser := JSON.new()
	var source := FileAccess.get_file_as_string(path)
	if parser.parse(source) != OK:
		push_error("could not parse JSON: %s" % path)
		return null
	return _db._normalize_json_numbers(parser.data)


func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	return true
