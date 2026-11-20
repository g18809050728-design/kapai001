class_name RunRelicRoster
extends RefCounted
## Full-pool economy and cross-combat effects. Commands only write a detached run.

const LIMITS := {"RX-C25":2,"RX-C27":3,"RX-C29":2,"RX-C31":1,"RX-C32":2,"RX-C38":3,"RX-C39":1,"RX-C40":1}
const FIELDS := {"normal_wins":TYPE_INT,"review_year":TYPE_INT,"audition_ready":TYPE_BOOL,"meal_ready":TYPE_STRING}


static func enabled(run: RunState) -> bool:
	return run.manifest_id == RelicPilot.ROSTER


static func equipped(run: RunState, id: String) -> bool:
	return enabled(run) and run.relics.any(func(slot): return slot.definition_id == id)


static func remaining(run: RunState, id: String) -> int:
	return int(LIMITS.get(id,0))-int(run.campaign.get("rx_uses",{}).get(id,0))


static func active(run: RunState, id: String) -> bool:
	return equipped(run,id) and (not LIMITS.has(id) or remaining(run,id) > 0)


static func initialize(run: RunState) -> void:
	run.campaign["rx_state"] = {"normal_wins":0,"review_year":0,"audition_ready":false,"meal_ready":""}


## Keep pre-RX reward milestones without changing the stored map algorithm.
static func upgrade_base_campaign(run: RunState) -> void:
	run.campaign["legacy_relic_layers"] = true
	run.campaign["rx_uses"] = {}
	initialize(run)


static func validate(data: Dictionary, issues: Array[String]) -> void:
	var count := issues.size()
	RunCodec.shape(data,FIELDS,"run.campaign.rx_state",issues)
	if count != issues.size(): return
	if data.normal_wins < 0 or data.normal_wins > 2 or data.review_year < 0 or data.review_year > 4:
		issues.append("invalid RX progress")


static func upgrade_discount(run: RunState, cost: int) -> int:
	return mini(8,cost) if active(run,"RX-C25") else 0


static func paid_removal(run: RunState, cost: int) -> void:
	if cost > 0 and active(run,"RX-C31"):
		RelicPilot.consume(run,"RX-C31")
		run.campaign.rx_state.audition_ready = true


static func meal(run: RunState, node_id: String, vitality_before: int) -> void:
	if run.vitality > vitality_before and active(run,"RX-C32"):
		run.campaign.rx_state.meal_ready = node_id


static func replaced(run: RunState, id: String) -> void:
	if not enabled(run): return
	if id == "RX-C31": run.campaign.rx_state.audition_ready = false
	elif id == "RX-C32": run.campaign.rx_state.meal_ready = ""


static func entered(run: RunState, node: RunNodeState) -> void:
	if not enabled(run) or str(run.campaign.rx_state.meal_ready).is_empty(): return
	if node.kind != "normal" or run.node_path.is_empty() or run.node_path.back() != run.campaign.rx_state.meal_ready:
		run.campaign.rx_state.meal_ready = ""


static func battle_input(run: RunState) -> Dictionary:
	var out := {}
	if not enabled(run): return out
	if equipped(run,"RX-C31") and bool(run.campaign.rx_state.audition_ready):
		out["RX-C31"] = 1
		run.campaign.rx_state.audition_ready = false
	if equipped(run,"RX-C39") and remaining(run,"RX-C39") == 0:
		out["RX-C39"] = 1
	return out


static func award_event(run: RunState, receipt: Array[RuleEvent], id: String, where: String, amount: int, resource: String) -> void:
	if amount <= 0: return
	receipt.append(RuleEvent.new(receipt.size(),&"relic_triggered",id,[],{"relic_id":id,"at":where,"amount":amount,"resource":resource,"remaining":remaining(run,id) if LIMITS.has(id) else 0}))


static func settle(run: RunState, node: RunNodeState, outcome: Dictionary, events: Array[RuleEvent]) -> void:
	if not enabled(run): return
	if active(run,"RX-C39") and bool(outcome.get("summary",{}).get("rx_rescue",false)):
		RelicPilot.consume(run,"RX-C39")
	var meal_node := str(run.campaign.rx_state.meal_ready)
	run.campaign.rx_state.meal_ready = ""
	if outcome.result != "won" or run.vitality <= 0: return
	if node.kind == "normal":
		if active(run,"RX-C27"):
			run.campaign.rx_state.normal_wins += 1
			if run.campaign.rx_state.normal_wins == 3:
				run.campaign.rx_state.normal_wins = 0
				run.money += 12
				RelicPilot.consume(run,"RX-C27")
				award_event(run,events,"RX-C27","normal_win_streak",12,"金钱")
		if not meal_node.is_empty() and active(run,"RX-C32"):
			var gain := mini(4,run.max_vitality-run.vitality)
			run.vitality += gain
			RelicPilot.consume(run,"RX-C32")
			award_event(run,events,"RX-C32","walk_after_meal",gain,"精力")


static func bonus_upgrade(run: RunState, catalog: ContentDB, selected: String) -> bool:
	if run.term >= 4 or not active(run,"RX-C40"): return false
	for card in run.cards:
		if card.card_id == selected or int(card.upgrade_level) != 0: continue
		var definition := catalog.get_definition("card",str(card.definition_id))
		if not definition.ok or definition.data.get("type") not in ["work","strategy"] or definition.data.get("upgrade",{}).is_empty(): continue
		if definition.data.get("rarity") != "basic" and not definition.data.get("tags",[]).has("basic"): continue
		if not bool(definition.data.get("permanent",true)): continue
		card.upgrade_level = 1
		RelicPilot.consume(run,"RX-C40")
		return true
	return false
