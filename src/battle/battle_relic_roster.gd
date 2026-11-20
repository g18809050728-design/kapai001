class_name BattleRelicRoster
extends RefCounted
## Additional RX rules. Use the host's rule queue, resource events and RNG;
## persistent flags are integer snapshot counters, never singleton state.

const CATEGORIES := {"work": 1, "strategy": 2, "ability": 3, "scene": 4, "cooperation": 5}
const FULL_LIMIT := 2147483647
const WORK_BONUS_CAP := 10
const COOPERATION_BONUS_CAP := 8
const PREPARE_FOCUS_CAP := 2
var _host: WeakRef
var host: Object:
	get: return _host.get_ref()


func _init(engine: Object) -> void:
	_host = weakref(engine)


static func available(s: BattleState, id: String, limit: int = 1, per_round: int = 0) -> bool:
	return BattleRelicPilot.eligible(s, id, limit, per_round)


static func key(id: String, field: String, scope: String = "battle") -> String:
	return scope + "|" + id + "|rx_" + field


static func value(s: BattleState, id: String, field: String, scope: String = "battle") -> int:
	return int(s.counters.get(key(id, field, scope), 0))


static func mark(s: BattleState, id: String, field: String, n: int = 1, scope: String = "battle") -> void:
	s.counters[key(id, field, scope)] = n


static func paper_value(s: BattleState) -> int:
	var p: Dictionary = s.v3.get("paper", {})
	return clampi(int(p.get("progress", 0)) * 7 + int(p.get("citations", 0)) * 6 + int(p.get("modifier", 0)), 0, 100)


static func price(s: BattleState, face: Dictionary, cost: int, legacy_work_discount: int) -> Dictionary:
	var out := {}
	var turn: Dictionary = s.v3.get("turn", {})
	var types: Dictionary = turn.get("played_types", {})
	var kind := str(face.get("type", ""))
	var base := int(face.get("cost", 0))
	if kind == "strategy" and base >= 1 and s.round_index <= 2 and s.relics.has("RX-C37") and value(s,"RX-C37","tax","round") == 0:
		out["RX-C37"] = 1
		cost += 1
	if kind == "work" and base >= 2 and legacy_work_discount == 0 and cost > 0 and int(types.get("strategy",0)) >= 2 and int(types.get("work",0)) == 0 and available(s,"RX-P01-10",2,1):
		out["RX-P01-10"] = -1
		cost -= 1
	if kind == "strategy" and bool(face.get("permanent",false)) and cost > 0 and value(s,"RX-P01-14","armed","round") > 0:
		out["RX-P01-14"] = -1
		cost -= 1
	if face.id == "R3-T201" and cost > 1 and paper_value(s) >= 65 and available(s,"RX-P02-06"):
		out["RX-P02-06"] = -1
	return out


func pulse(s: BattleState, id: String, at: String, amount: int, limit: int, events: Array[RuleEvent], targets: Array = [], consume: bool = true, resource: String = "效果") -> void:
	host._rx_trigger(s, id, at, amount, limit, events, targets, consume, resource)


func relax(s: BattleState, id: String, at: String, amount: int, limit: int, events: Array[RuleEvent], consume: bool = true) -> void:
	host._rx_relax(s, id, at, amount, limit, events, consume)


func draw(s: BattleState, id: String, n: int, limit: int, rng: RandomSource, events: Array[RuleEvent], consume: bool = true) -> void:
	var start := events.size()
	host._draw_cards(s, n, rng, events, id)
	var actual := 0
	for index in range(start, events.size()):
		if events[index].type == &"card_drawn" and events[index].source_id == id:
			actual += 1
	if actual > 0:
		pulse(s,id,"roster_draw",actual,limit,events,[],consume,"抽牌")
	elif consume:
		BattleRelicPilot.consume(s,id)


func resource(s: BattleState, field: String, delta: int, id: String, events: Array[RuleEvent]) -> int:
	var before := int(s.player.get(field,0))
	var cap := int(s.player.get("max_vitality", before)) if field == "vitality" else int(host._loaded_ruleset().data.battle.focus_cap)
	var after := clampi(before + delta, 0, cap)
	s.player[field] = after
	if field == "vitality":
		if after != before:
			host._add_event(events, "vitality_changed", id, [str(s.player.entity_id)], {"before": before, "after": after, "delta": after - before, "reason": "relic_effect"})
	else:
		host._resource_event(s, events, field, before, after, "relic_effect", id)
	return absi(after - before)


func permanent(s: BattleState, instance: String) -> bool:
	var card: Dictionary = s.card_by_id.get(instance,{})
	var def: GameResult = host._catalog.get_definition("card",str(card.get("definition_id","")))
	return def.ok and bool(def.data.get("permanent", true)) and not def.data.get("tags", []).has("temporary")


func complete(s: BattleState, id: String, task: String, n: int, limit: int, rng: RandomSource, events: Array[RuleEvent], consume: bool = true) -> GameResult:
	if task.is_empty() or s.phase == "finished":
		return GameResult.success(null)
	pulse(s,id,"roster_completion",n,limit,events,[task],consume,"完成量")
	return host._v3_status_complete_task(s,task,n,rng,events,id)


func earliest(s: BattleState) -> String:
	var chosen := ""
	var order := FULL_LIMIT
	for t in s.tasks:
		if int(t.get("work_remaining",0)) > 0 and int(t.entered_order) < order:
			order = int(t.entered_order)
			chosen = str(t.task_id)
	return chosen


func action_end(s: BattleState, rng: RandomSource, events: Array[RuleEvent]) -> GameResult:
	if s.relics.has("RX-C08") and s.round_index == 1:
		mark(s,"RX-C08","last_plays",int(s.counters.get("round|played:any|played",0)))
	if available(s,"RX-C06",2) and int(s.player.focus) >= 1:
		mark(s,"RX-C06","next",s.round_index + 1)
	if available(s,"RX-P01-16",2) and value(s,"RX-P01-16","ready","round") == 1:
		var order := value(s,"RX-P01-16","task","round")
		for t in s.tasks:
			if int(t.entered_order) == order and int(t.work_remaining) > 0:
				var extra := complete(s,"RX-P01-16",str(t.task_id),7,2,rng,events)
				if not extra.ok or s.phase == "finished": return extra
	if available(s,"RX-P03-04",2):
		var chosen := ""
		var order := FULL_LIMIT
		for t in s.tasks:
			var task_id := str(t.task_id)
			if int(t.entered_order) < order and int(host._status_stacks(s,"erosion",task_id)) >= 5:
				chosen = task_id
				order = int(t.entered_order)
		if not chosen.is_empty():
			remove_stack(s,"erosion",chosen,2,"RX-P03-04",events)
			var extra := complete(s,"RX-P03-04",chosen,6,2,rng,events)
			if not extra.ok or s.phase == "finished": return extra
	if available(s,"RX-P04-05") and s.units.size() >= 2 and not s.exam_flags.has("independent_answer") and value(s,"RX-P04-05","seen") == 0:
		mark(s,"RX-P04-05","seen")
		mark(s,"RX-P04-05","armed",1,"round")
	if available(s,"RX-P04-16",2) and value(s,"RX-P04-16","eligible_ends") < 2 and int(s.v3.get("synergy",0)) >= 2:
		# Only the first two eligible rounds qualify. Track the window separately
		# from actual receipts, since a partner segment can be fully clipped.
		mark(s,"RX-P04-16","eligible_ends",value(s,"RX-P04-16","eligible_ends")+1)
		if s.units.is_empty():
			relax(s,"RX-P04-16","solo_end",3,2,events)
		else:
			mark(s,"RX-P04-16","armed",1,"round")
	return GameResult.success(null)


func prepare(s: BattleState, anxiety: int, natural: int, events: Array[RuleEvent]) -> void:
	var round_id := s.round_index
	var focus_budget := PREPARE_FOCUS_CAP
	if available(s,"RX-P04-13",2) and s.units.is_empty() and int(s.v3.get("synergy",0)) >= 3:
		mark(s,"RX-P04-13","draw",1,"round")
	for id in s.relics:
		match id:
			"RX-C01":
				if round_id == 1 and available(s,id): relax(s,id,"natural_focus",4,1,events)
			"RX-C02", "RX-C23":
				var alarm := id == "RX-C23" and s.ddl <= 2 and not s.counters.has("battle|RX-C23|rx_alarm_seen")
				if not available(s,id) or not (alarm or (id == "RX-C02" and round_id == 2)): continue
				if alarm:
					s.counters["battle|RX-C23|rx_alarm_seen"] = 1
					s.counters["round|RX-C23|rx_alarm_draw"] = 1
				var gain := resource(s,"focus",mini(1,focus_budget),id,events)
				focus_budget -= gain
				if gain > 0: host._rx_trigger(s,id,"natural_focus",gain,1,events)
			"RX-C04":
				if round_id in [3,5]: relax(s,id,"set_round",4,2,events)
			"RX-C06":
				if value(s,id,"next") == round_id and available(s,id,2):
					var gained := resource(s,"focus",mini(1,focus_budget),id,events)
					focus_budget -= gained
					if gained > 0: pulse(s,id,"carry_focus",gained,2,events,[],true,"专注")
			"RX-C18":
				if anxiety > 0 and natural > 0 and available(s,id):
					relax(s,id,"anxiety",3,1,events)
					mark(s,id,"draw",1,"round")
			"RX-C21":
				if available(s,id) and value(s,id,"pressure") == round_id - 1 and round_id > 1 and value(s,id,"leak") != round_id - 1:
					relax(s,id,"fully_blocked",2,1,events)
					mark(s,id,"draw",1,"round")
			"RX-C22":
				if round_id == 1 and (s.exam_flags.has("independent_answer") or s.exam_flags.has("fixed_exam_room")):
					relax(s,id,"exam_prepare",7,1,events)
			"RX-C24", "RX-P03-14", "RX-P03-03", "RX-P04-09":
				if value(s,id,"next") == round_id:
					var limit := 2 if id in ["RX-P03-03","RX-P04-09"] else 1
					if not available(s,id,limit): continue
					relax(s,id,"delayed_prepare",3 if id == "RX-P03-14" else (5 if id == "RX-P03-03" else 4),limit,events)
					if id == "RX-C24": mark(s,id,"draw",1,"round")
					elif id == "RX-P03-14": mark(s,id,"draw_on_status",1,"round")
			"RX-C33":
				if round_id == 1 and int(s.player.vitality) >= 3:
					resource(s,"vitality",-2,id,events)
					var gained := resource(s,"focus",mini(1,focus_budget),id,events)
					focus_budget -= gained
					pulse(s,id,"overnight",gained if gained > 0 else 2,1,events,[],true,"专注" if gained > 0 else "消耗精力")
					mark(s,id,"draw",1,"round")
			"RX-C34":
				if round_id == 1:
					var spent := resource(s,"focus",-1,id,events)
					if spent > 0: pulse(s,id,"limited_pages",spent,1,events,[],false,"减少专注")
				elif round_id == 2:
					var gain := resource(s,"focus",mini(1,focus_budget),id,events)
					focus_budget -= gain
					if gain > 0: pulse(s,id,"extra_pages",gain,1,events,[],true,"专注")
					mark(s,id,"draw",2,"round")
			"RX-P01-12":
				if value(s,id,"tax_next") == round_id:
					var loss := resource(s,"focus",-1,id,events)
					if loss > 0: pulse(s,id,"construction_cost",loss,1,events,[],false,"减少专注")
			"RX-P02-12":
				if value(s,id,"focus_next") == round_id:
					var gain := resource(s,"focus",mini(1,focus_budget),id,events)
					focus_budget -= gain
					if gain > 0: pulse(s,id,"bound_spine_focus",gain,1,events,[],false,"专注")
			"RX-P04-15":
				if round_id <= 2 and s.units.is_empty():
					host._v3_gain_synergy(s,1,events,id)
					relax(s,id,"solo_prepare",3,2,events)


func base_draw(s: BattleState, rng: RandomSource, events: Array[RuleEvent]) -> void:
	for id in s.relics:
		if s.phase == "finished": return
		var queued := value(s,id,"draw","round")
		if queued > 0:
			draw(s,id,queued,2 if id == "RX-P04-13" else 1,rng,events,id == "RX-P04-13")
		if id == "RX-C05" and s.round_index == 1 and available(s,id):
			host._rx_search_draw(s,id,"strategy",true,"base_draw",events)
		elif id == "RX-C23" and int(s.counters.get("round|RX-C23|rx_alarm_draw",0)) > 0:
			host._rx_draw(s,id,"alarm_draw",1,BattleRelicPilot.used(s,id) == 0,rng,events)
		elif id == "RX-C08" and s.round_index == 2 and value(s,id,"last_plays") in [1,2]:
			draw(s,id,2,1,rng,events)
		elif id == "RX-C31" and s.round_index == 1 and value(s,id,"from_run") > 0:
			draw(s,id,2,1,rng,events)
		elif id == "RX-C36" and s.round_index == 1 and available(s,id):
			for cid in s.zones.hand.duplicate():
				var card: Dictionary = s.card_by_id[cid]
				if card.definition_id not in ["R3-C-01","R3-C-02"] or not permanent(s,cid) or s.retained_card_ids.has(cid): continue
				var definition: Dictionary = host._catalog.get_definition("card",card.definition_id).data
				if definition.get("flags",{}).get("innate",false): continue
				s.zones.hand.erase(cid)
				s.zones.exhaust.append(cid)
				host._add_event(events,"card_exhausted",id,[cid],{"definition_id":card.definition_id,"reason":"relic","to_zone":"exhaust"})
				pulse(s,id,"sealed_draft",1,1,events,[cid],true,"耗尽")
				draw(s,id,2,1,rng,events,false)
				break


func after_pressure(s: BattleState, loss: int, events: Array[RuleEvent]) -> void:
	if s.relics.has("RX-C21"):
		mark(s,"RX-C21","pressure",s.round_index)
		if loss > 0: mark(s,"RX-C21","leak",s.round_index)
	if loss >= 5 and int(s.player.vitality) > 0 and available(s,"RX-C20"):
		relax(s,"RX-C20","large_pressure",4,1,events)


func stage(s: BattleState) -> void:
	for id in ["RX-C24","RX-P03-14"]:
		if available(s,id) and value(s,id,"next") == 0:
			mark(s,id,"next",s.round_index + 1)


func charge_quote(s: BattleState, quote: Dictionary, rx: Dictionary, events: Array[RuleEvent]) -> void:
	for id in quote.get("rx_adjustments",{}):
		var n := int(quote.rx_adjustments[id])
		match id:
			"RX-C37": mark(s,id,"tax",1,"round")
			"RX-P01-14": mark(s,id,"armed",0,"round")
			"RX-P02-06": rx["publish_penalty"] = 8
		pulse(s,id,"cost_quote",absi(n),2 if id == "RX-P01-10" else 1,events,[],id not in ["RX-C37","RX-P01-14"],"费用增加" if n > 0 else "减费")


func status_delta(s: BattleState, target: String, kind: String, before: int, after: int, before_kinds: Array) -> void:
	var rx := BattleRelicPilot.card_context(s)
	if rx.is_empty() or after <= before: return
	rx["direct_status"] = true
	if kind == "erosion": rx["direct_erosion"] = true
	var direct: Dictionary = rx.get("debuffs", {})
	var row: Dictionary = direct.get(target, {"initial": before_kinds, "added": []})
	if before == 0 and not row.added.has(kind) and kind in ["erosion","induced","brittle","feebleness","weakness","vulnerability"]:
		row.added.append(kind)
	direct[target] = row
	rx["debuffs"] = direct


func remove_stack(s: BattleState, kind: String, task: String, n: int, id: String, events: Array[RuleEvent]) -> void:
	var index: int = host._status_index(s,kind,task)
	if index < 0: return
	var before := int(s.statuses[index].stacks)
	var after := maxi(0,before-n)
	if after == 0: s.statuses.remove_at(index)
	else: s.statuses[index].stacks = after
	host._add_event(events,"status_removed" if after == 0 else "status_changed",id,[task],{"status_definition_id":kind,"before":before,"after":after,"amount":before-after,"reason":"relic_effect"})


func main_is_current(s: BattleState, target: String, rx: Dictionary) -> bool:
	return not target.is_empty() and target == rx.main and int(rx.main_order) == int(host._rx_task_order(s,target)) and str(rx.main_phase) == str(host._rx_task_phase(s,target))


func work(s: BattleState, target: String, rx: Dictionary, events: Array[RuleEvent]) -> int:
	var r: Dictionary = s.resolution
	var types: Dictionary = r.get("v3_played_type_counts",{})
	var paid_work := int(rx.base_cost) >= 2 and int(rx.paid) >= 1
	var budget := WORK_BONUS_CAP
	for id in s.relics:
		var n := 0
		var limit := 1
		var per_round := 0
		match id:
			"RX-C13":
				limit = 3
				if int(types.get("work",0)) == 1: n = 2
			"RX-C37":
				limit = 2
				per_round = 1
				if s.round_index <= 2: n = 5
			"RX-P01-04":
				var i: int = host._task_index(s,target)
				if bool(r.get("v3_link",false)) and value(s,id,"armed") in [s.round_index,s.round_index-1] and value(s,id,"armed") > 0 and i >= 0 and available(s,id):
					var cut := mini(4,int(s.tasks[i].shield))
					if cut > 0:
						var before := int(s.tasks[i].shield)
						s.tasks[i].shield -= cut
						host._add_event(events,"shield_changed",id,[target],{"before":before,"after":s.tasks[i].shield,"reason":"relic_effect"})
						pulse(s,id,"linked_strip",cut,1,events,[target],true,"破除屏障")
			"RX-P01-12":
				if paid_work and int(types.get("strategy",0)) >= 2: n = 10
			"RX-P03-12":
				if paid_work and int(rx.main_debuff_kinds) >= 3 and rx.get("weak_at_play",false): n = 9
			"RX-P04-02":
				limit = 3
				per_round = 1
				if int(types.get("cooperation",0)) > 0: n = 4
			"RX-P04-14":
				if s.units.is_empty() and int(rx.get("synergy_paid",0)) >= 2: n = 6
			_:
				if budget <= 0: continue
				var old := BattleRelicPilot.work_bonus_for_slot(s,id,rx,types,bool(r.get("v3_link",false)))
				if not old.is_empty():
					var applied := mini(budget,int(old.amount))
					host._rx_trigger(s,id,"work_primary_segment",applied,int(old.limit),events,[target])
					budget -= applied
				continue
		var applied := mini(budget,n)
		if applied > 0 and available(s,id,limit,per_round):
			if id == "RX-P01-12": mark(s,id,"tax_next",s.round_index+1)
			elif id == "RX-P03-12": rx["strip_weakness"] = true
			pulse(s,id,"work_primary_segment",applied,limit,events,[target],true,"完成量")
			budget -= applied
	return WORK_BONUS_CAP - budget


func resolved(s: BattleState, rng: RandomSource, events: Array[RuleEvent]) -> void:
	var rx := BattleRelicPilot.card_context(s)
	if rx.is_empty() or s.phase == "finished": return
	var r: Dictionary = s.resolution
	var turn: Dictionary = host._v3_turn(s)
	var kind := str(r.card_type)
	var def_id := str(r.definition_id)
	var cid := str(r.card_instance_id)
	var previous := str(r.get("v3_previous_card_type",""))
	var paid := int(rx.paid)
	var count := int(s.counters.get("round|played:any|played",0))
	var types: Dictionary = turn.get("played_types",{})
	var notes := str(rx.get("main",""))
	var actual_new: Dictionary = rx.get("debuffs",{})
	for id in s.relics:
		if s.phase == "finished": return
		match id:
			"RX-C03":
				if kind in CATEGORIES and available(s,id) and CATEGORIES.keys().filter(func(k): return int(types.get(k,0)) > 0).size() == 3:
					draw(s,id,2,1,rng,events)
			"RX-C10":
				if count >= 3 and paid == 0 and available(s,id,3,1): relax(s,id,"late_free_card",3,3,events)
			"RX-C11":
				if available(s,id,2,1) and r.discarded_in_resolution.any(func(card): return permanent(s,str(card))): draw(s,id,1,2,rng,events)
			"RX-C12":
				if available(s,id,2,1) and s.zones.exhaust.has(cid) and permanent(s,cid):
					relax(s,id,"self_exhaust",2,2,events)
					draw(s,id,1,2,rng,events,false)
			"RX-C15":
				if rx.get("shield_removed",false) and available(s,id):
					relax(s,id,"explicit_shield_break",3,1,events)
					draw(s,id,1,1,rng,events,false)
			"RX-P01-02":
				if previous == "work" and kind == "strategy" and value(s,id,"paid_last","round") >= 1 and available(s,id,3,1): relax(s,id,"paid_work_strategy",3,3,events)
				mark(s,id,"paid_last",paid,"round")
			"RX-P01-03":
				var letter := 1 if kind == "strategy" else (2 if kind == "work" else 0)
				var seq := (value(s,id,"sequence","round") * 3 + letter) % 81
				mark(s,id,"sequence",seq,"round")
				if seq == 50 and available(s,id,2,1): draw(s,id,2,2,rng,events)
			"RX-P01-04":
				if value(s,id,"seen") == 0 and bool(r.get("v3_link",false)):
					mark(s,id,"seen")
					var i: int = host._task_index(s,notes)
					if i >= 0 and int(s.tasks[i].shield) > 0:
						mark(s,id,"armed",s.round_index)
						pulse(s,id,"linked_shield_armed",1,1,events,[notes],false,"待破盾")
			"RX-P01-07":
				# Key on the full instance id rather than on its definition.
				if paid >= 1 and value(s,id,"retrieved_" + cid,"round") == 1 and available(s,id):
					mark(s,id,"retrieved_" + cid,0,"round")
					var gain := resource(s,"focus",1,id,events)
					if gain > 0: pulse(s,id,"replayed_retrieved",gain,1,events,[],true,"专注")
			"RX-P01-08":
				if kind == "strategy" and available(s,id,2) and permanent(s,cid) and int(s.v3.get("battle",{}).get("instance_plays",{}).get(cid,0)) == 3:
					relax(s,id,"third_instance_play",5,2,events)
					draw(s,id,1,2,rng,events,false)
			"RX-P01-11":
				if kind == "work" and paid >= 2 and available(s,id):
					var prior := value(s,id,"round_seen")
					if prior == 0: mark(s,id,"round_seen",s.round_index)
					elif prior != s.round_index:
						relax(s,id,"two_paid_rounds",5,1,events)
						draw(s,id,1,1,rng,events,false)
			"RX-P01-13":
				if previous == "strategy" and kind in ["ability","scene","cooperation"] and available(s,id): relax(s,id,"broken_link",6,1,events)
			"RX-P01-14":
				if kind == "work" and paid >= 1 and not bool(r.get("v3_link",false)) and available(s,id):
					mark(s,id,"armed",1,"round")
					pulse(s,id,"unlinked_work",1,1,events,[],true,"待减费")
			"RX-P01-16":
				if available(s,id,2) and kind == "work" and paid >= 1 and value(s,id,"first_paid","round") == 0:
					mark(s,id,"first_paid",1,"round")
					if int(types.get("strategy",0)) == 0 and int(rx.get("main_order",0)) > 0:
						mark(s,id,"task",int(rx.main_order),"round")
				elif kind == "strategy" and value(s,id,"task","round") > 0:
					mark(s,id,"ready",1,"round")
			"RX-P02-16":
				var paper: Dictionary = s.v3.get("paper",{})
				if paper.get("open",false) and paper.get("chapters",[]).is_empty() and kind == "strategy" and paid >= 1 and not rx.get("is_chapter",false):
					var n := value(s,id,"nonchapter","round")+1
					mark(s,id,"nonchapter",n,"round")
					if n == 2 and available(s,id,2,1): relax(s,id,"empty_shelf",4,2,events)
			"RX-P03-06":
				if rx.get("induced_third",false) and available(s,id,2,1): relax(s,id,"third_induced",4,2,events)
			"RX-P03-08":
				if rx.get("induced_natural",[]).size() >= 2 and available(s,id):
					relax(s,id,"two_induced_targets",3,1,events)
					draw(s,id,1,1,rng,events,false)
			"RX-P03-11":
				if available(s,id,2,1) and actual_new.values().any(func(d): return d.initial.size() < 3 and d.initial.size() + d.added.size() >= 3):
					relax(s,id,"three_direct_debuffs",4,2,events)
					draw(s,id,1,2,rng,events,false)
			"RX-P03-12":
				if rx.get("strip_weakness",false) and main_is_current(s,notes,rx):
					remove_stack(s,"weakness",notes,1,id,events)
			"RX-P03-13":
				if available(s,id) and actual_new.values().any(func(d): return d.added.size() >= 2): relax(s,id,"two_new_debuffs",4,1,events)
			"RX-P03-14":
				if rx.get("direct_status",false) and value(s,id,"draw_on_status","round") > 0:
					mark(s,id,"draw_on_status",0,"round")
					draw(s,id,1,1,rng,events,false)
			"RX-P03-15":
				if value(s,id,"already_eroded","round") > 0 and not rx.get("induced_natural",[]).is_empty() and available(s,id):
					var gain := resource(s,"focus",1,id,events)
					if gain > 0: pulse(s,id,"prepared_induced",gain,1,events,[],true,"专注")
				if rx.get("direct_erosion",false): mark(s,id,"already_eroded",1,"round")
			"RX-P04-12":
				if kind in ["work","strategy"] and s.exam_flags.has("independent_answer") and int(rx.get("synergy_paid",0)) >= 1 and available(s,id,2,1): relax(s,id,"exam_synergy",4,2,events)
			"RX-P04-15":
				if kind == "cooperation" and s.round_index <= 2 and not s.exam_flags.has("independent_answer") and rx.get("partner_entered",false) and value(s,id,"paid_summon","round") == 0:
					mark(s,id,"paid_summon",1,"round")
					var cost := resource(s,"vitality",-2,id,events)
					if cost > 0: pulse(s,id,"summon_cost",cost,2,events,[],false,"消耗精力")
					host._check_battle_outcome(s,events)
			"RX-P01-15":
				if rx.check_work_search and not s.counters.has("battle|RX-P01-15|rx_search_seen"):
					s.counters["battle|RX-P01-15|rx_search_seen"] = 1
					host._rx_search_draw(s, id, "work", false, "strategy_without_work", events)
			"RX-P02-15":
				if rx.paid_chapter_reuse and BattleRelicPilot.eligible(s, id, 1) and not s.counters.has("battle|RX-P02-15|rx_reuse_seen"):
					s.counters["battle|RX-P02-15|rx_reuse_seen"] = 1
					if rx.chapter_ran_naturally:
						host._rx_relax(s, id, "paid_chapter_reuse", 4, 1, events)
			"RX-P03-16":
				if not rx.get("compound_armed", false) and s.counters.erase("round|RX-P03-16|rx_next_card"):
					host._rx_draw(s, id, "next_card_resolved", 1, false, rng, events)
			"RX-P04-01":
				if BattleRelicPilot.eligible(s, id, 1) and kind == "cooperation":
					if rx.exam or rx.get("partner_entered", false):
						host._rx_relax(s, id, "exam_substitute" if rx.exam else "partner_entered", 3 if rx.exam else 4, 1, events)
			"RX-P04-06":
				if BattleRelicPilot.eligible(s, id, 1):
					if rx.exam and def_id == "R3-P04-15":
						host._rx_relax(s, id, "exam_rest", 3, 1, events)
					elif not rx.exam and rx.get("partner_switched", false):
						host._rx_relax(s, id, "partner_switched", 3, 1, events)
						host._rx_draw(s, id, "partner_switched_draw", 1, false, rng, events)
			"RX-P04-08":
				if rx.exam and def_id == "R3-P04-06" and int(r.get("v3_last_synergy_spent", 0)) > 0 and BattleRelicPilot.eligible(s, id, 1):
					host._rx_relax(s, id, "exam_synergy_paid", 4, 1, events)

func choice_closed(s: BattleState, rng: RandomSource, events: Array[RuleEvent]) -> void:
	if s.zones.hand.is_empty() and available(s,"RX-C14",2,1): draw(s,"RX-C14",1,2,rng,events)


func partner_departed(s: BattleState) -> void:
	if not s.exam_flags.has("independent_answer") and available(s,"RX-P04-09",2):
		mark(s,"RX-P04-09","next",s.round_index+1)


func cooperation(s: BattleState, unit: Dictionary, task: String, n: int, events: Array[RuleEvent]) -> Array[int]:
	var budget := COOPERATION_BONUS_CAP
	var cost := 0
	if n <= 0 or s.exam_flags.has("independent_answer"): return [n,cost]
	for id in s.relics:
		var bonus := 0
		var limit := 1
		match id:
			"RX-P04-03":
				limit = 3
				if available(s,id,3,1): bonus = 2
			"RX-P04-05":
				if value(s,id,"armed","round") > 0 and int(unit.vitality) >= 2 and available(s,id):
					bonus = 6
					# Bind the first eligible partner; a clipped segment cannot
					# transfer the bonus to a different partner for this round.
					mark(s,id,"armed",0,"round")
			"RX-P04-10":
				if value(s,id,"replacement","round") == int(unit.entered_order) and available(s,id): bonus = 7
			"RX-P04-16":
				limit = 2
				if value(s,id,"armed","round") > 0:
					bonus = 3
					mark(s,id,"armed",0,"round")
		var applied := mini(budget,bonus)
		if applied > 0:
			budget -= applied
			if id == "RX-P04-05": cost = 1
			pulse(s,id,"regular_cooperation",applied,limit,events,[task],true,"完成量")
	return [n + COOPERATION_BONUS_CAP - budget,cost]


func chapters(s: BattleState, slots: Array, ready_count: int, c: int, rng: RandomSource, events: Array[RuleEvent]) -> GameResult:
	var ran := slots.size()
	if ran <= 0 or s.phase == "finished": return GameResult.success(null)
	var serial := value(s,"P02","paper_serial") + 1
	for id in s.relics:
		if s.phase == "finished": return GameResult.success(null)
		match id:
			"RX-P02-05":
				if c >= 85 and ready_count > 0 and available(s,id,2) and value(s,id,"paper") != serial:
					mark(s,id,"paper",serial)
					relax(s,id,"review_ready",6,2,events)
			"RX-P02-08":
				if ran >= 2 and available(s,id,2,1): draw(s,id,1,2,rng,events)
			"RX-P02-09":
				if ready_count == 1 and ran == 1 and available(s,id,3):
					var result := complete(s,id,earliest(s),4,3,rng,events)
					if not result.ok: return result
			"RX-P02-10":
				if slots.has(0) and slots.has(1) and available(s,id,2):
					relax(s,id,"second_chapter_slot",3,2,events)
					if slots.has(2):
						var result := complete(s,id,earliest(s),3,2,rng,events,false)
						if not result.ok: return result
			"RX-P02-12":
				if ran >= 3:
					var bound := value(s,id,"paper")
					if bound == 0:
						mark(s,id,"paper",serial)
						mark(s,id,"focus_next",s.round_index+1)
						pulse(s,id,"bound_spine",1,1,events,[],true,"待恢复专注")
					elif bound == serial:
						var result := complete(s,id,earliest(s),5,1,rng,events,false)
						if not result.ok: return result
	return GameResult.success(null)
