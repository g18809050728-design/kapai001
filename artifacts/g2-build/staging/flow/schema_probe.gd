extends SceneTree

const CONTENT_DB = preload("res://src/content/content_db.gd")


func _initialize() -> void:
	var failures := 0
	var db = CONTENT_DB.new()
	var paths := _definition_paths()
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("cannot read staged record: %s" % path)
			failures += 1
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		if parse_error != OK:
			push_error("staged record is not an object: %s" % path)
			failures += 1
			continue
		var record: Dictionary = db._normalize_json_numbers(parser.data)
		var kind := str(record.get("kind", ""))
		var definition: Variant = record.get("definition")
		var issues: Array[String] = []
		db._validate_definition_file(kind, [definition], issues)
		if issues.is_empty():
			print("SCHEMA_OK %s/%s" % [kind, record.get("id", "")])
		else:
			for issue in issues:
				push_error("%s/%s: %s" % [kind, record.get("id", ""), issue])
			failures += 1
	if failures > 0:
		print("FLOW_SCHEMA_PROBE=failed failures=%d" % failures)
		quit(1)
	print("FLOW_SCHEMA_PROBE=passed definitions=%d" % paths.size())
	quit(0)


func _definition_paths() -> Array[String]:
	var output: Array[String] = []
	for kind in ["task", "encounter", "event"]:
		for id in _ids_for(kind):
			output.append(
				"res://artifacts/g2-build/staging/flow/definitions/%s_%s.json" % [kind, id]
			)
	return output


func _ids_for(kind: String) -> Array[String]:
	match kind:
		"task", "encounter":
			return ["N01", "N02", "N03", "N04", "Q01", "B01"]
		"event":
			return ["V01", "V03", "V04", "V10"]
	return []
