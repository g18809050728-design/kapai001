class_name UiMapPaper
extends PanelContainer

## Original paper shared by the navigable route, its note, and the read-only map.
const FIBER = preload("res://assets/ui/map/parchment-fiber-v1.png")
var cool := false


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e1d0a8", 0)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	resized.connect(queue_redraw)


func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), cool)


static func paint(target: CanvasItem, rect: Rect2, cool_paper: bool = false) -> void:
	if rect.size.x < 12 or rect.size.y < 12:
		return
	var points := _outline(rect)
	var shade := PackedVector2Array()
	for point in points:
		shade.append(point + Vector2(3, 6))
	target.draw_colored_polygon(shade, Color(0, 0, 0, .28))
	var uv := PackedVector2Array()
	for point in points:
		uv.append((point - rect.position) / rect.size)
	var tint := Color(.94, 1.02, 1.05) if cool_paper else Color.WHITE
	target.draw_polygon(points, PackedColorArray([tint]), uv, FIBER)
	var edge := points.duplicate()
	edge.append(points[0])
	target.draw_polyline(edge, Color("7a6544", .65), 1.5, true)
	# Thin highlights catch on the worn paper edge; neither edge is a panel border.
	for index in range(1, points.size() - 1):
		if index % 3 == 0:
			target.draw_line(points[index] + Vector2(1, 0), points[index + 1] + Vector2(1, 0), Color("f2e0b6", .38), 1, true)


static func _outline(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var width := rect.size.x
	var height := rect.size.y
	var segments := maxi(4, ceili(height / 22))
	points.append(rect.position + Vector2(6, 4))
	for step in range(1, maxi(2, ceili(width / 35))):
		points.append(rect.position + Vector2(step * width / ceili(width / 35), 3 + sin(step * 2.7) * 1.8))
	points.append(rect.position + Vector2(width - 6, 4))
	for step in range(1, segments):
		points.append(rect.position + Vector2(width - 4 + sin(step * 4.1) * 2.1 + cos(step * 1.8), step * height / segments))
	points.append(rect.position + Vector2(width - 5, height - 5))
	for step in range(ceili(width / 35) - 1, 0, -1):
		points.append(rect.position + Vector2(step * width / ceili(width / 35), height - 4 + sin(step * 3.4) * 1.8))
	points.append(rect.position + Vector2(5, height - 4))
	for step in range(segments - 1, 0, -1):
		points.append(rect.position + Vector2(4 + sin(step * 3.7) * 2.0 + cos(step * 2.3), step * height / segments))
	return points
