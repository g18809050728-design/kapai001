extends RefCounted

var _failures: Array[String] = []


func run() -> Array[String]:
	var catalog := ContentDB.new("res://data/four_year")
	_check(catalog.load("campus_four_year").ok, "current production catalog loads")
	var rules := BattleCardRules.new(catalog)
	var representatives := {"R3-C-01": "attack", "R3-C-02": "defense", "R3-C-03": "utility", "R3-C-05": "defense", "R3-C-06": "ability", "R3-C-08": "field", "R3-C-11": "attack", "R3-P01-02": "attack", "R3-P01-37": "attack", "R3-P02-11": "defense", "R3-P02-40": "ability", "R3-P03-01": "attack", "R3-P04-01": "utility", "R3-P04-40": "attack"}
	var counts := {}
	var rows: Array = []
	for id in catalog.get_candidates({"kind": "card"}):
		var definition: Dictionary = catalog.get_definition("card", id).data
		for level in ([0, 1] if definition.has("upgrade") else [0]):
			var state := BattleState.new({"card_by_id": {"card": {"definition_id": id, "upgrade_level": level}}})
			var modes: Array = [[]]
			if definition.has("exam"):
				modes.append([str(definition.exam.condition)])
			for flags in modes:
				state.exam_flags.assign(flags)
				var resolved := rules.resolve_face(state, "card")
				_check(resolved.ok, "%s/%d resolves" % [id, level])
				if not resolved.ok:
					continue
				var face: Dictionary = resolved.data
				var before := SnapshotCodec.canonical_json(face)
				var model := CardDisplayModel.from_card({"definition_id": id, "face": face, "effective_cost": 0})
				_check(SnapshotCodec.canonical_json(face) == before, "%s presentation is read only" % id)
				_check(model.cost == 0 and model.kind == face.type, "%s keeps the quoted cost and original rule type" % id)
				_check(CardDisplayModel.CATEGORY_NAMES.has(model.category), "%s has a recognized category" % id)
				if flags.is_empty() and representatives.has(id):
					_check(model.category == representatives[id], "%s/%d category is %s" % [id, level, representatives[id]])
				if not flags.is_empty() and id == "R3-C-08":
					_check(model.category == "defense", "fixed exam room uses the resolved relax face, rather than the original field")
				if not flags.is_empty() and id == "R3-P04-01":
					_check(model.category == "attack", "independent answer uses the mixed attack/relax face, rather than partner summon")
				if level == 0 and flags.is_empty():
					counts[model.category] = int(counts.get(model.category, 0)) + 1
				var offer := UiOfferCard.new()
				offer.configure(id, face, "", false)
				_check(offer._face is CardFaceView and offer._face.model.category == model.category, "%s offer and battle share a category" % id)
				offer.free()
				rows.append({"id": id, "upgrade": level, "exam": flags, "category": model.category, "rule_type": model.kind, "quoted_cost": model.cost})
	_check(rows.size() >= 376, "all base, upgrade and exam faces were checked")
	var simple := CardDisplayModel.from_card({"id": "R3-C-02", "type": "strategy", "cost": 1, "effects": [{"op": "relax", "amount": 5}]})
	_check(simple.cost == 1 and simple.summary.contains("5"), "shield cost remains 1 while relax remains 5 in the text")
	var gain_next := CardDisplayModel.from_card({"type": "strategy", "effects": [{"op": "work_bonus_next", "amount": 4}]})
	_check(gain_next.category == "utility", "next-card bonus is functional, not an immediate attack")
	print("CARD_CATEGORY_EVIDENCE=", JSON.stringify({"faces": rows, "base_counts": counts, "failures": _failures}))
	return _failures


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append("Card categories: " + message)
