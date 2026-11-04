class_name UiContentText
extends RefCounted


static func describe_card(detail: Dictionary) -> String:
	if detail.is_empty():
		return "卡牌详情暂不可用"
	var lines: PackedStringArray = []
	var target := str(detail.get("target", "self"))
	lines.append(
		(
			"%s · 专注 %s%s · %s"
			% [
				UiStyle.label(str(detail.get("type", ""))),
				detail.get("cost", 0),
				(
					" · 精力 %s" % detail.vitality_cost
					if int(detail.get("vitality_cost", 0)) > 0
					else ""
				),
				{"task": "选择一个任务", "self": "自身", "all_tasks": "所有任务", "unit": "选择一位同学"}.get(
					target, UiStyle.label(target)
				)
			]
		)
	)
	if not detail.get("pre_effects", []).is_empty():
		lines.append("先执行：" + UiStyle.describe_effects(detail.pre_effects))
	if not detail.get("effects", []).is_empty():
		lines.append(UiStyle.describe_effects(detail.effects))
	if bool(detail.get("unplayable", false)):
		lines.append("不可主动打出")
	if bool(detail.get("exhaust", false)):
		lines.append("消耗：使用后本场战斗不再回到牌堆")
	var limit := describe_limit(detail.get("limit", {}))
	if not limit.is_empty():
		lines.append(limit)
	for unit in detail.get("related_units", {}).values():
		lines.append(
			(
				"%s：精力 %s · 合作值 %s%s"
				% [
					UiStyle.label(str(unit.id)),
					unit.get("vitality", 0),
					unit.get("cooperation", 0),
					" · 护卫" if unit.get("guard", false) else ""
				]
			)
		)
		var support: Dictionary = unit.get("support", {})
		match str(support.get("kind", "none")):
			"cleanse_or_relax":
				lines.append(
					(
						"支援：移除%s %s 层；没有时放松 %s"
						% [
							UiStyle.label(str(support.get("status", ""))),
							support.get("amount", 0),
							support.get("fallback_relax", 0)
						]
					)
				)
			"self_relax":
				lines.append("支援：同学自身放松 %s" % support.get("amount", 0))
	for scene in detail.get("related_scenes", {}).values():
		if not scene.get("prepare_effects", []).is_empty():
			lines.append("每回合准备：" + UiStyle.describe_effects(scene.prepare_effects))
		var options: Array = scene.get("prepare_random", {}).get("options", [])
		if not options.is_empty():
			var names: PackedStringArray = []
			for effects in options:
				names.append(UiStyle.describe_effects(effects))
			lines.append("每回合准备时随机一项：" + "；".join(names))
		var discount := int(scene.get("modifiers", {}).get("first_work_cost_discount", 0))
		if discount > 0:
			lines.append("每回合首张作业牌专注费用 -%s" % discount)
		if scene.has("battle_limit"):
			lines.append("每场战斗最多触发 %s 次" % scene.battle_limit)
	if detail.has("exam_effects"):
		lines.append("考试替代效果：" + UiStyle.describe_effects(detail.exam_effects))
	return "\n".join(lines)


static func describe_limit(limit: Dictionary) -> String:
	if limit.is_empty():
		return ""
	var period := str(limit.get("per", "battle"))
	return (
		"%s限 %s 次"
		% [
			{"round": "每回合", "instance_round": "每张牌每回合", "battle": "每场战斗"}.get(period, period),
			limit.get("times", 1)
		]
	)


static func describe_relic(detail: Dictionary) -> String:
	if detail.is_empty():
		return "饰品详情暂不可用"
	var lines: PackedStringArray = []
	var work_bonus := int(detail.get("modifiers", {}).get("work_flat_bonus", 0))
	if work_bonus > 0:
		lines.append("作业牌完成量 +%s；%s" % [work_bonus, describe_limit(detail.get("limit", {}))])
	for hook in detail.get("hooks", []):
		var trigger := str(hook.get("at", ""))
		var prefix := str(
			(
				{
					"round_start": "玩家准备阶段",
					"draw": "基础抽牌后",
					"cost_quote": "费用报价",
					"card_resolved": "牌结算后",
					"before_status_gain": "每战首次获得困倦前",
					"work_segment": "工作牌完成量结算时",
					"unit_action_completed": "合作单位行动完成后",
					"stage_entered": "任务完成并进入下一阶段后",
					"shop_price": "商店购买"
				}
				. get(trigger, trigger)
			)
		)
		if hook.has("rounds"):
			prefix += "（第 %s 回合）" % "/".join(hook.rounds.map(func(value): return str(value)))
		if hook.has("card_type"):
			var card_type := str(hook.card_type)
			prefix += "·" + ("工作" if card_type == "work" else UiStyle.label(card_type)) + "牌"
		if hook.has("definition_id"):
			prefix += "·" + UiStyle.label(str(hook.definition_id))
		if hook.has("status") and trigger != "before_status_gain":
			prefix += "·" + UiStyle.label(str(hook.status))
		if hook.get("first_work_card", false):
			prefix += "·本回合首张工作牌"
		if hook.has("segment_index"):
			prefix += "·第 %s 段" % (int(hook.segment_index) + 1)
		if hook.has("max_ddl"):
			prefix += "·DDL≤%s" % hook.max_ddl
		var effects := UiStyle.describe_effects(hook.get("effects", []))
		if hook.has("prevent_stacks"):
			effects = "抵消 %s 层" % hook.prevent_stacks
		if hook.has("completion_bonus"):
			effects = "完成量 +%s" % hook.completion_bonus
		if hook.has("discount"):
			effects += "专注费用 -%s" % hook.discount
			if hook.get("require_actual_discount", false):
				effects += "（仅实际减免时计次）"
		if hook.get("skip_vitality_cost", false):
			effects += "免除精力费用"
		if hook.has("multiplier_percent"):
			effects += "卡牌与饰品价格为原价 %s%%（向上取整）" % hook.multiplier_percent
		var limit := describe_limit(hook.get("limit", {}))
		lines.append(prefix + "：" + effects + ("；" + limit if not limit.is_empty() else ""))
	return "\n".join(lines)
