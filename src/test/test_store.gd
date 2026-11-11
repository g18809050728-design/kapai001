class_name TestStore
extends RefCounted

## Isolated test-room file store. Never touches user://saves/.

const SCHEMA_VERSION := 1
const KINDS := {
	"preset": {"folder": "presets", "kind": "test_room_preset"},
	"snapshot": {"folder": "snapshots", "kind": "test_room_snapshot"},
	"record": {"folder": "records", "kind": "test_room_record"},
	"export": {"folder": "exports", "kind": "test_room_record"},
}

var base_path: String


func _init(p_base_path: String = "user://test_room") -> void:
	base_path = p_base_path


func save(kind: String, id: String, name: String, payload: Dictionary) -> GameResult:
	var meta: Dictionary = KINDS.get(kind, {})
	if meta.is_empty():
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.kind", {"kind": kind})
	if not _safe_id(id):
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.id", {"id": id})
	var folder := "%s/%s" % [base_path, meta.folder]
	var created := DirAccess.make_dir_recursive_absolute(folder)
	if created != OK and created != ERR_ALREADY_EXISTS:
		return _failure(GameConstants.ERROR_TEST_IO_ERROR, "test.file.directory", {"path": folder})
	var document := {
		"schema_version": SCHEMA_VERSION,
		"kind": meta.kind,
		"test_file": true,
		"id": id,
		"name": name,
		"payload": payload.duplicate(true),
	}
	var target := "%s/%s.json" % [folder, id]
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure(
			GameConstants.ERROR_TEST_IO_ERROR,
			"test.file.write",
			{"path": temporary, "error": FileAccess.get_open_error()}
		)
	file.store_string(SnapshotCodec.canonical_json(document))
	file.close()
	var renamed := DirAccess.rename_absolute(temporary, target)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return _failure(
			GameConstants.ERROR_TEST_IO_ERROR, "test.file.rename", {"path": target, "error": renamed}
		)
	return GameResult.success({"id": id, "name": name, "path": target, "kind": meta.kind})


func load_file(kind: String, id: String) -> GameResult:
	var meta: Dictionary = KINDS.get(kind, {})
	if meta.is_empty():
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.kind", {"kind": kind})
	if not _safe_id(id):
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.id", {"id": id})
	var path := "%s/%s/%s.json" % [base_path, meta.folder, id]
	if not FileAccess.file_exists(path):
		return _failure(GameConstants.ERROR_SAVE_NOT_FOUND, "test.file.not_found", {"id": id})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(
			GameConstants.ERROR_TEST_IO_ERROR,
			"test.file.read",
			{"path": path, "error": FileAccess.get_open_error()}
		)
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.corrupt", {"id": id})
	var document: Dictionary = parsed
	if (
		int(document.get("schema_version", -1)) != SCHEMA_VERSION
		or document.get("kind") != meta.kind
		or not bool(document.get("test_file", false))
	):
		return _failure(
			GameConstants.ERROR_VERSION_MISMATCH,
			"test.file.version",
			{"id": id, "schema_version": document.get("schema_version")}
		)
	var payload: Variant = document.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload", {"id": id})
	return GameResult.success(
		{"id": id, "name": str(document.get("name", id)), "payload": payload, "path": path}
	)


func list(kind: String) -> Array[Dictionary]:
	var meta: Dictionary = KINDS.get(kind, {})
	var entries: Array[Dictionary] = []
	if meta.is_empty():
		return entries
	var folder := "%s/%s" % [base_path, meta.folder]
	var directory := DirAccess.open(folder)
	if directory == null:
		return entries
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir() and name.ends_with(".json"):
			var id := name.trim_suffix(".json")
			var document := _read_document("%s/%s" % [folder, name])
			entries.append(
				{
					"id": id,
					"name": str(document.get("name", id)),
					"kind": str(document.get("kind", "")),
					"schema_version": int(document.get("schema_version", 0)),
					"compatible": int(document.get("schema_version", -1)) == SCHEMA_VERSION,
				}
			)
		name = directory.get_next()
	directory.list_dir_end()
	entries.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return entries


func remove(kind: String, id: String) -> GameResult:
	var meta: Dictionary = KINDS.get(kind, {})
	if meta.is_empty():
		return _failure(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.kind", {"kind": kind})
	var path := "%s/%s/%s.json" % [base_path, meta.folder, id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return GameResult.success(true)


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var allowed := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code == 95
			or code == 45
			or code == 46
		)
		if not allowed:
			return false
	return true


static func _failure(code: StringName, key: String, details: Dictionary = {}) -> GameResult:
	return GameResult.failure(ApiError.new(code, key, details))
