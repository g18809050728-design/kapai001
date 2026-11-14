class_name RoomSceneView
extends Control

var room := "menu"
var title := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var key := str({"menu":"BG_home","setup":"BG_campus","shop":"BG_shop","event":"BG_dorm","rest":"BG_dorm","campaign":"BG_study","reward":"BG_success","summary":"BG_success","map":"BG_campus","settings":"BG_study"}.get(room,"BG_campus"))
	var art := UiStyle.texture(key)
	if art != null:
		var source := Rect2(Vector2.ZERO,art.get_size())
		var ratio := size.x/maxf(1,size.y)
		if source.size.x/source.size.y > ratio:
			source.size.x = source.size.y*ratio
			source.position.x = (art.get_width()-source.size.x)*.5
		else:
			source.size.y = source.size.x/ratio
			source.position.y = (art.get_height()-source.size.y)*.5
		draw_texture_rect_region(art,Rect2(Vector2.ZERO,size),source)
	draw_rect(Rect2(Vector2.ZERO,size),Color(UiStyle.NIGHT,.18 if room in ["setup","shop"] else .35))
	draw_texture_rect(UiStyle.gradient(Color(UiStyle.NIGHT,0),Color(UiStyle.NIGHT,.82)),Rect2(0,size.y*.3,size.x,size.y*.7),false)
	if room == "menu":
		draw_texture_rect(UiStyle.gradient(Color(UiStyle.NIGHT,.98),Color(UiStyle.NIGHT,0),true),Rect2(0,0,size.x*.78,size.y),false)
	elif room in ["event","rest","setup"]:
		draw_texture_rect(UiStyle.gradient(Color(UiStyle.NIGHT,0),Color(UiStyle.NIGHT,.52),true),Rect2(size.x*.30,0,size.x*.7,size.y),false)
	if room in ["reward","campaign"]:
		draw_rect(Rect2(Vector2.ZERO,size),Color(.01,.03,.06,.42))
		draw_texture_rect(UiStyle.gradient(Color(0,0,0,0),Color(0,0,0,.7)),Rect2(0,0,size.x,size.y*.4),false)
	if room == "map":
		draw_rect(Rect2(Vector2.ZERO,size),Color("0e191e", .55))
		draw_texture_rect(UiStyle.gradient(Color("081319", .72),Color("081319", 0),true),Rect2(0,0,size.x*.32,size.y),false)
		draw_texture_rect(UiStyle.gradient(Color("081319", 0),Color("081319", .72),true),Rect2(size.x*.68,0,size.x*.32,size.y),false)
	if room == "shop":
		var table := Rect2(size.x*.06,size.y*.43,size.x*.88,size.y*.43)
		draw_style_box(UiStyle.surface(Color("49372d"),Color("9b7952"),5),table)
		for index in 5:
			var y := table.position.y+index*table.size.y/5.0
			draw_line(Vector2(table.position.x+4,y),Vector2(table.end.x-4,y),Color(.05,.03,.02,.35),2,true)
