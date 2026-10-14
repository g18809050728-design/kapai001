class_name UiEndingPage
extends "res://src/ui/ui_page.gd"
##
## 结局选择页（《界面层契约》§11）：整局打赢后，从 view.eligible_endings 里选结局。
##
## 可选项完全来自 RunService.eligible_endings（视图字段 eligible_endings），页面不做任何门槛判断。
##

## 结局 ID 的稳定值（唯一来源是 RunService.ENDING_*；eligible_endings 给的就是这些串）。
const ENDING_GRAD_RECOMMEND := "grad_recommend"
const ENDING_GRAD_EXAM := "grad_exam"
const ENDING_ABROAD := "abroad"
const ENDING_EMPLOYMENT := "employment"
const ENDING_STARTUP := "startup"
const ENDING_FREE := "free_exploration"


func _render(parent: Node) -> void:
	_header(parent, "毕业结局", "四年结束：选一个结局收尾")
	var endings: Array = view.get("eligible_endings", [])
	if endings.is_empty():
		_hint(parent, "当前没有可选结局（需要先赢下最终首领）。")
	for raw_ending in endings:
		var ending_id := String(raw_ending)
		_action_button(parent, "ending:" + ending_id, _ending_name(ending_id), {
			"type": "choose_ending",
			"payload": {"ending_id": ending_id},
		})
	_spacer(parent)
	_action_button(parent, "ending:menu", "回主菜单", {"type": "ui.menu", "payload": {}})


func _ending_name(ending_id: String) -> String:
	match ending_id:
		ENDING_GRAD_RECOMMEND:
			return "保研（%s）" % ending_id
		ENDING_GRAD_EXAM:
			return "考研上岸（%s）" % ending_id
		ENDING_ABROAD:
			return "出国深造（%s）" % ending_id
		ENDING_EMPLOYMENT:
			return "就业（%s）" % ending_id
		ENDING_STARTUP:
			return "创业（%s）" % ending_id
		ENDING_FREE:
			return "自由探索（%s）" % ending_id
	return ending_id


func _handle(uid: String) -> void:
	if uid.begins_with("ending:") and uid != "ending:menu":
		_submit({"type": "choose_ending", "payload": {"ending_id": uid.trim_prefix("ending:")}})
		return
	if uid == "ending:menu":
		_submit({"type": "ui.menu", "payload": {}})