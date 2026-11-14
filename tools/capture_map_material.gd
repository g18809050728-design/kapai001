extends SceneTree

var _out := "res://artifacts/verification/map-material-feedback-20261114/screens-dense-final"
var _captures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("CAMPUS_MAP_MATERIAL_OUT").is_empty():
		_out = OS.get_environment("CAMPUS_MAP_MATERIAL_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var generated := AnnualMapGenerator.generate(4, "map-material-year-four", {"research": 6, "direction": "research", "destination": "research"})
	var indexed := {}
	for node in generated.nodes:
		indexed[str(node.key)] = node
	var visited: Array[String] = []
	var current := str(generated.nodes[0].key)
	while int(indexed[current].layer) < 8:
		visited.append(current)
		current = str(indexed[current].next[0])
	var available: Array = indexed[current].next.duplicate()
	var nodes: Array = []
	for entry in generated.nodes:
		var node: Dictionary = entry.duplicate(true)
		node.node_id = str(entry.key)
		node.term = 4
		node.next_ids = entry.next.duplicate()
		node.status = "completed" if visited.has(str(entry.key)) else "unvisited"
		nodes.append(node)
	var data := {"run_id": "controlled-year-four-material-view", "revision": 19, "term": 4, "year_title": generated.title, "year_layers": generated.layers,
		"nodes": nodes, "current_node_id": current, "reachable_node_ids": available, "vitality": 49, "max_vitality": 72, "money": 85, "relics": [], "cards": []}
	var frozen := data.duplicate(true)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale_value in [100, 125, 150]:
			root.size = dimensions
			UiStyle.text_scale = scale_value / 100.0
			var page := UiExperiencePage.new()
			page.screen = "map"
			page.theme = UiStyle.make_theme()
			root.add_child(page)
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			page.render(data)
			await _frames(16)
			page.press("node:" + str(available[0]))
			await _capture("year-four-detail-%d-%d" % [dimensions.x, scale_value])
			page.press("map:overview")
			await _frames(14)
			await _capture("year-four-overview-%d-%d" % [dimensions.x, scale_value])
			page.free()
			await _frames(3)
	var result := {"fixture": "pure production v3 generator, year 4; controlled completed path through layer 8, not a natural playthrough",
		"nodes": nodes.size(), "generator": generated, "captures": _captures, "view_unchanged": data == frozen}
	var file := FileAccess.open(_out + "/capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	quit(0 if data == frozen and _captures.size() == 12 else 1)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _capture(caption: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(_out + "/" + caption + ".png") == OK:
		_captures.append(caption + ".png")
