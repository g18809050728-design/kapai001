class_name UiRouteCanvas
extends Control

signal node_inspected(node_id: String)

const Forecast = preload("res://src/run/route_forecast.gd")
const NodeStamp = preload("res://src/ui/map_node_stamp.gd")
const NODE_WIDTH := 76.0
const COLUMN_GAP := 16.0
const ROW_HEIGHT := 84.0
const ROUTE_SPAN := 6 * (NODE_WIDTH + COLUMN_GAP)

var nodes: Array = []
var reachable: Array = []
var current := ""
var selected := ""
var positions: Dictionary = {}
var forecast_node_ids: Array[String] = []
var overview := false
var overview_height := 210.0
var background_texture: Texture2D
var node_textures: Dictionary = {}
var edge_paths: Dictionary = {}


func row_height() -> float:
	return ROW_HEIGHT + maxf(0, UiStyle.text_scale - 1) * 24


func configure(entries: Array, available: Array, current_id: String, selected_id: String = "", depth: int = 3) -> void:
	nodes = entries.duplicate(true)
	reachable = available.duplicate()
	current = current_id
	selected = selected_id
	_load_optional_art()
	forecast_node_ids.assign(Forecast.describe(nodes, selected, depth).node_ids)
	var last_layer := 1
	for node in nodes:
		last_layer = maxi(last_layer, int(node.get("layer", 1)))
	custom_minimum_size = Vector2(ROUTE_SPAN + NODE_WIDTH, (last_layer - 1) * row_height() + 100)
	if overview:
		custom_minimum_size = Vector2(0, overview_height)
	if not resized.is_connected(arrange):
		resized.connect(arrange)
	queue_redraw()


func _load_optional_art() -> void:
	background_texture = null
	node_textures.clear()
	if not nodes.is_empty():
		background_texture = UiStyle.texture("map.background.y%d" % int(nodes[0].get("term", 1)))
	for node in nodes:
		var subtype := str(node.get("subtype", ""))
		if subtype.is_empty():
			subtype = str({"normal": "N", "elite": "EL", "boss": "B", "shop": "S", "rest": "R", "event": "E"}.get(str(node.get("kind", "")), ""))
		var icon := UiStyle.texture("map.node." + subtype)
		if icon != null:
			node_textures[str(node.node_id)] = icon


func arrange() -> void:
	positions.clear()
	var layers := {}
	var last_layer := 1
	for node in nodes:
		var layer := int(node.get("layer", 1))
		last_layer = maxi(layer, last_layer)
		if not layers.has(layer):
			layers[layer] = []
		layers[layer].append(node)
	var width := minf(ROUTE_SPAN, maxf(1, size.x - (32 if overview else NODE_WIDTH)))
	var padding := (size.x - width) * .5
	var row_step := (size.y - 28) / maxi(1, last_layer - 1) if overview else row_height()
	for layer in layers:
		var entries: Array = layers[layer]
		entries.sort_custom(func(a, b): return str(a.node_id) < str(b.node_id))
		for index in entries.size():
			var node: Dictionary = entries[index]
			var column := clampf(float(node.column), 0, 6) if node.has("column") else (index + 1) * 6.0 / (entries.size() + 1)
			positions[str(node.node_id)] = Vector2(padding + column * width / 6.0, (14 if overview else 52) + (int(layer) - 1) * row_step)
	for child in get_children():
		var id := str(child.get_meta("node_id", ""))
		if child is Control and positions.has(id):
			child.position = positions[id] - child.size * 0.5
	_link_keyboard_neighbors()
	_arrange_edges()
	queue_redraw()


func _arrange_edges() -> void:
	edge_paths.clear()
	var buttons := {}
	var incoming := {}
	for node in nodes:
		for next_id in node.get("next_ids", []):
			var id := str(next_id)
			if not incoming.has(id):
				incoming[id] = []
			incoming[id].append(str(node.node_id))
	for id in incoming:
		incoming[id].sort_custom(func(a, b): return positions.get(a, Vector2.ZERO).x < positions.get(b, Vector2.ZERO).x)
	for child in get_children():
		if child is Button and child.has_meta("node_id"):
			buttons[str(child.get_meta("node_id"))] = child
	for node in nodes:
		var source := str(node.node_id)
		if not positions.has(source):
			continue
		var next_ids: Array = node.get("next_ids", [])
		for index in next_ids.size():
			var destination := str(next_ids[index])
			if not positions.has(destination):
				continue
			var start: Vector2 = positions[source]
			var end: Vector2 = positions[destination]
			var curve := Curve2D.new()
			if overview or not buttons.has(source) or not buttons.has(destination):
				var bend := Vector2(0, (end.y - start.y) * .45)
				curve.add_point(start, Vector2.ZERO, bend)
				curve.add_point(end, -bend)
			else:
				var source_button: Button = buttons[source]
				var target_button: Button = buttons[destination]
				start = source_button.position + source_button.stamp_center()
				end = target_button.position + target_button.stamp_center()
				var side := signf(end.x - start.x)
				if is_zero_approx(side):
					side = -1 if next_ids.size() > 1 and index == 0 else 1
				# Exit beside the stamp, pass outside its label, then turn in the
				# gap between rows. Separate ports keep a fork's arrows distinct.
				var port := start + Vector2(side * 22, 3)
				var label: Rect2 = source_button.label_rect()
				var corridor := start.x + side * maxf(25, label.size.x * .5 + 9)
				var band := source_button.get_rect().end.y + 6 + index * 3
				var turn := Vector2(corridor, band)
				var arrivals: Array = incoming[destination]
				var angle := -PI / 2 + (arrivals.find(source) - (arrivals.size() - 1) * .5) * .45
				var tip := end + Vector2.from_angle(angle) * 23
				curve.add_point(port, Vector2.ZERO, Vector2(corridor - port.x, 0))
				curve.add_point(turn, Vector2(0, -14), Vector2(0, 6))
				curve.add_point(tip, Vector2(0, band - tip.y))
			curve.bake_interval = 2
			edge_paths[source + ">" + destination] = curve.get_baked_points()


func _link_keyboard_neighbors() -> void:
	var buttons := {}
	for child in get_children():
		if child is Button and child.has_meta("node_id"):
			buttons[str(child.get_meta("node_id"))] = child
	for id in buttons:
		var button: Button = buttons[id]
		var origin: Vector2 = positions[id]
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var candidate := ""
			var best := INF
			for other_id in buttons:
				if id == other_id:
					continue
				var delta: Vector2 = positions[other_id] - origin
				var forward := delta.dot(direction)
				var across := absf(delta.cross(direction))
				if forward <= 0.5:
					continue
				var score := forward + across * 8
				if score < best:
					best = score
					candidate = str(other_id)
			var path := button.get_path_to(buttons[candidate]) if not candidate.is_empty() else NodePath("")
			if direction == Vector2.LEFT:
				button.focus_neighbor_left = path
			elif direction == Vector2.RIGHT:
				button.focus_neighbor_right = path
			elif direction == Vector2.UP:
				button.focus_neighbor_top = path
			else:
				button.focus_neighbor_bottom = path


func _draw() -> void:
	if background_texture != null:
		draw_texture_rect(background_texture, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, .08))
	for node in nodes:
		var source := str(node.node_id)
		if not positions.has(source):
			continue
		for next_id in node.get("next_ids", []):
			if not positions.has(str(next_id)):
				continue
			var destination := str(next_id)
			var color := Color("aebdb5")
			var width := 1.5
			if forecast_node_ids.has(source) and forecast_node_ids.has(destination):
				color = UiStyle.GREEN.darkened(.22)
				width = 3.5
			if source == current and reachable.has(destination):
				color = UiStyle.GOLD.darkened(.16)
				width = 4
			var points: PackedVector2Array = edge_paths.get(source + ">" + destination, PackedVector2Array())
			if points.size() < 2:
				continue
			draw_polyline(points, color, width if not overview else minf(width, 1.5), true)
			if not overview:
				var tip := points[points.size() - 1]
				var direction := (tip - points[maxi(0, points.size() - 5)]).normalized()
				var across := direction.orthogonal() * 3
				draw_colored_polygon(PackedVector2Array([tip, tip - direction * 6 + across, tip - direction * 6 - across]), color)
	if overview:
		var last_layer := 1
		for node in nodes:
			last_layer = maxi(last_layer, int(node.get("layer", 1)))
		var radius := clampf((size.y - 28) / maxi(1, last_layer - 1) * .38, 2, 5)
		var icon_size := clampf((size.y - 28) / maxi(1, last_layer - 1) * .8, 4, 20)
		for node in nodes:
			var id := str(node.node_id)
			var point: Vector2 = positions[id]
			var color := UiStyle.INK if id == current else (UiStyle.GREEN if forecast_node_ids.has(id) else Color("a1b2a5"))
			draw_circle(point, radius, color, true, -1, true)
			var icon: Texture2D = node_textures.get(id)
			var marker_radius := radius
			if icon != null:
				draw_texture_rect(icon, Rect2(point - Vector2.ONE * icon_size * .5, Vector2.ONE * icon_size), false)
				marker_radius = icon_size * .5
				if id == current:
					draw_circle(point, marker_radius + 2, UiStyle.INK, false, 2, true)
			if reachable.has(id) or id == selected:
				draw_circle(point, marker_radius + (2 if id == selected else 1), UiStyle.GOLD.darkened(.25), false, 2, true)


func _gui_input(event: InputEvent) -> void:
	if overview and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var nearest := ""
		var distance := 14.0
		for id in positions:
			var candidate: float = positions[id].distance_to(event.position)
			if candidate < distance:
				distance = candidate
				nearest = str(id)
		if not nearest.is_empty():
			node_inspected.emit(nearest)
			accept_event()
