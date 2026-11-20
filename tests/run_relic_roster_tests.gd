extends "res://tests/run_relic_pilot_tests.gd"
## Real engine and transaction commands against controlled contexts. Not a balance simulation.

const ID := RelicPilot.ROSTER
const W := "R3-C-01"
const S := "R3-C-02"


func _run() -> void:
	if not _ok(_catalog.load(ID), "load full roster"):
		_finish()
		return
	_engine = BattleEngine.new(_catalog)
	_service = RunService.new(_catalog)
	_verify_roster()
	_test_prepare()
	_test_work()
	_test_lin()
	_test_paper()
	_test_debuffs()
	_test_partners()
	_common_prepare()
	_common_plays()
	_common_pressure()
	_lin_added()
	_paper_added()
	_debuff_added()
	_partner_added()
	_slot_order_caps()
	_economy()
	_annual_route()
	var missing: Array[String] = []
	for id in _catalog.get_candidates({"kind":"relic"}):
		if RelicPilot.is_rx(id) and not _receipts.has(id): missing.append(id)
	print("RX_ROSTER_UNOBSERVED=" + JSON.stringify(missing))
	_check(missing.is_empty(), "every RX emits a receipt in its real rule path")
	_finish()


func _finish() -> void:
	print("RX_ROSTER_CHECKS=%d FAILURES=%d UNIQUE_TRIGGERED=%d" % [_checks, _failures.size(), _receipts.size()])
	print("RX_ROSTER_EVENTS=" + JSON.stringify(_receipts, "", true))
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _verify_roster() -> void:
	var base := ContentDB.new("res://data/four_year")
	var pilot := ContentDB.new("res://data/four_year")
	if not _ok(base.load(RelicPilot.BASE), "historical four-year catalog loads for verification") or not _ok(pilot.load(RelicPilot.MANIFEST), "RX-only pilot loads"):
		return
	var ids := _catalog.get_candidates({"kind":"relic"})
	_check(ids.size() == 104 and ids.all(RelicPilot.is_rx) and base.get_candidates({"kind":"relic"}).size() == 16 and pilot.get_candidates({"kind":"relic"}).size() == 24,"only RX live, separate historical decode catalog")
	for id in base.get_candidates({"kind":"relic"}):
		_check(not _catalog.get_definition("relic",id).ok and not pilot.get_definition("relic",id).ok, "retired relic disabled " + id)
	for id in RelicPilot.IDS:
		_check(pilot.get_definition("relic",id).data == _catalog.get_definition("relic",id).data, "pilot mechanics unchanged " + id)
	var encyclopedia := CompendiumView.build(_catalog)
	_check(encyclopedia.ok and encyclopedia.data.relics.size() == 104, "all definitions on compendium tab")
	for entry in encyclopedia.data.relics:
		_check(not entry.terms.is_empty() and UiStyle.texture(entry.id) != null, "source and art present " + entry.id)
	var room := TestRoomService.new()
	var room_ids: Array = room.options().get("relics", []).map(func(row): return row.id)
	_check(room_ids.size() == 104 and room_ids.all(RelicPilot.is_rx), "normal test room uses all and only RX")
	_check(not room.start({"character_id":"P01","seed":"42","relics":["FY_Y1_1"]}).ok, "retired relic cannot be pre-equipped in test room")
	var old_engine := BattleEngine.new(base)
	var inputs := {"battle_id":"same", "encounter_id":"NR2", "character_id":"P02", "relics":[],
		"cards":[{"card_id":"stable","definition_id":W,"upgrade_level":0}], "rng_state":RandomSource.new("42").export_state().to_dictionary()}
	var older := old_engine.begin(inputs)
	var roster := _engine.begin(inputs)
	_check(older.ok and roster.ok and older.data.state.to_dictionary() == roster.data.state.to_dictionary() and older.data.rng_state == roster.data.rng_state, "unequipped battle A/B matches old state and RNG")
	for character in ["P01","P02","P03","P04"]:
		var created := _service.create(StartRunRequest.new(character,&"normal",ID,"42"))
		var old := RunService.new(base).create(StartRunRequest.new(character,&"normal",RelicPilot.BASE,"42"))
		if not _ok(created,"roster start") or not _ok(old,"old start"): continue
		var run: RunState = created.data.state
		_check(run.relics.is_empty() and run.campaign.years == old.data.state.campaign.years and created.data.rng_states == old.data.rng_states, "same seed retains annual map and RNG " + character)
		var sampled := {}
		for year in range(1,5):
			run.term = year
			# Treat missing final year paths as no exam; the route test below uses actual map gates.
			for n in range(24):
				var rng := RandomSource.new(str(n))
				var before := rng.export_state().to_dictionary()
				var offer := RelicPilot.candidates(run,_catalog,rng)
				if not _ok(offer,"three-way full offer"): continue
				var gold := 0
				for id in offer.data:
					var d: Dictionary = _catalog.get_definition("relic",id).data
					gold += int(d.rarity == "gold")
					_check(RelicPilot.is_rx(id) and RelicPilot.is_candidate(d,character,year,true), "RX year / owner safe " + id)
					sampled[id] = true
				_check(offer.data.size() == 3 and offer.data.reduce(func(unique: Dictionary, id): unique[id] = true; return unique, {}).size() == 3 and gold <= 1, "unique offer + maximum one gold")
				var after := rng.export_state().to_dictionary()
				_check(["battle","map","event"].all(func(key): return before.streams[key] == after.streams[key]), "reward stream only")
		_check(sampled.size() >= 25, "expanded pool sampled " + character)


func _expect(step: GameResult, id: String, amount: int, at: String = "") -> bool:
	if not _check(step != null and step.ok, "receipt step succeeds " + id): return false
	var actual := 0
	for e: RuleEvent in step.data.events:
		if e.type == &"relic_triggered" and e.source_id == id and (at.is_empty() or e.data.at == at):
			actual += int(e.data.amount)
			_check(e.data.relic_id == id and int(e.data.remaining) >= 0,"receipt identity/remaining " + id)
			_receipts[id] = e.data.duplicate(true)
	return _check(actual == amount,"%s %s amount %s, expected %s" % [id,at,actual,amount])


func _choice(step: GameResult, pick_first: bool = true) -> GameResult:
	if not step.ok or step.data.pending_choice == null: return step
	var pending: Dictionary = step.data.pending_choice
	var ids := []
	var need := maxi(int(pending.min_count), int(pick_first and not pending.candidates.is_empty()))
	for n in need: ids.append(str(pending.candidates[n].id))
	var confirmed := _engine.apply(step.data.state,ActionDraft.new(&"confirm_choice",{"choice_id":pending.choice_id,"selected_ids":ids}),step.data.rng_state)
	_ok(confirmed,"confirm real " + str(pending.kind))
	return confirmed


func _high(step: GameResult) -> GameResult:
	if step.ok:
		step.data.state.player.focus = 10
		step.data.state.ddl = 40
	return step


func _ready(step: GameResult) -> GameResult:
	if step.ok: step.data.state.player.focus = 10
	return step


func _common_prepare() -> void:
	var step := _high(_battle("P01",["RX-C04","RX-C06","RX-C08"],[S]))
	step = _play(step,S)
	step = _end(step)
	_expect(step,"RX-C06",1,"carry_focus")
	_expect(step,"RX-C08",2,"roster_draw")
	step = _end(step)
	_expect(step,"RX-C04",4,"set_round")
	_expect(step,"RX-C06",1,"carry_focus")
	step = _end(step)
	_expect(step,"RX-C06",0)
	_expect(step,"RX-C04",0)
	_expect(_end(step),"RX-C04",4,"set_round")
	var clock := _battle("P01",["RX-C33","RX-C34","RX-C36"])
	_expect(clock,"RX-C33",1,"overnight")
	_expect(clock,"RX-C34",1,"limited_pages")
	_expect(clock,"RX-C36",1,"sealed_draft")
	_check(clock.data.state.zones.exhaust.size() == 1 and clock.data.state.player.vitality == 70, "draft exhaust and vitality cost are actual")
	clock = _end(clock)
	_expect(clock,"RX-C34",1,"extra_pages")
	_expect(clock,"RX-C34",2,"roster_draw")
	var loads := _battle("P01",["RX-C16"],["X03","X03","X03","X03","X03","X03","X03","X03","X03","X03","X03","X03"])
	_expect(loads,"RX-C16",4,"burden_drawn")
	var shade := _battle("P04",["RX-C22"],[],"FY_B2")
	_expect(shade,"RX-C22",7,"exam_prepare")
	var recycle := _battle("P01",["RX-C07","RX-C18"])
	var st: BattleState = recycle.data.state
	st.zones.discard.append_array(st.zones.draw)
	st.zones.draw.clear()
	_stack(recycle,"anxiety",1,str(st.player.entity_id))
	var next := _end(recycle)
	_expect(next,"RX-C07",4,"reshuffle_done")
	_expect(next,"RX-C18",3,"anxiety")
	_expect(next,"RX-C18",1,"roster_draw")
	_check(next.data.state.player.focus == 2, "anxiety still lowers natural focus")


func _common_plays() -> void:
	var mix := _high(_battle("P01",["RX-C03","RX-C10","RX-C13"],[W,W,S,"R3-P01-10","R3-P01-39"]))
	mix = _play(mix,S)
	mix = _choice(_play(mix,W,_target(mix)))
	mix = _play(mix,"R3-P01-10")
	_expect(mix,"RX-C03",2,"roster_draw")
	mix = _choice(_play(mix,W,_target(mix)))
	_expect(mix,"RX-C13",2,"work_primary_segment")
	mix = _play(mix,"R3-P01-39")
	_expect(mix,"RX-C10",3,"late_free_card")
	var disc := _high(_battle("P01",["RX-C11","RX-C12","RX-C15"],["R3-C-03","R3-P01-10","R3-C-11"]))
	disc = _play(disc,"R3-C-03")
	_expect(disc,"RX-C11",0)
	disc = _choice(disc)
	_expect(disc,"RX-C11",1,"roster_draw")
	disc = _play(disc,"R3-P01-10")
	_expect(disc,"RX-C12",2,"self_exhaust")
	disc.data.state.tasks[0].shield = 7
	disc = _play(disc,"R3-C-11",_target(disc))
	_expect(disc,"RX-C15",3,"explicit_shield_break")
	var empty := _high(_battle("P01",["RX-C14","RX-P01-06"],["R3-P01-04","R3-P01-02"]))
	empty = _play(empty,"R3-P01-04")
	var state: BattleState = empty.data.state
	var work := _instance(state,"R3-P01-02")
	for instance in state.zones.hand.duplicate():
		if instance != work:
			state.zones.hand.erase(instance)
			state.zones.draw.append(instance)
	empty = _play(empty,"R3-P01-02",_target(empty))
	_check(empty.ok and empty.data.pending_choice != null, "empty-hand rule waits for actual passive choice")
	_expect(empty,"RX-C14",0)
	var no_refill := _choice(empty,true)
	_expect(no_refill,"RX-C14",0)
	var decline := _choice(empty,false)
	_expect(decline,"RX-P01-06",2,"roster_draw")
	_expect(decline,"RX-C14",0)
	var alone := _battle("P01",["RX-C14"],[W])
	state = alone.data.state
	work = _instance(state,W)
	for instance in state.zones.hand.duplicate():
		if instance != work:
			state.zones.hand.erase(instance)
			state.zones.draw.append(instance)
	_expect(_play(alone,W,_target(alone)),"RX-C14",1,"roster_draw")
	var strict := _high(_battle("P01",["RX-C35","RX-C37"],[S,W]))
	strict.data.state.ddl = 1
	strict = _play(strict,S)
	_expect(strict,"RX-C37",1,"cost_quote")
	var hold := _end(strict)
	_expect(hold,"RX-C35",1,"pause_ddl")
	_check(hold.data.state.ddl == 1,"native DDL pause retains one point")
	var work_turn := _play(hold,W,_target(hold))
	_expect(work_turn,"RX-C37",5,"work_primary_segment")
	_expect(_end(work_turn),"RX-C35",0)


func _common_pressure() -> void:
	var low := _battle("P01",["RX-C20","RX-C21","RX-C39"],[W])
	low.data.state.player.vitality = 6
	low.data.state.tasks[0].intent_snapshot["pressure"] = 20
	var saved := _end(low)
	_expect(saved,"RX-C39",1,"lethal_pressure_saved")
	_expect(saved,"RX-C20",4,"large_pressure")
	_check(saved.data.state.player.vitality == 1 and saved.data.outcome == null,"one lethal segment leaves one vitality")
	var blocked := _battle("P01",["RX-C21"])
	blocked.data.state.player.relax = 30
	blocked.data.state.tasks[0].intent_snapshot["pressure"] = 6
	blocked = _end(blocked)
	_expect(blocked,"RX-C21",2,"fully_blocked")
	var stage := _battle("P01",["RX-C24","RX-C19"],[W,W],"FY_B1")
	stage.data.state.tasks[0].work_remaining = 1
	stage = _play(stage,W,_target(stage))
	_check(stage.data.state.phase != "finished", "real multi-stage boss moves to another stage")
	stage = _end(stage)
	_expect(stage,"RX-C24",4,"delayed_prepare")
	var win := _battle("P01",["RX-C19"],[W])
	win.data.state.player.vitality = 24
	win.data.state.tasks[0].work_remaining = 1
	win = _play(win,W,_target(win))
	_expect(win,"RX-C19",3,"won_low_vitality")
	_check(win.data.state.player.vitality == 27,"actual victory heal incl. run handoff")


func _lin_added() -> void:
	var lin := _high(_battle("P01",["RX-P01-02","RX-P01-03","RX-P01-04"],[S,S,W,W]))
	lin.data.state.tasks[0].shield = 70
	lin = _play(lin,S)
	lin = _play(lin,W,_target(lin))
	_expect(lin,"RX-P01-04",1,"linked_shield_armed")
	lin = _choice(lin)
	lin = _play(lin,S)
	_expect(lin,"RX-P01-02",3,"paid_work_strategy")
	lin = _choice(_play(lin,W,_target(lin)))
	_expect(lin,"RX-P01-03",2,"roster_draw")
	_expect(lin,"RX-P01-04",4,"linked_strip")
	var replay := _high(_battle("P01",["RX-P01-07","RX-P01-08"],["R3-P01-07","R3-P01-02","R3-P01-29"]))
	replay = _play(replay,"R3-P01-07")
	replay = _choice(_play(replay,"R3-P01-02",_target(replay)))
	replay = _play(replay,"R3-P01-07")
	_expect(replay,"RX-P01-07",1,"replayed_retrieved")
	# Keep the same instance; the second legal recall is via authored card text.
	replay = _ready(_choice(_play(replay,"R3-P01-29")))
	replay = _play(replay,"R3-P01-07")
	_expect(replay,"RX-P01-08",5,"third_instance_play")
	var heavy := _high(_battle("P01",["RX-P01-10","RX-P01-11","RX-P01-12"],[S,S,"R3-P01-09","R3-P01-23"]))
	heavy = _play(heavy,S)
	heavy = _play(heavy,S)
	heavy = _play(heavy,"R3-P01-09",_target(heavy))
	_expect(heavy,"RX-P01-10",1,"cost_quote")
	_expect(heavy,"RX-P01-12",10,"work_primary_segment")
	heavy = _choice(heavy)
	heavy = _play(heavy,"R3-P01-23",_target(heavy))
	_expect(heavy,"RX-P01-11",0)
	heavy = _end(heavy)
	_expect(heavy,"RX-P01-12",1,"construction_cost")
	heavy = _play(heavy,"R3-P01-23",_target(heavy))
	_expect(heavy,"RX-P01-11",5,"two_paid_rounds")
	var paths := _high(_battle("P01",["RX-P01-13","RX-P01-14","RX-P01-16"],[S,W,"R3-P01-10"]))
	paths = _play(paths,W,_target(paths))
	paths = _play(paths,S)
	_expect(paths,"RX-P01-14",1,"cost_quote")
	paths = _play(paths,"R3-P01-10")
	_expect(paths,"RX-P01-13",6,"broken_link")
	_expect(_end(paths),"RX-P01-16",7,"roster_completion")
	var search := _high(_battle("P01",["RX-P01-15"],[S,W]))
	var inst := _instance(search.data.state,W)
	if search.data.state.zones.hand.has(inst):
		search.data.state.zones.hand.erase(inst)
		search.data.state.zones.draw.push_front(inst)
	_expect(_play(search,S),"RX-P01-15",1,"strategy_without_work")


func _paper_added() -> void:
	var cites := _high(_battle("P02",["RX-P02-03","RX-P02-04","RX-P02-16"],["R3-P02-01","R3-P02-06","R3-P02-07","R3-P02-08"]))
	cites = _play(cites,"R3-P02-01")
	cites.data.state.v3.paper.citations = 2
	cites = _play(cites,"R3-P02-06")
	_expect(cites,"RX-P02-03",1,"paid_citation")
	cites = _play(cites,"R3-P02-07")
	_expect(cites,"RX-P02-16",4,"empty_shelf")
	cites = _play(cites,"R3-P02-08")
	_expect(cites,"RX-P02-04",5,"three_names")
	var seminar := _high(_battle("P02",["RX-P02-05","RX-P02-09","RX-P02-11"],["R3-P02-01","R3-P02-11","R3-P02-20"]))
	seminar = _play(seminar,"R3-P02-01")
	seminar = _play(seminar,"R3-P02-11")
	seminar.data.state.v3.paper.modifier = 90
	seminar = _play(seminar,"R3-P02-20")
	_expect(seminar,"RX-P02-11",5)
	_expect(seminar,"RX-P02-09",0)
	seminar = _end(seminar)
	_expect(seminar,"RX-P02-05",6,"review_ready")
	_expect(seminar,"RX-P02-09",4,"roster_completion")
	var binding := _high(_battle("P02",["RX-P02-08","RX-P02-10","RX-P02-12"],["R3-P02-01","R3-P02-11","R3-P02-12","R3-P02-13"]))
	for id in ["R3-P02-01","R3-P02-11","R3-P02-12","R3-P02-13"]:
		binding = _play(binding,id)
	binding = _end(binding)
	_expect(binding,"RX-P02-08",1,"roster_draw")
	_expect(binding,"RX-P02-10",3,"second_chapter_slot")
	_expect(binding,"RX-P02-10",3,"roster_completion")
	_expect(binding,"RX-P02-12",1,"bound_spine")
	binding = _end(binding)
	_expect(binding,"RX-P02-12",1,"bound_spine_focus")
	_expect(binding,"RX-P02-12",5,"roster_completion")
	var publish := _high(_battle("P02",["RX-P02-06","RX-P02-13","RX-P02-14"],["R3-P02-01","R3-P02-11","R3-P02-12","R3-P02-21"],"NR2",true,["N01","N02"]))
	for id in ["R3-P02-01","R3-P02-11","R3-P02-12"]:
		publish = _play(publish,id)
	publish = _choice(_play(publish,"R3-P02-21"))
	_expect(publish,"RX-P02-14",5,"topic_reset")
	publish.data.state.v3.paper.modifier = 70
	publish.data.state.v3.paper.progress = 0
	publish.data.state.v3.paper.citations = 0
	publish = _play(publish,"R3-T201")
	_expect(publish,"RX-P02-06",1,"cost_quote")
	_expect(publish,"RX-P02-13",2,"roster_draw")
	_check(publish.data.state.tasks[0].work_remaining == 927 and publish.data.state.tasks[1].work_remaining == 972, "publication penalty subtracts eight from main and secondary without changing C")


func _debuff_added() -> void:
	var erosion := _high(_battle("P03",["RX-P03-02","RX-P03-03","RX-P03-04"],[],"NR2",true,["N01","N02"]))
	_stack(erosion,"erosion",6)
	_stack(erosion,"erosion",1,str(erosion.data.state.tasks[1].task_id))
	erosion = _end(erosion)
	_expect(erosion,"RX-P03-04",6,"roster_completion")
	_expect(erosion,"RX-P03-02",2,"natural_erosion")
	_expect(erosion,"RX-P03-03",5,"delayed_prepare")
	var triggered := _high(_battle("P03",["RX-P03-06","RX-P03-07","RX-P03-08"],[S,S,S,S],"NR2",true,["N01","N02"]))
	var first := _target(triggered)
	var second: String = triggered.data.state.tasks[1].task_id
	_stack(triggered,"induced",1,first)
	_stack(triggered,"induced",1,second)
	triggered.data.state.tasks.reverse()
	for i in range(4):
		triggered = _play(triggered,S)
		if i == 0: _expect(triggered,"RX-P03-08",4)
		if i == 2: _expect(triggered,"RX-P03-06",4,"third_induced")
		if i == 3:
			_expect(triggered,"RX-P03-07",4,"fourth_induced")
			var targets: Array = triggered.data.events.filter(func(e): return e.type == &"relic_triggered" and e.source_id == "RX-P03-07")
			_check(targets.size() == 1 and targets[0].target_ids == [first],"fourth induced bonus chooses creation order, not array order")
	var debuff := _high(_battle("P03",["RX-P03-10","RX-P03-11","RX-P03-13"],["R3-P03-26","R3-P03-21"]))
	debuff = _play(debuff,"R3-P03-26",_target(debuff))
	_expect(debuff,"RX-P03-11",5)
	_expect(debuff,"RX-P03-13",4,"two_new_debuffs")
	debuff = _play(debuff,"R3-P03-21",_target(debuff))
	for i in range(3):
		_stack(debuff,"weakness",1)
		_stack(debuff,"feebleness",1)
		debuff.data.state.tasks[0].intent_snapshot.pressure = 16
		debuff = _end(debuff)
		_expect(debuff,"RX-P03-10",3 if i < 2 else 0,"mixed_pressure")
	var staged := _high(_battle("P03",["RX-P03-12","RX-P03-14","RX-P03-15"],["R3-P03-29","R3-P03-02","R3-P03-02",S],"FY_B1"))
	for status in ["weakness","brittle","induced"]: _stack(staged,status,1)
	staged = _play(staged,"R3-P03-02",_target(staged))
	_expect(staged,"RX-P03-15",0)
	staged = _play(staged,S)
	_expect(staged,"RX-P03-15",1,"prepared_induced")
	staged.data.state.tasks[0].work_remaining = 1
	var original := _target(staged)
	staged = _play(staged,"R3-P03-29",original)
	_expect(staged,"RX-P03-12",9,"work_primary_segment")
	_check(_target(staged) != original and staged.data.events.any(func(e): return e.type == &"task_advanced") and not staged.data.events.any(func(e): return e.type == &"status_removed" and e.source_id == "RX-P03-12"),"phase change never transfers the old weakness cost")
	staged = _end(staged)
	_expect(staged,"RX-P03-14",3,"delayed_prepare")
	staged = _play(staged,"R3-P03-02",_target(staged))
	_expect(staged,"RX-P03-14",1,"roster_draw")


func _partner_added() -> void:
	var party := _high(_battle("P04",["RX-P04-03","RX-P04-04","RX-P04-05"],["R3-P04-01","R3-P04-04"]))
	party = _play(party,"R3-P04-01")
	party = _play(party,"R3-P04-04")
	party = _end(party)
	_expect(party,"RX-P04-03",2,"regular_cooperation")
	_expect(party,"RX-P04-04",3,"two_partners")
	_expect(party,"RX-P04-05",6,"regular_cooperation")
	var swap := _high(_battle("P04",["RX-P04-02","RX-P04-07","RX-P04-10"],["R3-P04-01","R3-P04-04","R3-P04-08","R3-P04-21","R3-P04-16",W]))
	for id in ["R3-P04-01","R3-P04-04","R3-P04-08"]:
		swap = _play(_ready(swap),id)
	var old: Dictionary = swap.data.state.units[0]
	old.vitality = old.max_vitality - 1
	swap = _play(_ready(swap),"R3-P04-16",old.unit_id)
	_expect(swap,"RX-P04-07",2,"actual_partner_heal")
	swap = _play(swap,"R3-P04-21","",old.unit_id)
	swap = _play(swap,W,_target(swap))
	_expect(swap,"RX-P04-02",4,"work_primary_segment")
	_expect(_end(swap),"RX-P04-10",7,"regular_cooperation")
	var quiet := _high(_battle("P04",["RX-P04-09","RX-P04-15","RX-P04-16"],["R3-P04-01"]))
	_expect(quiet,"RX-P04-15",3,"solo_prepare")
	quiet = _play(quiet,"R3-P04-01")
	_expect(quiet,"RX-P04-15",2,"summon_cost")
	quiet.data.state.units[0].vitality = 1
	quiet.data.state.v3.synergy = 2
	quiet = _end(quiet)
	_expect(quiet,"RX-P04-16",3,"regular_cooperation")
	_expect(quiet,"RX-P04-09",4,"delayed_prepare")
	var exam := _high(_battle("P04",["RX-P04-12","RX-P04-13","RX-P04-14"],["R3-P04-40","R3-P04-06"],"Q01"))
	exam.data.state.v3.synergy = 4
	exam = _end(exam)
	_expect(exam,"RX-P04-13",1,"roster_draw")
	var other := _battle("P04",["RX-P04-14"],["R3-P04-40"],"NR2",true,["N01","N02"])
	var control := _battle("P04",[],["R3-P04-40"],"NR2",true,["N01","N02"])
	for ab in [other,control]: ab.data.state.v3.synergy = 2
	other = _play(other,"R3-P04-40",_target(other))
	control = _play(control,"R3-P04-40")
	_expect(other,"RX-P04-14",6,"work_primary_segment")
	_check(other.data.state.tasks[0].work_remaining == control.data.state.tasks[0].work_remaining - 6 and other.data.state.tasks[1].work_remaining == control.data.state.tasks[1].work_remaining and other.data.state.v3.synergy == 0,"submission shifts only designated main segment and pays all synergy")
	exam = _play(exam,"R3-P04-40",_target(exam))
	_expect(exam,"RX-P04-12",4,"exam_synergy")


func _slot_order_caps() -> void:
	for order in [["RX-C02","RX-C06","RX-C34"],["RX-C34","RX-C02","RX-C06"],["RX-C06","RX-C02","RX-C23"]]:
		var prep := _high(_battle("P01",order))
		if order.has("RX-C23"): prep.data.state.ddl = 3
		prep = _end(prep)
		_expect(prep,order[0],1,"carry_focus" if order[0] == "RX-C06" else ("extra_pages" if order[0] == "RX-C34" else "natural_focus"))
		_expect(prep,order[1],1,"carry_focus" if order[1] == "RX-C06" else "natural_focus")
		var last_at := "extra_pages" if order[2] == "RX-C34" else ("carry_focus" if order[2] == "RX-C06" else "natural_focus")
		_expect(prep,order[2],0,last_at)
		_check(prep.ok and prep.data.state.player.focus == 5,"base 3 + two actual RX focus gains across both groups")
		if order.has("RX-C34"): _expect(prep,"RX-C34",2,"roster_draw")
		if order.has("RX-C23"): _expect(prep,"RX-C23",1,"alarm_draw")
		if order[2] == "RX-C06":
			_check(BattleRelicPilot.used(prep.data.state,"RX-C06") == 0,"clipped carry gains no use")
			_expect(_end(prep),"RX-C06",1,"carry_focus")

	var heavy := "R3-P01-09"
	for order in [["RX-C09","RX-P01-09","RX-P01-12"],["RX-P01-12","RX-C09","RX-P01-09"]]:
		var work := _high(_battle("P01",order,[S,S,heavy]))
		work = _play(_play(work,S),S)
		work = _play(work,heavy,_target(work))
		var gold_first: bool = order[0] == "RX-P01-12"
		_expect(work,"RX-C09",0 if gold_first else 4,"work_primary_segment")
		_expect(work,"RX-P01-09",0 if gold_first else 5,"work_primary_segment")
		_expect(work,"RX-P01-12",10 if gold_first else 1,"work_primary_segment")
		_check(work.ok and BattleRelicPilot.used(work.data.state,"RX-C09") == (0 if gold_first else 1),"no first-actual use when a work bonus gets zero")
		_expect(_end(_choice(work)),"RX-P01-12",1,"construction_cost")

	for order in [["RX-P04-03","RX-P04-16","RX-P04-05"],["RX-P04-03","RX-P04-05","RX-P04-16"]]:
		var team := _high(_battle("P04",order,["R3-P04-01","R3-P04-04"]))
		team = _play(_play(team,"R3-P04-01"),"R3-P04-04")
		team.data.state.v3.synergy = 2
		var first: Dictionary = team.data.state.units[0]
		var second: Dictionary = team.data.state.units[1]
		var end := _end(team)
		var paired_first: bool = order[1] == "RX-P04-16"
		_expect(end,"RX-P04-03",2,"regular_cooperation")
		_expect(end,"RX-P04-16",3 if paired_first else 0,"regular_cooperation")
		_expect(end,"RX-P04-05",3 if paired_first else 6,"regular_cooperation")
		if not end.ok: continue
		var segments: Array = end.data.events.filter(func(e): return e.type == &"completion_applied" and e.source_id in [first.unit_id,second.unit_id])
		_check(segments.size() == 2 and segments[0].data.amount == int(first.cooperation) + 8 and segments[1].data.amount == int(second.cooperation),"cap belongs to the first qualifying partner only")
		var keep: Array = end.data.state.units.filter(func(unit): return unit.unit_id == first.unit_id)
		_check(keep.size() == 1 and int(keep[0].vitality) == int(first.vitality)-2,"clipped positive cooperation still pays its full extra vitality")
		_check(BattleRelicPilot.used(end.data.state,"RX-P04-16") == int(paired_first),"fully clipped cooperation is not marked as paid")

	var marks := _high(_battle("P03",["RX-C09","RX-P03-09","RX-P03-12"],["R3-P03-29"],"NR2",true,["N01","N02"]))
	for status in ["weakness","brittle","induced"]: _stack(marks,status,1)
	var other_task: Dictionary = marks.data.state.tasks[1]
	var marked_target := _target(marks)
	_stack(marks,"weakness",1,str(other_task.task_id))
	marks = _play(marks,"R3-P03-29",marked_target)
	_expect(marks,"RX-C09",4,"work_primary_segment")
	_expect(marks,"RX-P03-09",4,"work_primary_segment")
	_expect(marks,"RX-P03-12",2,"work_primary_segment")
	_check(marks.data.events.any(func(e): return e.type == &"status_removed" and e.source_id == "RX-P03-12" and Array(e.target_ids) == [marked_target]),"partially clipped gold removes weakness only on selected primary")
	_check(marks.data.state.statuses.any(func(st): return st.status_id == "weakness" and st.target_id == other_task.task_id),"another area target keeps its weakness")
	var free := _high(_battle("P03",["RX-P03-12"],["R3-P03-29"]))
	for status in ["weakness","brittle","induced"]: _stack(free,status,1)
	free.data.state.v3.pending_cost_discount = {"amount":10,"min_base_cost":2}
	free = _play(free,"R3-P03-29")
	_expect(free,"RX-P03-12",0,"work_primary_segment")
	_check(free.ok and free.data.state.player.focus == 10,"a zero-paid area work card does not request a primary just for the relic")


func _created(ids: Array) -> GameResult:
	var step := _service.create(StartRunRequest.new("P01",&"normal",ID,"42"))
	if not _ok(step,"new full roster run"): return step
	for i in ids.size(): _service.transactions().add_relic(step.data.state,ids[i],"",i)
	return step


func _place(run: RunState, kind: String, subtype: String = "", index: int = 0) -> RunNodeState:
	var choices := run.nodes.filter(func(n): return n.kind == kind and (subtype.is_empty() or CampaignProgression.metadata(run,n.node_id).get("subtype","") == subtype))
	if not _check(choices.size() > index,"annual map has fixture room " + kind + "/" + subtype): return null
	var node: RunNodeState = choices[index]
	run.current_node_id = node.node_id
	node.status = "active"
	run.pending_reward = null
	run.campaign.pending = {}
	return node


func _settle_fixture(run: RunState, rng: Dictionary, kind: String, index: int = 0) -> GameResult:
	var node := _place(run,kind,"",index)
	if node == null: return GameResult.failure(ApiError.new(&"fixture_missing","fixture_missing"))
	run.active_battle_id = node.node_id
	run.active_encounter_id = "N01"
	node.context = {"encounter_id":"N01","settled":false}
	var won := _service.settle_battle(run,{"battle_id":node.node_id,"result":"won","remaining_vitality":25},rng)
	_ok(won,"publish staged battle result " + kind)
	return won


func _economy() -> void:
	var start := _created(["RX-C25","RX-C29","RX-C31"])
	var run: RunState = start.data.state
	var rng: Dictionary = start.data.rng_states
	var lib := _place(run,"rest","L")
	run.money = 500
	var service := CampaignService.new(_catalog)
	service.enter(run,lib)
	var plan := {"offer_id":run.campaign.pending.offer_id,"option_id":"upgrade","candidate_id":run.cards[0].card_id}
	var upgrade := _apply(run,&"choose_campaign",plan,rng)
	_expect(upgrade,"RX-C25",8)
	_check(upgrade.data.state.cards[0].upgrade_level == 1 and upgrade.data.state.money == 500 - service.service_cost(run,"L") + 8,"service charges documented discount and upgrades actual instance")
	var shop_node := _place(run,"shop")
	var shop := _service.rewards().generate_shop(shop_node,run,RandomSource.new("42"))
	_ok(shop,"actual shop stock")
	shop_node.context = {"shop":shop.data}
	var slots: Array = shop.data.stocks.filter(func(s): return s.kind == "card")
	var a := _apply(run,&"buy_item",{"shop_id":shop.data.shop_id,"stock_id":slots[0].stock_id},rng)
	_expect(a,"RX-C29",0)
	var b_draft := GameAction.new(&"buy_item",{"shop_id":shop.data.shop_id,"stock_id":slots[1].stock_id})
	var poor: RunState = a.data.state.copy_for_write()
	poor.money = int(slots[1].price)-1
	_check(not _service.apply(poor,b_draft,rng).ok,"rebate doesn't pre-finance price")
	var b := _service.apply(a.data.state,b_draft,rng)
	_expect(b,"RX-C29",12)
	_check(b.data.state.money == a.data.state.money - slots[1].price + 12 and b.data.state.cards.size() == a.data.state.cards.size() + 1,"second stock is bought first, then actual rebate")
	var remove := _apply(b.data.state,&"remove_card",{"shop_id":shop.data.shop_id,"card_instance_id":b.data.state.cards[0].card_id},rng)
	_expect(remove,"RX-C31",1)
	var after: RunState = remove.data.state
	var discard_marker := after.copy_for_write()
	_service.transactions().add_relic(discard_marker,"RX-C19",discard_marker.relics[2].relic_id,2)
	_check(not discard_marker.campaign.rx_state.audition_ready and int(discard_marker.campaign.rx_uses["RX-C31"]) == 1,"replaced before redemption loses mark only")
	var plain := _created(["RX-C31"])
	plain.data.state.campaign = after.campaign.duplicate(true)
	var node_id := str(plain.data.state.reachable_node_ids().front())
	var entry := _apply(plain.data.state,&"enter_node",{"node_id":node_id},plain.data.rng_states)
	_check(entry.ok and entry.data.battle_input.get("rx_run",{}).get("RX-C31") == 1 and not entry.data.state.campaign.rx_state.audition_ready,"next real battle transfers marker once")
	_expect(_engine.begin(entry.data.battle_input),"RX-C31",2,"roster_draw")

	start = _created(["RX-C27","RX-C30","RX-C38"])
	run = start.data.state
	rng = start.data.rng_states
	var normal := _settle_fixture(run,rng,"normal")
	var expected_count := int(_catalog.get_definition("ruleset",run.ruleset_id).data.rewards.candidate_count)
	_check(normal.data.state.pending_reward.get_item("card").candidates.size() == expected_count-1,"ordinary candidates really reduced")
	var elite := _settle_fixture(run,rng,"elite")
	_expect(elite,"RX-C30",1,"extra_elite_candidate")
	_expect(elite,"RX-C38",16,"elite_payday")
	_check(elite.data.state.pending_reward.get_item("card").candidates.size() == expected_count+1,"elite has actual extra candidate")
	var normal_two := _settle_fixture(normal.data.state,normal.data.rng_states,"normal",1)
	var normal_three := _settle_fixture(normal_two.data.state,normal_two.data.rng_states,"normal",2)
	_expect(normal_two,"RX-C27",0)
	_expect(normal_three,"RX-C27",12,"normal_win_streak")
	_check(normal_three.data.state.campaign.rx_state.normal_wins == 0,"cycle clears only after third win")

	start = _created(["RX-C32","RX-C39","RX-C40"])
	run = start.data.state
	rng = start.data.rng_states
	var cafeteria := _place(run,"rest","C")
	if cafeteria != null:
		run.vitality = 30
		service.enter(run,cafeteria)
		var eat := _apply(run,&"choose_campaign",{"offer_id":run.campaign.pending.offer_id,"option_id":"heal"},rng)
		_check(eat.ok and eat.data.state.vitality == 38 and eat.data.state.campaign.rx_state.meal_ready == cafeteria.node_id,"actual cafeteria recovery arms adjacent battle")
		var elected := eat.data.state.copy_for_write() as RunState
		RunRelicRoster.entered(elected, RunNodeState.new({"kind":"shop"}))
		_check(elected.campaign.rx_state.meal_ready.is_empty(),"changing room type drops meal marker")
		var rewarded := _settle_fixture(eat.data.state,rng,"normal")
		_expect(rewarded,"RX-C32",4,"walk_after_meal")
	var boss := _settle_fixture(run,rng,"boss")
	var grand := _apply(boss.data.state,&"choose_campaign",{"offer_id":boss.data.state.campaign.pending.offer_id,"option_id":"upgrade","candidate_id":run.cards[0].card_id},boss.data.rng_states)
	_expect(grand,"RX-C40",1)
	_check(grand.data.state.cards[0].upgrade_level == 1 and grand.data.state.cards[1].upgrade_level == 1,"grand uses next legal basic instance in order")

	# Drive a real battle from a real enter_node result, save after the lethal pressure,
	# finish it by actual play, and observe the cross-battle marker after settlement.
	var first := str(run.reachable_node_ids().front()) if not run.reachable_node_ids().is_empty() else ""
	start = _created(["RX-C39"])
	run = start.data.state
	first = run.reachable_node_ids().front()
	entry = _apply(run,&"enter_node",{"node_id":first},start.data.rng_states)
	if not _ok(entry,"enter combat for rescue test") or not entry.data.battle_input is Dictionary: return
	var inputs: Dictionary = entry.data.battle_input.duplicate(true)
	inputs.encounter_id = "N01"
	inputs.erase("member_ids")
	inputs.vitality = 2
	var fight := _engine.begin(inputs)
	fight.data.state.tasks[0].intent_snapshot.pressure = 8
	fight = _end(fight)
	_expect(fight,"RX-C39",1,"lethal_pressure_saved")
	var encoded := BattleCodec.encode(fight.data.state)
	_check(encoded.ok and BattleCodec.decode(encoded.data,_catalog).ok,"battle codec accepts used rescue after real pressure")
	fight.data.state.tasks[0].work_remaining = 1
	fight.data.state.tasks[0].shield = 0
	fight = _play(fight,W,_target(fight))
	if not _check(fight.ok and fight.data.outcome is Dictionary and fight.data.outcome.result == "won","real play ends rescue fight"): return
	var settled := _service.settle_battle(entry.data.state,fight.data.outcome,fight.data.rng_state)
	_check(settled.ok and int(settled.data.state.campaign.rx_uses.get("RX-C39",0)) == 1,"real rescue is persisted on battle handoff")
	if not settled.ok: return
	var roundtrip := RunCodec.encode(settled.data.state)
	_check(roundtrip.ok and RunCodec.decode(roundtrip.data,_catalog).ok,"run codec roundtrips the consumed charge")
	inputs.rx_run = RunRelicRoster.battle_input(settled.data.state)
	fight = _engine.begin(inputs)
	fight.data.state.tasks[0].intent_snapshot.pressure = 8
	fight = _end(fight)
	_expect(fight,"RX-C39",0)
	_check(fight.data.outcome is Dictionary and fight.data.outcome.result == "lost","later fight cannot rescue again")


func _annual_route() -> void:
	_test_run_flow(ID)
