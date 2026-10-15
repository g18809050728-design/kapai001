class_name ShopState
extends RefCounted

var shop_id: String
var node_id: String
var stocks: Array[Dictionary] = []
var removal_count: int


func _init(values: Dictionary = {}) -> void:
	shop_id = str(values.get("shop_id", ""))
	node_id = str(values.get("node_id", ""))
	for stock in values.get("stocks", []):
		stocks.append(stock.duplicate(true))
	removal_count = int(values.get("removal_count", 0))


static func create(values: Dictionary = {}) -> ShopState:
	return ShopState.new(values)


func copy() -> ShopState:
	return ShopState.new(to_dictionary())


func copy_for_write() -> ShopState:
	return copy()


func to_dictionary() -> Dictionary:
	return {
		"shop_id": shop_id,
		"node_id": node_id,
		"stocks": stocks.duplicate(true),
		"removal_count": removal_count
	}


func get_stock(stock_id: String) -> Dictionary:
	for stock in stocks:
		if str(stock.get("stock_id", "")) == stock_id:
			return stock
	return {}
