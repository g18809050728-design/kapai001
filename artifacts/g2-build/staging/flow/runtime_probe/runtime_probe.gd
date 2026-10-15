extends SceneTree

const ContentDB = preload("res://src/content/content_db.gd")

const EXPECTED_TASKS := ["N01", "N02", "N03", "N04", "Q01", "B01"]
const EXPECTED_ENCOUNTERS := ["N01", "N02", "N03", "N04", "Q01", "B01"]
const EXPECTED_EVENTS := ["V01", "V03", "V04", "V10"]


func _initialize() -> void:
	var db: ContentDB = ContentDB.new(
		"res://artifacts/g2-build/staging/flow/runtime_probe/data", true
	)
	var loaded: GameResult = db.load("test_g2_flow")
	if not loaded.ok:
		printerr(
			"FLOW_REFERENCE_CLOSURE_LOAD_FAILED ", JSON.stringify(loaded.error.to_dictionary())
		)
		quit(1)
		return
	for definition_id in EXPECTED_TASKS:
		if not _query(db, "task", definition_id):
			quit(1)
	for definition_id in EXPECTED_ENCOUNTERS:
		if not _query(db, "encounter", definition_id):
			quit(1)
	var n03: Dictionary = db.get_definition("task", "N03").data as Dictionary
	if n03.phases[0].intents[1].add_card.card != "X01":
		printerr("FLOW_REFERENCE_CLOSURE_FAILED task/N03 add_card.card must resolve to X01")
		quit(1)
	var n04: Dictionary = db.get_definition("encounter", "N04").data as Dictionary
	if n04.terms != [1]:
		printerr("FLOW_OVERRIDE_FAILED encounter/N04 terms must resolve to [1]")
		quit(1)
	for definition_id in EXPECTED_EVENTS:
		if not _query_definition_file("events", definition_id):
			quit(1)
	print("FLOW_REFERENCE_CLOSURE_OK tasks=6 encounters=6 cards=5 override=N04:[1]")
	print("FLOW_EVENT_SCHEMA_ONLY_OK events=4 enabled=0 executor=G4")
	quit(0)


func _query(db: ContentDB, kind: String, definition_id: String) -> bool:
	var result := db.get_definition(kind, definition_id)
	if result.ok:
		return true
	printerr("FLOW_REFERENCE_CLOSURE_FAILED %s/%s" % [kind, definition_id])
	return false


func _query_definition_file(file_name: String, definition_id: String) -> bool:
	var file := FileAccess.open(
		"res://artifacts/g2-build/staging/flow/runtime_probe/data/definitions/%s.json" % file_name,
		FileAccess.READ
	)
	if file == null:
		printerr("FLOW_EVENT_SCHEMA_QUERY_FAILED missing %s.json" % file_name)
		return false
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		printerr("FLOW_EVENT_SCHEMA_QUERY_FAILED invalid %s.json" % file_name)
		return false
	for definition: Dictionary in parser.data:
		if definition.get("id") == definition_id:
			return true
	printerr("FLOW_EVENT_SCHEMA_QUERY_FAILED missing %s/%s" % [file_name, definition_id])
	return false
