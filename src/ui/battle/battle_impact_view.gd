class_name BattleImpactView
extends Control

var origin := Vector2.ZERO
var destination := Vector2.ZERO
var glyph := "work"
var ink := UiStyle.GREEN
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func _draw() -> void:
	var points := PackedVector2Array()
	for index in 18:
		var t := clampf(progress-float(17-index)*.018,0,1)
		points.append(_point(t))
	draw_polyline(points,Color(ink,.09),13.0,true)
	draw_polyline(points,Color(ink,.19),6.0,true)
	for index in range(1,points.size()):
		draw_line(points[index-1],points[index],Color(ink,.15+.65*index/17.0),.8+2.5*index/17.0,true)
	var center := _point(progress)
	var axis := (destination-origin).normalized()
	var normal := axis.orthogonal()
	if glyph == "pressure":
		var paper := PackedVector2Array([center-axis*10-normal*5,center+axis*7-normal*5,center+axis*10+normal*2,center-axis*8+normal*5])
		draw_colored_polygon(paper,Color(ink,.85))
		draw_line(center-axis*5-normal*2,center+axis*5-normal*2,Color("fff1d8"),1.4,true)
		draw_line(center-axis*5+normal*2,center+axis*2+normal*2,Color("fff1d8"),1.4,true)
	elif glyph == "work":
		draw_colored_polygon(PackedVector2Array([center-axis*17,center-normal*3.5,center+axis*9,center+normal*3.5]),ink)
		draw_line(center-axis*8,center+axis*7,Color("fff0c6"),1.8,true)
	else:
		EffectGlyph.paint(self,glyph,center,8,ink)

func _point(t: float) -> Vector2:
	var bow := Vector2(0,-minf(65,origin.distance_to(destination)*.18))
	return origin.lerp(destination,t)+bow*sin(t*PI)
