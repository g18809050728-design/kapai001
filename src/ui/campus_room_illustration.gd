class_name CampusRoomIllustration
extends Control

const SCENES := {
	"C": ["R3-P04-10", "BG_campus", "社团伙伴围坐讨论，一次活动也可以是喘息的机会。"],
	"I": ["R3-P04-30", "BG_campus", "从校园走向实践，把今天的投入转成下一段旅程的准备。"],
	"L": ["R3-P02-03", "BG_study", "翻开参考书，在安静的书桌前重新整理自己的方法。"],
	"LAB": ["R3-P01-27", "BG_classroom", "把想法放到实验台上，反复验证，直到找到更好的做法。"],
	"T": ["R3-P02-01", "BG_study", "带着问题坐下来，让一次交流变成下一步的方向。"],
	"ST": ["R3-P02-01", "BG_study", "摊开材料与草稿，让毕业设计向前推进一点。"],
	"E": ["BG_campus", "BG_campus", "校园中的一次相遇，接下来怎样行动，由你决定。"],
	"R": ["BG_dorm", "BG_dorm", "暂时放下手里的任务，给自己留一点恢复的时间。"]
}
var subtype := "C"
var caption := "校园活动"
var artwork: Texture2D
var background: Texture2D


func configure(kind: String, title: String) -> void:
	subtype = kind
	caption = title
	var entry: Array = SCENES.get(kind, SCENES.E)
	artwork = UiStyle.texture(str(entry[0]))
	background = UiStyle.texture(str(entry[1]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "CampusRoomIllustration"
	resized.connect(queue_redraw)
	queue_redraw()


static func narrative(kind: String) -> String:
	return str(SCENES.get(kind, SCENES.E)[2])


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_style_box(UiStyle.surface(Color("2d3d45"), UiStyle.BRASS, 3), bounds)
	if background != null:
		draw_texture_rect(background, bounds.grow(-4), false, Color(.8, .8, .8, .4))
	if artwork != null:
		var area := bounds.grow(-18)
		area.size.y -= 32
		var image_size := artwork.get_size()
		var factor := minf(area.size.x / image_size.x, area.size.y / image_size.y)
		var fitted := image_size * factor
		draw_texture_rect(artwork, Rect2(area.get_center() - fitted * .5, fitted), false)
	draw_rect(Rect2(4,size.y-50,size.x-8,46),Color(UiStyle.NIGHT,.86))
	draw_string(get_theme_font("font"),Vector2(16,size.y-20),caption,HORIZONTAL_ALIGNMENT_CENTER,maxf(1,size.x-32),20,UiStyle.CREAM)
