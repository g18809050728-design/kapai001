extends SceneTree


func _initialize() -> void:
	var content := ContentDB.new("res://.godot/g2_full_candidate")
	var loaded := content.load("campus_mvp")
	if not loaded.ok:
		print(JSON.stringify(loaded.error.to_dictionary()))
		quit(1)
		return
	var total := 0
	for kind in ContentDB.CONTENT_KINDS:
		var ids := content.get_candidates({"kind": kind})
		total += ids.size()
		print("G2_ENABLED %s=%d" % [kind, ids.size()])
	var event_result := content.get_definition("event", "V03")
	var encounter_result := content.get_definition("encounter", "N04")
	if (
		total != 66
		or event_result.data.options[0].effects[0].card_pool != ["K14", "K05", "K60"]
		or encounter_result.data.terms != [1]
	):
		push_error("G0 scope count or approved effective overrides did not match")
		quit(1)
		return
	print("G2_FULL_PACKAGE_LOAD_OK total=%d hash=%s" % [total, content.get_info().content_hash])
	quit(0)
