class_name ShopState
extends RefCounted
##
## 商店（《数据库与实体关系设计》§5 ShopState / StockItem；《统一设计文档》§10.1）。
##
## 库存与价格在进入节点、生成商店时冻结（RewardGenerator.generate_shop 用 reward 流），
## 售出不补；重新打开界面不重抽。交易整体校验后一次性应用（TransactionResolver）。
##

const RunCopy := preload("res://src/run/run_copy.gd")

const STOCK_CARD := "card"
const STOCK_RELIC := "relic"
const STOCK_MEAL := "meal"
const STOCK_KINDS: Array[String] = [STOCK_CARD, STOCK_RELIC, STOCK_MEAL]


class StockItem:
	var stock_id: String = ""
	var kind: String = "card"
	## 餐食没有内容定义，留空串。
	var definition_id: String = ""
	var price: int = 0
	var sold: bool = false
	## 餐食 {"heal": 12}；卡/饰品留空。
	var meta: Dictionary = {}


var shop_id: String = ""
var node_id: String = ""
var stocks: Array = []
## 本商店已使用的删牌次数（每店上限 shop.removals_per_shop）。
## 全局删牌价格递增看 RunState.removals_used（事件删卡不增加商店费用）。
var removal_count: int = 0


static func create(p_shop_id: String, p_node_id: String) -> ShopState:
	var shop: ShopState = load("res://src/run/run_shop_state.gd").new()
	shop.shop_id = p_shop_id
	shop.node_id = p_node_id
	return shop


static func create_stock(p_stock_id: String, p_kind: String, p_definition_id: String, p_price: int) -> StockItem:
	var stock := StockItem.new()
	stock.stock_id = p_stock_id
	stock.kind = p_kind
	stock.definition_id = p_definition_id
	stock.price = p_price
	return stock


func add_stock(p_stock_id: String, p_kind: String, p_definition_id: String, p_price: int) -> StockItem:
	var stock := create_stock(p_stock_id, p_kind, p_definition_id, p_price)
	stocks.append(stock)
	return stock


func find_stock(stock_id: String) -> StockItem:
	for raw_stock in stocks:
		var stock: StockItem = raw_stock
		if stock.stock_id == stock_id:
			return stock
	return null


## 「同类别同名不重复」：生成库存时用它去重（同样品 ID 在同类里只能有一件）。
func has_definition(kind: String, definition_id: String) -> bool:
	if definition_id.is_empty():
		return false
	for raw_stock in stocks:
		var stock: StockItem = raw_stock
		if stock.kind == kind and stock.definition_id == definition_id:
			return true
	return false


func copy_for_write() -> ShopState:
	var copied: ShopState = create(shop_id, node_id)
	copied.removal_count = removal_count
	for raw_stock in stocks:
		var stock: StockItem = raw_stock
		var stock_copy := create_stock(stock.stock_id, stock.kind, stock.definition_id, stock.price)
		stock_copy.sold = stock.sold
		stock_copy.meta = RunCopy.dictionary(stock.meta)
		copied.stocks.append(stock_copy)
	return copied