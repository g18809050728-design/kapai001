class_name CampusRoomIllustration
extends Control

const STORIES = preload("res://src/ui/room_stories.json")
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
var story_key := ""


func configure(kind: String, title: String, event_id: String = "") -> void:
	subtype = kind
	caption = title
	var entry: Array = SCENES.get(kind, SCENES.E)
	artwork = UiStyle.texture(str(entry[0]))
	background = UiStyle.texture(str(entry[1]))
	var story := details(kind, event_id)
	var selected := _texture(str(story.get("art", "")))
	if selected != null:
		story_key = event_id if not event_id.is_empty() else kind
		artwork = selected
		caption = str(story.get("location", title))
		var scene := background_texture(kind, event_id)
		if scene != null:
			background = scene
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "CampusRoomIllustration"
	resized.connect(queue_redraw)
	queue_redraw()


static func details(kind: String, event_id: String = "") -> Dictionary:
	var group := "events" if not event_id.is_empty() else "rooms"
	var story_id := event_id if not event_id.is_empty() else kind
	var result: Dictionary = STORIES.data.get(group, {}).get(story_id, {}).duplicate(true)
	if result.is_empty():
		return result
	var prefix := "story:%s.%s" % [group, story_id]
	for field in ["title", "location", "narrative"]:
		if result.has(field):
			result[field] = TextOverrides.text(prefix + "." + field, str(result[field]))
	var option_titles: Dictionary = result.get("option_titles", {})
	if not option_titles.is_empty():
		var updated: Dictionary = {}
		for option in option_titles:
			updated[option] = TextOverrides.text(
				prefix + ".option_titles." + str(option), str(option_titles[option])
			)
		result["option_titles"] = updated
	return result


static func narrative(kind: String, event_id: String = "") -> String:
	return str(details(kind, event_id).get("narrative", SCENES.get(kind, SCENES.E)[2]))


static func option_title(event_id: String, option: String, fallback: String) -> String:
	return str(details("E", event_id).get("option_titles", {}).get(option, fallback))


static func background_texture(kind: String, event_id: String = "") -> Texture2D:
	return _texture(str(details(kind, event_id).get("background", "")))


static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	if not story_key.is_empty():
		var area := Rect2(0, 0, size.x, maxf(1, size.y - 42))
		var factor := minf(area.size.x / artwork.get_width(), area.size.y / artwork.get_height())
		var fitted := artwork.get_size() * factor
		draw_texture_rect(artwork, Rect2(area.get_center() - fitted * .5, fitted), false)
		var line_y := minf(area.end.y - 4, area.get_center().y + fitted.y * .5 + 12)
		draw_line(Vector2(size.x * .32, line_y), Vector2(size.x * .68, line_y), Color(UiStyle.BRASS, .65), 1, true)
		draw_string(get_theme_font("font"), Vector2(8, line_y + 26), caption, HORIZONTAL_ALIGNMENT_CENTER, maxf(1, size.x - 16), roundi(14 * minf(UiStyle.text_scale, 1.25)), Color("d8ceb8"))
		return
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
