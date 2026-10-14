class_name UiEventPage
extends "res://src/ui/ui_page.gd"
##
## 事件页（《界面层契约》§7）：把 view.event.options 画成可点项。
##
## 需要玩家选择的事件选项（带目标的收益）在视图里已经给出「这个选项的冻结候选」；
## 页面按 RunService 的 op 名决定画哪种选择控件（选卡 / 选候选饰品 / 选替换目标），
## 但**不判断合法性**：提交时 RunService 会整项校验，shell 也会先用 preview 禁用非法按钮。
##

## RunService.EV_OP_* 的稳定值（内容 JSON 的唯一写法）。
const OP_UPGRADE_CARD := "upgrade_card"
const OP_REMOVE_CARD := "remove_card"
const OP_GAIN_CARD := "gain_card"
const OP_GAIN_RELIC := "gain_relic"

var _replace: Dictionary = {}


func _render(parent: Node) -> void:
	var raw_event: Variant = view.get("event")
	if typeof(raw_event) != TYPE_DICTIONARY:
		_header(parent, "突发事件", "当前没有事件")
		return
	var event: Dictionary = raw_event
	_header(parent, "突发事件", "%s（%s）" % [
		String(event.get("name_key", "")),
		String(event.get("definition_id", "")),
	])
	var resolved := String(event.get("resolved_option_id", ""))
	if not resolved.is_empty():
		_hint(parent, "已选择：%s。可以离开节点了。" % resolved)

	for raw_option in (event.get("options", []) as Array):
		var option: Dictionary = raw_option
		var option_id := String(option.get("option_id", ""))
		_section(parent, "选项 %s" % option_id)
		_text(parent, "%s    成本：%s" % [String(option.get("label_key", "")), _cost_text(option.get("cost"))])
		if not bool(option.get("enabled", true)):
			_hint(parent, "不可选：%s" % str(option.get("blocking", [])))
		if String(event.get("resolved_option_id", "")) == option_id:
			_hint(parent, "（已选过这一项）")
			continue
		_render_option_buttons(parent, option)

	_spacer(parent)
	_action_button(parent, "event:leave", "离开事件", {
		"type": "leave_node",
		"payload": {"node_id": String(view.get("current_node_id", ""))},
	})


func _render_option_buttons(parent: Node, option: Dictionary) -> void:
	var option_id := String(option.get("option_id", ""))
	var disabled := not bool(option.get("enabled", true)) or not (option.get("blocking", []) as Array).is_empty()
	var target_cards := _card_targets(option)
	var replace_relic_id := String(_replace.get(option_id, ""))
	var candidates: Array = option.get("candidates", [])
	var needs_candidate := _needs_candidate_pick(option, candidates)

	if not target_cards.is_empty():
		var row := _row(parent)
		for raw_target in target_cards:
			var target: Dictionary = raw_target
			var card_id := String(target.get("card_id", ""))
			var button := _action_button(row, "event:%s:card:%s" % [option_id, card_id],
				"选 %s" % String(target.get("label", card_id)),
				Callable(self, "option_draft").bind(option_id, [card_id]))
			if disabled:
				button.disabled = true
				_reasons[String(button.get_meta("uid"))] = "选项不可选"
		return
	if needs_candidate:
		var row2 := _row(parent)
		for raw_candidate in candidates:
			var candidate_id := String(raw_candidate)
			var button := _action_button(row2, "event:%s:pick:%s" % [option_id, candidate_id],
				"选 %s" % candidate_id,
				Callable(self, "option_draft").bind(option_id, [candidate_id]))
			if disabled:
				button.disabled = true
				_reasons[String(button.get_meta("uid"))] = "选项不可选"
		if bool(view.get("event", {}).get("relic_slots_full", false)) and _needs_replace(option):
			_hint(parent, "饰品槽已满：先选一个要替换的旧饰品。")
			var replace_row := _row(parent)
			for raw_relic in (view.get("relics", []) as Array):
				var relic: Dictionary = raw_relic
				var relic_id := String(relic.get("relic_id", ""))
				var text := "替换 %s" % String(relic.get("definition_id", ""))
				if relic_id == replace_relic_id:
					text = "▶ " + text
				_local_button(replace_row, "event:%s:replace:%s" % [option_id, relic_id], text)
		return
	var button := _action_button(parent, "event:%s" % option_id, "选择这一项", Callable(self, "option_draft").bind(option_id, []))
	if disabled:
		button.disabled = true
		_reasons[String(button.get_meta("uid"))] = "选项不可选"


func option_draft(option_id: String, selection_ids: Array) -> Dictionary:
	var payload := {"option_id": option_id}
	if not selection_ids.is_empty():
		payload["selection_ids"] = selection_ids.duplicate()
	var replace_relic_id := String(_replace.get(option_id, ""))
	if not replace_relic_id.is_empty():
		payload["replace_relic_id"] = replace_relic_id
	return {"type": "choose_event", "payload": payload}


## 该选项现在可以选哪些卡：优先用规则层给的 selection_candidates（卡实例 ID + 展示名），
## 字段缺失时回退到「扫 effects + 画整副牌」，让 shell 的门控去挡非法目标。
func _card_targets(option: Dictionary) -> Array:
	var out := []
	var raw_targets: Variant = option.get("selection_candidates", [])
	if typeof(raw_targets) == TYPE_ARRAY and not (raw_targets as Array).is_empty():
		for raw_target in (raw_targets as Array):
			if typeof(raw_target) == TYPE_DICTIONARY:
				var entry: Dictionary = raw_target
				out.append({"card_id": String(entry.get("card_id", "")), "label": String(entry.get("label", entry.get("card_id", "")))})
			else:
				out.append({"card_id": String(raw_target), "label": String(raw_target)})
		return out
	if not _needs_card_pick(option):
		return out
	for raw_card in (view.get("cards", []) as Array):
		var card: Dictionary = raw_card
		out.append({"card_id": String(card.get("card_id", "")), "label": String(card.get("definition_id", ""))})
	return out


func _needs_card_pick(option: Dictionary) -> bool:
	for raw_effect in (option.get("effects", []) as Array):
		var op := String((raw_effect as Dictionary).get("op", ""))
		if op == OP_UPGRADE_CARD or op == OP_REMOVE_CARD:
			return true
	return false


func _needs_candidate_pick(option: Dictionary, candidates: Array) -> bool:
	if candidates.size() <= 1:
		return false
	for raw_effect in (option.get("effects", []) as Array):
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if op == OP_GAIN_CARD and not effect.has("card_id"):
			return true
		if op == OP_GAIN_RELIC and not effect.has("relic_id"):
			return true
	return false


func _needs_replace(option: Dictionary) -> bool:
	for raw_effect in (option.get("effects", []) as Array):
		if String((raw_effect as Dictionary).get("op", "")) == OP_GAIN_RELIC:
			return true
	return false


func _cost_text(raw_cost: Variant) -> String:
	if typeof(raw_cost) != TYPE_DICTIONARY:
		return "无"
	var cost: Dictionary = raw_cost
	if cost.is_empty():
		return "无"
	return flatten(cost)


func _handle(uid: String) -> void:
	var parts := uid.split(":")
	if parts.size() < 2 or String(parts[0]) != "event":
		return
	if parts.size() == 2:
		var single := String(parts[1])
		if single == "leave":
			_submit({"type": "leave_node", "payload": {"node_id": String(view.get("current_node_id", ""))}})
			return
		## 不需要选择的选项（effects 为空或收益无目标）：一次点击直接选它。
		_submit(option_draft(single, []))
		return
	if parts.size() == 4:
		var option_id := String(parts[1])
		var kind := String(parts[2])
		var value := String(parts[3])
		if kind == "card" or kind == "pick":
			_submit(option_draft(option_id, [value]))
			return
		if kind == "replace":
			_replace[option_id] = value
			_selection_changed()
			return

