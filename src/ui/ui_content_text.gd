class_name UiContentText
extends RefCounted


static func describe_character_passive(passive_id: String) -> String:
	match passive_id:
		"r3_p01_link_replay":
			return "被动 · 步骤复用\n每回合首次合法的“策略→工作”连携后，自动从弃牌堆取回前一张永久策略，费用与限次不变；满手仍消耗机会。当前尚无放弃取回选择。"
		"r3_p02_paper_record":
			return "被动 · 论文记录\n开题后，本篇首次使用的牌名使进度 +1（上限 10），重复牌名尝试获得引用 +1（上限 5）。第 3/4/5 层引用额外支付 1/2/3 专注；不足则改抽 1 张。"
		"r3_p03_compound_reaction":
			return "被动 · 复合反应\n每回合一次：卡牌主效果在已有其他负面的任务上新施加一种负面，结算后使该新负面额外 +1 层；仅成功加层才消耗机会。"
		"r3_p04_teamwork":
			return "被动 · 分工默契\n每回合首张合作牌结算后，协同 +1、放松 +2；协同上限 6，考试替代面同样触发。本次获得的协同不能支付该牌费用。"
	return ""


static func card_summary(detail: Dictionary) -> String:
	var result := UiStyle.describe_effects(detail.get("effects", []))
	var ability: Dictionary = detail.get("ability", {})
	if not ability.is_empty():
		var parts: PackedStringArray = ["下回合起" if ability.get("activate", "next_round") == "next_round" else "立即生效"]
		for trigger in ability.get("triggers", []):
			var effects: Array = trigger.get("upgrade_effects", trigger.get("effects", [])) if int(detail.get("upgrade_level", 0)) > 0 else trigger.get("effects", [])
			if str(trigger.get("on", "")) == "erosion_applied_event" and effects.size() == 1 and effects[0].get("op", "") == "status_complete" and effects[0].get("target", "") == "all_tasks":
				var condition: Dictionary = effects[0].get("condition", {})
				if condition.get("kind", "") == "erosion_applied_events_min":
					parts.append("本回合施加侵蚀达%s次后，全体状态完成量%s；每回合一次" % [condition.get("value", 3), effects[0].get("amount", 0)])
					continue
			parts.append(trigger_name(str(trigger.get("on", ""))) + "：" + UiStyle.describe_effects(effects))
		result += ("\n" if not result.is_empty() else "") + "；".join(parts)
	var chapter: Dictionary = detail.get("chapter", {})
	if result.is_empty() and not chapter.is_empty():
		var resident: Dictionary = chapter.get("upgraded_resident", chapter.get("resident", {})) if int(detail.get("upgrade_level", 0)) > 0 else chapter.get("resident", {})
		result = "章节 · 下回合起：" + UiStyle.describe_effects(resident.get("effects", []))
	return result


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
	var requirements := UiStyle.describe_conditions(detail.get("requirements", []))
	if not requirements.is_empty():
		lines.append("使用条件：" + requirements)
	var flags: Dictionary = detail.get("flags", {})
	if bool(flags.get("retain", false)):
		lines.append("保留：轮末留在手牌")
	if bool(flags.get("innate", false)):
		lines.append("固有：进入开局手牌")
	var ability: Dictionary = detail.get("ability", {})
	if not ability.is_empty():
		lines.append("持续能力：" + ("从下回合生效" if ability.get("activate", "next_round") == "next_round" else "立即生效") + "；同名不叠加" )
		var condition := UiStyle.describe_condition(ability.get("condition", {}))
		if not condition.is_empty():
			lines.append("触发条件：" + condition)
		for trigger in ability.get("triggers", []):
			var effects: Array = trigger.get("upgrade_effects", trigger.get("effects", [])) if int(detail.get("upgrade_level", 0)) > 0 else trigger.get("effects", [])
			lines.append(trigger_name(str(trigger.get("on", ""))) + "：" + UiStyle.describe_effects(effects))
			lines.append("每回合两次" if str(trigger.get("limit", "")) == "twice_per_turn" or effects.any(func(effect): return effect.get("limit", "") == "twice_per_turn") else "每回合一次")
		if not ability.get("extra_effects", []).is_empty():
			lines.append("触发成功后追加：" + UiStyle.describe_effects(ability.extra_effects))
	var chapter: Dictionary = detail.get("chapter", {})
	if not chapter.is_empty():
		var resident: Dictionary = chapter.get("upgraded_resident", chapter.get("resident", {})) if int(detail.get("upgrade_level", 0)) > 0 else chapter.get("resident", {})
		lines.append("章节常驻：从下回合生效；准备阶段按槽位顺序运行，不重复支付出牌费用。")
		lines.append(UiStyle.describe_effects(resident.get("effects", [])))
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
		lines.append("正常合作：轮末对最早任务合作，随后自身精力 -1；精力耗尽退场。")
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


static func trigger_name(id: String) -> String:
	return str({"prepare": "准备阶段", "round_start": "回合开始", "link_work_resolved": "连携工作结算后", "paper_progress_gained": "获得论文进度后", "first_work_card_resolving": "本回合首张工作牌结算时", "first_cooperation_resolved": "本回合首张合作牌结算后", "card_resolved": "卡牌结算后", "work_resolved": "工作牌结算后", "work_card_resolved": "工作牌结算后", "strategy_resolved": "策略牌结算后", "chapter_window_end": "章节窗口结束后", "passive_retrieve_success": "被动成功取回后", "passive_retrieved": "被动取回后", "first_unused_permanent_card_resolved": "本回合首张本篇未用永久牌结算后", "paper_name_unused": "使用本篇新牌名后", "partner_healed": "治疗伙伴后", "partner_summoned": "召入伙伴后", "erosion_applied_event": "成功施加侵蚀后", "erosion_gained": "施加侵蚀后", "induced_trigger": "诱发触发后", "induced_triggered": "触发诱发后", "compound_reaction_success": "复合反应成功后", "passive_rule": "被动规则"}.get(id, UiStyle.label(id)))


static func keyword_help(detail: Dictionary) -> String:
	var text := describe_card(detail)
	var terms := {"专注": "专注：支付卡牌费用，每回合准备时恢复。", "放松": "放松：抵挡压力，按轮末与准备时序结算。", "连携": "连携：前一张已结算牌为策略，本张为工作。", "章节": "章节：进入论文槽位，按槽序在准备阶段运行。", "侵蚀": "侵蚀：按规则在轮末结算完成量，再衰减。", "消耗": "消耗：本场战斗移出普通抽弃循环。"}
	var result: PackedStringArray = []
	for term in terms:
		if text.contains(term):
			result.append(terms[term])
	return "\n".join(result)


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
	if detail.get("campaign") is Dictionary:
		var campaign: Dictionary = detail.campaign
		var labels := {"event_money": "每次完成事件：金钱 +%d", "rest_heal": "每次完成休息：额外恢复 %d 精力", "service_discount": "图书馆/导师/实验室服务费用 -%d（最低0）", "service_money": "社团/实习经济选项：额外金钱 +%d", "elite_money": "每次精英胜利：额外金钱 +%d", "battle_money": "每次普通/精英胜利：额外金钱 +%d"}
		lines.append(str(labels.get(campaign.get("effect", ""), "地图收益 +%d")) % int(campaign.get("amount", 0)))
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
