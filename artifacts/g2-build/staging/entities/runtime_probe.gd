extends SceneTree

const ContentDB = preload("res://src/content/content_db.gd")
const EXPECTED := {
	"character": ["P01", "P04"],
	"relic": ["A01", "A04", "A05", "A07", "A08", "A11", "A15", "A18"],
	"unit": ["F01", "F02", "F03", "F04"],
	"scene": ["L01", "L02", "L03"],
}


func _initialize() -> void:
	var db := ContentDB.new("res://artifacts/g2-build/staging/entities/runtime_probe/data", true)
	var result := db.load("test_g2_entities")
	if not result.ok:
		printerr("G2 entity staging load failed: %s" % str(result.error))
		quit(1)
		return
	for kind in EXPECTED:
		for definition_id in EXPECTED[kind]:
			var definition_result := db.get_definition(kind, definition_id)
			if not definition_result.ok:
				printerr("G2 entity missing after schema load: %s/%s" % [kind, definition_id])
				quit(1)
				return
	print(
		"SCHEMA_OK entity_count=17 ids=character:P01,character:P04,relic:A01,relic:A04,relic:A05,relic:A07,relic:A08,relic:A11,relic:A15,relic:A18,unit:F01,unit:F02,unit:F03,unit:F04,scene:L01,scene:L02,scene:L03"
	)
	quit(0)
