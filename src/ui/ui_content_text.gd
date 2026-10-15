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
					"round_start": "回合开始",
					"draw": "抽牌阶段",
					"cost_quote": "打出",
					"card_resolved": "打出后",
					"shop_price": "商店购买"
				}
				. get(trigger, trigger)
			)
		)
		if hook.has("rounds"):
			prefix += "（第 %s 回合）" % "/".join(hook.rounds.map(func(value): return str(value)))
		if hook.has("card_type"):
			prefix += "·" + UiStyle.label(str(hook.card_type)) + "牌"
		if hook.has("definition_id"):
			prefix += "·" + UiStyle.label(str(hook.definition_id))
		var effects := UiStyle.describe_effects(hook.get("effects", []))
		if hook.has("discount"):
			effects += "专注费用 -%s" % hook.discount
		if hook.get("skip_vitality_cost", false):
			effects += "免除精力费用"
		if hook.has("multiplier_percent"):
			effects += "卡牌与饰品价格为原价 %s%%（向上取整）" % hook.multiplier_percent
		var limit := describe_limit(hook.get("limit", {}))
		lines.append(prefix + "：" + effects + ("；" + limit if not limit.is_empty() else ""))
	return "\n".join(lines)
