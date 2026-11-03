extends RefCounted

const EXPECTED_TOTAL := 174
const EXPECTED_PERMANENT_OWNERS := {
	"C": 12,
	"P01": 40,
	"P02": 40,
	"P03": 40,
	"P04": 40,
}


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := CardCatalogV3.new()
	var loaded := catalog.load_catalog()
	_check(loaded.ok, "cards v3 catalog loads", failures)
	if not loaded.ok:
		failures.append(
			"cards v3 catalog: load error " + JSON.stringify(loaded.error.to_dictionary())
		)
		return failures
	var meta := catalog.get_catalog_meta()
	_check(int(meta.get("total", 0)) == EXPECTED_TOTAL, "cards v3 catalog has 174 entries", failures)
	_check(
		meta.get("permanent_owners", {}) == EXPECTED_PERMANENT_OWNERS,
		"cards v3 permanent owner counts",
		failures
	)
	_check(not catalog.is_runtime_enabled(), "cards v3 catalog is not runtime enabled", failures)
	var cards := catalog.get_cards()
	_check(cards.size() == EXPECTED_TOTAL, "cards v3 catalog returns all entries", failures)
	var ids := {}
	var runtime_enabled := 0
	var missing_effects := 0
	for card: Dictionary in cards:
		var card_id := str(card.get("id", ""))
		_check(not card_id.is_empty(), "cards v3 catalog entry has id", failures)
		_check(not ids.has(card_id), "cards v3 catalog id is unique: " + card_id, failures)
		ids[card_id] = true
		var implementation: Dictionary = card.get("implementation", {})
		if bool(implementation.get("runtime_enabled", true)):
			runtime_enabled += 1
		_check(
			str(implementation.get("status", "")) == "catalog_only",
			card_id + " is catalog_only",
			failures
		)
		_check(
			not implementation.get("pending_mechanics", []).is_empty(),
			card_id + " lists pending mechanics",
			failures
		)
		if (
			card.get("effects", []).is_empty()
			and not card.has("ability")
			and not card.has("chapter")
			and not card.has("exam")
		):
			missing_effects += 1
	_check(runtime_enabled == 0, "cards v3 catalog is not runtime enabled", failures)
	_check(missing_effects == 0, "every card has an effect face", failures)
	var p01 := catalog.get_cards("P01")
	_check(p01.size() == 40, "P01 exposes 40 cards", failures)
	var starters := catalog.get_starters()
	var common: Array = starters.get("common", [])
	var common_total := 0
	for item: Dictionary in common:
		common_total += int(item.get("count", 0))
	_check(common_total == 10, "v3 common starter counts total 10", failures)
	var characters: Dictionary = starters.get("characters", {})
	_check(characters.size() == 4, "v3 starters cover four characters", failures)
	for owner in ["P01", "P02", "P03", "P04"]:
		_check(
			characters.get(owner, []).size() == 2,
			owner + " has two exclusive starter cards",
			failures
		)
	var unknown := catalog.get_card("R3-UNKNOWN")
	_check(not unknown.ok, "unknown card is rejected", failures)
	if failures.is_empty():
		print(
			"CARDS_V3_CATALOG_EVIDENCE=",
			JSON.stringify(
				{
					"total": cards.size(),
					"owners": meta.get("permanent_owners", {}),
					"runtime_enabled": runtime_enabled,
					"missing_effects": missing_effects,
					"loader": "CardCatalogV3",
				}
			)
		)
	return failures


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("cards v3 catalog: " + label)
