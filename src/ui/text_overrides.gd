class_name TextOverrides
extends RefCounted

## User-editable display text layered over the original content files.
##
## Bundled defaults are loaded from res://data/text_defaults.json; user edits in
## user://text_overrides.json take precedence. Only presentation strings are
## stored here. Gameplay definitions, numbers, commands, RNG, saves and schema
## never read these files. The original text is always kept in the source
## JSON/GDScript data so an entry can be reset.

const DEFAULT_PATH := "user://text_overrides.json"
const DEFAULT_TEXT_PATH := "res://data/text_defaults.json"
const SCHEMA_VERSION := 1
const MAX_ENTRIES := 4000
const MAX_UID_LENGTH := 256
const MAX_TEXT_LENGTH := 20000

static var _path := DEFAULT_PATH
static var _values: Dictionary = {}
static var _loaded := false
static var _load_error := ""
static var _defaults_path := DEFAULT_TEXT_PATH
static var _defaults: Dictionary = {}
static var _defaults_loaded := false
static var _defaults_error := ""


static func use_path(path: String) -> void:
	_path = path if not path.strip_edges().is_empty() else DEFAULT_PATH
	_values = {}
	_loaded = false
	_load_error = ""


static func use_defaults_path(path: String) -> void:
	_defaults_path = path.strip_edges()
	_defaults = {}
	_defaults_loaded = false
	_defaults_error = ""


static func defaults_path() -> String:
	return _defaults_path


static func defaults_error() -> String:
	ensure_defaults_loaded()
	return _defaults_error


static func current_path() -> String:
	return _path


static func last_error() -> String:
	ensure_loaded()
	return _load_error


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_values = {}
	_load_error = ""
	if not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		_load_error = "无法读取文本覆盖文件（%s）。" % error_string(FileAccess.get_open_error())
		return
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		_load_error = "文本覆盖文件格式无效，已按原始文本运行。"
		return
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		_load_error = "文本覆盖文件格式无效，已按原始文本运行。"
		return
	if int(parsed.get("schema_version", 0)) != SCHEMA_VERSION:
		_load_error = "文本覆盖文件版本不支持，已按原始文本运行。"
		return
	var entries: Variant = parsed.get("entries", {})
	if not entries is Dictionary:
		_load_error = "文本覆盖条目格式无效，已按原始文本运行。"
		return
	for raw_key in entries:
		var uid := str(raw_key)
		var value: Variant = entries[raw_key]
		if uid.is_empty() or uid.length() > MAX_UID_LENGTH:
			continue
		if not value is String or str(value).length() > MAX_TEXT_LENGTH:
			continue
		_values[uid] = str(value)
		if _values.size() >= MAX_ENTRIES:
			break
	_migrate_battle_glossary(_values)


static func ensure_defaults_loaded() -> void:
	if _defaults_loaded:
		return
	_defaults_loaded = true
	_defaults = {}
	_defaults_error = ""
	if _defaults_path.is_empty() or not FileAccess.file_exists(_defaults_path):
		return
	var file := FileAccess.open(_defaults_path, FileAccess.READ)
	if file == null:
		_defaults_error = "无法读取内置默认文本（%s）。" % error_string(FileAccess.get_open_error())
		return
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		_defaults_error = "内置默认文本格式无效，已按原始文本运行。"
		return
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		_defaults_error = "内置默认文本格式无效，已按原始文本运行。"
		return
	if int(parsed.get("schema_version", 0)) != SCHEMA_VERSION:
		_defaults_error = "内置默认文本版本不支持，已按原始文本运行。"
		return
	var entries: Variant = parsed.get("entries", {})
	if not entries is Dictionary:
		_defaults_error = "内置默认文本条目格式无效，已按原始文本运行。"
		return
	for raw_key in entries:
		var uid := str(raw_key)
		var value: Variant = entries[raw_key]
		if uid.is_empty() or uid.length() > MAX_UID_LENGTH:
			continue
		if not value is String or str(value).length() > MAX_TEXT_LENGTH:
			continue
		_defaults[uid] = str(value)
		if _defaults.size() >= MAX_ENTRIES:
			break
	_migrate_battle_glossary(_defaults)


## Battle explanations used to carry their glossary at the end of one string,
## and an old ordered-resolution heading at the start of the effect block.
## Clean both once on load so the editor and battle window use the current
## split text without losing any other line.
static func _migrate_battle_glossary(values: Dictionary) -> void:
	var marker := "名词解释："
	var split_values: Dictionary = {}
	for raw_uid in values.keys():
		var uid := str(raw_uid)
		if not uid.ends_with(":battle"):
			continue
		var value := str(values[raw_uid])
		var index := value.find(marker)
		var effect := value
		var glossary := ""
		if index >= 0:
			effect = value.substr(0, index).strip_edges()
			glossary = value.substr(index + marker.length()).strip_edges()
		var cleaned := _strip_battle_heading(effect)
		if cleaned != value:
			split_values[uid] = cleaned
		if index >= 0:
			var glossary_uid := uid.trim_suffix(":battle") + ":battle_glossary"
			if not values.has(glossary_uid):
				split_values[glossary_uid] = glossary
	for uid in split_values:
		values[uid] = split_values[uid]


static func _strip_battle_heading(value: String) -> String:
	var heading := "打出后按顺序结算："
	var lines := value.split("\n")
	for index in lines.size():
		if lines[index].strip_edges() == heading:
			lines.remove_at(index)
			return "\n".join(lines)
	return value


static func reload_from_disk() -> void:
	_loaded = false
	ensure_loaded()


static func get_optional(uid: String) -> Variant:
	ensure_loaded()
	if _values.has(uid):
		return _values[uid]
	ensure_defaults_loaded()
	return _defaults[uid] if _defaults.has(uid) else null


static func default_text(uid: String, fallback: String) -> String:
	ensure_defaults_loaded()
	return str(_defaults[uid]) if _defaults.has(uid) else fallback


static func default_snapshot() -> Dictionary:
	ensure_defaults_loaded()
	return _defaults.duplicate(true)


static func has_default(uid: String) -> bool:
	ensure_defaults_loaded()
	return _defaults.has(uid)


static func has(uid: String) -> bool:
	ensure_loaded()
	return _values.has(uid)


static func text(uid: String, fallback: String) -> String:
	var value: Variant = get_optional(uid)
	return fallback if value == null else str(value)


static func snapshot() -> Dictionary:
	ensure_loaded()
	return _values.duplicate(true)


static func count() -> int:
	ensure_loaded()
	return _values.size()


static func save_values(values: Dictionary) -> String:
	if values.size() > MAX_ENTRIES:
		return "修改条目过多（最多 %d 条）。" % MAX_ENTRIES
	var cleaned: Dictionary = {}
	for raw_key in values:
		var uid := str(raw_key)
		var value: Variant = values[raw_key]
		if uid.is_empty() or uid.length() > MAX_UID_LENGTH:
			return "存在无法识别的文本条目。"
		if not value is String:
			return "文本条目必须是字符串。"
		if str(value).length() > MAX_TEXT_LENGTH:
			return "单条文本过长（最多 %d 字）。" % MAX_TEXT_LENGTH
		cleaned[uid] = str(value)
	var document := {
		"schema_version": SCHEMA_VERSION,
		"updated_at": Time.get_datetime_string_from_system(true),
		"entries": cleaned,
	}
	var absolute := ProjectSettings.globalize_path(_path)
	var directory := absolute.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(directory)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return "无法创建文本覆盖目录（%s）。" % error_string(dir_error)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入文本覆盖文件（%s）。" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	file.close()
	var backup := absolute + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute):
		var move_error := DirAccess.rename_absolute(absolute, backup)
		if move_error != OK:
			DirAccess.remove_absolute(temporary)
			return "无法替换文本覆盖文件（%s）。" % error_string(move_error)
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		DirAccess.remove_absolute(temporary)
		return "无法保存文本覆盖文件（%s）。" % error_string(rename_error)
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	_values = cleaned.duplicate(true)
	_loaded = true
	_load_error = ""
	return ""
