extends SceneTree
## Independent deterministic offer coverage on generated maps at real reward
## layers. This stages the checkpoint; it is not a playthrough or a balance test.

const ID := RelicPilot.ROSTER
const MAP_SEED := "42"
const MAX_ROLLS := 2048


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ContentDB.new("res://data/four_year")
	if not catalog.load(ID).ok:
		_fail("cannot load ordinary full roster")
		return
	var ids := catalog.get_candidates({"kind":"relic", "availability":"drop"})
	if ids.size() != 104 or not ids.all(RelicPilot.is_rx):
		_fail("expected exactly 104 RX and no retired definitions")
		return
	var service := CampaignService.new(catalog)
	var cases: Array[Dictionary] = []
	var observed := {}
	for character in ["P01", "P02", "P03", "P04"]:
		var start := RunService.new(catalog).create(StartRunRequest.new(character, &"normal", ID, MAP_SEED))
		if not start.ok:
			_fail("cannot start " + character)
			return
		var run: RunState = start.data.state
		for year in range(1, 5):
			run.term = year
			run.campaign.pending = {}
			if year == 4: run.campaign.destination = "job"
			if not CampaignProgression.ensure_year(run).ok:
				_fail("cannot stage year %d for %s" % [year, character])
				return
			# P04 exercises all four year weights and the exam-restricted rewards.
			# For the other protagonists year four enables every own rarity.
			if character != "P04" and year != 4: continue
			var layer := int(CampaignService.relic_layers(run).front())
			var checkpoints := run.nodes.filter(func(node): return node.term == year and node.layer == layer and not node.next_ids.is_empty())
			if checkpoints.is_empty():
				_fail("no authored reward layer for %s year %d" % [character,year])
				return
			var node: RunNodeState = checkpoints.front()
			run.current_node_id = node.node_id
			node.status = "completed"
			var remaining := {}
			for id in ids:
				var definition: Dictionary = catalog.get_definition("relic",id).data
				if RelicPilot.is_candidate(definition,character,year,true): remaining[id] = true
			var count := remaining.size()
			var rolled := 0
			for n in range(MAX_ROLLS):
				run.campaign.pending = {}
				run.campaign.triggered.clear()
				if not service.completed(run,node,RandomSource.new(str(n))).ok or run.campaign.pending.get("kind") != "relic":
					_fail("normal completion did not generate a frozen relic offer")
					return
				rolled += 1
				var frozen: Array = run.campaign.pending.candidates
				var gold := 0
				for id in frozen:
					if id not in ids or not RelicPilot.is_candidate(catalog.get_definition("relic", id).data, character, year, true):
						_fail("illegal offer: %s year %d %s" % [character, year, id])
						return
					gold += int(catalog.get_definition("relic", id).data.rarity == "gold")
					remaining.erase(id)
					if not observed.has(id): observed[id] = {"character":character,"year":year,"layer":layer,"reward_seed":str(n)}
				if frozen.size() != 3 or frozen[0] == frozen[1] or frozen[0] == frozen[2] or frozen[1] == frozen[2] or gold > 1:
					_fail("offer is not three distinct options with at most one gold")
					return
				if remaining.is_empty(): break
			if not remaining.is_empty():
				_fail("unobserved offers for %s year %d: %s" % [character,year,remaining.keys()])
				return
			cases.append({"character":character,"year":year,"layer":layer,"pool":count,"offers_checked":rolled})
	var missing := ids.filter(func(id): return not observed.has(id))
	if not missing.is_empty():
		_fail("unobserved offers: %s" % [missing])
		return
	print("RELIC_REWARD_COVERAGE=" + JSON.stringify({"observed":observed,"cases":cases,"map_seed":MAP_SEED,"entries":observed.size()}))
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
