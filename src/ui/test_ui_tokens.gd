class_name TestUiTokens
extends RefCounted

## Semantic tokens for the test-room editor. Primitive colors live here; the
## panel and components only reference these names, never raw hex.

const PAGE := Color("f4eedf")
const SURFACE := Color("fffbf1")
const SURFACE_ALT := Color("f8f3e6")
const TINT := Color("f3e7c9")
const TINT_DANGER := Color("f6e0dc")
const INK := Color("1f3a44")
const INK_SOFT := Color("4e615b")
const ON_INK := Color("fffbf1")
const ACCENT := Color("dda957")
const ACCENT_TEXT := Color("8a6420")
const DANGER := Color("9c4f49")
const DANGER_HOVER := Color("7c3f3a")
const SUCCESS := Color("3f6b5c")
const LINE := Color(0.12, 0.23, 0.27, 0.16)
const LINE_STRONG := Color(0.12, 0.23, 0.27, 0.30)
const HOVER := Color(0.12, 0.23, 0.27, 0.06)

const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24
const RADIUS := 10
const PANEL_WIDTH := 520.0
const ROW_HEIGHT := 36.0
const PRIMARY_HEIGHT := 40.0
const LABEL_WIDTH := 128.0


static func font(size: int) -> int:
	return roundi(size * UiStyle.text_scale)


static func height(value: float) -> float:
	return value * UiStyle.text_scale


static func panel_style() -> StyleBoxFlat:
	var style := _box(SURFACE)
	style.border_color = LINE_STRONG
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = SPACE_LG
	style.content_margin_right = SPACE_LG
	style.content_margin_top = SPACE_MD
	style.content_margin_bottom = SPACE_MD
	style.shadow_color = Color(0.06, 0.12, 0.14, 0.18)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	return style


static func banner_style(danger: bool = false) -> StyleBoxFlat:
	var style := _box(TINT_DANGER if danger else TINT)
	style.border_color = DANGER if danger else ACCENT
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = SPACE_MD
	style.content_margin_right = SPACE_MD
	style.content_margin_top = SPACE_SM
	style.content_margin_bottom = SPACE_SM
	return style


static func chip_style(accent: bool = false) -> StyleBoxFlat:
	var style := _box(TINT if accent else SURFACE_ALT)
	style.border_color = ACCENT if accent else LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(999)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


static func field_style() -> StyleBoxFlat:
	var style := _box(Color("ffffff"))
	style.border_color = LINE_STRONG
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = SPACE_XS
	style.content_margin_bottom = SPACE_XS
	return style


static func button_style(kind: String, state: String) -> StyleBoxFlat:
	var bg := SURFACE
	var border := LINE
	var width := 1
	match kind:
		"primary":
			bg = INK
			border = INK
			if state == "hover":
				bg = Color("2b4a56")
			elif state == "pressed":
				bg = Color("162b33")
			elif state == "disabled":
				bg = Color("d9d5c8")
				border = Color("d9d5c8")
		"danger":
			bg = TINT_DANGER
			border = DANGER
			if state == "hover":
				bg = Color("f2d3cf")
			elif state == "pressed":
				bg = Color("ebc2bd")
		"ghost":
			bg = Color.TRANSPARENT
			border = Color.TRANSPARENT
			width = 0
			if state == "hover":
				bg = HOVER
			elif state == "pressed":
				bg = Color(0.12, 0.23, 0.27, 0.10)
		"tab":
			bg = Color.TRANSPARENT
			border = Color.TRANSPARENT
			width = 0
			if state == "hover":
				bg = HOVER
			elif state == "pressed":
				bg = TINT
		"tab_active":
			bg = TINT
			border = INK
			width = 2
		_:
			bg = SURFACE
			border = LINE
			if state == "hover":
				bg = TINT
			elif state == "pressed":
				bg = Color("eadfc4")
	var style := _box(bg)
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = SPACE_MD
	style.content_margin_right = SPACE_MD
	style.content_margin_top = SPACE_XS
	style.content_margin_bottom = SPACE_XS
	return style


static func focus_style() -> StyleBoxFlat:
	var style := _box(Color.TRANSPARENT)
	style.border_color = INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


static func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
