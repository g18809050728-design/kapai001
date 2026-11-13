class_name CardFaceView
extends Control

var model: Dictionary = {}
var picked := false
var unavailable := false

func configure(value: Dictionary, selected: bool = false) -> void:
	model = value
	picked = selected
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), model, picked, unavailable)

static func paint(canvas: Control, bounds: Rect2, data: Dictionary, selected: bool = false, disabled: bool = false, shortcut: int = 0) -> void:
	if data.is_empty():
		return
	var scale_factor := bounds.size / Vector2(168,244)
	canvas.draw_set_transform(bounds.position,0,scale_factor)
	var category := str(data.get("category", "utility"))
	var accent := category_color(category)
	var edge := UiStyle.GOLD.darkened(.15) if selected else accent
	var shadow := UiStyle.box(Color(0.02,.05,.06,.38))
	canvas.draw_style_box(shadow,Rect2(2,5,168,244))
	var frame := UiStyle.box(UiStyle.NIGHT)
	frame.set_corner_radius_all(6)
	frame.border_color = edge
	frame.set_border_width_all(3 if selected else 2)
	canvas.draw_style_box(frame,Rect2(0,0,168,244))
	var paper := UiStyle.box(UiStyle.CREAM)
	paper.set_corner_radius_all(3)
	canvas.draw_style_box(paper,Rect2(5,130,158,109))
	canvas.draw_rect(Rect2(5,38,3,196),accent)
	canvas.draw_line(Vector2(7,35),Vector2(160,35),Color(UiStyle.BRASS,.65),1,true)
	canvas.draw_line(Vector2(8,240),Vector2(160,240),Color(UiStyle.BRASS,.55),.7,true)
	var font := canvas.get_theme_font("font")
	var title := TextParagraph.new()
	title.add_string(str(data.get("name","")),font,14)
	title.width = 117
	title.max_lines_visible = 2
	title.alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.draw(canvas.get_canvas_item(),Vector2(42,7),UiStyle.CREAM)
	var art := UiStyle.texture(str(data.get("id","")))
	if art != null:
		var source := Rect2(Vector2.ZERO,art.get_size())
		var ratio := 154.0/94
		if source.size.x/source.size.y > ratio:
			source.size.x = source.size.y * ratio
			source.position.x = (art.get_width()-source.size.x)*.5
		else:
			source.size.y = source.size.x/ratio
			source.position.y = (art.get_height()-source.size.y)*.38
		canvas.draw_texture_rect_region(art,Rect2(8,38,154,94),source)
	else:
		canvas.draw_rect(Rect2(8,38,154,94),Color("d9ddce"))
		EffectGlyph.paint(canvas,"book",Vector2(85,84),25,Color(accent,.6))
	canvas.draw_line(Vector2(8,132),Vector2(160,132),Color(UiStyle.BRASS,.65),1,true)
	paint_category_badge(canvas, category, Vector2(21,22), 18)
	paint_category_cost(canvas, font, category, str(data.get("cost","—")), Vector2(21,22), 18)
	var category_name := str(data.get("category_name", "功能"))
	var rule_kind := UiStyle.label(str(data.get("kind","")))
	var semantics := category_name + (" · " + rule_kind if category_name != rule_kind else "") + " · " + str(data.get("target",""))
	canvas.draw_string(font,Vector2(10,145),semantics,HORIZONTAL_ALIGNMENT_CENTER,148,10,accent)
	canvas.draw_line(Vector2(12,150),Vector2(156,150),Color(accent,.24),1,true)
	var summary := str(data.get("summary",""))
	var requirements := str(data.get("requirements",""))
	if not requirements.is_empty():
		summary = "需："+requirements+"\n"+summary
	if int(data.get("vitality_cost",0)) > 0:
		summary = "支付%d精力\n" % data.vitality_cost + summary
	var paragraph := TextParagraph.new()
	paragraph.add_string(summary,font,13)
	paragraph.width = 140
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	var overflow := paragraph.get_size().y > 64
	paragraph.max_lines_visible = 3 if overflow else 4
	paragraph.draw(canvas.get_canvas_item(),Vector2(14,156),UiStyle.INK)
	if overflow:
		canvas.draw_string(font,Vector2(13,216),"… I 查看完整条件与效果",HORIZONTAL_ALIGNMENT_LEFT,142,10,accent)
	canvas.draw_line(Vector2(12,221),Vector2(156,221),Color(accent,.3),1,true)
	var tags := str(data.get("tags",""))
	if tags.is_empty():
		tags = str(data.get("timing","即时"))
	canvas.draw_string(font,Vector2(11,235),tags,HORIZONTAL_ALIGNMENT_LEFT,145,10,UiStyle.MUTED)
	if shortcut > 0:
		canvas.draw_circle(Vector2(149,120),8,UiStyle.NIGHT,true,-1,true)
		canvas.draw_string(font,Vector2(141,124),str(shortcut),HORIZONTAL_ALIGNMENT_CENTER,16,10,UiStyle.CREAM)
	if selected:
		EffectGlyph.line(canvas,Vector2(147,233),6,[[-1,0],[-.3,.6],[1,-.8]],UiStyle.INK)
	if disabled:
		canvas.draw_style_box(UiStyle.box(Color(.1,.15,.16,.22)),Rect2(0,0,168,244))
	canvas.draw_set_transform(Vector2.ZERO)


static func category_color(category: String) -> Color:
	return Color(str({"attack": "96513f", "defense": "3c7168", "utility": "4b687c", "field": "846338", "ability": "725b7e", "burden": "785958"}.get(category, "4b687c")))


static func paint_category_badge(canvas: CanvasItem, category: String, center: Vector2, radius: float) -> void:
	# Each silhouette is a recognizable object in the original cost corner.
	# The sword keeps its hilt and guard; a pointed badge alone cannot convey attack.
	var outline: Array = []
	var accent := category_color(category)
	match category:
		"attack":
			outline = [[38,1],[36,16],[22,30],[25,33],[21,37],[16,32],[8,40],[3,35],[11,27],[6,22],[10,18],[14,22],[28,8]]
		"defense":
			outline = [[3,7],[20,1],[37,7],[35,23],[29,33],[20,40],[11,33],[5,23]]
		"field":
			outline = [[20,1],[40,15],[36,19],[35,18],[35,39],[5,39],[5,18],[4,19],[0,15]]
		"ability":
			outline = [[21,0],[5,24],[17,24],[13,40],[37,13],[25,13],[31,0]]
		"burden":
			outline = [[4,2],[28,2],[37,11],[37,39],[24,39],[20,33],[13,39],[4,39]]
		_:
			# Eight distinct teeth and a central bearing read as a gear, not a cross.
			for tooth in 8:
				for corner in [[-17,.77],[-12,1.0],[12,1.0],[17,.77]]:
					var angle := deg_to_rad(tooth * 45.0 + corner[0])
					outline.append([20 + cos(angle) * 20 * corner[1], 20 + sin(angle) * 20 * corner[1]])
	var points := PackedVector2Array()
	var shadow := PackedVector2Array()
	for pair in outline:
		var offset := (Vector2(pair[0], pair[1]) - Vector2(20,20)) * radius / 20
		points.append(center + offset)
		shadow.append(center + offset + Vector2(0, 2))
	canvas.draw_colored_polygon(shadow, Color(UiStyle.INK, .22))
	canvas.draw_colored_polygon(points, accent)
	points.append(points[0])
	canvas.draw_polyline(points, Color("fffaf0"), 1.3, true)
	var detail := Color("f0d9a6")
	match category:
		"attack":
			_badge_line(canvas, center, radius, [[9,21],[22,34]], detail, 2.7)
			_badge_line(canvas, center, radius, [[7,35],[13,29]], detail, 2.5)
			_badge_line(canvas, center, radius, [[17,22],[29,10],[35,5]], Color(1,1,1,.55), 1.1)
		"defense":
			_badge_line(canvas, center, radius, [[8,10],[20,6],[32,10],[30,23],[25,31],[20,35],[15,31],[10,23],[8,10]], detail, 1.2)
		"field":
			_badge_line(canvas, center, radius, [[5,17],[20,6],[35,17]], detail, 1.3)
			_badge_line(canvas, center, radius, [[10,24],[10,32]], detail, 2.2)
			_badge_line(canvas, center, radius, [[30,24],[30,32]], detail, 2.2)
			_badge_line(canvas, center, radius, [[4,39],[36,39]], detail, 1.4)
		"ability":
			_badge_line(canvas, center, radius, [[22,4],[10,21],[15,21]], Color(1,1,1,.5), 1.1)
		"burden":
			_badge_line(canvas, center, radius, [[28,3],[28,11],[36,11]], detail, 1.2)
			_badge_line(canvas, center, radius, [[29,27],[24,31],[27,36]], detail, 1.3)
		_:
			canvas.draw_circle(center, radius * .57, accent.darkened(.25), true, -1, true)
			canvas.draw_circle(center, radius * .57, detail, false, 1.2, true)


static func paint_category_cost(canvas: CanvasItem, font: Font, category: String, cost: String, center: Vector2, radius: float) -> void:
	var local_center := Vector2(20,20)
	var font_size := 20
	if category == "attack":
		local_center = Vector2(25,16)
		font_size = 18
	elif category == "field":
		local_center = Vector2(20,28)
		font_size = 18
	elif category == "ability":
		local_center = Vector2(21,19)
		font_size = 18
	if cost.length() > 1:
		font_size = 14
	font_size = maxi(8, roundi(font_size * radius / 18))
	var text_center := center + (local_center - Vector2(20,20)) * radius / 20
	var width := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := text_center + Vector2(-width * .5, (font.get_ascent(font_size) - font.get_descent(font_size)) * .5)
	canvas.draw_string_outline(font, baseline, cost, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(1, roundi(3 * radius / 18)), UiStyle.INK.darkened(.25))
	canvas.draw_string(font, baseline, cost, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("fffaf0"))


static func _badge_line(canvas: CanvasItem, center: Vector2, radius: float, values: Array, ink: Color, width: float) -> void:
	var points := PackedVector2Array()
	for pair in values:
		points.append(center + (Vector2(pair[0],pair[1]) - Vector2(20,20)) * radius / 20)
	canvas.draw_polyline(points, ink, width * radius / 18, true)
