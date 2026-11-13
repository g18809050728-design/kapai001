class_name CampaignService
extends RefCounted

const DIRECTIONS := ["theory", "engineering", "competition", "practice"]
const DESTINATIONS := ["job", "exam", "research", "abroad"]
const FIELDS := {"version": TYPE_INT, "exploration": TYPE_INT, "visited_types": TYPE_ARRAY,
	"direction": TYPE_STRING, "direction_changed": TYPE_BOOL, "resume": TYPE_INT,
	"thesis": TYPE_INT, "destination": TYPE_STRING, "pending": TYPE_DICTIONARY,
	"triggered": TYPE_ARRAY, "history": TYPE_ARRAY}

var _catalog: ContentDB

func _init(catalog: ContentDB = null) -> void:
	_catalog = catalog

static func enabled(run: RunState) -> bool:
	return run.manifest_id == "campus_four_year"

static func initial() -> Dictionary:
	return {"version": 1, "exploration": 0, "visited_types": [], "direction": "",
		"direction_changed": false, "resume": 0, "thesis": 0, "destination": "",
		"pending": {}, "triggered": [], "history": []}

static func validate(data: Dictionary, issues: Array[String]) -> void:
	var start := issues.size()
	var initial_issues := start
	var fields := FIELDS.duplicate()
	if data.get("version") == 2:
		fields.merge(CampaignProgression.MAP_FIELDS)
	RunCodec.shape(data, fields, "run.campaign", issues)
	if issues.size() != start:
		return
	if data.version not in [1, 2] or data.exploration < 0 or data.exploration > 6 or data.resume < 0 or data.resume > 6 or data.thesis < 0 or data.thesis > 5:
		issues.append("campaign version/counter invalid")
	if data.direction not in [""] + DIRECTIONS or data.destination not in [""] + DESTINATIONS:
		issues.append("campaign direction/destination invalid")
	RunCodec.strings(data.visited_types, "campaign.visited_types", issues)
	RunCodec.strings(data.triggered, "campaign.triggered", issues)
	var resolved := {}
	for record in data.history:
		start = issues.size()
		RunCodec.shape(record, {"offer_id": TYPE_STRING, "option_id": TYPE_STRING, "candidate_id": TYPE_STRING}, "campaign.history", issues)
		if issues.size() == start:
			RunCodec.unique(record.offer_id, resolved, "campaign.history.offer_id", issues)
			if record.offer_id not in data.triggered:
				issues.append("campaign history has no triggered offer")
	if not data.pending.is_empty():
		start = issues.size()
		RunCodec.shape(data.pending, {"offer_id": TYPE_STRING, "kind": TYPE_STRING, "source_node_id": TYPE_STRING, "candidates": TYPE_ARRAY}, "campaign.pending", issues)
		if issues.size() == start:
			RunCodec.strings(data.pending.candidates, "campaign.pending.candidates", issues)
			if data.pending.kind not in ["relic", "grand", "service", "direction", "destination", "familiar"] or not data.triggered.has(data.pending.offer_id):
				issues.append("campaign pending kind/key invalid")
			if resolved.has(data.pending.offer_id):
				issues.append("campaign pending offer was already resolved")
			if data.pending.kind not in ["relic", "grand"] and not data.pending.candidates.is_empty():
				issues.append("campaign service cannot contain reward candidates")
	if data.version == 2 and issues.size() == initial_issues:
		CampaignProgression.validate_campaign(data, issues)

func bonus(run: RunState, effect: String) -> int:
	var amount := 0
	for relic in run.relics:
		var definition := _catalog.get_definition("relic", str(relic.definition_id))
		if definition.ok and definition.data.get("campaign", {}).get("effect", "") == effect:
			amount += int(definition.data.campaign.amount)
	return amount

func service_cost(run: RunState, subtype: String) -> int:
	var cost := 20 if subtype == "L" else (15 if subtype == "LAB" else 10)
	var direction: String = run.campaign.direction
	if (subtype == "L" and direction == "theory") or (subtype == "LAB" and direction == "engineering"):
		cost -= 10
	if int(run.campaign.resume) >= 2:
		cost -= 5
	return maxi(0, cost - bonus(run, "service_discount"))

func enter(run: RunState, node: RunNodeState) -> void:
	var meta := CampaignProgression.metadata(run, node.node_id)
	var subtype: String = meta.subtype
	if run.term == 1 and not run.campaign.visited_types.has(subtype):
		run.campaign.visited_types.append(subtype)
		run.campaign.exploration = mini(6, run.campaign.visited_types.size())
	if node.kind == "rest" and subtype != "R":
		_set_pending(run, "service", node.node_id + "|service", node.node_id, [])

func completed(run: RunState, node: RunNodeState, rng: RandomSource) -> GameResult:
	var meta := CampaignProgression.metadata(run, node.node_id)
	var subtype: String = meta.subtype
	var used := true
	if node.kind == "rest" and subtype != "R":
		used = run.campaign.history.any(func(record): return record.offer_id == node.node_id + "|service" and record.option_id in ["upgrade", "remove", "heal", "money", "progress"])
	var resume_node: bool = subtype in ["I", "K", "T", "LAB"] if CampaignProgression.enabled(run) else (subtype in ["I", "K", "T"] or meta.title in ["科研组会", "导师项目"])
	if used and run.term == 3 and resume_node:
		run.campaign.resume = mini(6, int(run.campaign.resume) + 1)
	if used and run.term == 4 and subtype in ["LAB", "ST", "T"]:
		run.campaign.thesis = mini(5, int(run.campaign.thesis) + 1)
	if subtype == "R":
		run.vitality = mini(run.max_vitality, run.vitality + bonus(run, "rest_heal"))
	if node.kind == "event":
		run.money += bonus(run, "event_money")
		if run.term == 1 and int(run.campaign.exploration) >= 4:
			_set_pending(run, "familiar", node.node_id + "|familiar", node.node_id, [])
	var map: Dictionary = CampaignProgression.year_info(run, run.term)
	if map.relic_layers.has(node.layer):
		var key := "%s|y%d|relic%d" % [run.run_id, run.term, map.relic_layers.find(node.layer)]
		if not run.campaign.triggered.has(key):
			var pool: Array = []
			for id in _catalog.get_candidates({"kind": "relic"}):
				var d: Dictionary = _catalog.get_definition("relic", id).data
				if int(d.get("campaign", {}).get("year", 0)) == run.term:
					pool.append(id)
			var chosen := _sample(pool, 3, rng)
			_set_pending(run, "relic", key, node.node_id, chosen)
	return GameResult.success(true)

func grand(run: RunState, node: RunNodeState, rng: RandomSource) -> GameResult:
	var generated := RewardGenerator.new(_catalog).card_candidates(run, 3, rng, {"white": 0, "blue": 30, "purple": 50, "gold": 20})
	if not generated.ok:
		return generated
	_set_pending(run, "grand", node.node_id + "|grand", node.node_id, generated.data)
	return GameResult.success(true)

func _set_pending(run: RunState, kind: String, id: String, source: String, candidates: Array) -> void:
	run.campaign.triggered.append(id)
	run.campaign.pending = {"offer_id": id, "kind": kind, "source_node_id": source, "candidates": candidates.duplicate()}

func choose(run: RunState, payload: Dictionary) -> GameResult:
	var pending: Dictionary = run.campaign.pending
	if pending.is_empty() or payload.get("offer_id", "") != pending.offer_id:
		return _error("run.campaign.offer.invalid")
	var option := str(payload.get("option_id", ""))
	var candidate := str(payload.get("candidate_id", ""))
	var checked: GameResult
	match str(pending.kind):
		"relic":
			checked = _relic(run, pending, option, candidate, str(payload.get("replace_relic_id", "")))
		"grand":
			checked = _grand_choice(run, pending, option, candidate)
		"service":
			checked = _service(run, pending, option, candidate)
		"familiar":
			if option not in ["money", "skip"]:
				return _error("run.campaign.option.invalid")
			if option == "money": run.money += 10
			checked = GameResult.success(true)
		"direction", "destination":
			var choices: Array = DIRECTIONS if pending.kind == "direction" else DESTINATIONS
			if option not in choices:
				return _error("run.campaign.option.invalid")
			run.campaign[pending.kind] = option
			checked = GameResult.success(true)
		_:
			return _error("run.campaign.kind.invalid")
	if not checked.ok:
		return checked
	if pending.kind == "grand":
		CampaignProgression.complete_year(run)
	run.campaign.history.append({"offer_id": pending.offer_id, "option_id": option, "candidate_id": candidate})
	run.campaign.pending = {}
	if pending.kind == "service":
		var node := run.find_node(pending.source_node_id)
		node.context = {"used": true, "option_id": "train"}
	if pending.kind == "grand" and run.term < 4:
		run.term += 1
		run.pending_reward = null
		if run.term == 2:
			_set_pending(run, "direction", run.run_id + "|direction", run.current_node_id, [])
		elif run.term == 4:
			if int(run.campaign.resume) >= 6:
				run.money += 30
			_set_pending(run, "destination", run.run_id + "|destination", run.current_node_id, [])
	var generated := CampaignProgression.ensure_year(run)
	if not generated.ok:
		return generated
	return GameResult.success({"graduated": pending.kind == "grand" and run.term == 4 and run.find_node(run.current_node_id).term == 4})

func _relic(run: RunState, pending: Dictionary, option: String, candidate: String, replace_id: String) -> GameResult:
	if option == "skip":
		run.money += 20
		return GameResult.success(true)
	if candidate not in pending.candidates or option not in ["claim", "convert"]:
		return _error("run.campaign.candidate.invalid")
	for relic in run.relics:
		if relic.definition_id == candidate:
			run.money += 25
			return GameResult.success(true)
	if option == "convert":
		if run.relics.size() < 3:
			return _error("run.campaign.convert.requires_full")
		run.money += 30
		return GameResult.success(true)
	var used: Array = run.relics.map(func(relic): return int(relic.slot))
	var slot := 0
	while used.has(slot):
		slot += 1
	if run.relics.size() >= 3:
		var replacement: Array = run.relics.filter(func(relic): return relic.relic_id == replace_id)
		if replacement.is_empty():
			return _error("run.campaign.replacement.required")
		slot = int(replacement[0].slot)
	elif not replace_id.is_empty():
		return _error("run.campaign.replacement.invalid")
	TransactionResolver.new(_catalog).add_relic(run, candidate, replace_id, slot)
	return GameResult.success(true)

func _grand_choice(run: RunState, pending: Dictionary, option: String, candidate: String) -> GameResult:
	match option:
		"card":
			if candidate not in pending.candidates:
				return _error("run.campaign.candidate.invalid")
			TransactionResolver.new(_catalog).add_card(run, candidate, "year_grand")
		"upgrade", "remove":
			return _change_card(run, option, candidate)
		"resources":
			run.money += 60
			if (run.term == 1 and int(run.campaign.exploration) >= 6) or (run.term == 4 and int(run.campaign.thesis) >= 4):
				run.money += 20
			run.vitality = mini(run.max_vitality, run.vitality + int(floor(run.max_vitality * 0.2)))
		"skip":
			run.money += 30
		_:
			return _error("run.campaign.option.invalid")
	return GameResult.success(true)

func _change_card(run: RunState, option: String, id: String) -> GameResult:
	for index in run.cards.size():
		var card: Dictionary = run.cards[index]
		if card.card_id != id:
			continue
		if option == "upgrade":
			var definition: Dictionary = _catalog.get_definition("card", str(card.definition_id)).data
			if int(card.upgrade_level) >= 1 or definition.get("upgrade", {}).is_empty():
				return _error("run.campaign.upgrade.invalid")
			card.upgrade_level += 1
		elif option == "remove" and run.cards.size() > 5:
			run.cards.remove_at(index)
		else:
			return _error("run.campaign.deck.minimum")
		return GameResult.success(true)
	return _error("run.campaign.card.invalid")

func _service(run: RunState, pending: Dictionary, option: String, candidate: String) -> GameResult:
	var meta := CampaignProgression.metadata(run, pending.source_node_id)
	var subtype: String = meta.subtype
	if option == "skip":
		return GameResult.success(true)
	if option.begins_with("direction_") and run.term == 2 and int(meta.layer) >= 7 and not run.campaign.direction_changed:
		var direction := option.trim_prefix("direction_")
		if direction not in DIRECTIONS or run.money < 30:
			return _error("run.campaign.direction.invalid")
		run.money -= 30
		run.campaign.direction = direction
		run.campaign.direction_changed = true
		return GameResult.success(true)
	if subtype in ["L", "T", "LAB"]:
		if option not in (["upgrade"] if subtype == "LAB" else ["upgrade", "remove"]):
			return _error("run.campaign.option.invalid")
		var cost := service_cost(run, subtype)
		if run.money < cost or (subtype == "LAB" and run.vitality <= 5):
			return _error("run.campaign.resources.insufficient")
		var changed := _change_card(run, option, candidate)
		if not changed.ok:
			return changed
		run.money -= cost
		if subtype == "LAB":
			run.vitality -= 5
	elif subtype == "C" and option in ["heal", "money"]:
		if option == "heal":
			run.vitality = mini(run.max_vitality, run.vitality + 8)
		else:
			run.money += 15 + bonus(run, "service_money") + (10 if run.campaign.direction == "practice" else 0)
	elif subtype == "I" and option == "money":
		run.money += 25 + bonus(run, "service_money") + (10 if run.campaign.direction == "practice" else 0)
	elif subtype == "ST" and option == "progress":
		run.vitality = mini(run.max_vitality, run.vitality + 4)
	else:
		return _error("run.campaign.option.invalid")
	return GameResult.success(true)

func _sample(pool: Array, count: int, rng: RandomSource) -> Array:
	var result: Array = []
	var available := pool.duplicate()
	while not available.is_empty() and result.size() < count:
		var index := int(rng.draw_int("reward", 0, available.size() - 1).data)
		result.append(available.pop_at(index))
	return result

func _error(key: String) -> GameResult:
	return GameResult.failure(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, key))
