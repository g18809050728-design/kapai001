class_name UiTermPage
extends "res://src/ui/ui_page.gd"
##
## 学期结算页（《界面层契约》§10）：方向奖励（可跳过）+ 第 5 学期前的履历方向（不可跳过）。
##
## 视图 = RunView 的 settlement 段：{settlement_id, term, complete, current_step_id,
##   steps:[{step_id, kind, status, candidates, skippable, chosen_id}]}。
## 一次点击 = 一条 choose_term_option 草稿；完成最后一步后 RunService 自动进入下一学期。
##

const STEP_DIRECTION_REWARD := "direction_reward"
const STEP_CAREER_TRACK := "career_track"


func _render(parent: Node) -> void:
	var raw_settlement: Variant = view.get("settlement")
	if typeof(raw_settlement) != TYPE_DICTIONARY:
		_header(parent, "学期结算", "当前没有结算")
		return
	var settlement: Dictionary = raw_settlement
	var settlement_id := String(settlement.get("settlement_id", ""))
	_header(parent, "第 %s 学期结算" % str(settlement.get("term")), "结算完成后进入下一学期")
	_text(parent, "精力 %s/%s    钱 %s    牌组 %s 张" % [
		str(view.get("vitality")),
		str(view.get("max_vitality")),
		str(view.get("money")),
		str(view.get("deck_size")),
	])
	var current_step_id := String(settlement.get("current_step_id", ""))
	for raw_step in (settlement.get("steps", []) as Array):
		var step: Dictionary = raw_step
		var step_id := String(step.get("step_id", ""))
		var kind := String(step.get("kind", ""))
		var status := String(step.get("status", ""))
		_section(parent, "%s（%s）%s" % [_step_name(kind), step_id, "✓ 已完成" if status == "done" else ""])
		if status == "done":
			_hint(parent, "结果：%s" % String(step.get("chosen_id", "")))
			continue
		if step_id != current_step_id:
			_hint(parent, "等前一步处理完。")
			continue
		_render_step_buttons(parent, settlement_id, step)

	_spacer(parent)
	_action_button(parent, "term:menu", "回主菜单（进度已自动保存）", {"type": "ui.menu", "payload": {}})


func _render_step_buttons(parent: Node, settlement_id: String, step: Dictionary) -> void:
	var step_id := String(step.get("step_id", ""))
	var kind := String(step.get("kind", ""))
	var candidates: Array = step.get("candidates", [])
	if kind == STEP_DIRECTION_REWARD:
		var row := _row(parent)
		for raw_candidate in candidates:
			var candidate_id := String(raw_candidate)
			_action_button(row, "term:%s:choose:%s" % [step_id, candidate_id],
				"拿 %s" % candidate_id,
				{"type": "choose_term_option", "payload": {
					"settlement_id": settlement_id,
					"step_id": step_id,
					"option_id": "choose",
					"candidate_id": candidate_id,
				}})
		if bool(step.get("skippable", false)):
			_action_button(parent, "term:%s:skip" % step_id, "跳过（不要这张牌）", {
				"type": "choose_term_option",
				"payload": {"settlement_id": settlement_id, "step_id": step_id, "option_id": "skip"},
			})
		return
	if kind == STEP_CAREER_TRACK:
		var row2 := _row(parent)
		for raw_track in candidates:
			var track := String(raw_track)
			_action_button(row2, "term:%s:track:%s" % [step_id, track], _track_name(track), {
				"type": "choose_term_option",
				"payload": {
					"settlement_id": settlement_id,
					"step_id": step_id,
					"option_id": track,
				},
			})
		return
	_hint(parent, "未知步骤类型：%s" % kind)


func _step_name(kind: String) -> String:
	match kind:
		STEP_DIRECTION_REWARD:
			return "方向奖励"
		STEP_CAREER_TRACK:
			return "履历方向"
	return kind


func _track_name(track: String) -> String:
	match track:
		"research":
			return "科研"
		"competition":
			return "竞赛"
		"internship":
			return "实习"
		"graduate":
			return "升学"
	return track


func _handle(uid: String) -> void:
	var parts := uid.split(":")
	if parts.size() >= 3 and parts[0] == "term":
		var settlement: Variant = view.get("settlement")
		var settlement_id := ""
		if typeof(settlement) == TYPE_DICTIONARY:
			settlement_id = String((settlement as Dictionary).get("settlement_id", ""))
		var step_id := String(parts[1])
		if String(parts[2]) == "skip":
			_submit({"type": "choose_term_option", "payload": {
				"settlement_id": settlement_id, "step_id": step_id, "option_id": "skip",
			}})
			return
		if parts.size() == 4 and String(parts[2]) == "choose":
			_submit({"type": "choose_term_option", "payload": {
				"settlement_id": settlement_id, "step_id": step_id,
				"option_id": "choose", "candidate_id": String(parts[3]),
			}})
			return
		if parts.size() == 4 and String(parts[2]) == "track":
			_submit({"type": "choose_term_option", "payload": {
				"settlement_id": settlement_id, "step_id": step_id, "option_id": String(parts[3]),
			}})
			return
	if uid == "term:menu":
		_submit({"type": "ui.menu", "payload": {}})