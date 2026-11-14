class_name MapNodeGlyph
extends RefCounted

## Original campus symbols share one optical space and stroke vocabulary.
const GLYPHS := {
	"N": preload("res://assets/ui/map/glyphs/n.svg"),
	"EL": preload("res://assets/ui/map/glyphs/el.svg"),
	"B": preload("res://assets/ui/map/glyphs/b.svg"),
	"S": preload("res://assets/ui/map/glyphs/s.svg"),
	"R": preload("res://assets/ui/map/glyphs/r.svg"),
	"L": preload("res://assets/ui/map/glyphs/l.svg"),
	"LAB": preload("res://assets/ui/map/glyphs/lab.svg"),
	"K": preload("res://assets/ui/map/glyphs/k.svg"),
	"C": preload("res://assets/ui/map/glyphs/c.svg"),
	"T": preload("res://assets/ui/map/glyphs/t.svg"),
	"I": preload("res://assets/ui/map/glyphs/i.svg"),
	"ST": preload("res://assets/ui/map/glyphs/st.svg"),
	"E": preload("res://assets/ui/map/glyphs/e.svg"),
}


static func paint(target: CanvasItem, subtype: String, center: Vector2, color: Color) -> void:
	var extent := 35.0 if subtype == "B" else 32.0
	target.draw_texture_rect(GLYPHS.get(subtype, GLYPHS.E), Rect2(center - Vector2.ONE * extent * .5, Vector2.ONE * extent), false, color)


static func ink(subtype: String) -> Color:
	return Color(str({"EL": "70483f", "B": "653f35", "K": "765239", "S": "606040", "R": "8a5339", "L": "4b5c51", "LAB": "4b5c51", "E": "746344"}.get(subtype, "454738")))
