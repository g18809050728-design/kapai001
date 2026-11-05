class_name CardCatalogV3
extends RefCounted

const DEFAULT_PATH := "res://data/catalog/cards_v3.json"
const SCHEMA_VERSION := "r3-card-catalog.v1"
const EXPECTED_TOTAL := 174
const EXPECTED_PERMANENT_OWNERS := {
	"C": 12,
	"P01": 40,
	"P02": 40,
	"P03": 40,
	"P04": 40,
}
const OWNERS := ["C", "P01", "P02", "P03", "P04"]
const TYPES := ["work", "strategy", "ability", "cooperation", "scene"]
const RARITIES := ["basic", "common", "advanced", "rare", "token"]
const TARGETS := ["self", "task", "all_tasks", "unit", "discard", "paper", "earliest_task"]

var _cards: Dictionary = {}
var _order: Array[String] = []
var _meta: Dictionary = {}
var _starters: Dictionary = {}


func load_catalog(path: String = DEFAULT_PATH) -> GameResult:
	_cards.clear()
	_order.clear()
	_meta.clear()
	_starters.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _invalid("cards_v3.catalog.unreadable", {"path": path})
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _invalid("cards_v3.catalog.invalid_json", {"path": path})
	var catalog: Dictionary = parsed
	if str(catalog.get("schema_version", "")) != SCHEMA_VERSION:
		return _invalid("cards_v3.catalog.schema_version", {"path": path})
	var cards: Variant = catalog.get("cards")
	if typeof(cards) != TYPE_ARRAY:
		return _invalid("cards_v3.catalog.cards_missing", {"path": path})
	var values: Array = cards
	if values.size() != EXPECTED_TOTAL:
		return _invalid(
			"cards_v3.catalog.total", {"expected": EXPECTED_TOTAL, "actual": values.size()}
		)
	var owners := {}
	for value: Variant in values:
		if typeof(value) != TYPE_DICTIONARY:
			return _invalid("cards_v3.catalog.entry_not_object", {})
		var card: Dictionary = value
		var card_id := str(card.get("id", ""))
		if card_id.is_empty() or _cards.has(card_id):
			return _invalid("cards_v3.catalog.id", {"id": card_id})
		var checked := _check_card(card, card_id)
		if not checked.ok:
			return checked
		if bool(card.get("permanent", false)):
			var owner := str(card.get("owner", ""))
			owners[owner] = int(owners.get(owner, 0)) + 1
		_cards[card_id] = card.duplicate(true)
		_order.append(card_id)
	if owners != EXPECTED_PERMANENT_OWNERS:
		return _invalid(
			"cards_v3.catalog.owner_counts",
			{"expected": EXPECTED_PERMANENT_OWNERS, "actual": owners}
		)
	var starters: Variant = catalog.get("starters")
	if typeof(starters) != TYPE_DICTIONARY:
		return _invalid("cards_v3.catalog.starters", {})
	var common: Variant = starters.get("common")
	var characters: Variant = starters.get("characters")
	if typeof(common) != TYPE_ARRAY or typeof(characters) != TYPE_DICTIONARY:
		return _invalid("cards_v3.catalog.starters", {})
	var common_total := 0
	for item: Variant in common:
		if typeof(item) != TYPE_DICTIONARY or not _cards.has(str(item.get("card", ""))):
			return _invalid("cards_v3.catalog.starter_card", {})
		common_total += int(item.get("count", 0))
	if common_total != 10:
		return _invalid("cards_v3.catalog.starter_common_total", {"actual": common_total})
	for owner in ["P01", "P02", "P03", "P04"]:
		if not characters.has(owner):
			return _invalid("cards_v3.catalog.starter_owner", {"owner": owner})
		var entries: Variant = characters[owner]
		if typeof(entries) != TYPE_ARRAY or entries.size() != 2:
			return _invalid("cards_v3.catalog.starter_exclusive", {"owner": owner})
		for card_id in entries:
			if (
				not _cards.has(str(card_id))
				or str(_cards[str(card_id)].get("owner", "")) != owner
				or not bool(_cards[str(card_id)].get("permanent", false))
			):
				return _invalid(
					"cards_v3.catalog.starter_exclusive", {"owner": owner, "id": str(card_id)}
				)
	_starters = starters.duplicate(true)
	_meta = {
		"schema_version": SCHEMA_VERSION,
		"total": values.size(),
		"permanent_owners": owners,
		"runtime_enabled": false,
	}
	return GameResult.success(_meta.duplicate(true))


func get_card(card_id: String) -> GameResult:
	if not _cards.has(card_id):
		return _invalid("cards_v3.catalog.unknown_card", {"id": card_id})
	return GameResult.success(_cards[card_id].duplicate(true))


func get_cards(owner: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_id in _order:
		var card: Dictionary = _cards[card_id]
		if owner.is_empty() or str(card.get("owner", "")) == owner:
			result.append(card.duplicate(true))
	return result


func get_catalog_meta() -> Dictionary:
	return _meta.duplicate(true)


func get_starters() -> Dictionary:
	return _starters.duplicate(true)


func is_runtime_enabled() -> bool:
	return false


func _check_card(card: Dictionary, card_id: String) -> GameResult:
	for field in [
		"id",
		"name_key",
		"name",
		"owner",
		"type",
		"rarity",
		"cost",
		"upgraded_cost",
		"target",
		"effects",
		"implementation"
	]:
		if not card.has(field):
			return _invalid("cards_v3.catalog.field", {"id": card_id, "field": field})
	if not OWNERS.has(str(card.get("owner", ""))):
		return _invalid("cards_v3.catalog.owner", {"id": card_id})
	if not TYPES.has(str(card.get("type", ""))):
		return _invalid("cards_v3.catalog.type", {"id": card_id})
	if not RARITIES.has(str(card.get("rarity", ""))):
		return _invalid("cards_v3.catalog.rarity", {"id": card_id})
	if not TARGETS.has(str(card.get("target", ""))):
		return _invalid("cards_v3.catalog.target", {"id": card_id})
	if card.has("exam"):
		var exam: Variant = card.get("exam")
		if typeof(exam) != TYPE_DICTIONARY or not TARGETS.has(str(exam.get("target", ""))):
			return _invalid("cards_v3.catalog.exam_target", {"id": card_id})
	if typeof(card.get("cost")) != TYPE_FLOAT and typeof(card.get("cost")) != TYPE_INT:
		return _invalid("cards_v3.catalog.cost", {"id": card_id})
	if (
		typeof(card.get("upgraded_cost")) != TYPE_FLOAT
		and typeof(card.get("upgraded_cost")) != TYPE_INT
	):
		return _invalid("cards_v3.catalog.upgraded_cost", {"id": card_id})
	if int(card.get("cost", -1)) < 0 or int(card.get("upgraded_cost", -1)) < 0:
		return _invalid("cards_v3.catalog.cost", {"id": card_id})
	if typeof(card.get("effects")) != TYPE_ARRAY:
		return _invalid("cards_v3.catalog.effects", {"id": card_id})
	if (
		card.effects.is_empty()
		and not card.has("ability")
		and not card.has("chapter")
		and not card.has("exam")
	):
		return _invalid("cards_v3.catalog.effect_face_missing", {"id": card_id})
	var implementation: Variant = card.get("implementation")
	if typeof(implementation) != TYPE_DICTIONARY:
		return _invalid("cards_v3.catalog.implementation", {"id": card_id})
	var impl: Dictionary = implementation
	if str(impl.get("status", "")) != "catalog_only":
		return _invalid("cards_v3.catalog.runtime_status", {"id": card_id})
	if bool(impl.get("runtime_enabled", true)):
		return _invalid("cards_v3.catalog.runtime_enabled", {"id": card_id})
	if typeof(impl.get("pending_mechanics")) != TYPE_ARRAY or impl.pending_mechanics.is_empty():
		return _invalid("cards_v3.catalog.pending_mechanics", {"id": card_id})
	return GameResult.success(true)


func _invalid(message_key: String, details: Dictionary) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_CONTENT_INVALID, message_key, details)
	)
