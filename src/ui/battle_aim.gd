class_name BattleAim
extends Control

var origin := Vector2.ZERO
var destination := Vector2.ZERO
var valid_target: bool = false


func _draw() -> void:
	if not visible or origin.distance_to(destination) < 18:
		return
	var color := Color("efce88") if valid_target else Color("c6d9ce")
	var control_point := (origin + destination) * 0.5 + Vector2(0, -90)
	var points := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		points.append(
			(1 - t) * (1 - t) * origin + 2 * (1 - t) * t * control_point + t * t * destination
		)
	draw_polyline(points, Color(0.04, 0.1, 0.12, 0.65), 7, true)
	draw_polyline(points, color, 3, true)
	var direction := (destination - points[29]).normalized()
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(
		PackedVector2Array(
			[
				destination + direction * 5,
				destination - direction * 17 + normal * 9,
				destination - direction * 17 - normal * 9
			]
		),
		color
	)
	draw_arc(destination, 19, 0, TAU, 36, color, 2, true)
