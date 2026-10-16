class_name SaveStore
extends RefCounted

const SLOTS := ["current_run", "profile", "settings"]

var debug_hooks: Dictionary = {}
var _base_path: String


func _init(base_path: String = "user://saves") -> void:
	_base_path = ProjectSettings.globalize_path(base_path).simplify_path()


func inspect(slot: String) -> GameResult:
	return _inspect(slot, false)


func inspect_backup(slot: String) -> GameResult:
	return _inspect(slot, true)


func load(slot: String) -> GameResult:
	if not SLOTS.has(slot):
		return _invalid_slot(slot)
	return _read_snapshot(_path(slot))


func load_backup(slot: String) -> GameResult:
	if not SLOTS.has(slot):
		return _invalid_slot(slot)
	return _read_snapshot(_path(slot) + ".bak")


func archive_current_run() -> GameResult:
	# Preserve bytes, including corrupt/unsupported documents, before replacement.
	var nonce := Crypto.new().generate_random_bytes(16)
	if nonce.size() != 16:
		return _io_error("save.archive.random_failed", _base_path)
	var destination := _base_path.path_join("recovery").path_join(nonce.hex_encode())
	if DirAccess.dir_exists_absolute(destination):
		return _io_error("save.archive.exists", destination)
	var made := DirAccess.make_dir_recursive_absolute(destination)
	if made != OK:
		return _io_error("save.archive.directory_failed", destination, made)
	for suffix in ["", ".bak"]:
		var source: String = _path("current_run") + suffix
		if not FileAccess.file_exists(source):
			continue
		var target := destination.path_join(source.get_file())
		var copied := (
			FAILED
			if _hook("current_run", "fail_archive")
			else DirAccess.copy_absolute(source, target)
		)
		if copied != OK:
			return _io_error("save.archive.copy_failed", target, copied)
		var digest := FileAccess.get_sha256(source)
		if digest.is_empty() or FileAccess.get_sha256(target) != digest:
			return _io_error("save.archive.verify_failed", target)
	return GameResult.success(destination)


func save(slot: String, snapshot: Dictionary) -> GameResult:
	if not SLOTS.has(slot):
		return _invalid_slot(slot)
	var validated := _integrity(snapshot, _path(slot))
	if not validated.ok:
		return validated
	var make_error := DirAccess.make_dir_recursive_absolute(_base_path)
	if make_error != OK:
		return _io_error("save.directory.failed", _base_path, make_error)
	var path := _path(slot)
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var backup_temporary := backup + ".tmp"
	if _hook(slot, "fail_write"):
		return _io_error("save.debug.fail_write", temporary)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _io_error("save.write.failed", temporary, FileAccess.get_open_error())
	var serialized := SnapshotCodec.canonical_json(snapshot)
	file.store_string(
		(
			serialized.substr(0, maxi(1, serialized.length() / 2))
			if _hook(slot, "truncate_temp")
			else serialized
		)
	)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _io_error("save.write.failed", temporary, write_error)
	var checked := _read_snapshot(temporary)
	if not checked.ok:
		return checked
	if FileAccess.file_exists(path):
		var existing := _read_snapshot(path)
		if existing.ok:
			var copied := DirAccess.copy_absolute(path, backup_temporary)
			if copied != OK:
				return _io_error("save.backup.copy_failed", backup_temporary, copied)
			var backup_checked := _read_snapshot(backup_temporary)
			if not backup_checked.ok:
				return backup_checked
			if FileAccess.file_exists(backup):
				var removed := DirAccess.remove_absolute(backup)
				if removed != OK:
					return _io_error("save.backup.replace_failed", backup, removed)
			var renamed := DirAccess.rename_absolute(backup_temporary, backup)
			if renamed != OK:
				return _io_error("save.backup.replace_failed", backup, renamed)
	if _hook(slot, "fail_after_backup"):
		return _io_error("save.debug.fail_after_backup", backup)
	if FileAccess.file_exists(path):
		var removed := DirAccess.remove_absolute(path)
		if removed != OK:
			return _io_error("save.replace.remove_failed", path, removed)
	var replaced := (
		FAILED if _hook(slot, "fail_rename") else DirAccess.rename_absolute(temporary, path)
	)
	if replaced != OK:
		_restore_backup(path, backup)
		return _io_error("save.replace.failed", path, replaced)
	var published := _read_snapshot(path)
	if not published.ok:
		_restore_backup(path, backup)
		return published
	var receipt := SaveReceipt.new()
	receipt.slot = StringName(slot)
	receipt.revision = int(snapshot.get("revision", 0)) if snapshot.get("revision") != null else 0
	receipt.checksum = snapshot.checksum
	receipt.written_at = Time.get_datetime_string_from_system(true)
	return GameResult.success(receipt)


func _inspect(slot: String, backup: bool) -> GameResult:
	if not SLOTS.has(slot):
		return _invalid_slot(slot)
	var path := _path(slot) + (".bak" if backup else "")
	if not FileAccess.file_exists(path):
		return _not_found(path)
	var checked := _read_snapshot(path)
	var snapshot: Dictionary = checked.data if checked.ok else {}
	var metadata := {
		"slot": slot,
		"path": path,
		"saved_at": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path)),
		"schema_version": snapshot.get("schema_version"),
		"content_version": snapshot.get("content_version"),
		"revision": snapshot.get("revision"),
		"checksum": snapshot.get("checksum", ""),
		"valid": checked.ok,
		"problems": [],
	}
	if not checked.ok:
		metadata.problems.append(checked.error.to_dictionary())
	return GameResult.success(metadata)


func _read_snapshot(path: String) -> GameResult:
	if not FileAccess.file_exists(path):
		return _not_found(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _io_error("save.read.failed", path, FileAccess.get_open_error())
	var source := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK or not parser.data is Dictionary:
		return _corrupt(
			"save.json.invalid",
			path,
			{"line": parser.get_error_line(), "message": parser.get_error_message()}
		)
	var snapshot: Dictionary = SnapshotCodec.normalize_numbers(parser.data)
	var checked := _integrity(snapshot, path)
	return GameResult.success(snapshot) if checked.ok else checked


func _integrity(snapshot: Dictionary, path: String) -> GameResult:
	var issues := SnapshotCodec.validate_structure(snapshot)
	if not issues.is_empty():
		return _corrupt("save.structure.invalid", path, {"issues": Array(issues)})
	if not SnapshotCodec.checksum_matches(snapshot):
		return _corrupt("save.checksum.invalid", path)
	return GameResult.success(true)


func _restore_backup(path: String, backup: String) -> void:
	if not _read_snapshot(backup).ok:
		return
	DirAccess.copy_absolute(backup, path)


func _path(slot: String) -> String:
	return _base_path.path_join(slot + ".json")


func _hook(slot: String, name: String) -> bool:
	return (
		bool(debug_hooks.get(slot, {}).get(name, false))
		or bool(debug_hooks.get("*", {}).get(name, false))
	)


func _invalid_slot(slot: String) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "save.slot.invalid", {"slot": slot})
	)


func _not_found(path: String) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_SAVE_NOT_FOUND, "save.not_found", {"path": path})
	)


func _io_error(key: String, path: String, error: int = FAILED) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_SAVE_IO_ERROR, key, {"path": path, "error": error})
	)


func _corrupt(key: String, path: String, extra: Dictionary = {}) -> GameResult:
	var details := extra.duplicate(true)
	details.path = path
	return GameResult.failure(ApiError.new(GameConstants.ERROR_SAVE_CORRUPT, key, details))
