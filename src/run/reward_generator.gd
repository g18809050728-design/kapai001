class_name RewardGenerator
extends RefCounted
##
## 奖励与商店生成（《类与方法设计》§4 RewardGenerator；《统一设计文档》§10.1）。
##
## 只用 reward 流抽候选；生成结果由 RunService 冻结进状态，重开界面不重抽。
## 品质先抽（相对权重），再在合法定义内等权抽；某品质池为空时在剩余品质上重新归一化，
## 零权重品质不会被抽中（《常量与规则配置》§3）。
##
## 池过滤：
##   · 奖励池排除 basic 标签（「基础标签不进随机奖励池」），商店卡池只按品质与定价过滤
##     （§10.1 只禁止金卡与金饰品进普通商店）。
##   · 饰品池排除 availability=starter、已持有同名与 rarity=null。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const RewardOffer := preload("res://src/run/run_reward_offer.gd")
const ShopState := preload("res://src/run/run_shop_state.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")

## 品质抽取的固定顺序（白→蓝→紫→金），不依赖字典遍历顺序。
const RARITY_ORDER: Array[String] = [
	GameConstants.RARITY_WHITE,
	GameConstants.RARITY_BLUE,
	GameConstants.RARITY_PURPLE,
	GameConstants.RARITY_GOLD,
]

var catalog: ContentDB = null


func _init(catalog_ref = null) -> void:
	catalog = catalog_ref


func set_catalog(catalog_ref) -> void:
	catalog = catalog_ref


# ── 战斗奖励 ──────────────────────────────────────────────

## Result<RewardOffer>：普通/精英/首领胜利后需要玩家处理的奖励项。
## 直接生活费由 RunService 写回并发 money_gained 事件；这里只生成需要选择的项。
func generate_battle_reward(node, run, rng) -> Dictionary:
	var source_kind := _source_kind(node)
	var offer := RewardOffer.create(run.allocate_instance_id(), node.node_id, source_kind)
	var card_picked := _add_card_item(offer, "item_card", _weight_group(source_kind), run, rng)
	if not Result.is_ok(card_picked):
		return card_picked
	if node.kind == RunNodeState.KIND_ELITE:
		var relic_picked := _add_relic_item(offer, "item_relic", "general", 1, run, rng)
		if not Result.is_ok(relic_picked):
			return relic_picked
	elif node.kind == RunNodeState.KIND_BOSS:
		var boss_relic := _add_relic_item(offer, "item_relic", "boss", 3, run, rng)
		if not Result.is_ok(boss_relic):
			return boss_relic
	return Result.ok(offer)


func _add_card_item(offer, item_id: String, group: String, run, rng) -> Dictionary:
	var candidates := card_candidates_by_weights(group, _candidate_count(), run, rng)
	if not Result.is_ok(candidates):
		return candidates
	var ids: Array = candidates["data"]
	if ids.is_empty():
		return Result.ok(null)
	offer.add_item(item_id, RewardOffer.ITEM_CARD, ids, true)
	return Result.ok(null)


## 饰品项：池耗尽时按「全部饰品池耗尽转生活费」退回 meta.relic_fallback_money，由 RunService 发钱。
func _add_relic_item(offer, item_id: String, group: String, count: int, run, rng) -> Dictionary:
	var candidates := relic_candidates_by_weights(group, count, run, rng)
	if not Result.is_ok(candidates):
		return candidates
	var ids: Array = candidates["data"]
	if ids.is_empty():
		offer.meta["relic_fallback_money"] = _rewards_int("empty_relic_pool_money", 30)
		return Result.ok(null)
	offer.add_item(item_id, RewardOffer.ITEM_RELIC, ids, true)
	return Result.ok(null)


# ── 候选池（品质加权）─────────────────────────────────────

## Result<Array[String]>：按权重组抽 count 个不同名候选（不足时返回实际数量）。
func card_candidates_by_weights(group: String, count: int, run, rng, tags: Array = []) -> Dictionary:
	var weights := _card_weights(group)
	var picked := []
	for _index in range(count):
		var rarity := _roll_rarity(weights, GameConstants.KIND_CARD, run, picked, rng, tags)
		if not Result.is_ok(rarity):
			return rarity
		var rarity_id := String(rarity["data"])
		if rarity_id.is_empty():
			break
		var one := card_candidates_of_rarity(rarity_id, 1, run, rng, picked)
		if not Result.is_ok(one):
			return one
		var ids: Array = one["data"]
		if ids.is_empty():
			break
		picked.append(String(ids[0]))
	return Result.ok(picked)


## Result<Array[String]>：指定品质的卡候选（excluded 用于去重）。
func card_candidates_of_rarity(rarity: String, count: int, run, rng, excluded: Array = []) -> Dictionary:
	var pool := _card_pool(rarity, excluded)
	return _take_distinct(pool, count, rng)


func relic_candidates_by_weights(group: String, count: int, run, rng) -> Dictionary:
	var weights := _relic_weights(group)
	var picked := []
	for _index in range(count):
		var rarity := _roll_rarity(weights, GameConstants.KIND_RELIC, run, picked, rng)
		if not Result.is_ok(rarity):
			return rarity
		var rarity_id := String(rarity["data"])
		if rarity_id.is_empty():
			break
		var one := relic_candidates_of_rarity(rarity_id, 1, run, rng, picked)
		if not Result.is_ok(one):
			return one
		var ids: Array = one["data"]
		if ids.is_empty():
			break
		picked.append(String(ids[0]))
	return Result.ok(picked)


func relic_candidates_of_rarity(rarity: String, count: int, run, rng, excluded: Array = []) -> Dictionary:
	var pool := _relic_pool(rarity, run, excluded)
	return _take_distinct(pool, count, rng)


## 预览用：权重组是否还有任何可用定义（不消费随机）。
func has_card_pool(group: String, run, tags: Array = []) -> bool:
	return _has_any_pool(_card_weights(group), GameConstants.KIND_CARD, run, tags)


func has_relic_pool(group: String, run, tags: Array = []) -> bool:
	return _has_any_pool(_relic_weights(group), GameConstants.KIND_RELIC, run, tags)
# ── 商店 ──────────────────────────────────────────────────

## Result<ShopState>：库存与价格在生成时冻结，售出不补（《统一设计文档》§10.1）。
func generate_shop(node, run, rng) -> Dictionary:
	var shop_rules := catalog.section("shop")
	var shop := ShopState.create(run.allocate_instance_id(), node.node_id)
	var card_prices: Dictionary = shop_rules.get("card_prices", {})
	var card_stock: Dictionary = shop_rules.get("card_stock", {})
	for rarity in RARITY_ORDER:
		var count := _int(card_stock.get(rarity), 0)
		if count <= 0 or not card_prices.has(rarity):
			continue
		var picked := _take_distinct(_shop_card_pool(rarity), count, rng)
		if not Result.is_ok(picked):
			return picked
		for raw_id in (picked["data"] as Array):
			shop.add_stock(_stock_id(shop, "card"), ShopState.STOCK_CARD, String(raw_id), _int(card_prices.get(rarity), 0))
	var relic_prices: Dictionary = shop_rules.get("relic_prices", {})
	var relic_stock: Dictionary = shop_rules.get("relic_stock", {})
	for rarity in RARITY_ORDER:
		var count := _int(relic_stock.get(rarity), 0)
		if count <= 0 or not relic_prices.has(rarity):
			continue
		var picked := _take_distinct(_relic_pool(rarity, run, []), count, rng)
		if not Result.is_ok(picked):
			return picked
		for raw_id in (picked["data"] as Array):
			shop.add_stock(_stock_id(shop, "relic"), ShopState.STOCK_RELIC, String(raw_id), _int(relic_prices.get(rarity), 0))
	var meal_count := _int(shop_rules.get("meal_stock"), 0)
	for _index in range(meal_count):
		var stock = shop.add_stock(_stock_id(shop, "meal"), ShopState.STOCK_MEAL, "", _int(shop_rules.get("meal_price"), 0))
		stock.meta["heal"] = _int(shop_rules.get("meal_heal"), 0)
	return Result.ok(shop)


func _stock_id(shop, prefix: String) -> String:
	return "%s|%s%d" % [shop.shop_id, prefix, shop.stocks.size()]


# ── 抽取工具 ──────────────────────────────────────────────

## Result<String>：按相对权重抽品质；池为空的品质不参与、在剩余品质上重新归一化。
## 没有可用品质时返回空串（调用方按各自回退规则处理）。
func _roll_rarity(weights: Dictionary, kind: String, run, excluded: Array, rng, tags: Array = []) -> Dictionary:
	var entries := []
	var total := 0
	for rarity in RARITY_ORDER:
		var weight := _int(weights.get(rarity), 0)
		if weight <= 0:
			continue
		if _pool_for(kind, rarity, run, excluded, tags).is_empty():
			continue
		entries.append({"rarity": rarity, "weight": weight})
		total += weight
	if entries.is_empty():
		return Result.ok("")
	var roll: Dictionary = rng.draw_int(GameConstants.RNG_REWARD, 1, total)
	if not Result.is_ok(roll):
		return roll
	var point := int(roll["data"])
	var cursor := 0
	for entry in entries:
		cursor += int(entry["weight"])
		if point <= cursor:
			return Result.ok(String(entry["rarity"]))
	return Result.ok(String(entries[entries.size() - 1]["rarity"]))


func _has_any_pool(weights: Dictionary, kind: String, run, tags: Array = []) -> bool:
	for rarity in RARITY_ORDER:
		if _int(weights.get(rarity), 0) <= 0:
			continue
		if not _pool_for(kind, rarity, run, [], tags).is_empty():
			return true
	return false


func _pool_for(kind: String, rarity: String, run, excluded: Array, tags: Array = []) -> Array:
	if kind == GameConstants.KIND_RELIC:
		return _relic_pool(rarity, run, excluded)
	return _filter_by_tags(_card_pool(rarity, excluded), tags)


## 奖励卡池：排除 basic 标签（「基础标签不进随机奖励池」）。
func _card_pool(rarity: String, excluded: Array) -> Array:
	return catalog.get_candidates({
		"kind": GameConstants.KIND_CARD,
		"rarity": rarity,
		"excluded_ids": excluded,
		"exclude_tag": GameConstants.TAG_BASIC,
	})


## 商店卡池：只按品质与定价过滤——§10.1 只禁止金卡，basic 标签不在禁止范围内。
func _shop_card_pool(rarity: String) -> Array:
	return catalog.get_candidates({
		"kind": GameConstants.KIND_CARD,
		"rarity": rarity,
		"excluded_ids": [],
	})


## 饰品池：排除初始获取限制（availability=starter）与已持有同名。
func _relic_pool(rarity: String, run, excluded: Array) -> Array:
	var raw := catalog.get_candidates({
		"kind": GameConstants.KIND_RELIC,
		"rarity": rarity,
		"excluded_ids": excluded,
	})
	var pool := []
	for raw_id in raw:
		var definition_id := String(raw_id)
		if run != null and run.has_relic_definition(definition_id):
			continue
		var definition: Dictionary = catalog.definition(GameConstants.KIND_RELIC, definition_id)
		if String(definition.get("availability", "")) == GameConstants.AVAILABILITY_STARTER:
			continue
		pool.append(definition_id)
	return pool


## 等权抽 count 个不同定义（打乱后取前 N；池不足时返回实际数量）。
func _take_distinct(pool: Array, count: int, rng) -> Dictionary:
	if count <= 0 or pool.is_empty():
		return Result.ok([])
	var shuffled: Dictionary = rng.shuffle(GameConstants.RNG_REWARD, pool)
	if not Result.is_ok(shuffled):
		return shuffled
	var ids: Array = shuffled["data"]
	var taken := []
	for index in range(mini(count, ids.size())):
		taken.append(String(ids[index]))
	return Result.ok(taken)


# ── 配置读取 ──────────────────────────────────────────────

func _source_kind(node) -> String:
	if node.kind == RunNodeState.KIND_ELITE:
		return RewardOffer.SOURCE_ELITE
	if node.kind == RunNodeState.KIND_BOSS:
		return RewardOffer.SOURCE_BOSS
	return RewardOffer.SOURCE_NORMAL


## rewards.card_rarity_weights 的组名与来源同名（normal / elite / boss）。
func _weight_group(source_kind: String) -> String:
	return source_kind


func _candidate_count() -> int:
	return _rewards_int("candidate_count", 3)


func _card_weights(group: String) -> Dictionary:
	return _weight_table("card_rarity_weights", group)


func _relic_weights(group: String) -> Dictionary:
	return _weight_table("relic_rarity_weights", group)


func _weight_table(key: String, group: String) -> Dictionary:
	var rewards := catalog.section("rewards")
	var table: Variant = rewards.get(key)
	if typeof(table) != TYPE_DICTIONARY:
		return {}
	var raw: Variant = (table as Dictionary).get(group)
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _rewards_int(key: String, fallback: int) -> int:
	return _int(catalog.section("rewards").get(key), fallback)


## 统一读整数：JSON 里所有数字都是 float，字符串十进制也接受。
func _int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)):
		return int(value)
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return String(value).to_int()
	return fallback
## 可选标签过滤（方向奖励用它把候选限制在与履历方向匹配的卡上）：
## 要求候选命中全部 tags；空 tags 直接返回原池，不做任何过滤。
func _filter_by_tags(pool: Array, tags: Array) -> Array:
	if tags.is_empty():
		return pool
	var filtered := []
	for raw_id in pool:
		var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, String(raw_id))
		var definition_tags: Array = definition.get("tags", [])
		var matched := true
		for tag in tags:
			if not definition_tags.has(tag):
				matched = false
				break
		if matched:
			filtered.append(String(raw_id))
	return filtered