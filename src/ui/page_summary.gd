class_name UiSummaryPage
extends "res://src/ui/ui_page.gd"
##
## 局终摘要页（《界面层契约》§11）：胜利/失败/放弃都走这里；失败重开 = 用同人物同难度换个种子开新局。
##
## 视图 = RunView 的 run_summary 段：{run_id, result, reason, ending_id, character_id, difficulty,
##   term, stats, unlocked_ids}。本页不发规则操作，只发两个 ui.* 导航动作。
##

func _render(parent: Node) -> void:
	var raw_summary: Variant = view.get("run_summary")
	if typeof(raw_summary) != TYPE_DICTIONARY:
		_header(parent, "本局结束", "没有摘要数据")
		return
	var summary: Dictionary = raw_summary
	var result := String(summary.get("result", ""))
	_header(parent, _result_name(result), "原因：%s    第 %s 学期" % [
		_reason_name(String(summary.get("reason", ""))),
		str(summary.get("term")),
	])
	_text(parent, "人物 %s    难度 %s    局 ID %s" % [
		String(summary.get("character_id", "")),
		String(summary.get("difficulty", "")),
		String(summary.get("run_id", "")),
	])
	if String(summary.get("ending_id", "")) != "":
		_text(parent, "结局：%s" % String(summary.get("ending_id", "")))
	_section(parent, "统计")
	var stats: Variant = summary.get("stats")
	if typeof(stats) == TYPE_DICTIONARY:
		_text(parent, flatten(stats))
	var unlocked: Variant = summary.get("unlocked_ids")
	if typeof(unlocked) == TYPE_ARRAY and not (unlocked as Array).is_empty():
		_text(parent, "解锁：%s" % str(unlocked))

	_spacer(parent)
	_hint(parent, "本局摘要已写入 Profile（失败也能攒解锁），继续按钮会开一局新的。")
	var row := _row(parent)
	_action_button(row, "summary:retry", "重开一局", {"type": "ui.retry", "payload": {}})
	_action_button(row, "summary:menu", "回主菜单", {"type": "ui.menu", "payload": {}})
	_action_button(row, "summary:battle_log", "战斗日志", {"type": "ui.battle_log", "payload": {}})


func _result_name(result: String) -> String:
	match result:
		"won":
			return "本局通关"
		"lost":
			return "本局失败"
		"abandoned":
			return "本局已放弃"
	return "本局结束（%s）" % result


func _reason_name(reason: String) -> String:
	match reason:
		"vitality_depleted":
			return "精力归零"
		"deadline_expired":
			return "DDL 超时"
		"tasks_completed":
			return "任务全部完成"
		"abandoned":
			return "主动放弃"
	return reason


func _handle(uid: String) -> void:
	match uid:
		"summary:retry":
			_submit({"type": "ui.retry", "payload": {}})
		"summary:battle_log":
			_submit({"type": "ui.battle_log", "payload": {}})
		"summary:menu":
			_submit({"type": "ui.menu", "payload": {}})

