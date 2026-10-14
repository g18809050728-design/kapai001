class_name UiShopPage
extends "res://src/ui/ui_page.gd"
##
## 商店页（《界面层契约》§6）：库存冻结（view.shop.stocks），价格/删牌次数来自视图。
##
## 购买与删牌都是「一次点击 = 一条 buy_item / remove_card 草稿」，可用性由 shell 用
## RunService.preview 门控（钱不够 / 已卖出 / 删牌次数用完 / 牌组触底都会直接禁用按钮）。
##

func _render(parent: Node) -> void:
	var raw_shop: Variant = view.get("shop")
	if typeof(raw_shop) != TYPE_DICTIONARY:
		_header(parent, "商店", "当前没有商店")
		return
	var shop: Dictionary = raw_shop
	_header(parent, "商店", "钱 %s    节点 %s" % [str(view.get("money")), String(shop.get("node_id", ""))])

	_section(parent, "货架")
	for raw_stock in (shop.get("stocks", []) as Array):
		var stock: Dictionary = raw_stock
		var stock_id := String(stock.get("stock_id", ""))
		var row := _row(parent)
		var text := "%s %s  %s 元" % [
			String(stock.get("kind", "")),
			String(stock.get("definition_id", "")),
			str(stock.get("price", 0)),
		]
		if bool(stock.get("sold", false)):
			text += "（已卖出）"
		_text(row, text)
		if not bool(stock.get("sold", false)):
			_action_button(row, "shop:buy:" + stock_id, "购买", {
				"type": "buy_item",
				"payload": {"stock_id": stock_id},
			})

	var removal: Dictionary = shop.get("removal", {})
	_section(parent, "删牌服务")
	_hint(parent, "价格 %s 元    已用 %s/%s    牌组 %s 张（下限 %s）" % [
		str(removal.get("price", 0)),
		str(removal.get("used", 0)),
		str(removal.get("max", 0)),
		str(removal.get("deck_size", 0)),
		str(removal.get("minimum_deck_size", 0)),
	])
	for raw_card in (view.get("cards", []) as Array):
		var card: Dictionary = raw_card
		var card_id := String(card.get("card_id", ""))
		var row2 := _row(parent)
		_text(row2, "%s（%s）" % [String(card.get("definition_id", "")), card_id])
		_action_button(row2, "shop:remove:" + card_id, "删掉这张", {
			"type": "remove_card",
			"payload": {"card_instance_id": card_id},
		})

	_spacer(parent)
	_action_button(parent, "shop:leave", "离开商店", {
		"type": "leave_node",
		"payload": {"node_id": String(shop.get("node_id", ""))},
	})


func _handle(uid: String) -> void:
	if uid.begins_with("shop:buy:"):
		_submit({"type": "buy_item", "payload": {"stock_id": uid.trim_prefix("shop:buy:")}})
		return
	if uid.begins_with("shop:remove:"):
		_submit({"type": "remove_card", "payload": {"card_instance_id": uid.trim_prefix("shop:remove:")}})
		return
	if uid == "shop:leave":
		var shop: Variant = view.get("shop")
		var node_id := ""
		if typeof(shop) == TYPE_DICTIONARY:
			node_id = String((shop as Dictionary).get("node_id", ""))
		_submit({"type": "leave_node", "payload": {"node_id": node_id}})