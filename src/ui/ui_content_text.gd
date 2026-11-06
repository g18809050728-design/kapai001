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
			if effects.size() == 1 and effects[0].get("op", "") == "modify_erosion_window":
				parts.append("轮末侵蚀自然结算%s次，每次减1层" % int(effects[0].get("times", 1)))
				continue
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
	return _describe_card(detail, false)


static func describe_battle_card(detail: Dictionary) -> String:
	return _describe_card(_normalize_battle_numbers(detail), true)


static func _describe_card(detail: Dictionary, battle_explanation: bool) -> String:
	if detail.is_empty():
		return "卡牌详情暂不可用"
	var lines: PackedStringArray = []
	var target := str(detail.get("target", "self"))
	lines.append(
		(
			"%s · 专注 %s%s · %s"
			% [
				UiStyle.label(str(detail.get("type", ""))),
				str(_battle_display_number(detail.get("cost", 0))) if battle_explanation else detail.get("cost", 0),
				(
					" · 精力 %s" % (str(_battle_display_number(detail.vitality_cost)) if battle_explanation else detail.vitality_cost)
					if int(detail.get("vitality_cost", 0)) > 0
					else ""
				),
				{"task": "选择一个任务", "self": "自身", "all_tasks": "所有任务", "unit": "选择一位同学"}.get(
					target, UiStyle.label(target)
				)
			]
		)
	)
	var requirements := _describe_battle_conditions(detail.get("requirements", [])) if battle_explanation else UiStyle.describe_conditions(detail.get("requirements", []))
	if not requirements.is_empty():
		lines.append(("打出前提：" if battle_explanation else "使用条件：") + requirements)
	if not detail.get("pre_effects", []).is_empty():
		if battle_explanation:
			lines.append("先执行：")
			lines.append_array(_battle_effect_steps(detail.pre_effects, target))
		else:
			lines.append("先执行：" + UiStyle.describe_effects(detail.pre_effects))
	if not detail.get("effects", []).is_empty():
		if battle_explanation:
			lines.append("打出后按顺序结算：")
			lines.append_array(_battle_effect_steps(detail.effects, target))
		else:
			lines.append(UiStyle.describe_effects(detail.effects))
	var flags: Dictionary = detail.get("flags", {})
	if bool(flags.get("retain", detail.get("retain", false))):
		lines.append("保留：轮末留在手牌")
	if bool(flags.get("innate", false)):
		lines.append("固有：进入开局手牌")
	var ability: Dictionary = detail.get("ability", {})
	if not ability.is_empty():
		if battle_explanation:
			lines.append("持续能力：" + ("从下回合开始生效" if ability.get("activate", "next_round") == "next_round" else "打出后立即生效") + ("；同名能力不叠加" if ability.get("stack", "unique_name") == "unique_name" else ""))
		else:
			lines.append("持续能力：" + ("从下回合生效" if ability.get("activate", "next_round") == "next_round" else "立即生效") + "；同名不叠加" )
		var condition := _describe_battle_condition(ability.get("condition", {})) if battle_explanation else UiStyle.describe_condition(ability.get("condition", {}))
		if not condition.is_empty():
			lines.append("触发条件：" + condition)
		for trigger in ability.get("triggers", []):
			var effects: Array = trigger.get("upgrade_effects", trigger.get("effects", [])) if int(detail.get("upgrade_level", 0)) > 0 else trigger.get("effects", [])
			if battle_explanation:
				lines.append("触发时机：" + trigger_name(str(trigger.get("on", ""))))
				lines.append_array(_battle_effect_steps(effects, "earliest_task"))
				var trigger_limit := _describe_trigger_limit(trigger, effects)
				if not trigger_limit.is_empty():
					lines.append(trigger_limit)
			else:
				lines.append(trigger_name(str(trigger.get("on", ""))) + "：" + UiStyle.describe_effects(effects))
				lines.append("每回合两次" if str(trigger.get("limit", "")) == "twice_per_turn" or effects.any(func(effect): return effect.get("limit", "") == "twice_per_turn") else "每回合一次")
		if not ability.get("extra_effects", []).is_empty():
			if battle_explanation:
				lines.append("触发后追加：")
				lines.append_array(_battle_effect_steps(ability.extra_effects, "earliest_task"))
			else:
				lines.append("触发成功后追加：" + UiStyle.describe_effects(ability.extra_effects))
	var chapter: Dictionary = detail.get("chapter", {})
	if not chapter.is_empty():
		var resident: Dictionary = chapter.get("upgraded_resident", chapter.get("resident", {})) if int(detail.get("upgrade_level", 0)) > 0 else chapter.get("resident", {})
		if battle_explanation:
			lines.append("章节常驻：从下回合起，每次准备阶段按槽位顺序自动运行，不再支付这张牌的费用。")
			lines.append_array(_battle_effect_steps(resident.get("effects", []), "earliest_task"))
		else:
			lines.append("章节常驻：从下回合生效；准备阶段按槽位顺序运行，不重复支付出牌费用。")
			lines.append(UiStyle.describe_effects(resident.get("effects", [])))
	if bool(detail.get("unplayable", false)):
		lines.append("不可主动打出")
	if bool(detail.get("exhaust", false)):
		lines.append("消耗：使用后本场战斗不再回到牌堆")
	var limit := _describe_battle_limits(detail) if battle_explanation else describe_limit(detail.get("limit", {}))
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
			if battle_explanation:
				lines.append("场景每次准备阶段生效：")
				lines.append_array(_battle_effect_steps(scene.prepare_effects))
			else:
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
		if not battle_explanation:
			lines.append("考试替代效果：" + UiStyle.describe_effects(detail.exam_effects))
	if battle_explanation:
		var glossary := _battle_keyword_help("\n".join(lines))
		if not glossary.is_empty():
			lines.append("名词解释：")
			lines.append_array(glossary)
	return "\n".join(lines)


static func _battle_effect_steps(effects: Array, default_target: String = "task") -> PackedStringArray:
	var lines := PackedStringArray()
	for index in effects.size():
		var effect: Variant = effects[index]
		if effect is Dictionary:
			lines.append("%s. %s" % [index + 1, _describe_battle_effect(effect, default_target)])
	return lines


static func _describe_battle_effect(effect: Dictionary, default_target: String = "task") -> String:
	var readable_effect: Dictionary = _normalize_battle_numbers(effect)
	var condition: Variant = readable_effect.get("condition", {})
	var bonus: Dictionary = readable_effect.get("bonus", {})
	var bonus_if: Dictionary = readable_effect.get("bonus_if", {})
	readable_effect.erase("condition")
	readable_effect.erase("bonus")
	readable_effect.erase("bonus_if")
	for key in ["then", "if_spent", "after"]:
		readable_effect.erase(key)
	var operation := str(readable_effect.get("op", ""))
	if not readable_effect.has("target") and operation in ["complete", "status_complete", "apply_status", "trigger_induced"]:
		readable_effect["target"] = default_target
	var phrase := _battle_effect_action(readable_effect)
	if phrase == operation or phrase.is_empty():
		phrase = "特殊效果（详细说明待补）"
	if condition is Dictionary and not condition.is_empty():
		phrase = "仅当%s时：%s；条件不满足则跳过这一步" % [_describe_battle_condition(condition), phrase]
	if not bonus.is_empty():
		var bonus_condition := _describe_battle_condition(bonus.get("condition", {}))
		var same_segment := bool(bonus.get("same_segment", false))
		var bonus_text := "额外 +%s" % bonus.get("amount", 0)
		if operation == "complete":
			bonus_text = "额外完成量 +%s" % bonus.get("amount", 0)
		if same_segment:
			bonus_text += "，与基础值合并为同一段完成量"
		phrase += "；若%s，本次%s" % [bonus_condition, bonus_text]
	if not bonus_if.is_empty():
		phrase += "；%s时额外 +%s" % [_describe_bonus_if(bonus_if), bonus_if.get("amount", 0)]
	if readable_effect.has("segment"):
		phrase = "第%s段：%s" % [readable_effect.get("segment", 0), phrase]
	if bool(readable_effect.get("no_transfer", false)):
		phrase += "；仍作用于同一任务，前一段完成任务后不会转向其他任务"
	for pair in [["then", "随后"], ["if_spent", "成功消耗后"], ["after", "最后"]]:
		var nested: Array = effect.get(pair[0], [])
		if not nested.is_empty():
			phrase += "\n   %s：\n" % pair[1]
			for index in nested.size():
				phrase += "   %s) %s%s" % [index + 1, _describe_battle_effect(nested[index], default_target), "\n" if index < nested.size() - 1 else ""]
	return phrase


static func _battle_effect_action(effect: Dictionary) -> String:
	var op := str(effect.get("op", ""))
	var amount := UiStyle.describe_amount(effect.get("amount", effect.get("stacks", 0)))
	var target := str({"all_tasks": "所有任务", "other_task": "另一个任务", "earliest_task": "最早的任务", "self": "自身", "all": "所有伙伴", "all_eligible": "所有本回合尚未额外行动的伙伴", "one": "所选伙伴"}.get(str(effect.get("target", "task")), "所选任务"))
	var phrase := ""
	match op:
		"complete", "status_complete":
			phrase = "对%s造成%s点%s" % [target, amount, "状态完成量" if op == "status_complete" else "完成量"]
		"relax":
			phrase = "获得%s点放松，用来抵挡压力" % amount
		"draw":
			phrase = "从抽牌堆抽%s张牌加入手牌" % amount
			if effect.get("amount", 0) is Dictionary:
				phrase = "抽取与本次已弃牌数量相同的牌加入手牌"
		"discard":
			phrase = "选择%s%s张手牌放入弃牌堆" % ["至多" if bool(effect.get("up_to", false)) else "", amount]
		"heal":
			phrase = "恢复自身%s点精力，不超过精力上限" % amount
		"gain_focus":
			phrase = "获得%s点专注，可继续支付其他卡牌的费用" % amount
		"lose_vitality":
			phrase = "直接失去%s点精力" % amount
			if bool(effect.get("can_kill", false)):
				phrase += "，精力降到0会失败"
		"apply_status":
			phrase = "给%s施加%s层%s" % [target, UiStyle.describe_amount(effect.get("stacks", 1)), UiStyle.label(str(effect.get("status", "")))]
		"remove_shield":
			phrase = "移除%s至多%s点屏障" % [target, amount]
		"work_bonus_next":
			phrase = "本回合下一张工作牌的首段完成量增加%s点；群体工作只给主目标加值" % amount
		"add_work_bonus":
			phrase = "本次工作牌的首段完成量增加%s点；群体工作只给主目标加值" % amount
		"modify_erosion_window":
			phrase = "轮末任务准备时，侵蚀自然结算改为%s次；每次按当时层数结算，随后减少1层" % effect.get("times", 1)
		"arm_erosion_on_next_draws":
			phrase = "本回合接下来%s次实际抽到牌时，各给所有任务施加%s层侵蚀" % [amount, effect.get("stacks", 1)]
		"trigger_induced":
			phrase = "让%s已有的诱发额外触发一次；仍计入每个任务每回合4次的上限" % target
		"paper_open":
			phrase = "开始一篇新论文，生成或取回「解题发表」到手牌；手牌已满则放入弃牌堆"
		"paper_publish":
			phrase = "按论文当前完成度交付：完成度＝进度×7＋引用×6＋修正，限制在0至100。主目标获得完成度＋10点完成量，其他任务各获得完成度的一半（向下取整）；完成度达到100时，每个目标再增加20点。随后结束论文、清空论文资源，并撤下全部章节"
		"paper_progress":
			phrase = "论文进度增加%s格（最多10格）" % amount
		"paper_modifier":
			phrase = "论文修正增加%s点，影响本篇论文发表时的完成度" % amount
		"paper_amplify":
			phrase = "获得%s层增幅（最多5层），供后续卡牌效果使用" % amount
		"spend_citation":
			phrase = "消耗%s层引用" % amount
		"retain":
			phrase = "选择%s张其他手牌保留，轮末不弃掉这些牌" % amount
		"exhaust_other":
			phrase = "选择%s张其他手牌消耗，本场战斗不再抽到这些牌" % amount
		"swap_chapter_slots":
			phrase = "交换前两个章节的槽位，改变以后自动运行的先后顺序"
		"copy_chapter_to_hand":
			phrase = "复制第一个章节，保留其升级等级，将副本加入手牌；手牌已满则放入弃牌堆"
		"shuffle_draw":
			phrase = "重新洗切当前抽牌堆，改变后续抽取顺序"
		"publication_cost_discount":
			phrase = "下一次「解题发表」的专注费用减少%s点" % amount
		"spend_synergy":
			phrase = "消耗%s点协同" % amount
			if bool(effect.get("optional", false)):
				phrase += "；协同足够时自动消耗，不足时跳过本步及其后续收益"
		"spend_synergy_up_to":
			phrase = "消耗当前已有的协同，至多%s点；0点也继续后续效果" % amount
		"spend_all_synergy":
			phrase = "消耗当前全部协同；0点也继续后续效果"
		"partner_retreat":
			phrase = "撤回所选伙伴；没有指定时撤回最早入场的伙伴，不返还召入卡牌"
		"chapter_deploy":
			phrase = "将本牌部署到论文的章节槽；从下回合起按槽位顺序自动运行常驻效果"
		"chapter_run":
			phrase = "让前%s个可额外运行的章节立即执行一次常驻效果；每章每回合最多额外运行一次" % amount
		"partner_heal":
			phrase = "恢复%s%s点精力，不超过伙伴精力上限" % [target, amount]
		"partner_extra_action":
			phrase = "让%s立即额外合作%s次，每次也会消耗伙伴精力；每位伙伴每回合最多额外合作一次" % [target, amount]
		"gain_synergy":
			phrase = "获得%s点协同（最多6点）" % amount
		_:
			return UiStyle.describe_effects([effect])
	for entry in [["per_link_work", "此前本回合已完成的连携工作", 3], ["per_partner", "在场伙伴", 3], ["per_other_chapter", "本次窗口中此前已运行的其他章节", 2], ["per_debuff_kind", "目标身上的一种负面状态", 6]]:
		if effect.has(entry[0]):
			phrase += "；每有一个%s，额外增加%s点，最多计%s个" % [entry[1], effect[entry[0]], effect.get("cap", entry[2])]
			if bool(effect.get("per_target", false)):
				phrase += "，各目标分别计算"
	if effect.has("per_spent"):
		phrase += "；本次每消耗1点协同，额外增加%s点" % effect.per_spent
	var limits := {"once_per_turn": "每回合最多一次", "twice_per_turn": "每回合最多两次", "three_per_turn": "每回合最多三次"}
	if limits.has(str(effect.get("limit", ""))):
		phrase += "；" + str(limits[str(effect.limit)])
	return phrase


static func _normalize_battle_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value:
			normalized[key] = _normalize_battle_numbers(value[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_battle_numbers(item))
		return normalized_array
	return _battle_display_number(value)


static func _battle_display_number(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		var rounded := roundf(number)
		if is_equal_approx(number, rounded):
			return int(rounded)
	return value


static func _describe_bonus_if(bonus: Dictionary) -> String:
	var bonus_data: Dictionary = _normalize_battle_numbers(bonus)
	if bonus_data.has("played_definition"):
		return "本回合打出过「%s」" % UiStyle.label(str(bonus_data.played_definition))
	if bonus_data.has("status"):
		return "场上满足至少%s层%s" % [bonus_data.get("min_stacks", 1), UiStyle.label(str(bonus_data.status))]
	if bonus_data.has("ddl_lte"):
		return "剩余 DDL 不超过%s" % bonus_data.ddl_lte
	return "加成条件成立"


static func _describe_battle_conditions(conditions: Array) -> String:
	var parts := PackedStringArray()
	for condition in conditions:
		var text := _describe_battle_condition(condition)
		if not text.is_empty():
			parts.append(text)
	return "；并且".join(parts)


static func _describe_battle_condition(condition: Variant) -> String:
	if not condition is Dictionary:
		return "满足卡牌条件"
	if condition.is_empty():
		return ""
	var condition_data: Dictionary = _normalize_battle_numbers(condition)
	if condition_data.has("all"):
		return "同时满足：" + _describe_battle_conditions(condition_data.all)
	if condition_data.has("any"):
		var options := PackedStringArray()
		for item in condition_data.any:
			options.append(_describe_battle_condition(item))
		return "满足其一：" + "；或".join(options)
	var kind := str(condition_data.get("kind", ""))
	var value: Variant = condition_data.get("value", "")
	var labels := {
		"link": "上一张成功打出的牌是策略牌，当前牌是工作牌（形成连携）",
		"link_work_resolved": "连携中的工作牌刚结算完成",
		"paper_progress_gained": "刚获得论文进度",
		"paper_name_turn_unused": "本回合还没有打出过这个牌名",
		"two_tasks": "场上至少有两个任务",
		"prev_card_type_is": "上一张成功打出的牌是%s牌" % UiStyle.label(str(value)),
		"hand_other_min": "手牌中除当前牌外至少有%s张可选牌" % condition_data.get("value", 1),
		"no_strategy_played_turn": "本回合还没有打出策略牌",
		"instance_plays_battle": "这张具体卡牌本场战斗已成功打出至少%s次" % condition_data.get("min", 1),
		"instance_played_before": "这张具体卡牌本场战斗已成功打出过",
		"previous_strategy_plays_min": "上一张策略牌的这个副本本场战斗已成功打出至少%s次" % value,
		"retrieved_strategy_this_turn": "本回合已触发被动取回策略牌的机会（手牌满时也算）",
		"paid_citation_focus_this_turn": "本回合曾为引用支付额外专注",
		"base_cost_min": "这张牌的基础专注费用至少%s" % value,
		"card_discarded_this_effect": "这张牌前面的效果已经弃掉至少一张手牌",
		"passive_retrieve_success": "刚刚成功触发被动取回",
		"target_status_kinds": "目标身上不同种类的负面状态数在%s至%s之间" % [condition_data.get("min", 0), condition_data.get("max", 6)],
		"target_has_any_timed_debuff": "目标有易伤、虚弱或脆化",
		"target_has_induced": "目标有诱发",
		"target_had_induced_at_play_start": "打出本牌时目标已经有诱发",
		"any_task_has_induced": "至少一个任务有诱发",
		"any_task_debuff_kinds_min": "至少一个任务有%s种不同负面状态" % value,
		"erosion_applied_events_min": "本回合已成功施加侵蚀至少%s次" % value,
		"first_induced_trigger": "本回合首次触发诱发",
		"compound_reaction_success": "复合反应刚刚成功触发",
		"prepare_window": "当前正处于准备阶段",
		"paper_open": "已经开题",
		"paper_closed": "还没有开题",
		"paper_name_unused": "这个牌名在本篇论文中还没有记过",
		"paper_name_used": "这个牌名已经记入本篇论文",
		"paper_progress_min": "论文进度至少%s" % value,
		"chapter_count_min": "场上至少有%s个章节" % value,
		"other_chapter_ran_window": "本次章节结算中，已有其他章节先运行",
		"citation_min": "引用层数至少%s" % value,
		"synergy_min": "协同至少%s" % value,
		"synergy_is_zero": "协同为0",
		"partner_count_min": "场上至少有%s位伙伴" % value,
		"no_partner": "场上没有伙伴",
		"ddl_lte": "剩余 DDL 不超过%s" % value,
		"independent_exam": "当前是独立作答考试面",
		"fixed_exam_room": "当前是固定考场考试面",
		"first_cooperation_resolved": "本回合首张合作牌刚结算完成",
		"played_type_count_turn": "本回合已成功打出至少%s张%s牌" % [condition_data.get("min", 1), UiStyle.label(str(condition_data.get("card_type", condition_data.get("value", ""))))],
		"target_has_status": "目标有%s" % UiStyle.label(str(condition_data.get("status", "状态"))),
		"target_still_alive": "目标在前面的效果结算后仍存活",
		"healed_partner_turn": "本回合治疗过伙伴",
		"summoned_partner_turn": "本回合召入过伙伴"
	}
	if labels.has(kind):
		return str(labels[kind])
	var fallback := UiStyle.describe_condition(condition_data)
	return fallback if not fallback.is_empty() else "满足卡牌标示的触发条件"


static func _describe_trigger_limit(trigger: Dictionary, effects: Array) -> String:
	var limits := {
		"once_per_turn": "每回合最多触发一次",
		"twice_per_turn": "每回合最多触发两次",
		"three_per_turn": "每回合最多触发三次"
	}
	var trigger_limit := str(trigger.get("limit", ""))
	if limits.has(trigger_limit):
		return str(limits[trigger_limit])
	for effect in effects:
		if not effect is Dictionary:
			continue
		var effect_limit := str(effect.get("limit", ""))
		if limits.has(effect_limit):
			return str(limits[effect_limit])
	return "每回合最多触发一次"


static func _describe_battle_limits(detail: Dictionary) -> String:
	var parts := PackedStringArray()
	var limit: Dictionary = detail.get("limit", {})
	if not limit.is_empty():
		var period := str(limit.get("per", "battle"))
		var times := int(limit.get("times", 1))
		match period:
			"round":
				parts.append("这张牌每回合最多打出%s次" % times)
			"instance_round":
				parts.append("这张卡牌副本每回合最多打出%s次；同名的其他副本各自计数" % times)
			_:
				parts.append("这张牌整场战斗最多打出%s次" % times)
	var limits: Dictionary = detail.get("limits", {})
	var instance_limit := int(limits.get("per_instance_per_turn", 0))
	if instance_limit > 0:
		parts.append("这个卡牌副本每回合最多打出%s次" % instance_limit)
	return "\n".join(parts)


static func _battle_keyword_help(text: String) -> PackedStringArray:
	var glossary := [
		["专注", "支付卡牌费用的资源，每回合准备时恢复。"],
		["完成量", "减少当前任务阶段的未完成量；任务屏障会先吸收完成量。"],
		["放松", "用于吸收轮末压力。"],
		["连携", "当前工作牌前一张成功打出的牌是策略牌。"],
		["屏障", "任务的防护值；工作完成量会先经过屏障。"],
		["消耗", "这张牌在本场战斗中移出抽牌与弃牌循环。"],
		["保留", "轮末仍留在手牌，不进入弃牌堆。"],
		["实例", "指手牌里的这一张具体卡牌副本；同名的其他副本分别计次。"],
		["侵蚀", "轮末进入任务准备阶段时，按当前层数产生状态完成量，随后减少1层。"],
		["诱发", "后续成功出牌按出牌前已有层数触发状态完成量；每个任务每回合最多触发4次，行动结束时清除。"],
		["易伤", "只提高直接工作牌完成量，不增强状态、伙伴或章节自动完成量。"],
		["虚弱", "使该任务每段压力乘0.75并向下取整。"],
		["脆化", "该任务新获得的屏障减半并向下取整。"],
		["乏力", "每层使该任务每段压力减少1点，最低减到0。"],
		["协同", "唐以宁的合作资源，上限6；部分卡牌检查数量，部分卡牌消耗它获得收益。"],
		["论文进度", "本篇论文的积累，上限10格；发表时每格计7点完成度。"],
		["引用", "论文资源，上限5层；发表时每层计6点完成度，第3/4/5层需额外支付1/2/3专注。"],
		["增幅", "上限5层；下一次符合条件的手动卡牌数值效果增加相应数值，随后清空；章节自动运行不消耗。"],
		["章节", "论文区最多放3章，通常从部署的下回合起按槽位顺序自动运行；发表会撤下全部章节。"],
		["取回", "把符合条件的牌从弃牌堆放回手牌；再次打出仍须支付费用，原有限次不重置。"],
		["状态完成量", "由任务状态产生的完成量，不受易伤或工作牌加值影响。"]
	]
	var lines := PackedStringArray()
	for entry in glossary:
		if str(entry[0]) == "消耗" and not text.contains("消耗：") and not text.contains("张其他手牌消耗"):
			continue
		if text.contains(str(entry[0])):
			lines.append("%s：%s" % [entry[0], entry[1]])
	return lines


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
