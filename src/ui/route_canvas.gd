class_name UiRouteCanvas
extends Control

signal node_inspected(node_id: String)

const Forecast = preload("res://src/run/route_forecast.gd")
const NodeStamp = preload("res://src/ui/map_node_stamp.gd")
const Paper = preload("res://src/ui/map_paper.gd")
const NODE_WIDTH := 76.0
const COLUMN_GAP := 16.0
const ROW_HEIGHT := 98.0
const ROUTE_SPAN := 624.0

var nodes: Array = []
var reachable: Array = []
var current := ""
var selected := ""
var positions: Dictionary = {}
var forecast_node_ids: Array[String] = []
var overview := false
var detailed_overview := false
var overview_height := 210.0
var background_texture: Texture2D
var node_textures: Dictionary = {}
var edge_paths: Dictionary = {}
var edge_segments: Dictionary = {}


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
	custom_minimum_size = Vector2(0, (last_layer - 1) * row_height() + 100)
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


func select_node(id: String) -> void:
	selected = id
	forecast_node_ids.assign(Forecast.describe(nodes, selected).node_ids)
	queue_redraw()


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
	var width := minf(ROUTE_SPAN, maxf(1, size.x - (48 if overview else NODE_WIDTH + 16)))
	var padding := (size.x - width) * .5
	var row_step := (size.y - 48) / maxi(1, last_layer - 1) if overview else row_height()
	for layer in layers:
		var entries: Array = layers[layer]
		entries.sort_custom(func(a, b): return str(a.node_id) < str(b.node_id))
		var columns: Array[float] = []
		for index in entries.size():
			columns.append(clampf(float(entries[index].column), 0, 6) if entries[index].has("column") else (index + 1) * 6.0 / (entries.size() + 1))
		var left_limit: float = (24.0 if overview else NODE_WIDTH * .5 + 8) - padding - columns.min() * width / 6.0
		var right_limit: float = size.x - (24.0 if overview else NODE_WIDTH * .5 + 8) - padding - columns.max() * width / 6.0
		var drift := clampf(sin(float(layer) * 1.13) * minf(29, width * .05), left_limit, right_limit)
		for index in entries.size():
			var node: Dictionary = entries[index]
			var column: float = columns[index]
			# The visual offset depends only on frozen layer/column, never selection,
			# input order or a random stream. Lane order and boundary lanes stay fixed.
			var wave := sin(float(layer) * 1.27 + column * .63) * sin(column * PI / 6.0)
			var offset_x := wave * minf(4, width / 130)
			var offset_y := sin(float(layer) * 1.73 + column * 1.17) * minf(7, row_step * .07)
			positions[str(node.node_id)] = Vector2(padding + column * width / 6.0 + drift + offset_x, (24 if overview else 52) + (last_layer - int(layer)) * row_step + offset_y)
	for child in get_children():
		var id := str(child.get_meta("node_id", ""))
		if child is Control and positions.has(id):
			child.position = positions[id] - child.size * 0.5
	_link_keyboard_neighbors()
	_arrange_edges()
	queue_redraw()


func _arrange_edges() -> void:
	edge_paths.clear()
	edge_segments.clear()
	var buttons := {}
	var keepouts: Array[Rect2] = []
	for child in get_children():
		if child is Button and child.has_meta("node_id"):
			buttons[str(child.get_meta("node_id"))] = child
			if not overview and child.has_method("label_rect"):
				var label: Rect2 = child.label_rect()
				label.position += child.position
				keepouts.append(label.grow(4))
	for node in nodes:
		var source := str(node.node_id)
		if not positions.has(source):
			continue
		for next_id in node.get("next_ids", []):
			var destination := str(next_id)
			if not positions.has(destination):
				continue
			var start: Vector2 = positions[source]
			var end: Vector2 = positions[destination]
			var radius := minf(9, start.distance_to(end) * .25) if overview else 25.0
			if not overview and buttons.has(source) and buttons.has(destination):
				start = buttons[source].position + buttons[source].stamp_center()
				end = buttons[destination].position + buttons[destination].stamp_center()
			var direction := (end - start).normalized()
			start += direction * radius
			end -= direction * radius
			var travel := end - start
			var sway := sin(float(node.get("layer", 1)) * 1.41 + float(node.get("column", 3))) * minf(11, absf(travel.y) * .14)
			var curve := Curve2D.new()
			curve.add_point(start, Vector2.ZERO, Vector2(travel.x * .28 + sway, travel.y * .40))
			curve.add_point(end, Vector2(-travel.x * .28 + sway, -travel.y * .40))
			curve.bake_interval = 2
			var points := curve.get_baked_points()
			var key := source + ">" + destination
			edge_paths[key] = points
			edge_segments[key] = _without_labels(points, keepouts)


func _without_labels(points: PackedVector2Array, keepouts: Array[Rect2]) -> Array[PackedVector2Array]:
	# Keep the continuous geometry; leave a short clean gap beneath each caption.
	# Sampling below one pixel keeps every drawn segment outside the text bounds.
	var result: Array[PackedVector2Array] = []
	var segment := PackedVector2Array()
	for index in range(1, points.size()):
		var steps := maxi(1, ceili(points[index - 1].distance_to(points[index]) * 2))
		for step in range(steps + 1):
			var point := points[index - 1].lerp(points[index], float(step) / steps)
			var blocked := false
			for label in keepouts:
				if label.has_point(point):
					blocked = true
					break
			if blocked:
				if segment.size() > 1:
					result.append(segment)
				segment = PackedVector2Array()
			else:
				segment.append(point)
	if segment.size() > 1:
		result.append(segment)
	return result


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
	# The drawing is a projection of frozen nodes; no visual randomness enters a run.
	Paper.paint(self, Rect2(Vector2.ZERO, size))
	if not overview and size.x > 750:
		_draw_compass(Vector2(53, size.y - 73))
	var visited := {}
	for node in nodes:
		if node.get("status", "") == "completed" or str(node.node_id) == current:
			visited[str(node.node_id)] = true
	if background_texture != null:
		draw_texture_rect(background_texture, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, .025))
	for node in nodes:
		var source := str(node.node_id)
		if not positions.has(source):
			continue
		for next_id in node.get("next_ids", []):
			if not positions.has(str(next_id)):
				continue
			var destination := str(next_id)
			var color := Color("6e624a", .57)
			var width := 1.3
			var walked: bool = visited.has(source) and visited.has(destination)
			if walked:
				color = Color("514c39", .88)
				width = 2.0
			if forecast_node_ids.has(source) and forecast_node_ids.has(destination):
				color = Color("91533c", .76)
				width = 1.7
			if source == current and reachable.has(destination):
				color = Color("5d573e", .94)
				width = 1.8
			for points: PackedVector2Array in edge_segments.get(source + ">" + destination, []):
				if points.size() < 2:
					continue
				if walked:
					draw_polyline(points, color, width if not overview else 1.5, true)
				else:
					_draw_dashes(points, color, minf(width, 1.2) if overview else width, 2.2 if overview else 3.4, 3.6 if overview else 4.6)
	if overview:
		var last_layer := 1
		for node in nodes:
			last_layer = maxi(last_layer, int(node.get("layer", 1)))
		var row_step := (size.y - 48) / maxi(1, last_layer - 1)
		var radius := clampf(row_step * .38, 2, 5)
		var icon_size := clampf(row_step * .8, 4, 20)
		for node in nodes:
			var id := str(node.node_id)
			if not positions.has(id):
				continue
			var point: Vector2 = positions[id]
			var color := Color("413b2d") if id == current else (Color("88513b") if forecast_node_ids.has(id) else Color("847455"))
			var icon: Texture2D = node_textures.get(id)
			var marker_radius := radius
			if detailed_overview:
				marker_radius = clampf(row_step * .31, 8, 13)
				var glyph_scale := marker_radius / 15.0
				var subtype := str(node.get("subtype", ""))
				if subtype.is_empty():
					subtype = str({"normal":"N", "elite":"EL", "boss":"B", "shop":"S", "rest":"R", "event":"E"}.get(str(node.get("kind", "")), "E"))
				draw_set_transform(point, 0, Vector2.ONE * glyph_scale)
				var ink := MapNodeGlyph.ink(subtype)
				ink.a = .92 if id == current or reachable.has(id) or forecast_node_ids.has(id) else .70
				MapNodeGlyph.paint(self, subtype, Vector2.ZERO, ink)
				draw_set_transform(Vector2.ZERO)
				if id == current or node.get("status", "") == "completed":
					draw_circle(point, marker_radius + 4, Color("4a5340", .8), false, 1.4, true)
			else:
				draw_circle(point, radius, color, true, -1, true)
				if icon != null:
					draw_texture_rect(icon, Rect2(point - Vector2.ONE * icon_size * .5, Vector2.ONE * icon_size), false)
					marker_radius = icon_size * .5
			if reachable.has(id) or id == selected:
				draw_circle(point, marker_radius + (4 if id == selected else 3), Color("983e2e") if id == selected else Color("746344"), false, 1.5, true)


func _draw_dashes(points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var distance := 0.0
	for index in range(1, points.size()):
		var start := points[index - 1]
		var end := points[index]
		var length := start.distance_to(end)
		if length < .001:
			continue
		var cursor := 0.0
		while cursor < length:
			var phase := fmod(distance + cursor, dash + gap)
			var visible := phase < dash
			var step := minf(length - cursor, (dash if visible else dash + gap) - phase)
			if step < .001:
				step = minf(.001, length - cursor)
			if visible:
				draw_line(start.lerp(end, cursor / length), start.lerp(end, (cursor + step) / length), color, width, true)
			cursor += step
		distance += length


func _draw_compass(center: Vector2) -> void:
	var ink := Color("62513a", .30)
	draw_arc(center, 22, 0, TAU, 48, ink, .8, true)
	for index in 4:
		var direction := Vector2.from_angle(-PI / 2 + index * PI / 2)
		var normal := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([center + direction * 30, center + normal * 4, center]), ink)
		draw_polyline(PackedVector2Array([center + direction * 30, center - normal * 4, center]), ink, .8, true)
	draw_circle(center, 3, ink, true, -1, true)



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
