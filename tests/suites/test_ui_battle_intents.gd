extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	var old_scale := UiStyle.text_scale
	var session := GameSession.new(SaveStore.new("user://enemy-intents-%d" % Time.get_ticks_usec()))
	_check_skill_forecasts(session)
	session.update_settings({"autosave": false, "presentation": {"animation_speed": 0, "reduced_motion": true, "text_scale": 100}})
	var shell: GameShell = _helpers.attach_shell(session)
	var started := session.start_test_room({"character_id": "P01", "encounter_id": "N16", "seed": "42"})
	_check(started.accepted, "start the real four-year N16 encounter")
	if started.accepted:
		shell.refresh()
		await _check_preview(shell, tree)
		_check_catalogue(session.get_compendium())
		session.close_test_room()
		await _check_summon(shell, tree)
		await _check_compendium_page(shell, tree)
	shell.free()
	tree.root.size = old_size
	UiStyle.text_scale = old_scale
	print("BATTLE_INTENT_CHECKS=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures


func _check_preview(shell: GameShell, tree: SceneTree) -> void:
	var session := shell.session
	var page := shell.page as BattleScreen
	var task: Dictionary = page.view.tasks[0]
	var id := str(task.task_id)
	var uid := "detail:task:" + id
	var debuff_uid := "buff:" + id + ":player_reduce_focus"
	var initial_focus := int(page.view.player.focus)
	var original := session.test_service().state.state_hash()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [100, 125, 150]:
			session.update_settings({"presentation": {"text_scale": scale}})
			shell._apply_presentation()
			shell.refresh()
			await _frames(tree)
			var hit := page._buttons.get(uid) as Button
			var label := page.find_child("TaskIntent_" + id.validate_node_name(), true, false) as Label
			_check(hit != null and label != null and label.text == "剩余专注 +2", "N16 preview at %s / %d%%" % [dimensions, scale])
			_check(not page._buttons.has(debuff_uid), "N16 grant does not display a focus penalty")
			if hit == null:
				continue
			var point := hit.get_global_rect().get_center()
			_check(page.get_global_rect().has_point(point), "intent inspection stays on screen")
			_check(hit.get_global_rect().size.y >= 43.9 and not hit.get_global_rect().intersects(page._button_rect("task:" + id)), "intent and target have separate physical hit areas")
			var motion := InputEventMouseMotion.new()
			motion.position = point
			tree.root.push_input(motion, true)
			await _frames(tree)
			_check(page._hover_target.get("uid") == uid and str(page._hover_target.get("body")).contains("结束回合后"), "pointer reads current enemy turn")
			for down in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = down
				click.position = point
				tree.root.push_input(click, true)
			await _frames(tree)
			_check(page._panel_text.contains("惊喜") and page._panel_text.contains("下一轮准备时会重新计算专注"), "click explains current and next-round focus")
			_check(page._panel_text.contains("压力 6 · 剩余专注 −1"), "detail shows the other step in the cycle")
			_check(session.test_service().state.state_hash() == original, "inspection preserves battle state, revision and RNG")
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			tree.root.push_input(escape, true)
			await _frames(tree)
			_check(page._panel_text.is_empty() and tree.root.gui_get_focus_owner() == page._buttons[uid], "Escape returns focus to the intent")
	var inspect := InputEventKey.new()
	inspect.keycode = KEY_I
	inspect.pressed = true
	tree.root.push_input(inspect, true)
	await _frames(tree)
	_check(page._panel_text.contains("惊喜"), "I opens the focused intent details")
	page._close_panel()
	await _frames(tree)
	var last_vitality := int(page.view.player.vitality)
	for expected_delta in [2, -1]:
		var turn := session.submit_test_action(shell._test_context(), {"type": "end_turn", "payload": {}})
		_check(turn.accepted, "end turn uses the real battle command")
		if not turn.accepted:
			return
		var focus_events := turn.events.filter(func(event: RuleEvent): return event.type == &"focus_changed")
		_check(focus_events.size() >= 2 and focus_events[0].data.get("delta") == expected_delta and focus_events[1].data.get("reason") == "player_prepare", "enemy focus change precedes player focus reset")
		shell.refresh()
		await _frames(tree)
		_check(int(page.view.player.focus) == initial_focus, "focus returns to standard amount")
		if expected_delta > 0:
			_check(int(page.view.player.vitality) == last_vitality, "first intent does not attack")
			_check(page._task_intent_text(page.view.tasks[0]) == "压力 6 · 剩余专注 −1", "second intent shows both effects")
			var slot := page._buttons.get(debuff_uid) as BattleStatusSlot
			_check(slot != null and slot.entry.count == "−1", "the source task forecasts a one-point focus penalty")
			_check(page.press(debuff_uid) and page._panel_text.contains("特殊机制 · 本轮意图") and page._panel_text.contains("下一轮准备时会重新计算专注"), "focus penalty slot explains the timing")
			if not page._panel_text.is_empty():
				page._close_panel()
				await _frames(tree)
		else:
			_check(int(page.view.player.vitality) == last_vitality - 6, "second intent applies the shown pressure")
			_check(page._task_intent_text(page.view.tasks[0]) == "剩余专注 +2", "third turn cycles back to first intent")
			_check(not page._buttons.has(debuff_uid), "the expired focus forecast disappears on the next round")


func _check_summon(shell: GameShell, tree: SceneTree) -> void:
	var session := shell.session
	var started := session.start_test_room({"character_id": "P01", "encounter_id": "FY_B1", "seed": "42"})
	_check(started.accepted, "start the real FY_B1 encounter")
	if not started.accepted:
		return
	shell.refresh()
	await _frames(tree)
	var page := shell.page as BattleScreen
	var task: Dictionary = page.view.tasks[0]
	_check(page._task_intent_text(task).contains("召唤 数学基础 ×1，带嘲讽"), "boss preview prioritizes its upcoming taunting summon")
	var summon_uid := "buff:" + str(task.task_id) + ":summon_tasks"
	var summon := page._buttons.get(summon_uid) as BattleStatusSlot
	_check(summon != null and summon.entry.count == "×1" and summon.entry.body.contains("只能触发一次"), "the status strip shows the upcoming summon count and limit")
	for _turn in 3:
		var result := session.submit_test_action(shell._test_context(), {"type": "end_turn", "payload": {}})
		_check(result.accepted, "boss turn resolves through test room command")
		if not result.accepted:
			break
	shell.refresh()
	await _frames(tree)
	task = page.view.tasks[0]
	var detail := str(page._task_hover_target(str(task.task_id)).get("detail", ""))
	_check(task.intent_cursor == 0 and detail.contains("本场已用过意图召唤"), "live preview marks the one-time summon used when the intent repeats")
	summon = page._buttons.get(summon_uid) as BattleStatusSlot
	_check(summon != null and summon.entry.title == "召唤已用" and summon.entry.count == "", "a consumed summon cannot read as a future reward")
	_check(page.view.tasks.size() == 2 and page.view.tasks[1].taunting, "for this encounter only the first summon created a taunting task")
	session.close_test_room()


func _check_catalogue(result: GameResult) -> void:
	_check(result.ok, "load production compendium")
	if not result.ok:
		return
	var by_id := {}
	var audited_intents := 0
	var special_monsters := 0
	for entry in result.data.monsters:
		var sections := CompendiumText.monster_sections(entry)
		if entry.id == "N33":
			_check(entry.terms == [3, 4] and entry.sources.all(func(source): return source.terms == [3, 4]), "grouped compendium sources use the monster's eligible years")
			_check(CompendiumText.years(entry.terms) == "大三 / 大四", "compendium shows each eligible year once")
		var all_text: PackedStringArray = []
		for section in sections:
			all_text.append(str(section.text))
		by_id[entry.id] = "\n".join(all_text)
		var has_mechanics := false
		for phase in entry.definition.phases:
			for intent in phase.intents:
				var description := TaskIntentText.describe(intent)
				_check(description not in ["待揭示。", "本次意图无行动效果。"], "%s intent %d has concrete effects" % [entry.id, intent.index])
				has_mechanics = _check_mechanic_coverage(entry, phase, intent) or has_mechanics
				audited_intents += 1
		special_monsters += int(has_mechanics)
	_check(by_id.size() == 60, "audit all 60 production monsters")
	print("ENEMY_MECHANIC_ROSTER=", JSON.stringify({"monsters": by_id.size(), "special_monsters": special_monsters, "intents": audited_intents}))
	var required := {
		"N14": ["对其他每个在场任务施加 4 点完成量", "屏障再减少 4 点"],
		"N16": ["下一轮准备时会重新计算专注", "最后一个之后回到第一个"],
		"N17": ["完成最终阶段时，玩家立即获得 2 点专注"],
		"N18": ["一整张工作牌", "同一张牌的多段完成量"],
		"N20": ["新轮次是 2 的倍数", "50%", "完成最终阶段"],
		"N21": ["每轮准备时精力上限累计降低 1 点"],
		"N22": ["单体卡牌只能选中有嘲讽的任务"],
		"N23": ["召唤 2 个「自我介绍」", "从下一轮行动"],
		"N25": ["完成最终阶段时，玩家立即获得 5 点专注"],
		"N26": ["每轮基础抽牌少 1 张", UiStyle.label("X03")],
		"N28": ["每轮打出的第一张牌增加 1 点专注费用"],
		"N29": ["每轮基础抽牌少 1 张", "完成最终阶段时，玩家立即获得 3 点专注"],
		"N31": ["玩家获得 1 层工作增益", "精力上限恢复"],
		"N33": ["保留剩余屏障", "屏障重新按新意图赋值"],
		"N34": ["从其余手牌随机弃掉至多 1 张"],
		"N35": ["完成最终阶段时，玩家和所有在场伙伴各承受 6 点压力"],
		"N37": ["玩家和所有在场伙伴各承受", "结算压力后自身退场"],
		"Q0B_2": ["仍会结算本轮正常倒计时", "压力阶段后转化"],
		"Q0E_2": ["自身获得 1 层绞尽脑汁", "附属任务"],
		"Q0E_3": ["自身获得 2 层迷惑", "附属任务"],
		"FY_B1_TASK": ["60%", "带嘲讽", "只能触发一次意图召唤", "精力上限降低 1 点"],
		"N03": ["弃牌堆加入 1 张", UiStyle.label("R3-C-05")],
		"E02": ["弃牌堆加入 1 张", UiStyle.label("R3-C-06")],
		"E06": ["手牌加入 1 张", UiStyle.label("R3-C-08")],
	}
	for id in required:
		for phrase in required[id]:
			_check(str(by_id.get(id, "")).contains(phrase), "%s describes %s" % [id, phrase])
	_check(not str(by_id.get("N03", "")).contains("分心消息") and not str(by_id.get("E02", "")).contains("分心消息") and not str(by_id.get("E06", "")).contains("面试题"), "legacy intent labels match the actual cards")


func _check_mechanic_coverage(entry: Dictionary, phase: Dictionary, intent: Dictionary) -> bool:
	var definition: Dictionary = entry.definition
	var badges := TaskIntentText.mechanics({
		"traits": definition, "taunting": definition.get("taunt", false),
		"intent_phase": phase, "intent_snapshot": intent,
	}, entry.get("status_rules", {}))
	var expected := {}
	for property in definition:
		match property:
			"id", "name_key", "kind", "phases", "spawn_group", "self_copy_interval", "self_copy_work_percent": pass
			"victory_required":
				if not definition.victory_required: expected.optional_task = true
			"self_copy_every_round": expected.self_copy = true
			"on_complete_effects":
				var effects: Array = definition.on_complete_effects
				var key := "completion_pressure_0" if effects.size() == 1 and effects[0].op == "pressure" else "completion"
				expected[key] = true
			_: expected[property] = true
	if phase.get("intent_loop") == "clamp":
		expected.intent_clamp = true
	for property in intent:
		match property:
			"index", "text_key", "pressure", "shield", "pressure_per_unit_cap", "pressure_vitality_step": pass
			"pressure_all", "pressure_times", "pressure_per_unit", "pressure_per_vitality", "pressure_has_unit_mult", "pressure_no_unit_mult", "pressure_when_shield", "pressure_per_card_type":
				expected.special_pressure = true
			"gain_status":
				var status: Dictionary = intent.gain_status
				var prefix := "gain_" if status.target == "task" else ("grant_" if status.status == "work_boost" else "inflict_")
				expected[prefix + str(status.status)] = true
			_: expected[property] = true
	var case_id := "%s/%s/%s" % [entry.id, phase.phase_key, intent.index]
	var actual := {}
	for badge in badges:
		_check(not actual.has(badge.key) and not str(badge.body).is_empty(), case_id + " has distinct readable mechanisms")
		actual[badge.key] = true
	_check(actual == expected, "%s badges expected %s, got %s" % [case_id, expected.keys(), actual.keys()])
	return not badges.is_empty()


func _check_compendium_page(shell: GameShell, tree: SceneTree) -> void:
	shell.show_screen("menu")
	_check(shell.press("menu:compendium"), "open compendium from the main menu")
	var page := shell.page as UiCompendiumPage
	if page == null:
		_check(false, "compendium page is installed")
		return
	page.show_tab("monsters")
	page.search("N16")
	page.open_detail("N16")
	await _frames(tree)
	var modal := page.detail
	_check(is_instance_valid(modal) and modal.selected_id == "N16", "search opens the Pre-study entry")
	if not is_instance_valid(modal):
		return
	var text: PackedStringArray = []
	for label in modal._words.find_children("*", "Label", true, false):
		text.append(label.text)
	var description := "\n".join(text)
	_check(description.contains("惊喜") and description.contains("惊吓") and description.contains("下一轮准备时会重新计算专注"), "the visible compendium detail explains both actions and focus reset")


func _check_skill_forecasts(session: GameSession) -> void:
	var fixture = preload("res://tests/suites/test_boss_mechanics.gd").new()
	if not fixture._catalog.load("campus_four_year").ok:
		_check(false, "load production forecasts")
		return
	for definition_id in ["Q0C", "N30"]:
		var step: GameResult = fixture._begin(definition_id)
		if step.ok and definition_id == "Q0C":
			step = fixture._end_turn(step)
		_check(step.ok, definition_id + " reaches the intended round")
		if not step.ok:
			continue
		var task: Dictionary = step.data.state.tasks[0]
		if definition_id == "N30":
			task.shield = 11
		var forecast: Dictionary = session._battle_view(step.data.state, fixture._catalog, fixture._engine, "P01").tasks[0]
		var resolved: GameResult = fixture._end_turn(step)
		_check(resolved.ok, definition_id + " resolves the forecast")
		if not resolved.ok:
			continue
		var pressures: Array = resolved.data.events.filter(func(event: RuleEvent):
			return event.type == &"pressure_applied" and event.source_id == task.task_id
		)
		var expected := 5 if definition_id == "Q0C" else 7
		_check(forecast.effective_pressure == expected and pressures.size() == 1 and pressures[0].data.amount == expected, definition_id + " previews pressure after enemy skill and shield clearing")


func _frames(tree: SceneTree) -> void:
	for _frame in 6:
		await tree.process_frame


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append("battle intent: " + message)
