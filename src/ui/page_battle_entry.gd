class_name UiBattleEntryPage
extends "res://src/ui/ui_page.gd"
##
## 战斗入口页（《界面层契约》§9）：RunService 给出 battle_input，战斗界面（t1）接过去打。
##
## 交接契约（与 src/ui/battle 约定）：
##   · shell 在收到 ui.start_battle 时发出 `battle_requested(battle_input)`；
##   · 战斗界面打完调 `shell.apply_battle_outcome(outcome)`（shell 内部走 RunService.settle_battle）；
##   · 没有安装战斗界面时，shell 打开开发回退（引擎代打）——按钮文案会写明。
##
## 本页不碰 BattleState / BattleEngine，只负责把 battle_input 交出去和显示当前局面。
##

func _render(parent: Node) -> void:
	var raw_battle: Variant = view.get("battle")
	if typeof(raw_battle) != TYPE_DICTIONARY:
		_header(parent, "战斗", "当前没有战斗节点")
		return
	var battle: Dictionary = raw_battle
	var raw_input: Variant = view.get("battle_input")
	var has_input := typeof(raw_input) == TYPE_DICTIONARY and not (raw_input as Dictionary).is_empty()
	_header(parent, "战斗节点", "%s" % String(battle.get("encounter_id", "")))
	_text(parent, "节点 %s    精力 %s/%s    战斗 %s" % [
		String(battle.get("battle_id", "")),
		str(view.get("vitality")),
		str(view.get("max_vitality")),
		"已结算" if bool(battle.get("settled", false)) else "未开打",
	])
	_text(parent, "牌组：%s 张    饰品：%s" % [
		str(view.get("deck_size")),
		str((view.get("relics", []) as Array).size()),
	])

	_spacer(parent)
	if has_input:
		var text := "进入战斗"
		if bool(view.get("dev_fallback", false)):
			text = "开发回退：用引擎自动打完这一场"
		_action_button(parent, "battle:start", text, {"type": "ui.start_battle", "payload": {}})
	elif bool(view.get("resume_available", false)):
		_action_button(parent, "battle:resume", "继续未打完的战斗", {"type": "ui.resume_battle", "payload": {}})
	else:
		_hint(parent, "这一场已经结算：奖励处理完后即可离开节点。")
	_action_button(parent, "battle:leave", "离开节点", {
		"type": "leave_node",
		"payload": {"node_id": String(view.get("current_node_id", ""))},
	})
	var row := _row(parent)
	_action_button(row, "battle:save", "保存进度", {"type": "ui.save", "payload": {}})
	_action_button(row, "battle:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


func _handle(uid: String) -> void:
	match uid:
		"battle:start":
			_submit({"type": "ui.start_battle", "payload": {}})
		"battle:resume":
			_submit({"type": "ui.resume_battle", "payload": {}})
		"battle:leave":
			_submit({"type": "leave_node", "payload": {"node_id": String(view.get("current_node_id", ""))}})
		"battle:save":
			_submit({"type": "ui.save", "payload": {}})
		"battle:menu":
			_submit({"type": "ui.menu", "payload": {}})