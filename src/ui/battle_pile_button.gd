class_name BattlePileButton
extends Button

var kind := "deck"
var count := 0
var on_dark := true


func configure(pile_kind: String, amount: int, dark_background: bool) -> void:
	kind = pile_kind
	count = amount
	on_dark = dark_background
	text = str({"deck": "牌组", "log": "记录", "draw": "抽牌堆", "discard": "弃牌堆", "exhaust": "消耗堆"}.get(kind, kind))
	# Native Button input/focus remains intact; the paper stack supplies its visuals.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	add_theme_font_size_override("font_size", roundi(14 * UiStyle.text_scale))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	queue_redraw()


func hover_content() -> Dictionary:
	var purpose := str({
		"deck": "查看本局全部卡牌、基础费用与效果，以及携带的饰品。快捷键 D。",
		"log": "回看已经发生的战斗事件与结算记录。快捷键 L。",
		"draw": "抽牌效果从此补充手牌。点击查看剩余卡牌，按卡牌整理，不显示实际抽取顺序。",
		"discard": "存放已弃置的卡牌。点击查看这些公开卡牌的完整费用与效果。",
		"exhaust": "存放本场已消耗的卡牌。点击查看这些公开卡牌的完整费用与效果。"
	}.get(kind, ""))
	return {
		"uid": str(get_meta("uid", "")), "title": text,
		"meta": ("%d 条已发生记录" if kind == "log" else "%d 张 · 点击查看") % count,
		"body": purpose, "detail": text + "\n\n" + purpose,
		"terms": [], "rect": get_global_rect()
	}


func _draw() -> void:
	if bool(get_meta("toolbar_button", false)):
		UiNavigationButton.paint(self)
		return
	var active := (is_hovered() or has_focus()) and not disabled
	var font := get_theme_font("font")
	var small := size.y < 60
	if small:
		var accent := UiStyle.GOLD if active else UiStyle.BRASS
		if active:
			draw_style_box(UiStyle.surface(Color("314654"),accent,3),Rect2(Vector2.ZERO,size))
		draw_texture_rect(UiNavIcon.texture(kind),Rect2(Vector2(2,6),Vector2(23,23)),false,Color(1,1,1,.45) if disabled else Color.WHITE)
		draw_string(font,Vector2(25,29),str(count),HORIZONTAL_ALIGNMENT_CENTER,maxf(18,size.x-25),13,UiStyle.CREAM)
		return
	var h := size.y-20 if not small else size.y-8
	var w := minf(size.x-22,h*.73)
	var face := Rect2((size.x-w)*.5-3,1,w,h)
	var accent := UiStyle.GOLD if active else Color("b2bda9")
	var color := Color("386584") if kind == "draw" else (Color("576d7b") if kind == "discard" else Color("d3c6ab"))
	if kind == "exhaust":
		color = Color("76607b")
	for offset in [Vector2(6,4),Vector2(3,2),Vector2.ZERO]:
		var paper := UiStyle.surface(color.darkened(.18) if offset != Vector2.ZERO else color,accent,3)
		paper.shadow_size = 0
		draw_style_box(paper,Rect2(face.position+offset,face.size))
	var c := face.get_center()
	if kind in ["deck","log"]:
		EffectGlyph.paint(self,"book",c,minf(11,h*.25),Color("394552"))
	else:
		draw_rect(face.grow(-5),Color(accent,.6),false,1)
		var diamond := PackedVector2Array([c+Vector2(0,-h*.27),c+Vector2(w*.28,0),c+Vector2(0,h*.27),c-Vector2(w*.28,0),c+Vector2(0,-h*.27)])
		draw_polyline(diamond,Color(accent,.7),1,true)
	var badge := Vector2(face.end.x+4,face.end.y-2)
	draw_circle(badge,10 if small else 12,Color("182a3a"),true,-1,true)
	draw_circle(badge,10 if small else 12,accent,false,1,true)
	draw_string(font,badge+Vector2(-12,5),str(count),HORIZONTAL_ALIGNMENT_CENTER,24,12 if small else 15,UiStyle.CREAM)
	if not small:
		draw_string(font,Vector2(0,size.y-2),text,HORIZONTAL_ALIGNMENT_CENTER,size.x,12,UiStyle.CREAM if on_dark else UiStyle.INK)
