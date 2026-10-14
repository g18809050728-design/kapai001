class_name RewardOffer
extends RefCounted
##
## 奖励候选（《数据库与实体关系设计》§5 RewardOffer / RewardItem）。
##
## 冻结规则：候选在生成时确定并写进状态；再次打开界面不重抽、不重新过滤。
## status = pending / claimed / skipped；已处理项再提交一律 ALREADY_RESOLVED（幂等键 = item_id）。
##
## 直接收益（战斗生活费）在 settle_battle 当次提交里就写回 RunState，不占 RewardItem；
## 需要玩家选择的牌/饰品才是 item。meta.money 只用于界面展示当次直接收益。
##

const RunCopy := preload("res://src/run/run_copy.gd")

const STATUS_PENDING := "pending"
const STATUS_CLAIMED := "claimed"
const STATUS_SKIPPED := "skipped"
const STATUS_IDS: Array[String] = [STATUS_PENDING, STATUS_CLAIMED, STATUS_SKIPPED]

## 奖励项类型。
const ITEM_CARD := "card"
const ITEM_RELIC := "relic"
const ITEM_KINDS: Array[String] = [ITEM_CARD, ITEM_RELIC]

## 奖励来源，决定品质权重组（normal / elite / boss）。
const SOURCE_NORMAL := "normal"
const SOURCE_ELITE := "elite"
const SOURCE_BOSS := "boss"
const SOURCE_IDS: Array[String] = [SOURCE_NORMAL, SOURCE_ELITE, SOURCE_BOSS]


class RewardItem:
	var item_id: String = ""
	var kind: String = "card"
	var candidates: Array = []
	var status: String = "pending"
	## 已领取时记录选中的定义 ID；pending/skipped 为空串。
	var chosen_id: String = ""
	## 是否允许跳过；false 的项必须领取才能离开节点。
	var skippable: bool = true


var offer_id: String = ""
var source_node_id: String = ""
var source_kind: String = SOURCE_NORMAL
var items: Array = []
## 界面展示用（如 {"money": 15}）；不参与领取结算。
var meta: Dictionary = {}


static func create(p_offer_id: String, p_source_node_id: String, p_source_kind: String) -> RewardOffer:
	var offer: RewardOffer = load("res://src/run/run_reward_offer.gd").new()
	offer.offer_id = p_offer_id
	offer.source_node_id = p_source_node_id
	offer.source_kind = p_source_kind
	return offer


## 造 item 的唯一入口（Godot 不暴露 Outer.Inner.new()，跨脚本一律走工厂）。
static func create_item(p_item_id: String, p_kind: String, p_candidates: Array, p_skippable: bool = true) -> RewardItem:
	var item := RewardItem.new()
	item.item_id = p_item_id
	item.kind = p_kind
	item.candidates = p_candidates.duplicate()
	item.skippable = p_skippable
	return item


func add_item(p_item_id: String, p_kind: String, p_candidates: Array, p_skippable: bool = true) -> RewardItem:
	var item := create_item(p_item_id, p_kind, p_candidates, p_skippable)
	items.append(item)
	return item


func find_item(item_id: String) -> RewardItem:
	for raw_item in items:
		var item: RewardItem = raw_item
		if item.item_id == item_id:
			return item
	return null


func pending_items() -> Array:
	var pending := []
	for raw_item in items:
		var item: RewardItem = raw_item
		if item.status == STATUS_PENDING:
			pending.append(item)
	return pending


## 所有项都已处理（领取或跳过）才算完成，完成后才允许离开节点。
func is_complete() -> bool:
	return pending_items().is_empty()


func copy_for_write() -> RewardOffer:
	var copied: RewardOffer = create(offer_id, source_node_id, source_kind)
	copied.meta = RunCopy.dictionary(meta)
	for raw_item in items:
		var item: RewardItem = raw_item
		var item_copy := create_item(item.item_id, item.kind, item.candidates, item.skippable)
		item_copy.status = item.status
		item_copy.chosen_id = item.chosen_id
		copied.items.append(item_copy)
	return copied