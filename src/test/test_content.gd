class_name TestContent
extends ContentDB

## Read-only content view used only by the test room. It layers a TestOverlay
## over an immutable base catalog; the base catalog and data/ stay untouched.

var base_catalog: ContentDB
var overlay: TestOverlay


func _init(p_base: ContentDB = null, p_overlay: TestOverlay = null) -> void:
	super("", false)
	base_catalog = p_base
	overlay = p_overlay if p_overlay != null else TestOverlay.new()


func get_definition(kind: String, id: String) -> GameResult:
	if base_catalog == null:
		return GameResult.failure(
			ApiError.new(
				GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE,
				"test.content.missing",
				{"kind": kind, "id": id}
			)
		)
	var value: Variant = null
	if overlay.definitions.has(kind) and overlay.definitions[kind].has(id):
		value = overlay.definitions[kind][id].duplicate(true)
	else:
		var loaded := base_catalog.get_definition(kind, id)
		if not loaded.ok:
			return loaded
		value = loaded.data
	if typeof(value) != TYPE_DICTIONARY:
		return GameResult.failure(
			ApiError.new(
				GameConstants.ERROR_CONTENT_INVALID,
				"test.content.definition_invalid",
				{"kind": kind, "id": id}
			)
		)
	return GameResult.success(overlay.apply(kind, id, value))


func get_candidates(query: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if base_catalog != null:
		found = base_catalog.get_candidates(query)
	var kind := str(query.get("kind", ""))
	if overlay.definitions.has(kind):
		var excluded: Array = query.get("exclude_ids", [])
		for id in overlay.definitions[kind]:
			if not excluded.has(id) and not found.has(id):
				found.append(id)
	return found


func get_info() -> ContentInfo:
	if base_catalog == null:
		return null
	var info := base_catalog.get_info()
	if info == null:
		return null
	var copied := info.copy()
	if not overlay.is_empty():
		copied.content_hash = "%s+test:%s" % [info.content_hash, overlay.hash]
	return copied
