extends SceneTree

var _failures: Array[String] = []
var _checks := 0
var _receipts := {}
var _catalog := ContentDB.new("res://data/four_year")
var _engine: BattleEngine
var _service: RunService


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded := _catalog.load(RelicPilot.MANIFEST)
	if not _ok(loaded, "pilot manifest"):
		_finish()
		return
	_engine = BattleEngine.new(_catalog)
	_service = RunService.new(_catalog)
	_test_package()
	_test_prepare()
	_test_work()
	_test_lin()
	_test_paper()
	_test_debuffs()
	_test_partners()
	_test_run()
	_test_test_room()
	_test_battle_matrix()
	for id in RelicPilot.IDS:
		_check(_receipts.has(id), "actual relic event observed for " + id)
	_finish()


func _finish() -> void:
	print("RX_PILOT_CHECKS=%d FAILURES=%d UNIQUE_TRIGGERED=%d" % [_checks, _failures.size(), _receipts.size()])
	print("RX_PILOT_EVENTS=" + JSON.stringify(_receipts, "", true))
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, name: String) -> bool:
	_checks += 1
	if not value:
		_failures.append(name)
	return value


func _ok(result: GameResult, name: String) -> bool:
	return _check(result != null and result.ok, name + (" " + str(result.error.to_dictionary()) if result != null and result.error != null else ""))


func _events(step: GameResult, id: String, at: String = "") -> int:
	if not step.ok:
		return 0
	var count := 0
	for event: RuleEvent in step.data.events:
		if event.type == &"relic_triggered" and event.source_id == id and (at.is_empty() or event.data.get("at") == at):
			_check(event.data.relic_id == id and int(event.data.amount) > 0 and int(event.data.remaining) >= 0, id + " source, actual amount and remaining")
			_receipts[id] = event.data.duplicate(true)
			count += 1
	return count


func _record(step: GameResult, id: String, at: String) -> Dictionary:
	if not step.ok:
		return {}
	for event: RuleEvent in step.data.events:
		if event.type == &"relic_triggered" and event.source_id == id and event.data.get("at") == at:
			return event.data
	return {}


func _battle(character: String, ids: Array, deck: Array = [], encounter: String = "N01", stabilize: bool = true, members: Array = []) -> GameResult:
	var cards: Array[Dictionary] = []
	for i in 12:
		cards.append({"card_id":"fixture_%d" % i, "definition_id": deck[i] if i < deck.size() else "R3-C-02", "upgrade_level":0})
	var input := {"battle_id":"rx-test", "encounter_id":encounter,
		"character_id":character, "relics":ids, "cards":cards, "vitality":72, "max_vitality":72,
		"rng_state":RandomSource.new("415").export_state().to_dictionary()}
	if not members.is_empty(): input["member_ids"] = members
	var step := _engine.begin(input)
	if _ok(step, "engine begins %s %s %s" % [character, encounter, ids]) and stabilize:
		for task in step.data.state.tasks:
			task.work_max = 999
			task.work_remaining = 999
			task.shield = 0
	return step


func _instance(state: BattleState, id: String, from_hand: bool = false) -> String:
	var zones: Array = ["hand"] if from_hand else ["hand", "draw", "discard"]
	for zone in zones:
		for inst: String in state.zones[zone]:
			if state.card_by_id[inst].definition_id == id:
				return inst
	return ""


func _put(state: BattleState, id: String) -> String:
	var instance := _instance(state, id)
	if not instance.is_empty() and not state.zones.hand.has(instance):
		if state.zones.hand.size() >= 10:
			state.zones.draw.append(state.zones.hand.pop_back())
		state.zones.draw.erase(instance)
		state.zones.discard.erase(instance)
		state.zones.hand.append(instance)
	return instance


func _play(step: GameResult, id: String, target: String = "", replace_id: String = "", should_succeed: bool = true) -> GameResult:
	if not step.ok:
		return step
	var state: BattleState = step.data.state
	var instance := _put(state, id)
	var draft := ActionDraft.new(&"play_card", {"card_instance_id":instance, "target_ids":[target] if not target.is_empty() else [], "replace_unit_id":replace_id})
	var before := state.to_dictionary()
	var random: Dictionary = step.data.rng_state.duplicate(true)
	_engine.preview(state, draft)
	_check(before == state.to_dictionary() and random == step.data.rng_state, "play preview is pure " + id)
	var result := _engine.apply(state, draft, random)
	if should_succeed:
		_ok(result, "actual play " + id)
	else:
		_check(not result.ok, "actual rejection " + id)
	return result


func _end(step: GameResult) -> GameResult:
	if not step.ok:
		return step
	var next := _engine.apply(step.data.state, ActionDraft.new(&"end_turn"), step.data.rng_state)
	_ok(next, "end turn")
	return next


func _target(step: GameResult) -> String:
	return str(step.data.state.tasks[0].task_id) if step.ok and not step.data.state.tasks.is_empty() else ""


func _stack(step: GameResult, id: String, count: int, target: String = "") -> void:
	if target.is_empty():
		target = _target(step)
	var state: BattleState = step.data.state
	state.statuses.append({"status_id":id, "instance_id":"fixture_%s_%s" % [target, id], "source_id":"", "target_id":target, "stacks":count, "expiry":"battle"})


func _stacks(step: GameResult, id: String) -> int:
	for record in step.data.state.statuses:
		if record.status_id == id and record.target_id == _target(step):
			return int(record.stacks)
	return 0


func _test_package() -> void:
	var base := ContentDB.new("res://data/four_year")
	if not _ok(base.load(RelicPilot.BASE), "unchanged base package"):
		return
	_check(base.get_info().content_hash == "73e947de8b2daa4c4c0f940a142fe12376bd939442aa6f7a08c320040b5acf60", "base catalog hash unchanged")
	var pilot := _catalog.get_info()
	_check(pilot.id == RelicPilot.MANIFEST and pilot.content_version == RelicPilot.VERSION and pilot.content_hash != base.get_info().content_hash, "dedicated compatibility identity")
	_check(base.get_candidates({"kind":"relic"}).size() == 16 and pilot.enabled.relic.size() == 24 and pilot.enabled.relic.all(RelicPilot.is_rx), "24 active pilot RX; no originals")
	var normal := GameSession.new(SaveStore.new("user://rx-test-base-%d" % OS.get_process_id()))
	_check(not normal.start_run(StartRunRequest.new("P01", &"normal", RelicPilot.MANIFEST, "42")).accepted, "normal launch rejects pilot")
	normal.free()
	for id in RelicPilot.IDS:
		_check(not base.get_definition("relic", id).ok, "pilot relic absent officially: " + id)
		var detail: Dictionary = _catalog.get_definition("relic", id).data
		_check(not UiStyle.label(id).begins_with("RX-") and UiContentText.describe_relic(detail) == detail.rx.text, "exact plan UI description " + id)
		if not DisplayServer.get_name() == "headless":
			_check(UiStyle.texture(id) != null, "imported artwork " + id)


func _test_prepare() -> void:
	var deck := ["R3-P01-11", "R3-P01-12", "R3-P01-13", "R3-P01-15", "R3-P01-16", "R3-P01-17", "R3-P01-25", "R3-P01-39"]
	var common := _battle("P01", ["RX-C01", "RX-C02", "RX-C05"], deck)
	var control := _battle("P01", [], deck)
	if not common.ok or not control.ok:
		return
	_check(common.data.state.player.relax == 4 and _events(common,"RX-C01") == 1, "bell grants 4 on round 1")
	_check(common.data.state.zones.hand.size() == 6 and _events(common,"RX-C05") == 1, "search moves the top eligible strategy after five draws")
	var drawn: Array = common.data.events.filter(func(event): return event.type == &"card_drawn")
	_check(drawn.size() == 5 and common.data.rng_state == control.data.rng_state, "search is not a draw and no extra RNG")
	var second := _end(common)
	if second.ok:
		_check(second.data.state.player.focus == 4 and _events(second,"RX-C02") == 1, "outlet gives exactly one extra focus on round 2")
	var third := _end(second)
	if third.ok:
		_check(third.data.state.player.focus == 3 and _events(third,"RX-C02") == 0, "outlet expires after round 2")
	var alarm := _battle("P01", ["RX-C23"])
	alarm.data.state.ddl = 3
	var low := _end(alarm)
	if low.ok:
		_check(low.data.state.ddl == 2 and low.data.state.player.focus == 4 and _events(low,"RX-C23") == 2 and low.data.state.zones.hand.size() == 6, "alarm grants focus and post-base draw without modifying DDL")
		var lower := _end(low)
		_check(lower.ok and lower.data.state.ddl == 1 and _events(lower,"RX-C23") == 0, "alarm is once per battle")
	var rain := _battle("P04", ["RX-C17"], ["R3-P04-08"])
	var guard := _play(rain, "R3-P04-08")
	var blocked := _end(guard)
	if blocked.ok:
		_check(_events(blocked,"RX-C17") == 0, "guard pressure is not player pressure")
		for unit in blocked.data.state.units:
			unit.vitality = 1
		blocked.data.state.statuses = blocked.data.state.statuses.filter(func(status): return status.status_id != "guard")
		var direct := _end(blocked)
		_check(direct.ok and _events(direct,"RX-C17") == 1, "raincoat only fires at positive pressure assigned to player")


func _test_work() -> void:
	var step := _battle("P01", ["RX-C09", "RX-P01-01", "RX-P01-09"], ["R3-P01-09", "R3-P01-23", "R3-P01-30", "R3-P01-04", "R3-P01-10"])
	if not step.ok:
		return
	step.data.state.player.focus = 10
	step.data.state.v3.pending_cost_discount = {"amount":2,"min_base_cost":2}
	var free_work := _play(step,"R3-P01-09",_target(step))
	if not free_work.ok:
		return
	_check(_events(free_work,"RX-C09") == 0, "unpaid cost-2 work does not consume counterweight")
	var area := _play(free_work,"R3-P01-30")
	if not area.ok:
		return
	_check(_events(area,"RX-C09") == 0, "area-only work has no primary target")
	var strat := _play(area,"R3-P01-04")
	var hit := _play(strat,"R3-P01-23",_target(strat))
	if hit.ok:
		_check(_events(hit,"RX-C09") == 1 and _events(hit,"RX-P01-01") == 1 and _events(hit,"RX-P01-09") == 1, "linked paid work triggers all three")
		_check(_record(hit,"RX-P01-09","work_primary_segment").get("amount") == 3, "4+3+5 caps at 10 in slot order")
	var immunity := _battle("P01", ["RX-C09"], ["R3-P01-23"])
	_stack(immunity,"attack_immunity",1)
	var immune := _play(immunity,"R3-P01-23",_target(immunity))
	_check(immune.ok and _events(immune,"RX-C09") == 1 and immune.data.state.tasks[0].work_remaining == 999, "written modifier consumes once before immunity")
	var interrupted := _battle("P01", ["RX-P01-01", "RX-P01-09"], ["R3-P01-04", "R3-P01-10", "R3-P01-09"])
	interrupted.data.state.player.focus = 10
	interrupted = _play(interrupted,"R3-P01-04")
	interrupted = _play(interrupted,"R3-P01-10")
	interrupted = _play(interrupted,"R3-P01-09",_target(interrupted))
	_check(interrupted.ok and _events(interrupted,"RX-P01-01") == 0 and _events(interrupted,"RX-P01-09") == 1, "strategy/ability/work breaks adjacency without clearing strategy history")


func _test_lin() -> void:
	var retrieve := _battle("P01", ["RX-P01-05"], ["R3-P01-04","R3-P01-02"])
	retrieve = _play(retrieve,"R3-P01-04")
	retrieve = _play(retrieve,"R3-P01-02",_target(retrieve))
	if not _check(retrieve.ok and retrieve.data.pending_choice != null, "step reuse offers choice"):
		return
	var choice: Dictionary = retrieve.data.pending_choice
	var select := str(choice.candidates[0].id)
	var confirmed := _engine.apply(retrieve.data.state, ActionDraft.new(&"confirm_choice", {"choice_id":choice.choice_id,"selected_ids":[select]}), retrieve.data.rng_state)
	var declined := _engine.apply(retrieve.data.state, ActionDraft.new(&"confirm_choice", {"choice_id":choice.choice_id,"selected_ids":[]}), retrieve.data.rng_state)
	if _ok(confirmed,"reuse confirmed") and _ok(declined,"reuse explicitly declined"):
		_check(_events(confirmed,"RX-P01-05") == 1 and _events(declined,"RX-P01-05") == 0 and confirmed.data.state.player.relax == declined.data.state.player.relax + 4, "only actual move to hand gives relax")
		_check(confirmed.data.rng_state == declined.data.rng_state, "choice without random effects leaves RNG unchanged")
	var search := _battle("P01", ["RX-P01-15"], ["R3-P01-04", "R3-C-01", "R3-P01-02"])
	for id in ["R3-C-01", "R3-P01-02"]:
		var inst := _instance(search.data.state,id)
		search.data.state.zones.hand.erase(inst)
		search.data.state.zones.draw.erase(inst)
		search.data.state.zones.draw.push_front(inst)
	var found := _play(search,"R3-P01-04")
	_check(found.ok and _events(found,"RX-P01-15") == 1 and not _instance(found.data.state,"R3-P01-02",true).is_empty(), "lin work search does not reorder the draw pile")


func _test_paper() -> void:
	for c in [49, 50, 79, 80, 99, 100]:
		var paper := _battle("P02", ["RX-P02-01","RX-P02-02"], ["R3-P02-01"], "NR2")
		paper = _play(paper,"R3-P02-01")
		if not paper.ok:
			continue
		_check(paper.data.state.v3.paper.modifier == 4 and _events(paper,"RX-P02-01") == 1, "opening records separate +4 modifier")
		paper.data.state.v3.paper.modifier = c
		paper.data.state.v3.paper.progress = 0
		var published := _play(paper,"R3-T201")
		if not published.ok:
			continue
		var extra := 8 if c >= 50 and c <= 79 else 0
		_check(_events(published,"RX-P02-02") == (1 if extra else 0), "seal eligibility C=%d" % c)
		_check(published.data.state.tasks[0].work_remaining == 999 - c - 10 - extra - (20 if c == 100 else 0), "seal main value at C=%d" % c)
		if _check(published.data.state.tasks.size() >= 2, "publication fixture has a real secondary target"):
			_check(published.data.state.tasks[1].work_remaining == 999 - int(c/2.0) - (20 if c == 100 else 0), "secondary unchanged at C=%d" % c)
		var event: RuleEvent = published.data.events.filter(func(e): return e.type == &"paper_published")[0]
		_check(event.data.completion == c and published.data.state.v3.paper.chapters.is_empty(), "published C and chapter return stay unchanged")
	var chapters := _battle("P02", ["RX-P02-07","RX-P02-15"], ["R3-P02-01","R3-P02-11","R3-P02-20","R3-P02-27"])
	chapters.data.state.player.focus = 10
	chapters = _play(chapters,"R3-P02-01")
	chapters = _play(chapters,"R3-P02-11")
	var extra_run := _play(chapters,"R3-P02-20")
	_check(extra_run.ok and _events(extra_run,"RX-P02-07") == 0, "extra chapter window does not count as natural")
	var natural := _end(extra_run)
	_check(natural.ok and _events(natural,"RX-P02-07") == 1, "natural window grants relax")
	var copied := _play(natural,"R3-P02-27")
	var reused := _play(copied,"R3-P02-11")
	_check(reused.ok and _events(reused,"RX-P02-15") == 1 and reused.data.state.v3.paper.chapters.size() == 1, "first paid reuse after natural run grants relax and doesn't redeploy")


func _test_debuffs() -> void:
	var dots := _battle("P03", ["RX-P03-01","RX-P03-05","RX-P03-16"], ["R3-P03-17","R3-P03-02","R3-C-04"])
	var first := _play(dots,"R3-P03-17",_target(dots))
	if not first.ok:
		return
	_check(_events(first,"RX-P03-05") == 0 and _events(first,"RX-P03-16","compound_reaction") == 1, "new induced not natural and actual compound reaction arms draw")
	var second := _play(first,"R3-P03-02",_target(first))
	if not second.ok:
		return
	_check(_stacks(second,"erosion") == 4 and _events(second,"RX-P03-01") == 1, "direct erosion becomes 3+1")
	_check(second.data.state.v3.turn.erosion_events == 1 and _events(second,"RX-P03-16","next_card_resolved") == 1, "extra layer is not another event, next card draws once")
	_check(_events(second,"RX-P03-05") == 1 and int(second.data.state.v3.turn.induced_triggers.get(_target(second))) == 1, "natural induced gets +2 without a new trigger")
	var capped := _battle("P03", ["RX-P03-01"], ["R3-P03-02"])
	_stack(capped,"erosion",20)
	capped = _play(capped,"R3-P03-02",_target(capped))
	_check(capped.ok and _stacks(capped,"erosion") == 20 and _events(capped,"RX-P03-01") == 0 and capped.data.state.v3.turn.erosion_events == 0, "capped erosion never counts")
	var mixed := _battle("P03", ["RX-P03-09"], ["R3-P03-22","R3-P03-35"])
	_stack(mixed,"erosion",1)
	_stack(mixed,"weakness",1)
	mixed = _play(mixed,"R3-P03-22",_target(mixed))
	_check(mixed.ok and _events(mixed,"RX-P03-09") == 0, "third status from this card isn't in play snapshot")
	mixed = _play(mixed,"R3-P03-35",_target(mixed))
	_check(mixed.ok and _events(mixed,"RX-P03-09") == 1, "three negative types already in snapshot grants +4")


func _test_partners() -> void:
	var deck := ["R3-P04-01","R3-P04-02","R3-P04-06","R3-P04-15","R3-P04-04","R3-P04-08","R3-P04-11","R3-P04-28"]
	for encounter in ["N01", "Q01", "FY_B1"]:
		var step := _battle("P04", ["RX-P04-01","RX-P04-06","RX-P04-08"], deck, encounter)
		if not step.ok:
			continue
		step.data.state.player.focus = 9
		var exam: bool = encounter != "N01"
		var recruited := _play(step,"R3-P04-01",_target(step) if exam else "")
		if not recruited.ok:
			continue
		_check(_events(recruited,"RX-P04-01") == 1 and recruited.data.state.units.size() == (0 if exam else 1), "cooperation first actual result " + encounter)
		var target := _target(recruited) if exam else str(recruited.data.state.units[0].unit_id)
		var coordination := _play(recruited,"R3-P04-06",target)
		if not coordination.ok:
			continue
		_check(_events(coordination,"RX-P04-08") == 1 and int(coordination.data.state.v3.synergy) == 0, "extra partner action or real paid substitute " + encounter)
		var rest := _play(coordination,"R3-P04-15","" if exam else target)
		_check(rest.ok and _events(rest,"RX-P04-06") >= 1 and rest.data.state.units.is_empty(), "manual rest vs exam substitute " + encounter)
	var solo := _battle("P04",["RX-P04-11"],deck)
	solo = _play(solo,"R3-P04-28",_target(solo))
	_check(solo.ok and _events(solo,"RX-P04-11") == 1, "solo work bonus")
	var gone := _battle("P04",["RX-P04-08"],deck)
	gone = _play(gone,"R3-P04-01")
	if gone.ok:
		gone.data.state.units[0].vitality = 1
		gone = _play(gone,"R3-P04-06",str(gone.data.state.units[0].unit_id))
		_check(gone.ok and gone.data.state.units.is_empty() and _events(gone,"RX-P04-08") == 0, "stopwatch cannot revive a departed partner")


func _test_run() -> void:
	for character in ["P01","P02","P03","P04"]:
		var created := _service.create(StartRunRequest.new(character,&"normal",RelicPilot.MANIFEST,"314"))
		if not _ok(created, "campaign setup " + character):
			continue
		var run: RunState = created.data.state
		_check(run.relics.is_empty(), "no startup relic in pilot")
		for year in range(1,5):
			run.term = year
			_check(CampaignService.relic_layers(run) == ([3,9] if year < 3 else [4,11]), "pilot uses plan layer schedule")
			for seed in 18:
				var rng := RandomSource.new(str(seed))
				var before := rng.export_state().to_dictionary()
				var picked := RelicPilot.candidates(run,_catalog,rng)
				if not _ok(picked,"weighted frozen sample"):
					continue
				_check(picked.data.size() == 3 and picked.data[0].begins_with("RX-C") and picked.data[1].begins_with("RX-"+character+"-") and picked.data[2] not in picked.data.slice(0,2), "ordered pool, uniqueness and ownership")
				var after := rng.export_state().to_dictionary()
				for stream in ["map","event","battle"]:
					_check(after.streams[stream] == before.streams[stream], "relic offer touches reward RNG only")
				var same := RelicPilot.candidates(run,_catalog,RandomSource.new(str(seed)))
				_check(same.ok and same.data == picked.data, "deterministic candidate sample")
				_check(picked.data.all(func(id): return RelicPilot.is_candidate(_catalog.get_definition("relic",id).data,character,year)), "year-weight legality")
	_test_run_flow()


func _apply(run: RunState, type: StringName, payload: Dictionary, rng: Dictionary) -> GameResult:
	var result := _service.apply(run, GameAction.new(type,payload),rng)
	_ok(result, "run command " + String(type))
	return result


func _test_run_flow(manifest: String = RelicPilot.MANIFEST) -> void:
	var started := _service.create(StartRunRequest.new("P03",&"normal",manifest,"42"))
	if not started.ok:
		return
	var run: RunState = started.data.state
	var rng: Dictionary = started.data.rng_states
	var transaction := TransactionResolver.new(_catalog)
	transaction.add_relic(run,"RX-C26","",0)
	transaction.add_relic(run,"RX-C28","",1)
	transaction.add_relic(run,"RX-C01","",2)
	# The path is a controlled programmatic playthrough: battles are settled as wins.
	var offers := 0
	var grands := 0
	var rests := 0
	var skips := 0
	for i in 400:
		if not run.outcome.is_empty():
			break
		var pending: Dictionary = run.campaign.pending
		var current := run.find_node(run.current_node_id)
		var next: GameResult
		if not pending.is_empty():
			var payload := {"offer_id":pending.offer_id,"option_id":"skip"}
			match pending.kind:
				"direction": payload.option_id = "theory"
				"destination": payload.option_id = "research"
				"grand":
					grands += 1
					payload.option_id = "resources"
				"relic":
					offers += 1
					if offers == 1:
						_test_frozen_offer(run,rng)
					_check(current.layer in CampaignService.relic_layers(run), "offer at true planned layer")
				"service": pass
			next = _apply(run,&"choose_campaign",payload,rng)
			if next.ok and pending.kind == "relic":
				_check(next.data.state.money == run.money + 20, "existing abandon conversion +20")
				_check(not _service.apply(next.data.state,GameAction.new(&"choose_campaign",payload),next.data.rng_states).ok, "offer cannot be reused")
		elif not run.active_battle_id.is_empty():
			next = _service.settle_battle(run,{"battle_id":run.active_battle_id,"result":"won","remaining_vitality":20},rng)
		elif current != null and current.status == "active":
			if run.pending_reward != null and not run.pending_reward.is_complete():
				var item: Dictionary = run.pending_reward.items[0]
				var payload := {"offer_id":run.pending_reward.offer_id,"item_id":item.item_id}
				var expected_bonus := 8 if skips < 3 else 0
				_check(int(_service.make_view(run).pending_reward.items[0].get("rx_skip_bonus", 0)) == expected_bonus, "skip display quotes actual remaining eligibility")
				if skips == 0:
					var none := run.copy_for_write()
					none.pending_reward.items[0].candidates = []
					var empty := _service.apply(none, GameAction.new(&"skip_reward", payload), rng)
					_check(empty.ok and _events(empty, "RX-C28") == 0 and empty.data.state.money == none.money, "empty reward does not pay or consume a charge")
				next = _apply(run,&"skip_reward",payload,rng)
				if next.ok:
					var triggered := _events(next,"RX-C28")
					if skips < 3:
						_check(triggered == 1 and next.data.state.money == run.money + 8,"legal skip pays +8 once")
					else:
						_check(triggered == 0 and next.data.state.money == run.money,"skip cap exhausted")
					skips += 1
			elif current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				var event: EventState = current.context.event
				next = _apply(run,&"choose_event",{"event_instance_id":event.event_instance_id,"option_id":"leave"},rng)
			elif current.kind == "rest" and not current.context.get("used", false):
				var was_missing := run.vitality < run.max_vitality - 22
				var rest_draft := {"node_id":current.node_id,"option_id":"heal"}
				if rests == 0 and was_missing:
					var full := run.copy_for_write()
					full.vitality = full.max_vitality
					var skipped := _service.apply(full, GameAction.new(&"take_rest", rest_draft),rng)
					_check(skipped.ok and _events(skipped, "RX-C26") == 0 and skipped.data.state.campaign.rx_uses == full.campaign.rx_uses, "a full-health rest consumes no charge")
					var partial := run.copy_for_write()
					var base := int(floor(partial.max_vitality * int(_catalog.get_definition("ruleset", partial.ruleset_id).data.run.rest_heal_percent) / 100.0))
					partial.vitality = partial.max_vitality - base - 2
					var quote: Dictionary = _service.make_view(partial).rest
					var clipped := _service.apply(partial, GameAction.new(&"take_rest", rest_draft), rng)
					_check(quote.get("rx_heal_bonus") == 2 and clipped.ok and _events(clipped,"RX-C26") == 1 and _record(clipped,"RX-C26","rest_heal").get("amount") == 2 and clipped.data.state.vitality == partial.max_vitality, "partial overheal is capped and stated exactly")
				next = _apply(run,&"take_rest",rest_draft,rng)
				if next.ok:
					var triggered := _events(next,"RX-C26")
					if was_missing and rests < 2:
						_check(triggered == 1,"ordinary actual heal bonus")
					rests += triggered
			else:
				next = _apply(run,&"leave_node",{"node_id":current.node_id},rng)
		else:
			var reachable := run.reachable_node_ids()
			if not _check(not reachable.is_empty(), "annual route continues"):
				break
			var chosen: String = reachable.front()
			for id in reachable:
				if CampaignProgression.metadata(run,id).get("subtype") == "R":
					chosen = id
					break
			next = _apply(run,&"enter_node",{"node_id":chosen},rng)
		if not _ok(next,"controlled annual route advances"):
			break
		run = next.data.state
		rng = next.data.rng_states
	_check(offers == 8 and grands == 4 and run.outcome == "won", "8 relics and 4 unchanged grand rewards over four years; scripted settlement")
	_check(run.campaign.rx_uses == {"RX-C26":2,"RX-C28":3}, "run caps are saved independently of slot")
	print("RX_STAGED_YEARS=offers:%d; grand:%d; skips:%d; rest_procs:%d" % [offers, grands, skips, rests])


func _test_frozen_offer(run: RunState, rng: Dictionary) -> void:
	var before := run.to_dictionary()
	var pending: Dictionary = run.campaign.pending
	var candidate := str(pending.candidates[1])
	var replacing := str(run.relics[0].relic_id)
	var converted := _service.apply(run, GameAction.new(&"choose_campaign", {"offer_id":pending.offer_id,"option_id":"convert","candidate_id":candidate}),rng)
	_check(converted.ok and converted.data.state.money == run.money + 30 and converted.data.state.relics == run.relics and converted.data.rng_states == rng, "an unowned frozen relic converts to exactly +30 at full slots")
	var duplicate := run.copy_for_write()
	duplicate.relics[2].definition_id = candidate
	var repeated := _service.apply(duplicate, GameAction.new(&"choose_campaign", {"offer_id":pending.offer_id,"option_id":"claim","candidate_id":candidate}),rng)
	_check(repeated.ok and repeated.data.state.money == run.money + 25 and repeated.data.state.relics == duplicate.relics and repeated.data.rng_states == rng, "a frozen owned relic converts to exactly +25")
	var draft := {"offer_id":pending.offer_id,"option_id":"claim","candidate_id":candidate,"replace_relic_id":replacing}
	_service.preview(run,ActionDraft.new(&"choose_campaign",draft))
	_check(run.to_dictionary() == before,"replacement preview keeps frozen run unchanged")
	var session_state := SessionState.new()
	session_state.run = run
	session_state.random_snapshot = rng
	var snapshot := SnapshotCodec.encode_session(session_state,_catalog.get_info())
	if not _ok(snapshot,"encode stable frozen pilot offer"):
		return
	var store := SaveStore.new("user://rx-pilot-suite-%d" % OS.get_process_id())
	if not _ok(store.save("current_run",snapshot.data),"isolated save write"):
		return
	var session := GameSession.new(store,Callable(),_catalog.get_info().id == RelicPilot.MANIFEST)
	if _ok(session.continue_run(),"public resume of frozen offer"):
		var view := session.get_view()
		_check(view.run.campaign_offer.candidates == pending.candidates,"resume keeps identical frozen order")
		var context := CommandContext.new(str(view.run_id),view.revision)
		var applied := session.submit(context,GameAction.new(&"choose_campaign",draft))
		_check(applied.accepted,"public replacement succeeds")
		_check(not session.submit(context,GameAction.new(&"choose_campaign",draft)).accepted,"stale command may not regrant")
		if applied.accepted:
			_check(applied.view.run.campaign.rx_uses == run.campaign.rx_uses,"changing slot cannot reset per-run charges")
			_check(applied.view.run.relics[0].definition_id == candidate and int(applied.view.run.relics[0].slot) == 0 and applied.view.run.money == run.money, "replacement does not convert, preserves slot index")
	session.free()
	var altered := before.duplicate(true)
	altered.campaign.pending.candidates[1] = "RX-P01-01"
	_check(not RunCodec.decode(altered,_catalog).ok,"codec rejects foreign owner")
	altered = before.duplicate(true)
	altered.campaign.pending.candidates[1] = altered.campaign.pending.candidates[0]
	_check(not RunCodec.decode(altered,_catalog).ok,"codec rejects duplicate")
	altered = before.duplicate(true)
	altered.campaign.rx_uses["RX-C26"] = 3
	_check(not RunCodec.decode(altered,_catalog).ok,"codec rejects bad persistent counter")


func _test_test_room() -> void:
	var test := TestRoomService.new(TestStore.new("user://rx-test-room-%d" % OS.get_process_id()),Callable(),RelicPilot.MANIFEST)
	_check(not test.start({"character_id":"P01","relics":["RX-P02-01"],"seed":"42"}).ok,"test room rejects another character's relic")
	_check(not test.start({"character_id":"P01","relics":["RX-C01","RX-C01"],"seed":"42"}).ok,"test room rejects duplicate")
	if _ok(test.start({"character_id":"P01","encounter_id":"N01","relics":["RX-C01","RX-C02"],"seed":"42"}),"real pilot test room starts"):
		_check(test.state.battle.relics == ["RX-C01","RX-C02"] and test.state.battle.player.relax == 4,"test room entry executes first relic")


# One fixed seed and policy per build. Useful for regressions, not a win-rate estimate.
func _test_battle_matrix() -> void:
	var builds := {
		"P01": {"relics":["RX-C01","RX-P01-01","RX-C02"],"deck":["R3-P01-04","R3-P01-11","R3-P01-02","R3-P01-03","R3-P01-05","R3-P01-02"]},
		"P02": {"relics":["RX-P02-01","RX-P02-07","RX-P02-02"],"deck":["R3-P02-01","R3-P02-11","R3-P02-12","R3-P02-20","R3-C-01","R3-P02-11"]},
		"P03": {"relics":["RX-P03-01","RX-P03-05","RX-P03-09"],"deck":["R3-P03-17","R3-P03-02","R3-P03-01","R3-P03-22","R3-P03-35","R3-P03-01"]},
		"P04": {"relics":["RX-P04-01","RX-P04-06","RX-P04-08"],"deck":["R3-P04-01","R3-P04-06","R3-P04-02","R3-P04-15","R3-P04-28","R3-P04-28"]},
	}
	var rows: Array[Dictionary] = []
	for character: String in builds:
		var build: Dictionary = builds[character]
		var deck: Array = build.deck + ["R3-C-01","R3-C-01","R3-C-02","R3-C-02","R3-C-05","R3-C-04"]
		var priority: Array = ["R3-P02-01", "R3-T201"] + build.deck if character == "P02" else build.deck
		for encounter: String in ["N01", "E03", "N15", "FY_B1", "Q01"]:
			var dealt: Array = []
			var rng := {}
			for slots: int in [0, 1, 3]:
				var step := _battle(character, build.relics.slice(0, slots), deck, encounter, false)
				if not step.ok:
					continue
				var battle_start: BattleState = step.data.state
				var hand: Array = battle_start.zones.hand.map(func(id): return battle_start.card_by_id[id].origin_card_id)
				if slots == 0:
					dealt = hand
					rng = step.data.rng_state.duplicate(true)
				else:
					_check(hand == dealt and step.data.rng_state == rng, "matrix same seed, initial deck instances and streams")
				var effects := {}
				var triggers := 0
				var commands := 0
				while step.ok:
					for event: RuleEvent in step.data.events:
						if event.type == &"relic_triggered" and event.source_id in RelicPilot.IDS:
							var key := "%s/%s" % [event.source_id, event.data.at]
							effects[key] = int(effects.get(key, 0)) + int(event.data.amount)
							triggers += 1
					if step.data.outcome != null or commands >= 220:
						break
					var command := _matrix_command(step.data, priority)
					step = _engine.apply(step.data.state, command, step.data.rng_state)
					commands += 1
				if not _ok(step, "matrix legal commands %s %s %d" % [character, encounter, slots]):
					continue
				if not _check(step.data.outcome != null, "matrix reaches actual terminal battle state"):
					continue
				var battle: BattleState = step.data.state
				_check(slots > 0 or triggers == 0, "no new relic events with an empty loadout")
				rows.append({"character":character,"encounter":encounter,"slots":slots,"seed":"415",
					"result":step.data.outcome,"round":battle.round_index,"ddl_left":battle.ddl,
					"vitality_delta":int(battle.player.vitality) - 72,"commands":commands,"trigger_count":triggers,"bonus_totals":effects})
	_check(rows.size() == 60, "all 20 same-seed 0/1/3 sets reached a natural battle result")
	print("RX_BATTLE_MATRIX=" + JSON.stringify(rows))


func _matrix_command(step: BattleStep, priority: Array) -> ActionDraft:
	if step.pending_choice is Dictionary:
		var decision: Dictionary = step.pending_choice
		var selected: Array[String] = []
		for index in mini(int(decision.get("min_count", 0)), decision.candidates.size()):
			selected.append(str(decision.candidates[index].id))
		return ActionDraft.new(&"confirm_choice", {"choice_id":decision.choice_id,"selected_ids":selected})
	var hand: Array = step.state.zones.hand.duplicate()
	var rank := priority + ["R3-C-01", "R3-C-05", "R3-C-04", "R3-C-02"]
	hand.sort_custom(func(a, b):
		var left := rank.find(step.state.card_by_id[a].definition_id)
		var right := rank.find(step.state.card_by_id[b].definition_id)
		if left == right:
			return str(step.state.card_by_id[a].origin_card_id) < str(step.state.card_by_id[b].origin_card_id)
		return (left if left >= 0 else rank.size()) < (right if right >= 0 else rank.size()))
	for instance: String in hand:
		var play := ActionDraft.new(&"play_card", {"card_instance_id":instance,"target_ids":[]})
		var quote := _engine.preview(step.state, play)
		if not quote.ok:
			continue
		if quote.data.can_submit:
			return play
		for selection: Dictionary in quote.data.required_selections:
			if selection.candidates.is_empty():
				continue
			var id := str(selection.candidates[0].id)
			var payload := {"card_instance_id":instance,"target_ids":[]}
			if selection.field == "target_ids":
				payload.target_ids = [id]
			elif selection.field == "replace_unit_id":
				payload.replace_unit_id = id
			var targeted := ActionDraft.new(&"play_card", payload)
			var verdict := _engine.preview(step.state, targeted)
			if verdict.ok and verdict.data.can_submit:
				return targeted
	return ActionDraft.new(&"end_turn")
