class_name TestOverlay
extends RefCounted

## Local, test-only content overlay. Never writes to data/ or the base catalog.

const KINDS := [
	"card", "character", "task", "encounter", "unit", "relic", "status", "scene", "ruleset"
]

const FIELDS := {
	"card": [
		"cost",
		"type",
		"target",
		"rarity",
		"tags",
		"effects",
		"upgrade",
		"flags",
		"limits",
		"requirements",
		"owner",
		"exhaust",
		"permanent",
	],
	"character": ["passive", "starter_cards", "starter_relic_id", "resources"],
	"task": ["phases", "kind", "exam_flags"],
	"encounter": ["members", "initial_members", "base_ddl", "exam_flags", "kind"],
	"unit": ["vitality", "max_vitality", "cooperation", "relax", "actions", "support", "slots"],
	"relic": ["hooks", "rarity", "availability", "campaign"],
	"status": ["target", "duration_policy", "stack_policy", "dispel_policy", "numeric_rule_key"],
	"scene": ["slots", "triggers", "effects", "duration"],
	"ruleset": ["battle", "statuses", "run"],
}

var definitions: Dictionary = {}
var fields: Dictionary = {}
var hash: String = ""


func is_empty() -> bool:
	return definitions.is_empty() and fields.is_empty()


func definition_count() -> int:
	var count := 0
	for kind in definitions:
		count += definitions[kind].size()
	return count


func field_count() -> int:
	var count := 0
	for kind in fields:
		for id in fields[kind]:
			count += fields[kind][id].size()
	return count


func to_dictionary() -> Dictionary:
	return {
		"definitions": definitions.duplicate(true),
		"fields": fields.duplicate(true),
		"hash": hash,
	}


static func from_dictionary(value: Variant) -> TestOverlay:
	var overlay := TestOverlay.new()
	if typeof(value) != TYPE_DICTIONARY:
		return overlay
	var definitions_value: Variant = value.get("definitions", {})
	if typeof(definitions_value) == TYPE_DICTIONARY:
		overlay.definitions = definitions_value.duplicate(true)
	var fields_value: Variant = value.get("fields", {})
	if typeof(fields_value) == TYPE_DICTIONARY:
		overlay.fields = fields_value.duplicate(true)
	overlay.recompute_hash()
	return overlay


func copy() -> TestOverlay:
	return TestOverlay.from_dictionary(to_dictionary())


func recompute_hash() -> void:
	hash = SnapshotCodec.canonical_json({"definitions": definitions, "fields": fields}).sha256_text()


func upsert(kind: String, id: String, definition: Dictionary) -> ApiError:
	if not KINDS.has(kind):
		return _error("test.patch.unknown_kind", {"kind": kind})
	if not id.begins_with("TEST.") or id.length() > 64:
		return _error("test.patch.invalid_test_id", {"id": id})
	if not _is_safe_id(id):
		return _error("test.patch.invalid_test_id", {"id": id})
	if typeof(definition) != TYPE_DICTIONARY:
		return _error("test.patch.invalid_definition", {"id": id})
	if str(definition.get("id", "")) != id:
		return _error("test.patch.definition_id_mismatch", {"id": id})
	if not definitions.has(kind):
		definitions[kind] = {}
	definitions[kind][id] = definition.duplicate(true)
	recompute_hash()
	return null


func remove(kind: String, id: String) -> ApiError:
	if not KINDS.has(kind):
		return _error("test.patch.unknown_kind", {"kind": kind})
	if not definitions.has(kind) or not definitions[kind].has(id):
		return _error("test.patch.unknown_definition", {"kind": kind, "id": id})
	definitions[kind].erase(id)
	if definitions[kind].is_empty():
		definitions.erase(kind)
	recompute_hash()
	return null


func set_field(kind: String, id: String, path: String, value: Variant) -> ApiError:
	if not KINDS.has(kind):
		return _error("test.patch.unknown_kind", {"kind": kind})
	var root := path.get_slice(".", 0)
	if not FIELDS[kind].has(root):
		return _error("test.patch.field_not_supported", {"kind": kind, "field": root})
	if not fields.has(kind):
		fields[kind] = {}
	if not fields[kind].has(id):
		fields[kind][id] = {}
	fields[kind][id][path] = _copy_value(value)
	recompute_hash()
	return null


func remove_field(kind: String, id: String, path: String) -> ApiError:
	if not fields.has(kind) or not fields[kind].has(id) or not fields[kind][id].has(path):
		return _error("test.patch.unknown_field_override", {"kind": kind, "id": id, "path": path})
	fields[kind][id].erase(path)
	if fields[kind][id].is_empty():
		fields[kind].erase(id)
	if fields[kind].is_empty():
		fields.erase(kind)
	recompute_hash()
	return null


func apply(kind: String, id: String, base: Dictionary) -> Dictionary:
	var value := base.duplicate(true)
	if definitions.has(kind) and definitions[kind].has(id):
		value = definitions[kind][id].duplicate(true)
	if fields.has(kind) and fields[kind].has(id):
		for path in fields[kind][id]:
			_set_path(value, str(path), fields[kind][id][path])
	return value


func summary() -> Dictionary:
	var by_kind := {}
	for kind in definitions:
		by_kind[kind] = definitions[kind].size()
	return {
		"hash": hash,
		"definition_count": definition_count(),
		"field_count": field_count(),
		"definitions_by_kind": by_kind,
	}


static func _set_path(target: Dictionary, path: String, value: Variant) -> void:
	var segments := path.split(".", false)
	if segments.is_empty():
		return
	var current: Variant = target
	for index in segments.size() - 1:
		var segment := segments[index]
		var next_segment := segments[index + 1]
		if current is Array:
			var position := int(segment)
			if position < 0 or position >= current.size():
				return
			if not (current[position] is Dictionary or current[position] is Array):
				current[position] = [] if next_segment.is_valid_int() else {}
			current = current[position]
		else:
			if not current.has(segment) or not (current[segment] is Dictionary or current[segment] is Array):
				current[segment] = [] if next_segment.is_valid_int() else {}
			current = current[segment]
	var last := segments[-1]
	if current is Array:
		var position := int(last)
		if position >= 0 and position < current.size():
			current[position] = _copy_value(value)
	else:
		current[last] = _copy_value(value)


static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _is_safe_id(value: String) -> bool:
	if value.is_empty():
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


static func _error(key: String, details: Dictionary) -> ApiError:
	return ApiError.new(GameConstants.ERROR_TEST_PATCH_INVALID, key, details)
