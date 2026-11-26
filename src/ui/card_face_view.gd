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

static func paint(canvas: Control, bounds: Rect2, data: Dictionary, selected: bool = false, disabled: bool = false, shortcut: int = 0, hand: bool = false) -> void:
	if data.is_empty():
		return
	canvas.draw_set_transform(bounds.position, 0, bounds.size / Vector2(168,244))
	var category := str(data.get("category", "utility"))
	var accent := category_color(category)
	var identity := str(data.get("id", ""))
	var frame_color := Color("327c84")
	if identity.contains("P01"):
		frame_color = Color("8b3d36")
	elif identity.contains("P02"):
		frame_color = Color("385f96")
	elif identity.contains("P03"):
		frame_color = Color("536c49")
	elif identity.contains("P04"):
		frame_color = Color("77538a")
	if category == "burden":
		frame_color = Color("605a68")
	var rarity := str(data.get("rarity", "common"))
	var edge := Color("bbad88")
	if rarity in ["rare", "advanced"]:
		edge = Color("edc567")
	elif rarity == "uncommon":
		edge = Color("a9d0e5")
	if selected:
		edge = Color("ffe79e")
	var frame := UiStyle.surface(frame_color.darkened(.27), edge, 10)
	frame.shadow_color = Color(0,0,0,.7)
	frame.shadow_size = 7
	frame.shadow_offset = Vector2(0,5)
	frame.set_border_width_all(3)
	canvas.draw_style_box(frame, Rect2(0,0,168,244))
	var inset := UiStyle.surface(frame_color, frame_color.lightened(.36), 7)
	inset.shadow_size = 0
	canvas.draw_style_box(inset, Rect2(5,5,158,234))
	var art := UiStyle.texture(identity)
	var art_height := 88.0 if hand else 103.0
	var art_bounds := Rect2(10, 31, 148, art_height)
	if art != null:
		var source := Rect2(Vector2.ZERO,art.get_size())
		var ratio := art_bounds.size.aspect()
		if source.size.x / source.size.y > ratio:
			source.size.x = source.size.y * ratio
			source.position.x = (art.get_width()-source.size.x)*.5
		else:
			source.size.y = source.size.x / ratio
			source.position.y = (art.get_height()-source.size.y)*.38
		canvas.draw_texture_rect_region(art,art_bounds,source)
	else:
		canvas.draw_rect(art_bounds,frame_color.darkened(.4))
		EffectGlyph.paint(canvas,"book",art_bounds.get_center(),27,edge)
	canvas.draw_rect(art_bounds,edge,false,1.4)
	var body_top := art_bounds.end.y + 3
	var paper := UiStyle.surface(Color("e8dcc4"),Color("bba780"),5)
	paper.shadow_size = 0
	canvas.draw_style_box(paper,Rect2(9,body_top,150,234 - body_top))
	# Keep the reference hierarchy and the user's original type-shaped cost corner.
	canvas.draw_style_box(UiStyle.cut_surface(frame_color.darkened(.1),edge),Rect2(18,5,143,30))
	var font := canvas.get_theme_font("font")
	var title := TextParagraph.new()
	title.add_string(str(data.get("name","")),font,16 if hand else 14)
	title.width = 115
	title.max_lines_visible = 1
	title.alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.draw(canvas.get_canvas_item(),Vector2(39,10),Color("fff3d8"))
	var cost := str(data.get("cost","—"))
	paint_category_badge(canvas, category, Vector2(18,18), 18)
	paint_category_cost(canvas, font, category, cost, Vector2(18,18), 18)
	var category_name := str(data.get("category_name", "功能"))
	var rule_kind := UiStyle.label(str(data.get("kind","")))
	var semantics := category_name + (" · " + rule_kind if category_name != rule_kind else "")
	canvas.draw_style_box(UiStyle.cut_surface(frame_color.darkened(.18),edge),Rect2(36,body_top - 11,96,19))
	canvas.draw_string(font,Vector2(36,body_top + 2),semantics,HORIZONTAL_ALIGNMENT_CENTER,96,11 if hand else 10,Color("fff4db"))
	var summary := str(data.get("summary",""))
	var requirements := str(data.get("requirements",""))
	if not requirements.is_empty():
		summary = "需："+requirements+"\n"+summary
	if int(data.get("vitality_cost",0)) > 0:
		summary = "支付%d精力\n" % data.vitality_cost + summary
	var paragraph := TextParagraph.new()
	paragraph.add_string(summary,font,roundi(15 * minf(UiStyle.text_scale, 1.2)) if hand else 13)
	paragraph.width = 134
	paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	var overflow: bool
	if hand:
		paragraph.break_flags |= TextServer.BREAK_ADAPTIVE
		var remaining_height := 213 - (body_top + 14)
		overflow = paragraph.get_size().y > remaining_height
		var visible_lines := 0
		for line in paragraph.get_line_count():
			var line_height := paragraph.get_line_size(line).y
			if line_height > remaining_height:
				break
			remaining_height -= line_height
			visible_lines += 1
		paragraph.max_lines_visible = maxi(1, visible_lines)
	else:
		overflow = paragraph.get_size().y > 62
		paragraph.max_lines_visible = 3 if overflow else 4
	paragraph.draw(canvas.get_canvas_item(),Vector2(17,body_top + 14),Color("211d19"))
	if overflow:
		canvas.draw_string(font,Vector2(16,225 if hand else 222),"… I 查看完整条件与效果",HORIZONTAL_ALIGNMENT_CENTER,136,11 if hand else 10,accent.darkened(.3) if hand else accent)
	var tags := str(data.get("tags",""))
	if tags.is_empty():
		tags = str(data.get("timing","即时"))
	if not overflow:
		canvas.draw_string(font,Vector2(15,229),tags,HORIZONTAL_ALIGNMENT_CENTER,138,10 if hand else 9,Color("584638"))
	if shortcut > 0:
		canvas.draw_circle(Vector2(147,art_bounds.end.y - 16),8,UiStyle.NIGHT,true,-1,true)
		canvas.draw_string(font,Vector2(139,art_bounds.end.y - 12),str(shortcut),HORIZONTAL_ALIGNMENT_CENTER,16,10,UiStyle.CREAM)
	if disabled:
		canvas.draw_style_box(UiStyle.box(Color(.03,.06,.09,.20 if hand else .35)),Rect2(0,0,168,244))
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
