class_name RunCodec
extends RefCounted
##
## RunState 及其局流程子实体的快照编解码（《数据库与实体关系设计》§7/§9）。
##
## 为什么放在 src/run：这些实体的字段与不变量由本模块拥有。存档层只需要两行委派：
##   SnapshotCodec.encode_run(run) -> RunCodec.encode_run(run)
##   SnapshotCodec.decode_run(data) -> RunCodec.decode_run(data)
## 不必知道地图/奖励/事件/学期结算的内部结构。
##
## 规范化编码：只输出 JSON 基础类型（对象键由 JSON 层排序、数组保持游戏顺序）；
## 读取时容忍 JSON 把数字变成 float，也接受十进制字符串。
## 不编码的内容：战斗状态（BattleState 由存档层负责）、随机快照、checksum（都在快照外层）。
##

const RunStateScript := preload("res://src/run/run_state.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const RewardOfferScript := preload("res://src/run/run_reward_offer.gd")
const ShopStateScript := preload("res://src/run/run_shop_state.gd")
const EventStateScript := preload("res://src/run/run_event_state.gd")
const TermSettlementScript := preload("res://src/run/run_term_settlement.gd")
const RunSummaryScript := preload("res://src/run/run_summary.gd")

## 解码时先用一个足够大的槽数重建饰品，再按存档里的 slot 覆盖（同存档层约定）。
const DECODE_RELIC_SLOT_HINT: int = 64


# ── RunState ──────────────────────────────────────────────

static func encode_run(run) -> Dictionary:
	var cards := []
	for card in run.cards:
		cards.append({
			"card_id": card.card_id,
			"definition_id": card.definition_id,
			"upgrade_level": card.upgrade_level,
			"acquired_from": card.acquired_from,
		})
	var relics := []
	for relic in run.relics:
		relics.append({
			"relic_id": relic.relic_id,
			"definition_id": relic.definition_id,
			"slot": relic.slot,
			"acquired_order": relic.acquired_order,
		})
	var nodes := []
	for node in run.nodes:
		nodes.append(encode_node(node))
	var data := {
		"run_id": run.run_id,
		"character_id": run.character_id,
		"ruleset_id": run.ruleset_id,
		"difficulty": run.difficulty,
		"manifest_id": run.manifest_id,
		"term": run.term,
		"money": run.money,
		"vitality": run.vitality,
		"max_vitality": run.max_vitality,
		"next_instance_seq": run.next_instance_seq,
		"cards": cards,
		"relics": relics,
		"career_progress": run.career_progress.duplicate(true),
		"settled_battle_ids": run.settled_battle_ids.duplicate(true),
		"nodes": nodes,
		"current_node_id": run.current_node_id,
		"node_path": run.node_path.duplicate(),
		"seen_event_ids": run.seen_event_ids.duplicate(true),
		"removals_used": run.removals_used,
		"career_direction": run.career_direction,
		"active_battle_id": run.active_battle_id,
		"active_encounter_id": run.active_encounter_id,
		"outcome": run.outcome,
		"pending_reward": null,
		"settlement": null,
		"run_summary": null,
		"profile_summary_pending": run.pending_profile_summary != null,
	}
	if run.pending_reward != null:
		data["pending_reward"] = encode_offer(run.pending_reward)
	if run.settlement != null:
		data["settlement"] = encode_settlement(run.settlement)
	if run.run_summary != null:
		data["run_summary"] = encode_summary(run.run_summary)
	return data


static func decode_run(data: Dictionary) -> RunStateScript:
	var run: RunStateScript = RunStateScript.new()
	run.run_id = _str(data, "run_id")
	run.character_id = _str(data, "character_id")
	run.ruleset_id = _str(data, "ruleset_id")
	run.difficulty = _str(data, "difficulty")
	run.manifest_id = _str(data, "manifest_id")
	run.term = _int(data, "term", 1)
	run.money = _int(data, "money", 0)
	run.vitality = _int(data, "vitality", 0)
	run.max_vitality = _int(data, "max_vitality", 0)
	for raw_card in _array(data, "cards"):
		var card_entry: Dictionary = raw_card
		var card = run.add_card(_str(card_entry, "definition_id"), _int(card_entry, "upgrade_level", 0), _str(card_entry, "acquired_from"))
		if card != null:
			card.card_id = _str(card_entry, "card_id")
	for raw_relic in _array(data, "relics"):
		var relic_entry: Dictionary = raw_relic
		var relic = run.equip_relic(_str(relic_entry, "definition_id"), DECODE_RELIC_SLOT_HINT, _int(relic_entry, "acquired_order", 0))
		if relic != null:
			relic.relic_id = _str(relic_entry, "relic_id")
			relic.slot = _int(relic_entry, "slot", -1)
	run.career_progress = _dict(data, "career_progress").duplicate(true)
	run.settled_battle_ids = _dict(data, "settled_battle_ids").duplicate(true)
	run.nodes = []
	for raw_node in _array(data, "nodes"):
		if typeof(raw_node) == TYPE_DICTIONARY:
			run.nodes.append(decode_node(raw_node))
	run.current_node_id = _str(data, "current_node_id")
	run.node_path = _array(data, "node_path").duplicate()
	run.seen_event_ids = _dict(data, "seen_event_ids").duplicate(true)
	run.removals_used = _int(data, "removals_used", 0)
	run.career_direction = _str(data, "career_direction")
	run.active_battle_id = _str(data, "active_battle_id")
	run.active_encounter_id = _str(data, "active_encounter_id")
	run.outcome = _str(data, "outcome")
	var raw_offer: Variant = data.get("pending_reward")
	if typeof(raw_offer) == TYPE_DICTIONARY:
		run.pending_reward = decode_offer(raw_offer)
	var raw_settlement: Variant = data.get("settlement")
	if typeof(raw_settlement) == TYPE_DICTIONARY:
		run.settlement = decode_settlement(raw_settlement)
	var raw_summary: Variant = data.get("run_summary")
	if typeof(raw_summary) == TYPE_DICTIONARY:
		run.run_summary = decode_summary(raw_summary)
	# 不变量：pending_profile_summary 与 run_summary 是同一对象（或都为 null）
	run.pending_profile_summary = run.run_summary if _bool(data, "profile_summary_pending", false) else null
	# next_instance_seq 必须最后恢复：重建 cards/relics 会用 allocate_instance_id 递增它
	run.next_instance_seq = _int(data, "next_instance_seq", 1)
	return run
# ── 节点 ──────────────────────────────────────────────────

static func encode_node(node) -> Dictionary:
	var data := {
		"node_id": node.node_id,
		"term": node.term,
		"layer": node.layer,
		"kind": node.kind,
		"status": node.status,
		"next_ids": node.next_ids.duplicate(),
	}
	if node.context.has("encounter_id"):
		data["encounter_id"] = String(node.context["encounter_id"])
	if node.context.has("used"):
		data["used"] = bool(node.context["used"])
	if node.context.has("shop") and node.context["shop"] != null:
		data["shop"] = encode_shop(node.context["shop"])
	if node.context.has("event") and node.context["event"] != null:
		data["event"] = encode_event(node.context["event"])
	return data


static func decode_node(data: Dictionary) -> RunNodeState:
	var node: RunNodeState = RunNodeState.create(
		_str(data, "node_id"), _int(data, "term", 1), _int(data, "layer", 1),
		_str(data, "kind", RunNodeState.KIND_NORMAL)
	)
	node.status = _str(data, "status", RunNodeState.STATUS_PENDING)
	node.next_ids = _array(data, "next_ids").duplicate()
	if data.has("encounter_id"):
		node.context["encounter_id"] = _str(data, "encounter_id")
	if data.has("used"):
		node.context["used"] = bool(data["used"])
	var raw_shop: Variant = data.get("shop")
	if typeof(raw_shop) == TYPE_DICTIONARY:
		node.context["shop"] = decode_shop(raw_shop)
	var raw_event: Variant = data.get("event")
	if typeof(raw_event) == TYPE_DICTIONARY:
		node.context["event"] = decode_event(raw_event)
	return node


# ── 奖励 ──────────────────────────────────────────────────

static func encode_offer(offer) -> Dictionary:
	var items := []
	for item in offer.items:
		items.append({
			"item_id": item.item_id,
			"kind": item.kind,
			"candidates": item.candidates.duplicate(),
			"status": item.status,
			"chosen_id": item.chosen_id,
			"skippable": item.skippable,
		})
	return {
		"offer_id": offer.offer_id,
		"source_node_id": offer.source_node_id,
		"source_kind": offer.source_kind,
		"meta": offer.meta.duplicate(true),
		"items": items,
	}


static func decode_offer(data: Dictionary) -> RewardOfferScript:
	var offer = RewardOfferScript.create(
		_str(data, "offer_id"), _str(data, "source_node_id"),
		_str(data, "source_kind", RewardOfferScript.SOURCE_NORMAL)
	)
	offer.meta = _dict(data, "meta").duplicate(true)
	for raw_item in _array(data, "items"):
		var entry: Dictionary = raw_item
		var item = RewardOfferScript.create_item(
			_str(entry, "item_id"), _str(entry, "kind", RewardOfferScript.ITEM_CARD),
			_array(entry, "candidates"), _bool(entry, "skippable", true)
		)
		item.status = _str(entry, "status", RewardOfferScript.STATUS_PENDING)
		item.chosen_id = _str(entry, "chosen_id")
		offer.items.append(item)
	return offer


# ── 商店 ──────────────────────────────────────────────────

static func encode_shop(shop) -> Dictionary:
	var stocks := []
	for stock in shop.stocks:
		stocks.append({
			"stock_id": stock.stock_id,
			"kind": stock.kind,
			"definition_id": stock.definition_id,
			"price": stock.price,
			"sold": stock.sold,
			"meta": stock.meta.duplicate(true),
		})
	return {
		"shop_id": shop.shop_id,
		"node_id": shop.node_id,
		"removal_count": shop.removal_count,
		"stocks": stocks,
	}


static func decode_shop(data: Dictionary) -> ShopStateScript:
	var shop = ShopStateScript.create(_str(data, "shop_id"), _str(data, "node_id"))
	shop.removal_count = _int(data, "removal_count", 0)
	for raw_stock in _array(data, "stocks"):
		var entry: Dictionary = raw_stock
		var stock = ShopStateScript.create_stock(
			_str(entry, "stock_id"), _str(entry, "kind", ShopStateScript.STOCK_CARD),
			_str(entry, "definition_id"), _int(entry, "price", 0)
		)
		stock.sold = _bool(entry, "sold", false)
		stock.meta = _dict(entry, "meta").duplicate(true)
		shop.stocks.append(stock)
	return shop


# ── 事件 ──────────────────────────────────────────────────

static func encode_event(instance) -> Dictionary:
	return {
		"event_instance_id": instance.event_instance_id,
		"node_id": instance.node_id,
		"definition_id": instance.definition_id,
		"resolved_option_id": instance.resolved_option_id,
		"frozen_candidates": instance.frozen_candidates.duplicate(true),
	}


static func decode_event(data: Dictionary) -> EventStateScript:
	var instance = EventStateScript.create(
		_str(data, "event_instance_id"), _str(data, "node_id"), _str(data, "definition_id")
	)
	instance.resolved_option_id = _str(data, "resolved_option_id")
	instance.frozen_candidates = _dict(data, "frozen_candidates").duplicate(true)
	return instance


# ── 学期结算 / 局摘要 ─────────────────────────────────────

static func encode_settlement(settlement) -> Dictionary:
	var steps := []
	for raw_step in settlement.steps:
		var step: Dictionary = raw_step
		steps.append(step.duplicate(true))
	return {
		"settlement_id": settlement.settlement_id,
		"term": settlement.term,
		"steps": steps,
	}


static func decode_settlement(data: Dictionary) -> TermSettlementScript:
	var settlement = TermSettlementScript.create(_str(data, "settlement_id"), _int(data, "term", 1))
	settlement.steps = []
	for raw_step in _array(data, "steps"):
		if typeof(raw_step) == TYPE_DICTIONARY:
			var step: Dictionary = raw_step
			settlement.steps.append(step.duplicate(true))
	return settlement


static func encode_summary(summary) -> Dictionary:
	return {
		"run_id": summary.run_id,
		"result": summary.result,
		"reason": summary.reason,
		"ending_id": summary.ending_id,
		"character_id": summary.character_id,
		"difficulty": summary.difficulty,
		"term": summary.term,
		"stats": summary.stats.duplicate(true),
		"unlocked_ids": summary.unlocked_ids.duplicate(),
	}


static func decode_summary(data: Dictionary) -> RunSummaryScript:
	var summary = RunSummaryScript.create(
		_str(data, "run_id"), _str(data, "result"), _str(data, "reason"),
		_str(data, "character_id"), _str(data, "difficulty"), _int(data, "term", 0)
	)
	summary.ending_id = _str(data, "ending_id")
	summary.stats = _dict(data, "stats").duplicate(true)
	summary.unlocked_ids = _array(data, "unlocked_ids").duplicate()
	return summary


# ── 读取工具（容忍 JSON 的 float 与十进制字符串）──────────

static func _str(data: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_STRING:
		return String(value)
	if typeof(value) == TYPE_STRING_NAME:
		return String(value)
	return fallback


static func _int(data: Dictionary, key: String, fallback: int = 0) -> int:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)):
		return int(value)
	if typeof(value) == TYPE_BOOL:
		return 1 if bool(value) else 0
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return String(value).to_int()
	return fallback


static func _bool(data: Dictionary, key: String, fallback: bool = false) -> bool:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if typeof(value) == TYPE_INT:
		return int(value) != 0
	if typeof(value) == TYPE_FLOAT:
		return float(value) != 0.0
	return fallback


static func _array(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key)
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}