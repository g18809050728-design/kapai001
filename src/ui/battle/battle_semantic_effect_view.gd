class_name BattleSemanticEffectView
extends Control

## Original local ink. No rule state, texture dependencies or independent timers.
var kind := "work_light"
var direction := Vector2.RIGHT
var ink := Color("e9c77b")
var intensity := 1.0
var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var center := size * .5
	var radius := minf(size.x, size.y) * .31 * clampf(intensity,.75,1.25)
	var fade := 1.0 - smoothstep(.58, 1.0, progress)
	var color := Color(ink, ink.a * fade)
	var edge := Color(Color("233343"), .6 * fade)
	match kind:
		"work_light", "work_heavy", "pressure_hit":
			_impact(center, radius, color, edge)
		"guard_gain", "guard_absorb", "guard_break":
			_guard(center, radius, color, edge)
		"heal":
			_heal(center, radius, color, edge)
		"resource_gain", "resource_spend":
			_resource(center, radius, color, edge)
		"status_attach", "status_decay", "status_remove":
			_status(center, radius, color, edge)
		"phase":
			_phase(center, radius, color, edge)
		"partner":
			_partner(center, radius, color, edge)


func _stroke(points: PackedVector2Array, color: Color, width: float, edge: Color) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, Color(color, color.a * .055), width + 12.0, true)
	draw_polyline(points, Color(color, color.a * .13), width + 5.0, true)
	draw_polyline(points, edge, width + 2.0, true)
	draw_polyline(points, color, width, true)


func _impact(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var axis := direction.normalized() if direction.length_squared() > .001 else Vector2.RIGHT
	var normal := axis.orthogonal()
	var heavy := kind == "work_heavy"
	var reach := radius * (1.25 if heavy else .8) * (.3 + .7 * ease(progress, .35))
	if kind == "pressure_hit":
		# Short correction marks press into the target; never a flame or a blade.
		for index in 3:
			var offset := normal * (index - 1) * radius * .23
			_stroke(PackedVector2Array([center + offset - axis * reach * .6, center + offset, center + offset + normal * radius * .14]), color, 3.3, edge)
		return
	for index in (7 if heavy else 4):
		var angle := -.95 + index * (1.9 / (6.0 if heavy else 3.0))
		var ray := axis.rotated(angle)
		var start := center + ray * radius * (.14 + progress * .27)
		var end := center + ray * reach * (1.0 - float(index % 3) * .17)
		_stroke(PackedVector2Array([start, end]), color, (4.7 if heavy else 2.8) * (1.0 - progress * .5), edge)
	var core := radius * (.18 if heavy else .11) * (1.0 - progress * .5)
	draw_colored_polygon(PackedVector2Array([center-axis*core*1.5, center-normal*core, center+axis*core*1.8, center+normal*core]), Color(Color("fff3cc"), color.a))
	if heavy:
		_stroke(PackedVector2Array([center-axis*radius*.7-normal*radius*.35, center+axis*radius*.48+normal*radius*.22]), Color(Color("fff0be"),color.a*.8), 2.2, edge)


func _guard(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var expansion := 1.0 + .12 * sin(progress * PI)
	for side in [-1.0, 1.0]:
		var split := progress * radius * .55 if kind == "guard_break" else 0.0
		var offset := Vector2(side * split, split * .35)
		var points := PackedVector2Array([
			center + offset + Vector2(side * radius * .84, -radius * .4) * expansion,
			center + offset + Vector2(side * radius * .74, radius * .27) * expansion,
			center + offset + Vector2(side * radius * .35, radius * .63) * expansion,
			center + offset + Vector2(side * radius * .05, radius * .72) * expansion])
		_stroke(points, color, 4.0, edge)
	if kind == "guard_absorb":
		var touch := center + Vector2(radius * .8, 0)
		for index in 3:
			var ray := Vector2.RIGHT.rotated((index - 1) * .7)
			_stroke(PackedVector2Array([touch+ray*radius*.12, touch+ray*radius*(.3+progress*.3)]), Color(Color("fff0bf"),color.a), 2.4, edge)
	elif kind == "guard_gain":
		draw_arc(center + Vector2(0,radius*.3), radius*.46, .3, PI-.3, 22, Color(color,color.a*.45), 1.8, true)


func _heal(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var inward := 1.0 - ease(progress, .65)
	for index in 5:
		var angle := PI * (.18 + index * .16)
		var outward := Vector2(cos(angle), sin(angle))
		var position := center + outward * radius * (.13 + inward * .83)
		var points := PackedVector2Array()
		for step in 9:
			var arc := angle - .22 + step * .055
			points.append(center + Vector2(cos(arc),sin(arc)) * radius * (.13 + inward * .83))
		_stroke(points, color, 3.8 - progress * 1.3, edge)
		draw_circle(position, 2.7, Color(Color("effff5"),color.a), true, -1, true)
	var lift := center - Vector2(0, progress * radius * .68)
	draw_circle(lift, radius * (.09 + .04 * sin(progress * PI)), Color(Color("f1fff2"),color.a), true, -1, true)
	draw_arc(center-Vector2(0,radius*.08), radius*.42, .15, PI-.15, 22, Color(color,color.a*.65), 2.0, true)


func _resource(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var incoming := kind == "resource_gain"
	var travel := (1.0 - ease(progress,.6)) if incoming else ease(progress,.6)
	for index in 4:
		var axis := Vector2.RIGHT.rotated(PI * (.15 + index * .5))
		var position := center + axis * radius * (.12 + travel * .85)
		if incoming:
			var normal := axis.orthogonal()
			draw_colored_polygon(PackedVector2Array([position-axis*8, position-normal*2.4, position+axis*5, position+normal*2.4]), color)
			_stroke(PackedVector2Array([position-axis*12,position-axis*5]), Color(color,color.a*.45),1.4,edge)
		else:
			_stroke(PackedVector2Array([position-axis*7,position+axis*5]), color,3.1,edge)
			_stroke(PackedVector2Array([position+axis.orthogonal()*3,position-axis.orthogonal()*3]),color,1.6,edge)
	if incoming:
		var half := radius * (.15 + travel * .14)
		draw_rect(Rect2(center-Vector2.ONE*half,Vector2.ONE*half*2),Color(color,color.a*.18))
		draw_rect(Rect2(center-Vector2.ONE*half,Vector2.ONE*half*2),color,false,2.0)
	else:
		_stroke(PackedVector2Array([center+Vector2(-8,6),center+Vector2(8,-6)]),color,2.5,edge)


func _status(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var removing := kind == "status_remove"
	var shrink := (1.0 - progress*.45) if kind == "status_decay" else 1.0
	var offset := progress * radius * .5 if removing else 0.0
	var pulse := .92 + .08 * sin(progress * TAU)
	for side in [-1.0,1.0]:
		var x: float = side * (radius*.63*shrink+offset)
		var points := PackedVector2Array([center+Vector2(x-side*7,-radius*.18),center+Vector2(x,-radius*.18),center+Vector2(x,radius*.32),center+Vector2(x-side*7,radius*.32)])
		_stroke(points,Color(color,color.a*pulse),2.5,edge)
	var note := center + Vector2(-radius*.2,-radius*.12-offset*.6)
	var points := PackedVector2Array([note+Vector2(-6,-8),note+Vector2(6,-8),note+Vector2(6,5),note+Vector2(1,9),note+Vector2(-6,9)])
	draw_colored_polygon(points,Color(color,color.a*.3))
	points.append(points[0])
	_stroke(points,color,1.8,edge)
	_stroke(PackedVector2Array([note+Vector2(-3,-2),note+Vector2(3,-2)]),color,1.6,edge)
	if removing:
		_stroke(PackedVector2Array([note+Vector2(-9,10),note+Vector2(9,-10)]),Color(Color("fff1d4"),color.a),2.0,edge)


func _phase(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var reveal := ease(progress,.5)
	var paper := PackedVector2Array([Vector2(-.55,-.65),Vector2(.34,-.65),Vector2(.58,-.4),Vector2(.58,.6),Vector2(-.55,.6),Vector2(-.55,-.65)])
	var back := PackedVector2Array()
	var front := PackedVector2Array()
	for point in paper:
		back.append(center+point*radius+Vector2(-radius*.25*reveal,-radius*.08*reveal))
		front.append(center+point*radius*Vector2(maxf(.08,reveal),1)+Vector2(radius*.17*(1-reveal),0))
	_stroke(back,Color(color,color.a*(1.0-progress)*.5),2.0,edge)
	draw_colored_polygon(front,Color(color,color.a*.13))
	_stroke(front,color,3.0,edge)
	var fold := center + Vector2(radius*.34*maxf(.08,reveal),-radius*.65)
	_stroke(PackedVector2Array([fold,fold+Vector2(0,radius*.25),fold+Vector2(radius*.24*reveal,radius*.25)]),Color(Color("fff0c8"),color.a),2.0,edge)
	for index in 3:
		_stroke(PackedVector2Array([center+Vector2(-radius*.28*reveal,radius*(-.24+index*.21)),center+Vector2(radius*.3*reveal,radius*(-.24+index*.21))]),Color(color,color.a*.6),1.7,edge)
	_stroke(PackedVector2Array([center+Vector2(-radius*.8,radius*.8),center+Vector2(radius*.8,radius*.8)]),color,2.7,edge)


func _partner(center: Vector2, radius: float, color: Color, edge: Color) -> void:
	var base := center + Vector2(0,radius*.55)
	draw_set_transform(base,0,Vector2(1,.3))
	draw_arc(Vector2.ZERO,radius*(.4+progress*.45),.1,PI*1.9,32,color,2.8,true)
	draw_set_transform(Vector2.ZERO)
	for side in [-1.0,1.0]:
		var note := center + Vector2(side*radius*(.7-progress*.35),radius*(.2-progress*.5))
		_stroke(PackedVector2Array([note+Vector2(-4,-6),note+Vector2(4,-6),note+Vector2(4,6),note+Vector2(-4,6),note+Vector2(-4,-6)]),color,2.2,edge)
