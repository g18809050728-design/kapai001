class_name UiRewardPage
extends "res://src/ui/ui_page.gd"
##
## 奖励页（《界面层契约》§5）：把 view.pending_reward 的每个 item 处理掉后才能离开节点。
##
## 视图 = RunView（用 pending_reward / relics / relic_slots / current_node_id）。
## 候选在生成时已冻结，页面只把 item.candidates 画成按钮，不做任何抽取或过滤。
## 饰品槽满时先选一个要替换的旧饰品（本地选择），再把 replace_relic_id 放进草稿；
## 没选之前 RunService.preview 会要求 replace_relic_id，shell 门控自然把「领取」按钮禁用。
##

var _replace: Dictionary = {}


func _render(parent: Node) -> void:
	var raw_offer: Variant = view.get("pending_reward")
	if typeof(raw_offer) != TYPE_DICTIONARY:
		_header(parent, "奖励", "当前没有待处理奖励")
		return
	var offer: Dictionary = raw_offer
	_header(parent, "奖励结算", "来源：%s    本场直接收益：+%s 元" % [
		String(offer.get("source_kind", "")),
		str(offer.get("money", 0)),
	])
	var offer_id := String(offer.get("offer_id", ""))
	var relic_full := (view.get("relics", []) as Array).size() >= int(view.get("relic_slots", 0))

	for raw_item in (offer.get("items", []) as Array):
		var item: Dictionary = raw_item
		var item_id := String(item.get("item_id", ""))
		var status := String(item.get("status", ""))
		_section(parent, "%s 奖励" % ("卡牌" if String(item.get("kind", "")) == "card" else "饰品"))
		if status != "pending":
			_hint(parent, "已处理：%s（%s）" % [status, String(item.get("chosen_id", ""))])
			continue
		var candidates: Array = item.get("candidates", [])
		if candidates.is_empty():
			_hint(parent, "候选为空（已按规则折算为钱，无需选择）")
		elif candidates.size() == 1:
			_action_button(parent, "reward:%s:claim" % item_id, "领取 %s" % String(candidates[0]),
				Callable(self, "claim_draft").bind(offer_id, item_id, String(candidates[0]), relic_full))
		else:
			var row := _row(parent)
			for raw_candidate in candidates:
				var candidate_id := String(raw_candidate)
				_action_button(row, "reward:%s:pick:%s" % [item_id, candidate_id],
					"领取 %s" % candidate_id,
					Callable(self, "claim_draft").bind(offer_id, item_id, candidate_id, relic_full))
		if String(item.get("kind", "")) == "relic" and relic_full:
			_hint(parent, "饰品槽已满：先选一个要替换的旧饰品。")
			var replace_row := _row(parent)
			for raw_relic in (view.get("relics", []) as Array):
				var relic: Dictionary = raw_relic
				var relic_id := String(relic.get("relic_id", ""))
				var text := "替换 %s（槽 %s）" % [String(relic.get("definition_id", "")), str(relic.get("slot", ""))]
				if String(_replace.get(item_id, "")) == relic_id:
					text = "▶ " + text
				_local_button(replace_row, "reward:%s:replace:%s" % [item_id, relic_id], text)
		if bool(item.get("skippable", true)):
			_action_button(parent, "reward:%s:skip" % item_id, "跳过这一项", {
				"type": "skip_reward",
				"payload": {"offer_id": offer_id, "item_id": item_id},
			})

	_spacer(parent)
	if bool(offer.get("complete", false)):
		_action_button(parent, "reward:leave", "处理完毕，继续", {
			"type": "leave_node",
			"payload": {"node_id": String(view.get("current_node_id", ""))},
		})
	else:
		_hint(parent, "还有未处理的奖励项：处理完才能离开节点。")


## 领取草稿；饰品槽满时必须带上 replace_relic_id（没选就不带，交给门控拦住）。
func claim_draft(offer_id: String, item_id: String, candidate_id: String, relic_full: bool) -> Dictionary:
	var payload := {"offer_id": offer_id, "item_id": item_id, "candidate_id": candidate_id}
	if relic_full:
		var replace_id := String(_replace.get(item_id, ""))
		if not replace_id.is_empty():
			payload["replace_relic_id"] = replace_id
	return {"type": "claim_reward", "payload": payload}


func _handle(uid: String) -> void:
	var parts := uid.split(":")
	if parts.size() >= 3 and parts[0] == "reward" and parts[1] != "":
		var item_id := String(parts[1])
		var offer: Variant = view.get("pending_reward")
		var offer_id := String((offer as Dictionary).get("offer_id", "")) if typeof(offer) == TYPE_DICTIONARY else ""
		if parts.size() == 3 and String(parts[2]) == "claim":
			_submit({"type": "claim_reward", "payload": {
				"offer_id": offer_id, "item_id": item_id,
				"candidate_id": String(_single_candidate(item_id)),
			}})
			return
		if parts.size() == 3 and String(parts[2]) == "skip":
			_submit({"type": "skip_reward", "payload": {"offer_id": offer_id, "item_id": item_id}})
			return
		if parts.size() == 4 and String(parts[2]) == "pick":
			_submit({"type": "claim_reward", "payload": {
				"offer_id": offer_id, "item_id": item_id, "candidate_id": String(parts[3]),
			}})
			return
		if parts.size() == 4 and String(parts[2]) == "replace":
			_replace[item_id] = String(parts[3])
			_selection_changed()
			return
	if uid == "reward:leave":
		_submit({"type": "leave_node", "payload": {"node_id": String(view.get("current_node_id", ""))}})


func _single_candidate(item_id: String) -> String:
	var offer: Variant = view.get("pending_reward")
	if typeof(offer) != TYPE_DICTIONARY:
		return ""
	for raw_item in ((offer as Dictionary).get("items", []) as Array):
		var item: Dictionary = raw_item
		if String(item.get("item_id", "")) == item_id:
			var candidates: Array = item.get("candidates", [])
			return "" if candidates.is_empty() else String(candidates[0])
	return ""