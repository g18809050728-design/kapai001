extends RefCounted

var failures: Array[String] = []
var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var capture_enabled := false
var capture_enemy_debuffs := false
var checks := 0
const OUT := "res://artifacts/verification/battle-buff-20261126"
const MECHANICS_OUT := "res://artifacts/verification/enemy-mechanics-20261126"


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	var shell: GameShell = helpers.attach_shell(
		GameSession.new(SaveStore.new("user://buff-%d" % Time.get_ticks_usec()))
	)
	shell.session.update_settings(
		{"autosave": false, "presentation": {"reduced_motion": true, "animation_speed": 0}}
	)
	_check(
		(
			shell
			. session
			. start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
			. accepted
		),
		"start P03"
	)
	shell.show_screen("")
	_check(
		helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])),
		"enter actual battle"
	)
	await _frames()
	var page := shell.page as BattleScreen
	page._finish_event_presentation()
	# Locate the authored erosion starter through ordinary draws, then play it.
	for round_index in 4:
		var poison := ""
		for card in page.view.hand:
			if card.definition_id == "R3-P03-01":
				poison = str(card.card_id)
		if not poison.is_empty():
			_check(shell.press("card:" + poison), "select poison starter")
			_check(
				shell.press("task:" + str(page.view.tasks[0].task_id)),
				"play poison on living target"
			)
			break
		shell.press("battle:end_turn")
		await _frames()
		page._finish_event_presentation()
	page = shell.page as BattleScreen
	_check(
		page._buttons.values().any(
			func(button): return button is BattleStatusSlot and button.entry.key == "erosion"
		),
		"real card command creates monster erosion slot"
	)
	var original: String = helpers.fingerprint(shell.session)
	var base := page.view.duplicate(true)
	page.animation_enabled = false
	await _check_enemy_mechanics(shell.session, page, base)
	if not capture_enemy_debuffs:
		await _check_boss_taunt(shell.session, page, base)
		await _check_status_rows(shell, page, base, original)
	shell.free()
	tree.root.size = old_size
	UiStyle.text_scale = 1
	print(
		"BATTLE_BUFF_CHECKS=",
		JSON.stringify(
			{
				"checks": checks,
				"failures": failures,
				"sizes": [1280, 960],
				"scales": [100, 125, 150]
			}
		)
	)
	return failures


func _check_status_rows(shell: GameShell, page: BattleScreen, base: Dictionary, original: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			tree.root.size = dimensions
			UiStyle.text_scale = scale / 100.0
			await _frames()
			var display := base.duplicate(true)
			display.statuses = []
			for key in ["anxiety", "procrastination", "drowsiness", "inspiration", "work_boost"]:
				display.statuses.append(
					{"target_id": display.player.entity_id, "status_id": key, "stacks": 2}
				)
			display.v3.abilities = [
				{
					"definition_id": "R3-C-06",
					"activate_round": int(display.round_index) + 1,
					"trigger": "first_work",
					"effects": [{"op": "add_work_bonus", "amount": 2}]
				}
			]
			display.v3.pending_work_bonus = 5
			display.tasks = []
			for index in 3:
				var task: Dictionary = base.tasks[0].duplicate(true)
				task.task_id = "status-task-%d" % index
				task.traits = {}
				task.intent_snapshot = {}
				task.intent_phase = {}
				task.intent_adds_burden = false
				task.taunting = false
				display.tasks.append(task)
				for key in [
					"erosion",
					"induced",
					"brittle",
					"feebleness",
					"weakness",
					"vulnerability",
					"attack_immunity"
				]:
					display.statuses.append(
						{"target_id": task.task_id, "status_id": key, "stacks": index + 1}
					)
			page.render(display)
			await _frames()
			for name in [
				"PlayerStatusBar",
				"TaskStatusBar_status-task-0",
				"TaskStatusBar_status-task-1",
				"TaskStatusBar_status-task-2"
			]:
				var bar := page._stage.get_node(name) as ScrollContainer
				_check(
					page.get_global_rect().encloses(bar.get_global_rect()),
					name + " inside viewport"
				)
				_check(bar.position.y + bar.size.y <= 548, name + " ends before resting hand")
				_check(bar.get_h_scroll_bar().max_value > bar.size.x, name + " overflow scrolls")
				for slot: BattleStatusSlot in bar.find_children("*", "Button", true, false):
					_check(
						(
							slot.get_global_rect().size.x >= 43.9
							and slot.get_global_rect().size.y >= 43.9
						),
						"physical target >=44"
					)
			var uid := "buff:status-task-1:feebleness"
			var slot: BattleStatusSlot = page._buttons[uid]
			var away := InputEventMouseMotion.new()
			away.position = Vector2(10, 150)
			away.global_position = away.position
			tree.root.push_input(away, true)
			slot.grab_focus()
			await _frames()
			_check(
				page._hover_target.get("uid", "") == uid,
				"keyboard focus explains individual status"
			)
			_check(
				page._buff_hover_target(uid).body.contains("×2"), "description uses actual ruleset"
			)
			_check(page.press(uid) and page._panel_text.contains("乏力"), "click opens effect detail")
			_check(
				helpers.fingerprint(shell.session) == original,
				"inspection preserves domain/RNG/revision"
			)
			page._close_panel()
			await _frames()
			_check(
				tree.root.gui_get_focus_owner() == page._buttons[uid], "close restores status focus"
			)
			# Actual pointer and wheel input must address the status, not its task/card.
			var visible_uid := "buff:status-task-0:erosion"
			var visible_slot: BattleStatusSlot = page._buttons[visible_uid]
			var point := visible_slot.get_global_rect().get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = point
			tree.root.push_input(motion, true)
			await _frames()
			_check(page._hover_target.get("uid", "") == visible_uid, "pointer identifies status")
			_check(page._hover_panel.visible, "status hover explanation is visible")
			for down in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = point
				click.global_position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = down
				tree.root.push_input(click, true)
			await _frames()
			_check(page._panel_text.contains("侵蚀"), "real click opens status instead of targeting")
			page._close_panel()
			await _frames()
			var visible_bar: ScrollContainer = page._buttons[visible_uid].get_meta("status_scroll")
			var wheel := InputEventMouseButton.new()
			wheel.position = point
			wheel.global_position = point
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			tree.root.push_input(wheel, true)
			await _frames()
			_check(visible_bar.scroll_horizontal > 0, "wheel scroll exposes additional buffs")
			_check(
				helpers.fingerprint(shell.session) == original, "pointer and wheel are read only"
			)
			if capture_enabled:
				await _capture(tree, "battle-%d-%d" % [dimensions.x, scale])
			# Same target changes and phase replacement remove stale badges.
			display.statuses = [
				{"target_id": "status-task-0", "status_id": "erosion", "stacks": 7},
				{"target_id": "status-task-0", "status_id": "weakness", "stacks": 0}
			]
			page.render(display)
			await _frames()
			_check(
				page._buttons["buff:status-task-0:erosion"].entry.count == 7,
				"layer changes refresh"
			)
			_check(
				(
					not page._buttons.has("buff:status-task-0:weakness")
					and not page._buttons.has("buff:status-task-1:erosion")
				),
				"zero and removed target statuses disappear"
			)
			_check(
				not page._stage.has_node("TaskStatusBar_status-task-1"),
				"the empty task creates no status UI"
			)


func _check_boss_taunt(session: GameSession, page: BattleScreen, base: Dictionary) -> void:
	var boss = preload("res://tests/suites/test_boss_mechanics.gd").new()
	_check(boss._catalog.load("campus_four_year").ok, "boss roster loads")
	var ended: GameResult = boss._end_turn(boss._begin("FY_B1"))
	_check(ended.ok, "first boss turn resolves")
	if not ended.ok:
		return
	var state: BattleState = ended.data.state
	var display := base.duplicate(true)
	display.merge(session._battle_view(state, boss._catalog, boss._engine), true)
	page.render(display)
	await _frames()
	var targets: Array[Dictionary] = boss._engine._target_candidates(state, "task")
	_check(targets.size() == 1, "taunt restricts the actual boss encounter target")
	if targets.size() != 1:
		return
	var task_id := str(targets[0].id)
	var uid := "buff:" + task_id + ":taunt"
	var slot := page._buttons.get(uid) as BattleStatusSlot
	_check(is_instance_valid(slot) and slot.text == "嘲讽", "summoned task has a taunt slot")
	_check(is_instance_valid(slot) and slot.entry.glyph == "taunt", "taunt uses its own emblem")
	_check(page._buff_hover_target(uid).get("body", "").contains("单体"), "taunt detail explains target restriction")
	page.consume_events(ended.data.events, "hud-boss-test", 1)
	_check(page._feedback_label.text.contains("召唤") and page._feedback_label.text.contains("嘲讽"), "boss summon remains visible after later draw and turn events")
	for fixture in [
		{"type": "task_transformed", "data": {"from_definition_id": "N14", "to_definition_id": "N22"}},
		{"type": "task_self_destructed", "data": {"definition_id": "N14"}}
	]:
		page.consume_events([fixture, {"type": "card_drawn"}], "hud-boss-test", 2 if fixture.type == "task_transformed" else 3)
		var caption := "转化为" if fixture.type == "task_transformed" else "自爆退场"
		_check(page._feedback_label.text.contains(caption), caption + " survives following draw feedback")
	var innate: GameResult = boss._begin("N22")
	_check(innate.ok, "innate taunt roster loads")
	if innate.ok:
		var innate_view := session._battle_view(innate.data.state, boss._catalog, boss._engine)
		_check(innate_view.tasks[0].get("taunting", false), "definition taunt reaches the battle view")
	page.render(base)


func _check_enemy_mechanics(session: GameSession, page: BattleScreen, base: Dictionary) -> void:
	var fixture = preload("res://tests/suites/test_boss_mechanics.gd").new()
	var loaded: GameResult = fixture._catalog.load("campus_four_year")
	_check(loaded.ok, "enemy debuffs use the four-year roster")
	if not loaded.ok:
		return
	var mixed := base.duplicate(true)
	mixed.tasks = []
	mixed.statuses = []
	var expected := {
		"N16": ["player_reduce_focus", "−1", "重新计算专注"],
		"N20": ["self_copy", "", "原型首阶段基础未完成量的 50%"],
		"N26": ["draw_reduction", "−1", "每轮基础抽牌少 1 张"],
		"N28": ["first_card_cost_bonus", "+1", "第一张牌增加 1 点专注费用"],
		"N29": ["completion", "+3", "完成最终阶段时，玩家立即获得 3 点专注"],
		"N31": ["max_vitality_reduction", "−1", "每轮准备时"],
		"N34": ["discard_on_first_card", "−1", "从其余手牌随机弃掉"],
		"N35": ["completion_pressure_0", 6, "在场伙伴各承受 6 点压力"],
		"N36": ["inflict_procrastination", "+1", "基础抽牌时，每层少抽 1 张"],
		"N37": ["intent_clamp", "", "到最后一个后停留"],
	}
	for definition_id in expected:
		var started: GameResult = fixture._begin(definition_id)
		if started.ok and definition_id in ["N16", "N37"]:
			started = fixture._end_turn(started)
		_check(started.ok, definition_id + " reaches its debuff")
		if not started.ok:
			continue
		var display := session._battle_view(started.data.state, fixture._catalog, fixture._engine, "P01")
		var task: Dictionary = display.tasks[0]
		var data: Array = expected[definition_id]
		var entries := BattleStatusSlot.entries(display, task.task_id, false)
		_check(entries.any(func(entry): return entry.key == data[0] and entry.count == data[1] and entry.body.contains(data[2])), definition_id + " has the source mechanic and actual amount")
		if definition_id == "N26":
			_check(display.hand.size() == 4, "N26 reduces actual starting draws from five to four")
			_check(entries.any(func(entry): return entry.key == "add_burden" and entry.body.contains(UiStyle.label("X03"))), "N26 previews its unplayable card")
		if definition_id == "N20":
			_check(entries.any(func(entry): return entry.key == "completion" and entry.body.contains("再减少 4 点")), "N20 exposes both completion effects")
			var next: GameResult = fixture._end_turn(started)
			_check(next.ok and next.data.state.tasks.size() == 2 and int(next.data.state.tasks[1].work_remaining) == 12, "N20 actually creates a half-work copy on round two")
		if definition_id == "N29":
			_check(entries.any(func(entry): return entry.key == "draw_reduction" and entry.count == "−1"), "N29 shows draw reduction alongside the completion reward")
			_check(started.data.state.zones.hand.size() == 4, "N29 reduces the actual base draw")
			_check_n29_completion(fixture._engine, started, task.task_id)
		if definition_id == "N31":
			var live := base.duplicate(true)
			live.merge(display, true)
			page.render(live)
			await _frames()
			var vitality := page._stage.get_node_or_null("PlayerVitalityValue") as Label
			_check(vitality != null and vitality.text == "199 / 199", "N31's real vitality cap is shown under the player")
			_check(page._toolbar.find_children("*", "Label", true, false).any(func(label): return label.text.contains("199/199")), "the top bar uses the same battle cap")
		if definition_id == "N36":
			_check(BattleStatusSlot.entries(display, display.player.entity_id, true).all(func(entry): return entry.key != "procrastination"), "N36 forecast is not an applied player status")
			var resolved: GameResult = fixture._end_turn(started)
			_check(resolved.ok and resolved.data.state.zones.hand.size() == 4, "N36 applies procrastination to the actual next draw")
		if definition_id in ["N20", "N29", "N36", "N37"]:
			mixed.tasks.append(task)
	if capture_enemy_debuffs:
		page._feedback_text = ""
		page._task_event_notices.clear()
	var tree := Engine.get_main_loop() as SceneTree
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		tree.root.size = dimensions
		for scale in [100, 125, 150]:
			UiStyle.text_scale = scale / 100.0
			page.render(mixed)
			await _frames()
			for task: Dictionary in mixed.tasks:
				var key: String = expected[task.definition_id][0]
				var uid := "buff:" + str(task.task_id) + ":" + key
				var slot := page._buttons.get(uid) as BattleStatusSlot
				var detail := page._buff_hover_target(uid)
				_check(slot != null and detail.get("meta", "").begins_with("特殊机制"), "%s mechanic is inspectable at %s / %d%%" % [task.definition_id, dimensions, scale])
				if slot != null:
					var visible: Rect2 = detail.rect
					_check(visible.size.x >= 43.9 and not visible.intersects(page._button_rect("task:" + str(task.task_id))), "mechanic has a full hit target under its source")
			if capture_enemy_debuffs and ((dimensions.x == 1280 and scale == 100) or (dimensions.x == 960 and scale == 150)):
				await _capture(tree, "battle-%d-%d" % [dimensions.x, scale], MECHANICS_OUT)
			if dimensions.x == 960 and scale == 150 and mixed.tasks.size() == 4:
				await _check_mixed_mechanic_inputs(page, mixed.tasks, tree)
	await _check_enemy_self_buffs(session, page, fixture, base)
	page.render(base)


func _check_n29_completion(engine: BattleEngine, started: GameResult, id: String) -> void:
	var state: BattleState = started.data.state.copy()
	state.tasks[0].work_remaining = 1
	var result := engine.apply(state, ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {
		"card_instance_id": state.zones.hand[0], "target_ids": [id],
	}), started.data.rng_state)
	_check(result.ok, "playing a real card completes N29")
	if not result.ok:
		return
	var reward: Array = result.data.events.filter(func(event: RuleEvent):
		return event.type == &"focus_changed" and event.source_id == id and event.data.get("delta", 0) == 3
	)
	_check(reward.size() == 1 and result.data.state.tasks.is_empty(), "completion grants three focus once and removes N29")


func _check_enemy_self_buffs(session: GameSession, page: BattleScreen, fixture: RefCounted, base: Dictionary) -> void:
	var step: GameResult = fixture._begin("Q0E")
	for _round in 2:
		if step.ok:
			step = fixture._end_turn(step)
	_check(step.ok and step.data.state.tasks.size() == 3, "the project calls both extra requirements")
	if not step.ok or step.data.state.tasks.size() != 3:
		return
	var cases := {"brainstorm": [str(step.data.state.tasks[1].task_id), 1], "confusion": [str(step.data.state.tasks[2].task_id), 2]}
	var display := base.duplicate(true)
	display.character_id = "P01"
	display.merge(session._battle_view(step.data.state, fixture._catalog, fixture._engine, "P01"), true)
	page.render(display)
	await _frames()
	for status: String in cases:
		var uid := "buff:%s:" % cases[status][0]
		var forecast := page._buttons.get(uid + "gain_" + status) as BattleStatusSlot
		_check(forecast != null and forecast.entry.count == "+%d" % cases[status][1] and not page._buttons.has(uid + status), "the correct task forecasts " + status + " before it resolves")
	step = fixture._end_turn(step)
	_check(step.ok, "both self buffs resolve on the real enemy turn")
	if not step.ok:
		return
	display.merge(session._battle_view(step.data.state, fixture._catalog, fixture._engine, "P01"), true)
	page.render(display)
	await _frames()
	for status: String in cases:
		var id: String = cases[status][0]
		var uid := "buff:" + id + ":" + status
		var applied := page._buttons.get(uid) as BattleStatusSlot
		_check(applied != null and applied.entry.count == cases[status][1] and not applied.entry.has("mechanic"), "live " + status + " has the actual stacks on its recipient")
		_check(not page._buttons.has("buff:" + id + ":gain_" + status), "the previous forecast is cleared")
		_check(page._buttons.keys().filter(func(key): return str(key).begins_with("buff:") and str(key).ends_with(":" + status)) == [uid], "no other enemy or player inherits " + status)
	_check(int(display.tasks[2].shield) == 10, "the two confusion stacks augment the next eight-point shield")
	if capture_enemy_debuffs:
		var tree := Engine.get_main_loop() as SceneTree
		await _capture(tree, "extra-requirements-active-960-150", MECHANICS_OUT)


func _check_mixed_mechanic_inputs(page: BattleScreen, tasks: Array, tree: SceneTree) -> void:
	var reward_uid := "buff:" + str(tasks[1].task_id) + ":completion"
	_check(page.press(reward_uid) and page._panel_text.contains("玩家立即获得 3 点专注"), "N29 completion detail opens in the narrow viewport")
	if not page._panel_text.is_empty():
		if capture_enemy_debuffs:
			await _frames()
			await _capture(tree, "n29-completion-960-150", MECHANICS_OUT)
		page._close_panel()
		await _frames()
	var pressure_uid := "buff:" + str(tasks[3].task_id) + ":special_pressure"
	var slot := page._buttons.get(pressure_uid) as BattleStatusSlot
	_check(slot != null, "last mechanic stays in the overflowing strip")
	if slot == null:
		return
	slot.grab_focus()
	await _frames()
	var strip := slot.get_meta("status_scroll") as ScrollContainer
	_check(strip.scroll_horizontal > 0 and strip.get_global_rect().encloses(slot.get_global_rect()), "keyboard focus scrolls the last mechanic fully into view")


func _frames() -> void:
	for i in 8:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _capture(tree: SceneTree, label: String, directory: String = OUT) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	_check(
		tree.root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK,
		"capture " + label
	)


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
