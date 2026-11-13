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
	var bow := Vector2(0,-minf(65,origin.distance_to(destination)*.18))
	for index in 18:
		var t := clampf(progress-float(17-index)*.018,0,1)
		points.append(origin.lerp(destination,t)+bow*sin(t*PI))
	draw_polyline(points,Color(ink,.65),2.6,true)
	var center := origin.lerp(destination,progress)+bow*sin(progress*PI)
	EffectGlyph.paint(self,glyph,center,9,ink)
