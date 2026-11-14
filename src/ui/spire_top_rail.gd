class_name SpireTopRail
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(size.x,0), Vector2(size.x,size.y-5)])
	for index in range(64,-1,-1):
		points.append(Vector2(size.x*index/64.0,size.y-5+sin(index*13.7)*2+cos(index*5.3)*1.5))
	points.append(Vector2.ZERO)
	draw_colored_polygon(points,Color("2c414d"))
	draw_polyline(points,Color("647780"),1.2,true)
	draw_line(Vector2(0,2),Vector2(size.x,2),Color("8a9b9d"),1,true)
	draw_line(Vector2(0,6),Vector2(size.x,6),Color(1,1,1,.035),4,true)
