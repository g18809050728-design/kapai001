class_name SnapshotCodec
extends RefCounted

const FIELDS := [
	"schema_version",
	"content_version",
	"content_hash",
	"manifest_id",
	"run_id",
	"revision",
	"random_state",
	"payload",
	"checksum"
]
const SESSION_FIELDS := ["run", "battle", "terminal_summary", "profile_merge_pending", "event_log"]
const DOCUMENT_KINDS := ["profile", "settings"]
const MAX_EXACT_INTEGER := 9007199254740991


static func normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = normalize_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize_numbers(item))
		return result
	if (
		value is float
		and is_finite(value)
		and absf(value) <= MAX_EXACT_INTEGER
		and value == floor(value)
	):
		return int(value)
	return value


static func canonical_json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var pairs: PackedStringArray = []
		for key in keys:
			pairs.append(JSON.stringify(str(key)) + ":" + canonical_json(value[key]))
		return "{" + ",".join(pairs) + "}"
	if value is Array:
		var items: PackedStringArray = []
		for item in value:
			items.append(canonical_json(item))
		return "[" + ",".join(items) + "]"
	return JSON.stringify(normalize_numbers(value))


static func compute_checksum(snapshot: Dictionary) -> String:
	var body := snapshot.duplicate(true)
	body.erase("checksum")
	return canonical_json(body).sha256_text()


static func checksum_matches(snapshot: Variant) -> bool:
	return (
		snapshot is Dictionary
		and snapshot.get("checksum") is String
		and snapshot.checksum == compute_checksum(snapshot)
	)


static func wrap_snapshot(payload: Dictionary, meta: Dictionary) -> Dictionary:
	var result := {
		"schema_version": meta.get("schema_version", GameConstants.SNAPSHOT_SCHEMA_VERSION),
		"content_version": meta.get("content_version", ""),
		"content_hash": meta.get("content_hash", ""),
		"manifest_id": meta.get("manifest_id", ""),
		"run_id": meta.get("run_id"),
		"revision": meta.get("revision"),
		"random_state": meta.get("random_state"),
		"payload": payload.duplicate(true)
	}
	result = result.duplicate(true)
	result["checksum"] = compute_checksum(result)
	return result


static func validate_structure(snapshot: Variant) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not snapshot is Dictionary:
		return PackedStringArray(["snapshot must be an object"])
	_check_keys(snapshot, FIELDS, "snapshot", issues)
	for field in ["content_version", "content_hash", "manifest_id", "checksum"]:
		if not snapshot.get(field) is String:
			issues.append("snapshot.%s must be a string" % field)
	if not snapshot.get("schema_version") is int:
		issues.append("snapshot.schema_version must be an integer")
	if not snapshot.get("payload") is Dictionary:
		issues.append("snapshot.payload must be an object")
	for field in ["run_id", "revision", "random_state"]:
		var value: Variant = snapshot.get(field)
		var expected: int = {
			"run_id": TYPE_STRING, "revision": TYPE_INT, "random_state": TYPE_DICTIONARY
		}[field]
		if value != null and typeof(value) != expected:
			issues.append("snapshot.%s has an invalid type" % field)
	var checksum: Variant = snapshot.get("checksum")
	if checksum is String:
		if checksum.length() != 64 or not checksum.is_valid_hex_number(false):
			issues.append("snapshot.checksum must be SHA-256 hex")
	_json_issues(snapshot, "snapshot", issues)
	return issues


static func encode_session(session: SessionState, content_info: ContentInfo) -> GameResult:
	if session == null or content_info == null:
		return _error(
			GameConstants.ERROR_INVALID_ARGUMENT, ["session and content_info are required"]
		)
	if (
		session.pending_choice != null
		or (session.battle != null and session.battle.resolution != null)
	):
		return _error(GameConstants.ERROR_CHOICE_PENDING, ["only stable sessions can be saved"])
	var issues := session.validate()
	_json_issues(session.event_log, "event_log", issues)
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	var run_result := RunCodec.encode(session.run)
	if not run_result.ok:
		return run_result
	var battle: Variant = null
	if session.battle != null:
		var battle_result := BattleCodec.encode(session.battle)
		if not battle_result.ok:
			return battle_result
		battle = battle_result.data
	var snapshot := wrap_snapshot(
		{
			"run": run_result.data,
			"battle": battle,
			"terminal_summary":
			(
				RunCodec.encode_summary(session.terminal_summary)
				if session.terminal_summary != null
				else null
			),
			"profile_merge_pending": session.profile_merge_pending,
			"event_log": session.event_log.duplicate(true)
		},
		{
			"content_version": content_info.content_version,
			"content_hash": content_info.content_hash,
			"manifest_id": content_info.id,
			"run_id": session.run.run_id,
			"revision": session.revision,
			"random_state": session.random_snapshot
		}
	)
	issues = validate_structure(snapshot)
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	return GameResult.success(snapshot)


static func encode_document(kind: String, payload: Dictionary, meta: Dictionary = {}) -> GameResult:
	if not DOCUMENT_KINDS.has(kind):
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, ["unsupported document kind"])
	var issues: PackedStringArray = []
	_json_issues(payload, "payload", issues)
	_json_issues(meta, "meta", issues)
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	var document_meta := meta.duplicate(true)
	document_meta.merge(
		{"manifest_id": kind, "run_id": null, "revision": null, "random_state": null}, true
	)
	var snapshot := wrap_snapshot(payload, document_meta)
	issues = validate_structure(snapshot)
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	return GameResult.success(snapshot)


static func decode_document(snapshot: Variant, expected_kind: String) -> GameResult:
	var checked := _check_snapshot(snapshot)
	if not checked.ok:
		return checked
	if not DOCUMENT_KINDS.has(expected_kind) or snapshot.manifest_id != expected_kind:
		return _error(GameConstants.ERROR_VERSION_MISMATCH, ["document kind mismatch"])
	if snapshot.run_id != null or snapshot.revision != null or snapshot.random_state != null:
		return _error(GameConstants.ERROR_SAVE_CORRUPT, ["document contains session metadata"])
	var meta: Dictionary = snapshot.duplicate(true)
	meta.erase("payload")
	return GameResult.success({"payload": normalize_numbers(snapshot.payload), "meta": meta})


static func decode_session(snapshot: Variant, catalog: ContentDB) -> GameResult:
	var checked := _check_snapshot(snapshot)
	if not checked.ok:
		return checked
	if catalog == null or catalog.get_info() == null:
		return _error(GameConstants.ERROR_CONTENT_INVALID, ["loaded catalog is required"])
	var info := catalog.get_info()
	if (
		snapshot.content_version != info.content_version
		or snapshot.content_hash != info.content_hash
		or snapshot.manifest_id != info.id
	):
		return _error(
			GameConstants.ERROR_VERSION_MISMATCH, ["content version/hash/manifest mismatch"]
		)
	var data: Dictionary = normalize_numbers(snapshot)
	var issues: PackedStringArray = []
	_check_keys(data.payload, SESSION_FIELDS, "payload", issues)
	if (
		not data.run_id is String
		or str(data.run_id).is_empty()
		or not data.revision is int
		or data.revision < 0
	):
		issues.append("run_id and nonnegative revision are required")
	if not data.random_state is Dictionary:
		issues.append("random_state is required")
	if not data.payload.get("run") is Dictionary:
		issues.append("payload.run must be an object")
	if data.payload.get("battle") != null and not data.payload.battle is Dictionary:
		issues.append("payload.battle must be an object or null")
	if (
		data.payload.get("terminal_summary") != null
		and not data.payload.terminal_summary is Dictionary
	):
		issues.append("payload.terminal_summary must be an object or null")
	if (
		not data.payload.get("profile_merge_pending") is bool
		or not data.payload.get("event_log") is Array
	):
		issues.append("invalid session marker or event log type")
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	if data.random_state.get("algorithm_version") != GameConstants.RANDOM_ALGORITHM_VERSION:
		return _error(GameConstants.ERROR_VERSION_MISMATCH, ["random algorithm version mismatch"])
	var rng := RandomSource.new()
	var restored := rng.restore_state(data.random_state)
	if not restored.ok:
		return _error(
			GameConstants.ERROR_SAVE_CORRUPT, ["invalid random streams"], restored.error.details
		)
	var run_result := RunCodec.decode(data.payload.run, catalog)
	if not run_result.ok:
		return run_result
	if run_result.data.ruleset_id != info.ruleset_id or run_result.data.manifest_id != info.id:
		return _error(GameConstants.ERROR_VERSION_MISMATCH, ["ruleset or run manifest mismatch"])
	var session := SessionState.new()
	session.run = run_result.data
	session.revision = data.revision
	session.random_snapshot = data.random_state.duplicate(true)
	if data.payload.battle != null:
		var battle_result := BattleCodec.decode(data.payload.battle, catalog)
		if not battle_result.ok:
			return battle_result
		session.battle = battle_result.data
	if data.payload.terminal_summary != null:
		var summary_result := RunCodec.decode_summary(data.payload.terminal_summary)
		if not summary_result.ok:
			return summary_result
		session.terminal_summary = summary_result.data
	session.profile_merge_pending = data.payload.profile_merge_pending
	for entry in data.payload.event_log:
		if not entry is Dictionary:
			return _error(GameConstants.ERROR_SAVE_CORRUPT, ["event log entries must be objects"])
		session.event_log.append(entry.duplicate(true))
	issues = session.validate()
	if session.run.run_id != data.run_id:
		issues.append("outer and inner run_id mismatch")
	if not issues.is_empty():
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	return GameResult.success(session)


static func migrate(snapshot: Variant, migrations: Dictionary = {}) -> GameResult:
	var issues := validate_structure(normalize_numbers(snapshot))
	if not issues.is_empty() or not checksum_matches(snapshot):
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	var working: Dictionary = normalize_numbers(snapshot)
	var visited := {}
	while working.schema_version != GameConstants.SNAPSHOT_SCHEMA_VERSION:
		var version: int = working.schema_version
		if (
			visited.has(version)
			or not migrations.get(version) is Callable
			or not migrations[version].is_valid()
		):
			return _error(GameConstants.ERROR_VERSION_MISMATCH, ["no supported migration path"])
		visited[version] = true
		var migrated: Variant = migrations[version].call(working.duplicate(true))
		if not migrated is Dictionary:
			return _error(GameConstants.ERROR_SAVE_CORRUPT, ["migration returned invalid snapshot"])
		working = normalize_numbers(migrated)
		working["checksum"] = "0".repeat(64)
		issues = validate_structure(working)
		if not issues.is_empty():
			return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
		working["checksum"] = compute_checksum(working)
	return GameResult.success(working)


static func _check_snapshot(snapshot: Variant) -> GameResult:
	var normalized: Variant = normalize_numbers(snapshot)
	var issues := validate_structure(normalized)
	if not issues.is_empty() or not checksum_matches(snapshot):
		return _error(GameConstants.ERROR_SAVE_CORRUPT, issues)
	if normalized.schema_version != GameConstants.SNAPSHOT_SCHEMA_VERSION:
		return _error(GameConstants.ERROR_VERSION_MISMATCH, ["unsupported snapshot schema"])
	return GameResult.success(true)


static func _check_keys(
	data: Dictionary, fields: Array, path: String, issues: PackedStringArray
) -> void:
	for key in fields:
		if not data.has(key):
			issues.append("%s.%s is required" % [path, key])
	for key in data:
		if not fields.has(key):
			issues.append("%s.%s is unknown" % [path, key])


static func _json_issues(value: Variant, path: String, issues: PackedStringArray) -> void:
	if value is Dictionary:
		for key in value:
			if not key is String:
				issues.append("%s keys must be strings" % path)
			_json_issues(value[key], path + "." + str(key), issues)
	elif value is Array:
		for index in value.size():
			_json_issues(value[index], "%s[%d]" % [path, index], issues)
	elif value is int:
		if value > MAX_EXACT_INTEGER or value < -MAX_EXACT_INTEGER:
			issues.append("%s integers outside JSON precision must use decimal strings" % path)
	elif value is float:
		if not is_finite(value) or absf(value) > MAX_EXACT_INTEGER:
			issues.append("%s contains an unsafe JSON number" % path)
	elif value != null and not value is String and not value is bool:
		issues.append("%s must use JSON primitive values" % path)


static func _error(
	code: StringName, issues: PackedStringArray, details: Dictionary = {}
) -> GameResult:
	var context := details.duplicate(true)
	context["issues"] = Array(issues)
	return GameResult.failure(ApiError.new(code, "error.save.codec", context))
