class_name UiMapPage
extends "res://src/ui/ui_page.gd"
##
## 地图页（《界面层契约》§4）：一学期 6 层、8 个节点（第 2/4 层二选一分支）。
##
## 视图就是 RunService.make_view 的 RunView。可达性只读 view.reachable_node_ids：
## 页面把所有节点都画出来（含不可达的），但每个节点按钮的可用性由 shell 用
## RunService.preview(enter_node) 统一门控 —— 所以点击不可达节点在界面上就是 disabled，
## 页面自身不做任何边计算，也不自行放行。
##

const RunNodeState := preload("res://src/run/run_node_state.gd")


func _render(parent: Node) -> void:
	_header(parent, "第 %s 学期 / 共 %s 学期" % [str(view.get("term")), str(view.get("term_count"))],
		"0 精力 = 学期失败；精力与钱按节点逐步消耗")
	_text(parent, "精力 %s/%s    钱 %s    牌组 %s 张    饰品 %s/%s    已删牌 %s" % [
		str(view.get("vitality")),
		str(view.get("max_vitality")),
		str(view.get("money")),
		str(view.get("deck_size")),
		str((view.get("relics", []) as Array).size()),
		str(view.get("relic_slots")),
		str(view.get("removals_used")),
	])
	var hint := String(view.get("tutorial_hint", ""))
	if not hint.is_empty():
		_hint(parent, hint)
	var reachable: Array = view.get("reachable_node_ids", [])
	var nodes: Array = view.get("nodes", [])
	if reachable.is_empty():
		_hint(parent, "本层没有可达节点：请检查内容清单（遭遇/事件池是否为空）。")

	var layers := {}
	for raw_node in nodes:
		var node: Dictionary = raw_node
		var layer := int(node.get("layer", 0))
		if not layers.has(layer):
			layers[layer] = []
		(layers[layer] as Array).append(node)
	var layer_ids := layers.keys()
	layer_ids.sort()
	for raw_layer in layer_ids:
		var layer := int(raw_layer)
		_section(parent, "第 %d 层" % layer)
		var row := _row(parent)
		for raw_node in (layers[raw_layer] as Array):
			var node: Dictionary = raw_node
			var node_id := String(node.get("node_id", ""))
			var status := String(node.get("status", ""))
			var text := "%s" % kind_label(String(node.get("kind", "")))
			if status == RunNodeState.STATUS_COMPLETED:
				text += "（已完成）"
			elif status == RunNodeState.STATUS_ACTIVE:
				text += "（当前）"
			elif reachable.has(node_id):
				text += "（可进入）"
			else:
				text += "（不可达）"
			if String(node.get("encounter_id", "")) != "":
				text += " %s" % String(node.get("encounter_id"))
			_action_button(row, "node:" + node_id, text, {
				"type": "enter_node",
				"payload": {"node_id": node_id},
			})
		var next_hint := []
		for raw_node in (layers[raw_layer] as Array):
			var node: Dictionary = raw_node
			next_hint.append("%s → %s" % [String(node.get("kind", "")), str(node.get("next_ids", []))])
		_hint(parent, "   ".join(next_hint))

	_spacer(parent)
	_hint(parent, "已走节点：%s" % str(view.get("node_path", [])))
	var row2 := _row(parent)
	_action_button(row2, "map:tutorial", "教学", {"type": "ui.tutorial", "payload": {}})
	_action_button(row2, "map:rules", "规则", {"type": "ui.rules", "payload": {}})
	var log_button := _action_button(row2, "map:battle_log", "上一场战斗日志", {"type": "ui.battle_log", "payload": {}})
	if not bool(view.get("has_battle_log", false)):
		log_button.disabled = true
		_reasons["map:battle_log"] = "还没有打过战斗"
	_action_button(row2, "map:save", "保存进度", {"type": "ui.save", "payload": {}})
	if _confirm_abandon:
		_action_button(row2, "map:abandon_confirm", "确认放弃本局", {
			"type": "abandon_run",
			"payload": {"confirmed": true},
		})
	else:
		_local_button(row2, "map:abandon", "放弃本局…")
	_action_button(row2, "map:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


var _confirm_abandon: bool = false


func _handle(uid: String) -> void:
	if uid.begins_with("node:"):
		_submit({"type": "enter_node", "payload": {"node_id": uid.trim_prefix("node:")}})
		return
	if uid == "map:tutorial":
		_submit({"type": "ui.tutorial", "payload": {}})
		return
	if uid == "map:rules":
		_submit({"type": "ui.rules", "payload": {}})
		return
	if uid == "map:battle_log":
		_submit({"type": "ui.battle_log", "payload": {}})
		return
	if uid == "map:save":
		_submit({"type": "ui.save", "payload": {}})
		return
	if uid == "map:abandon":
		_confirm_abandon = true
		_selection_changed()
		return
	if uid == "map:abandon_confirm":
		_confirm_abandon = false
		_submit({"type": "abandon_run", "payload": {"confirmed": true}})
		return
	if uid == "map:menu":
		_submit({"type": "ui.menu", "payload": {}})