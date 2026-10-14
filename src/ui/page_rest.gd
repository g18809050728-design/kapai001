class_name UiRestPage
extends "res://src/ui/ui_page.gd"
##
## 休息页（《界面层契约》§8）：四选一（恢复 / 升级 / 删负担 / 训练合作牌）。
##
## 视图 = RunView 的 rest 段：{node_id, heal_percent, heal_amount, options:[{option_id, enabled, blocking, needs_card}]}。
## 卡目标选项把牌组画成按钮（一次点击 = 一条 take_rest 草稿），合法目标由 shell 的 preview 门控筛出。
##

const REST_HEAL := "heal"
const REST_UPGRADE := "upgrade"
const REST_REMOVE_BURDEN := "remove_burden"
const REST_TRAIN := "train"


func _render(parent: Node) -> void:
	var raw_rest: Variant = view.get("rest")
	if typeof(raw_rest) != TYPE_DICTIONARY:
		_header(parent, "休息", "当前没有休息节点")
		return
	var rest: Dictionary = raw_rest
	var node_id := String(rest.get("node_id", ""))
	_header(parent, "休息", "恢复 %s%%（+%s 精力），四选一" % [
		str(rest.get("heal_percent", 0)),
		str(rest.get("heal_amount", 0)),
	])
	_text(parent, "精力 %s/%s    钱 %s    牌组 %s 张" % [
		str(view.get("vitality")),
		str(view.get("max_vitality")),
		str(view.get("money")),
		str(view.get("deck_size")),
	])

	for raw_option in (rest.get("options", []) as Array):
		var option: Dictionary = raw_option
		var option_id := String(option.get("option_id", ""))
		_section(parent, "%s（%s）" % [_option_name(option_id), option_id])
		if not bool(option.get("enabled", true)):
			_hint(parent, "不可选：%s" % str(option.get("blocking", [])))
			continue
		if not bool(option.get("needs_card", false)):
			_action_button(parent, "rest:take:%s" % option_id, _option_name(option_id), {
				"type": "take_rest",
				"payload": {"node_id": node_id, "option_id": option_id},
			})
			continue
		var row := _row(parent)
		for raw_card in (view.get("cards", []) as Array):
			var card: Dictionary = raw_card
			var card_id := String(card.get("card_id", ""))
			_action_button(row, "rest:take:%s:%s" % [option_id, card_id],
				"%s" % String(card.get("definition_id", "")),
				{
					"type": "take_rest",
					"payload": {
						"node_id": node_id,
						"option_id": option_id,
						"card_instance_id": card_id,
					},
				})

	_spacer(parent)
	_action_button(parent, "rest:leave", "休息完毕，继续", {
		"type": "leave_node",
		"payload": {"node_id": node_id},
	})


func _option_name(option_id: String) -> String:
	match option_id:
		REST_HEAL:
			return "恢复精力"
		REST_UPGRADE:
			return "升级一张牌"
		REST_REMOVE_BURDEN:
			return "删掉一张负担牌"
		REST_TRAIN:
			return "训练一张合作牌"
	return option_id


func _handle(uid: String) -> void:
	var parts := uid.split(":")
	if parts.size() >= 3 and parts[0] == "rest" and parts[1] == "take":
		var option_id := String(parts[2])
		var payload := {"node_id": _node_id(), "option_id": option_id}
		if parts.size() == 4:
			payload["card_instance_id"] = String(parts[3])
		_submit({"type": "take_rest", "payload": payload})
		return
	if uid == "rest:leave":
		_submit({"type": "leave_node", "payload": {"node_id": _node_id()}})


func _node_id() -> String:
	var rest: Variant = view.get("rest")
	if typeof(rest) != TYPE_DICTIONARY:
		return ""
	return String((rest as Dictionary).get("node_id", ""))