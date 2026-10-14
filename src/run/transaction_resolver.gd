class_name TransactionResolver
extends RefCounted
##
## 交易解析（《类与方法设计》§4 TransactionResolver；《接口文档》§5）。
##
## 一次交易 = prepare（读状态、收齐成本与收益、全部校验）→ apply（在工作副本上整体应用）。
## prepare 不改状态、不消费随机，可以直接给 preview 用；价格由本类从 rulesets 现算，
## UI 自报的价格一律不采信。取消交易停留在 UI，不调用 submit，因此不扣钱。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const ShopState := preload("res://src/run/run_shop_state.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")

const PLAN_BUY := "buy"
const PLAN_REMOVE := "remove"

var catalog: ContentDB = null


func _init(catalog_ref = null) -> void:
	catalog = catalog_ref


func set_catalog(catalog_ref) -> void:
	catalog = catalog_ref


## Result<TransactionPlan>。未知操作返回 INVALID_ARGUMENT。
func prepare(run, action: Dictionary) -> Dictionary:
	var action_type := String(action.get("type", ""))
	var payload: Variant = action.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.transaction.missing_payload", {})
	if action_type == GameConstants.ACTION_BUY_ITEM:
		return _prepare_buy(run, payload)
	if action_type == GameConstants.ACTION_REMOVE_CARD:
		return _prepare_removal(run, payload)
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.transaction.unknown_action", {
		"type": action_type,
	})


## Result<RunState>：整体应用 plan（调用方已经 prepare 通过，这里只做兜底检查）。
func apply(run, plan: Dictionary) -> Dictionary:
	var kind := String(plan.get("kind", ""))
	if kind == PLAN_BUY:
		return _apply_buy(run, plan)
	if kind == PLAN_REMOVE:
		return _apply_removal(run, plan)
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.transaction.unknown_plan", {})


# ── 购买 ──────────────────────────────────────────────────

## Result<int>：商店实际成交价 = 冻结标价 + 饰品 shop_price hook（A15 校园卡等）。
## 卡牌与饰品受影响；餐食与删牌费不受影响（《统一设计文档》§8 A15）。
## 展示（_shop_view）与购买校验必须用同一个报价函数，否则界面价与扣钱会不一致。
func quote_price(run, stock) -> int:
	var base := int(stock.price)
	if catalog == null or run == null or base <= 0:
		return base
	var price := base
	for relic in run.relics:
		var definition: Dictionary = catalog.definition(GameConstants.KIND_RELIC, String(relic.definition_id))
		var hooks: Variant = definition.get("hooks")
		if typeof(hooks) != TYPE_ARRAY:
			continue
		for raw_hook in (hooks as Array):
			var hook: Dictionary = raw_hook
			if String(hook.get("at", "")) != GameConstants.HOOK_SHOP_PRICE:
				continue
			if not (hook.get("kinds", []) as Array).has(String(stock.kind)):
				continue
			var percent := maxi(1, int(hook.get("multiplier_percent", 100)))
			var scaled := float(price) * float(percent) / 100.0
			if String(hook.get("rounding", "ceil")) == "floor":
				price = int(floor(scaled))
			else:
				price = int(ceil(scaled))
	return maxi(0, price)


func _prepare_buy(run, payload: Dictionary) -> Dictionary:
	var shop_result := _current_shop(run)
	if not Result.is_ok(shop_result):
		return shop_result
	var shop = shop_result["data"]
	var stock_id := String(payload.get("stock_id", ""))
	var stock = shop.find_stock(stock_id)
	if stock == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_stock", {"stock_id": stock_id})
	if stock.sold:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.shop.stock_sold", {"stock_id": stock_id})
	var price := quote_price(run, stock)
	if run.money < price:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.shop.not_enough_money", {
			"needed": price,
			"have": run.money,
		})
	var plan := {
		"kind": PLAN_BUY,
		"node_id": run.current_node_id,
		"shop_id": shop.shop_id,
		"stock_id": stock_id,
		"price": price,
		"base_price": int(stock.price),
		"money_after": run.money - price,
	}
	if stock.kind == ShopState.STOCK_CARD:
		var card_definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, stock.definition_id)
		if card_definition.is_empty():
			return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.shop.unknown_card", {
				"definition_id": stock.definition_id,
			})
		plan["card_definition_id"] = stock.definition_id
		return Result.ok(plan)
	if stock.kind == ShopState.STOCK_RELIC:
		return _prepare_relic_buy(run, stock, plan, payload)
	if stock.kind == ShopState.STOCK_MEAL:
		plan["heal"] = _int(stock.meta.get("heal"), 0)
		return Result.ok(plan)
	return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.shop.unknown_stock_kind", {
		"kind": stock.kind,
	})


func _prepare_relic_buy(run, stock, plan: Dictionary, payload: Dictionary) -> Dictionary:
	var definition: Dictionary = catalog.definition(GameConstants.KIND_RELIC, stock.definition_id)
	if definition.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.shop.unknown_relic", {
			"definition_id": stock.definition_id,
		})
	# 同局同名饰品唯一（《数据库与实体关系设计》§5）
	if run.has_relic_definition(stock.definition_id):
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.shop.relic_owned", {
			"definition_id": stock.definition_id,
		})
	var relic_slots: int = catalog.run_int("relic_slots", 6)
	var replace_id := String(payload.get("replace_relic_id", ""))
	if run.relics.size() >= relic_slots:
		if replace_id.is_empty():
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {
				"relic_slots": relic_slots,
			})
		if run.find_relic(replace_id) == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {
				"relic_id": replace_id,
			})
		plan["replace_relic_id"] = replace_id
	elif not replace_id.is_empty():
		if run.find_relic(replace_id) == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {
				"relic_id": replace_id,
			})
		plan["replace_relic_id"] = replace_id
	plan["relic_definition_id"] = stock.definition_id
	return Result.ok(plan)


func _apply_buy(run, plan: Dictionary) -> Dictionary:
	var shop_result := _current_shop(run)
	if not Result.is_ok(shop_result):
		return shop_result
	var shop = shop_result["data"]
	var stock = shop.find_stock(String(plan.get("stock_id", "")))
	if stock == null or stock.sold:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.shop.stock_sold", {})
	var price := int(plan.get("price", 0))
	if run.money < price:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.shop.not_enough_money", {
			"needed": price,
			"have": run.money,
		})
	run.money -= price
	stock.sold = true
	if plan.has("card_definition_id"):
		run.add_card(String(plan["card_definition_id"]), 0, "shop")
	elif plan.has("relic_definition_id"):
		var definition_id := String(plan["relic_definition_id"])
		var acquired_order: int = run.relics.size() + 1
		if plan.has("replace_relic_id"):
			if run.replace_relic(String(plan["replace_relic_id"]), definition_id, acquired_order) == null:
				return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {})
		else:
			if run.equip_relic(definition_id, catalog.run_int("relic_slots", 6), acquired_order) == null:
				return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {})
	elif plan.has("heal"):
		run.vitality = mini(run.max_vitality, run.vitality + int(plan["heal"]))
	return Result.ok(run)
# ── 删牌 ──────────────────────────────────────────────────

func _prepare_removal(run, payload: Dictionary) -> Dictionary:
	var shop_result := _current_shop(run)
	if not Result.is_ok(shop_result):
		return shop_result
	var shop = shop_result["data"]
	var card_instance_id := String(payload.get("card_instance_id", ""))
	if run.find_card(card_instance_id) == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_card_instance", {
			"card_instance_id": card_instance_id,
		})
	var shop_rules := catalog.section("shop")
	var max_per_shop := _int(shop_rules.get("removals_per_shop"), 1)
	if shop.removal_count >= max_per_shop:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.removal_used", {
			"max": max_per_shop,
		})
	var minimum: int = catalog.run_int("minimum_deck_size", 5)
	if run.cards.size() <= minimum:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.deck_minimum", {
			"minimum": minimum,
			"size": run.cards.size(),
		})
	var price := removal_price(run)
	if run.money < price:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.shop.not_enough_money", {
			"needed": price,
			"have": run.money,
		})
	return Result.ok({
		"kind": PLAN_REMOVE,
		"node_id": run.current_node_id,
		"shop_id": shop.shop_id,
		"card_instance_id": card_instance_id,
		"price": price,
		"money_after": run.money - price,
	})


## 删牌价格现算：首删 60，之后每次 +20（run.removals_used 是全局计数；事件删卡不增加）。
func removal_price(run) -> int:
	var shop_rules := catalog.section("shop")
	return _int(shop_rules.get("first_removal_price"), 60) + _int(shop_rules.get("removal_price_increment"), 20) * run.removals_used


func _apply_removal(run, plan: Dictionary) -> Dictionary:
	var shop_result := _current_shop(run)
	if not Result.is_ok(shop_result):
		return shop_result
	var shop = shop_result["data"]
	var card_instance_id := String(plan.get("card_instance_id", ""))
	if run.find_card(card_instance_id) == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_card_instance", {})
	var minimum: int = catalog.run_int("minimum_deck_size", 5)
	if run.cards.size() <= minimum:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.deck_minimum", {})
	var price := int(plan.get("price", 0))
	if run.money < price:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.shop.not_enough_money", {})
	if not run.remove_card(card_instance_id):
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_card_instance", {})
	run.money -= price
	shop.removal_count += 1
	run.removals_used += 1
	return Result.ok(run)


# ── 工具 ──────────────────────────────────────────────────

## 当前节点必须是已生成库存的商店。Result<ShopState>。
func _current_shop(run) -> Dictionary:
	var node = run.current_node()
	if node == null or node.kind != RunNodeState.KIND_SHOP or node.status != RunNodeState.STATUS_ACTIVE:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.shop.no_shop_node", {})
	var shop = node.context.get("shop")
	if shop == null:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.shop.not_generated", {})
	return Result.ok(shop)


func _int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)):
		return int(value)
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return String(value).to_int()
	return fallback