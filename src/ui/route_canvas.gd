class_name UiRouteCanvas
extends Control

var nodes: Array = []
var reachable: Array = []
var current := ""
var positions: Dictionary = {}


func configure(entries: Array, available: Array, current_id: String) -> void:
	nodes = entries.duplicate(true)
	reachable = available.duplicate()
	current = current_id
	custom_minimum_size = Vector2(650, 100)
	for node in nodes:
		custom_minimum_size.y = maxf(custom_minimum_size.y, int(node.get("layer", 1)) * 108 + 32)
	resized.connect(arrange)


func arrange() -> void:
	positions.clear()
	var layers := {}
	for node in nodes:
		var layer := int(node.get("layer", 1))
		if not layers.has(layer):
			layers[layer] = []
		layers[layer].append(node)
	for layer in layers:
		var entries: Array = layers[layer]
		for index in entries.size():
			var id := str(entries[index].node_id)
			positions[id] = Vector2((index + 1) * size.x / (entries.size() + 1), (int(layer) - 1) * 108 + 50)
			for child in get_children():
				if str(child.get_meta("node_id", "")) == id:
					child.position = positions[id] - child.size * 0.5
	queue_redraw()


func _draw() -> void:
	for node in nodes:
		var source := str(node.node_id)
		if not positions.has(source):
			continue
		for next_id in node.get("next_ids", []):
			if not positions.has(str(next_id)):
				continue
			var a: Vector2 = positions[source]
			var b: Vector2 = positions[str(next_id)]
			var active := source == current or reachable.has(str(next_id))
			draw_line(a, b, UiStyle.GREEN if active else Color("b9c5b9"), 3 if active else 1.5, true)
