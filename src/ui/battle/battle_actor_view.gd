class_name BattleActorView
extends Control

## Prototype paper stage. Portrait, moving prop, silhouette and hit zone are separate.
var definition_id := ""
var actor_kind := "task"
var phase_index := 1
var targeted := false
var action_strength := 0.0:
	set(value):
		action_strength = value
		queue_redraw()
var hit_strength := 0.0:
	set(value):
		hit_strength = value
		queue_redraw()
var guard_strength := 0.0:
	set(value):
		guard_strength = value
		queue_redraw()
var _portrait: Texture2D
var _pose_tween: Tween

func configure(id: String, kind: String, phase: int = 1) -> void:
	definition_id = id
	actor_kind = kind
	phase_index = phase
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "task":
		var key := str(UiStyle.LABELS.data.get("aliases",{}).get(id,id))
		var file := "res://assets/art/presentation-v3/tasks/"+key+".png"
		_portrait = load(file) as Texture2D if ResourceLoader.exists(file) else null
	else:
		var file := "res://assets/art/presentation-v2/actors/"+id+".png"
		_portrait = load(file) as Texture2D if ResourceLoader.exists(file) else UiStyle.texture(id)
	resized.connect(queue_redraw)
	queue_redraw()

func set_targeted(value: bool) -> void:
	targeted = value
	queue_redraw()

func cue(kind: String, speed: float) -> Tween:
	var property := "hit_strength" if kind == "hit" else ("guard_strength" if kind == "guard" else "action_strength")
	var tween := create_tween()
	tween.tween_property(self,property,1.0,.18/maxf(.05,speed)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self,property,0.0,.65/maxf(.05,speed)).set_trans(Tween.TRANS_SINE)
	return tween

func reset_pose() -> void:
	action_strength = 0
	hit_strength = 0
	guard_strength = 0
	modulate.a = 1

func action_anchor() -> Vector2:
	return Vector2(size.x*.7,size.y*.48)

func _draw() -> void:
	var floor_center := Vector2(size.x*.5,size.y-12)
	draw_set_transform(floor_center,0,Vector2(1,.22))
	draw_circle(Vector2.ZERO,size.x*.4,Color(UiStyle.INK,.15),true,-1,true)
	if targeted:
		draw_circle(Vector2.ZERO,size.x*.44,UiStyle.GREEN.darkened(.1),false,3,true)
	draw_set_transform(Vector2.ZERO)
	if actor_kind == "task":
		_draw_task()
	else:
		if _portrait != null:
			var height := size.y-16
			var width := minf(size.x,height*_portrait.get_width()/float(_portrait.get_height()))
			draw_texture_rect(_portrait,Rect2((size.x-width)*.5,0,width,height),false,Color(1,1-hit_strength*.32,1-hit_strength*.34))
		if action_strength > .01:
			_draw_prop()
	if guard_strength > .01:
		var center := Vector2(size.x*.5,size.y*.55)
		draw_circle(center,size.x*.44,Color(UiStyle.GREEN,guard_strength*.15),true,-1,true)
		EffectGlyph.paint(self,"relax",center,size.x*.34,Color("b2dac6")*Color(1,1,1,guard_strength))

func _draw_prop() -> void:
	var origin := Vector2(size.x*.64,size.y*.67)
	# A separate notebook and pen move around the hand, leaving the body/HUD still.
	draw_set_transform(origin,-.18-action_strength*.35,Vector2.ONE)
	var paper := PackedVector2Array([Vector2(-22,-18),Vector2(24,-22),Vector2(25,12),Vector2(-23,16)])
	draw_colored_polygon(paper,Color("f7efd8"))
	draw_polyline(PackedVector2Array([paper[0],paper[1],paper[2],paper[3],paper[0]]),UiStyle.INK,1.4,true)
	var family := "book" if definition_id == "P02" else ("erosion" if definition_id == "P03" else ("link" if definition_id == "P04" else "work"))
	EffectGlyph.paint(self,family,Vector2.ZERO,9,UiStyle.INK)
	draw_line(Vector2(-9,-13-action_strength*12),Vector2(24,-32+action_strength*18),UiStyle.INK,3,true)
	draw_set_transform(Vector2.ZERO)

func _draw_task() -> void:
	if _portrait != null:
		var factor := minf(size.x*.94/_portrait.get_width(),(size.y-18)/_portrait.get_height())
		var dimensions := _portrait.get_size()*factor
		var origin := Vector2(size.x*.5,size.y-18-action_strength*8)
		draw_set_transform(origin,-.025+action_strength*.06,Vector2.ONE*(1-hit_strength*.035))
		draw_texture_rect(_portrait,Rect2(Vector2(-dimensions.x*.5,-dimensions.y),dimensions),false,Color(1,1-hit_strength*.25,1-hit_strength*.28))
		draw_set_transform(Vector2.ZERO)
		return
	var w := size.x*.72
	var h := size.y*.64
	var origin := Vector2(size.x*.5,size.y*.5)
	var fold := hit_strength*10
	var color := Color("efe6cf").lerp(UiStyle.RED,hit_strength*.3)
	var signature := absi(definition_id.hash())
	var variant := signature % 3
	# Missing art remains a paper task; it does not invent a humanoid enemy.
	for layer in range(2,-1,-1):
		var offset := Vector2(layer*4,-layer*6)
		var points := PackedVector2Array([origin+Vector2(-w*.48,-h*.5)+offset,origin+Vector2(w*.34,-h*.5-fold)+offset,origin+Vector2(w*.5,-h*.32)+offset,origin+Vector2(w*.45,h*.5)+offset,origin+Vector2(-w*.5,h*.42)+offset])
		draw_colored_polygon(points,color.darkened(layer*.035))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline,UiStyle.INK,1.6,true)
	var top := origin+Vector2(0,-h*.5)
	if phase_index > 1 or variant == 2:
		draw_rect(Rect2(top-Vector2(w*.28,8),Vector2(w*.56,14)),UiStyle.INK,true)
	EffectGlyph.paint(self,["work","book","stamp"][variant],origin+Vector2(0,h*.21),minf(w,h)*.18,UiStyle.RED.darkened(.1))
	for index in 2:
		draw_line(origin+Vector2(-w*.32,-h*.35+index*7),origin+Vector2(w*.2,-h*.35+index*7),Color(UiStyle.INK,.25),1,true)
