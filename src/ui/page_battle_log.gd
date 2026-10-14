class_name UiBattleLogPage
extends "res://src/ui/ui_page.gd"
##
## 战斗日志页（t4）：局流程侧的「战斗日志入口」。
##
## 战斗界面里随时能看当场的日志（t1 的日志面板）；这一页是打完之后在局内回看**上一场**的日志，
## 由 shell 在战斗结束时从战斗界面取一次 log_lines() 缓存下来（界面只呈现，不重算规则）。
##
## 视图（shell 组装）：{lines: PackedStringArray, source_node: String, in_run: bool}
##

func _render(parent: Node) -> void:
	var lines: PackedStringArray = view.get("lines", PackedStringArray())
	_header(parent, "战斗日志", "上一场战斗的结算日志（%s）" % String(view.get("source_node", "—")))
	if lines.is_empty():
		_hint(parent, "还没有打过战斗：进入战斗节点并打完一场之后，这里会留下日志。")
	else:
		for raw_line in lines:
			_text(parent, String(raw_line))
	_spacer(parent)
	if bool(view.get("in_run", false)):
		_action_button(parent, "battle_log:back", "回到局内", {"type": "ui.back", "payload": {}})
	_action_button(parent, "battle_log:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


func _handle(uid: String) -> void:
	match uid:
		"battle_log:back":
			_submit({"type": "ui.back", "payload": {}})
		"battle_log:menu":
			_submit({"type": "ui.menu", "payload": {}})