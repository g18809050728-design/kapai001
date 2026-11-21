class_name UiNavIcon
extends RefCounted

static var _cache: Dictionary = {}
const PRIMARY := {
	"map": '<path fill="#d4bd90" d="m4 5 12-2 7 3 13-3-3 38-13 3-8-4-12 2Z"/><path fill="#f0ddaf" d="m16 3 7 3-3 38-8-4Zm20 0 7 3-3 35-7 0Z"/><path d="m16 3-4 37M23 6l-3 38M9 16l6 5 9-8 9 6M16 32l7-7 8 5"/><path d="m25 33 6 6m0-6-6 6" stroke="#a44f3c"/>',
	"deck": '<path fill="#83989f" d="m6 10 22-5 11 33-22 6Z"/><path fill="#eee2c9" d="m13 5 24 1-1 35-24-1Z"/><path fill="#c26354" d="m17 3 24 4-6 34-24-4Z"/><path fill="#f5e6c7" d="m18 5 20 4-5 29-19-3Z"/><path fill="#577984" d="m27 13 5 8-7 7-4-8Z"/>',
	"settings": '<path fill="#a8bfc3" d="m20 3 8 0 1 5 5 3 5-2 4 7-4 4v7l4 4-4 7-5-2-5 3-1 5h-8l-1-5-5-3-5 2-4-7 4-4v-7l-4-4 4-7 5 2 5-3Z"/><circle cx="24" cy="24" r="8" fill="#263e4c"/><path d="m20 18 8 0 4 6-4 6h-8l-4-6Z" stroke="#dbe5dc"/>',
	"relics": '<path fill="#c7a35f" d="m24 3 8 11 11 10-11 8-8 13-8-13L3 24l13-10Z"/><path fill="#f1d794" d="m24 9 10 15-10 15-10-15Z"/><path fill="#487d81" d="m24 15 6 9-6 9-6-9Z"/>'
}
const PATHS := {
	"account": '<circle cx="12" cy="8" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/>',
	"info": '<path d="M12 3 3 8v8l9 5 9-5V8Z"/><path d="M12 11v6M12 7v.2"/>',
	"focus": '<circle cx="12" cy="12" r="9"/><path d="m13 5-6 8h5l-1 6 6-9h-5Z"/>',
	"map": '<path d="m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2Zm6-2v16m6-14v16"/>',
	"deck": '<path d="M6 3h12v16H6zM3 6v16h12M9 7h6M9 11h6"/>',
	"log": '<path d="M5 4h13l2 3v14H5V4ZM3 7v12M8 8h8M8 12h3M8 16h3"/><path d="m14 12 1 1 3-3m-4 6 1 1 3-3"/>',
	"rules": '<path d="M12 5C8 2 4 3 2 4v15c4-2 7-1 10 1 3-2 6-3 10-1V4c-4-2-7-1-10 1Zm0 0v15M5 7l4 1M5 11l4 1M15 8l4-1M15 12l4-1"/>',
	"speed": '<path d="m3 5 8 7-8 7Zm10 0 8 7-8 7Z"/>',
	"animation": '<rect x="3" y="4" width="18" height="16" rx="1"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
	"save": '<path d="M4 3h13l3 3v15H4ZM8 3v6h8V3M8 21v-8h8v8"/>',
	"menu": '<path d="m3 11 9-8 9 8M5 9v12h14V9M10 21v-7h4v7"/>',
	"relics": '<path d="m12 2 4 6 6 4-6 4-4 6-4-6-6-4 6-4Z"/><circle cx="12" cy="12" r="3"/>',
	"settings": '<path d="M3 6h18M3 12h18M3 18h18"/><path d="M8 3v6M16 9v6M10 15v6"/>'
}


static func texture(kind: String) -> Texture2D:
	if not _cache.has(kind):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#e1c38b" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % str(PATHS.get(kind, PATHS.rules))
		var bitmap := Image.new()
		if bitmap.load_svg_from_string(svg) != OK:
			return null
		_cache[kind] = ImageTexture.create_from_image(bitmap)
	return _cache[kind]


static func primary_texture(kind: String) -> Texture2D:
	if not PRIMARY.has(kind):
		return texture(kind)
	var key := "primary:" + kind
	if not _cache.has(key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48"><g stroke="#243740" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % PRIMARY[kind]
		var bitmap := Image.new()
		if bitmap.load_svg_from_string(svg) != OK:
			return null
		_cache[key] = ImageTexture.create_from_image(bitmap)
	return _cache[key]


static func apply(button: Button, kind: String, caption: String, hint: String) -> void:
	button.icon = texture(kind)
	button.text = caption
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 23)
	button.add_theme_constant_override("h_separation", 5)
	button.add_theme_font_size_override("font_size", 13)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.tooltip_text = hint
	button.set_meta("nav_icon", kind)
	button.set_meta("navigation_hint", hint)
	UiStyle.button_skin(button, "quiet", true)
