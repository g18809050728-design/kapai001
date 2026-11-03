extends RefCounted

const V3_ROOT := "res://data/v3"


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new(V3_ROOT)
	var loaded := catalog.load("campus_v3")
	_check(loaded.ok, "v3 production catalog loads", failures)
	if not loaded.ok:
		return failures
	var p02_open := catalog.get_definition("card", "R3-P02-01")
	_check(
		(
			p02_open.ok
			and UiStyle.label("R3-P02-01") != "R3-P02-01"
			and UiStyle.describe_effects(p02_open.data.effects).contains("开题")
		),
		"v3 card labels and effect text render",
		failures
	)
	_check(
		(
			UiStyle.label("task.R3-AC-TASK-A.name") == "小组作业A"
			and UiStyle.label("encounter.R3-AC.name") == "验收遭遇"
			and UiStyle.label("main") == "主阶段"
		),
		"v3 task/encounter/phase labels render",
		failures
	)
	_check(
		(
			UiStyle.label("chapter_deployed") == "部署章节"
			and UiStyle.label("paper_published") == "论文发表"
			and UiStyle.label("card_exhausted") == "消耗卡牌"
		),
		"v3 event log labels render",
		failures
	)
	var turn_error := UiStyle.error_text(
		ApiError.new(GameConstants.ERROR_INVALID_TARGET, "error.play.paper_name_used_turn")
	)
	_check(
		turn_error == "本回合此牌名已使用" and not turn_error.contains("error."),
		"v3 preview errors show text, not codes",
		failures
	)
	var task_a := catalog.get_definition("task", "R3-AC-TASK-A")
	_check(
		task_a.ok and int(task_a.data.phases[0].intents[0].pressure) == 5,
		"v3 acceptance task carries a concrete intent",
		failures
	)
	_check(
		UiStyle.label("task.R3-AC-TASK-A.intent.a") == "催交作业A",
		"v3 intent shows concrete action text",
		failures
	)
	for card_id in catalog.get_info().enabled.card:
		if str(card_id).begins_with("R3-"):
			_check(
				UiStyle.label(str(card_id)) != str(card_id),
				"v3 card has a display name: " + str(card_id),
				failures
			)
	_check(
		not UiStyle.describe_effects([{"op": "paper_progress", "amount": 1}]).contains("paper_"),
		"v3 effect text does not expose op codes",
		failures
	)
	var encounter_pool := catalog.get_candidates({"kind": "encounter", "terms": 1})
	_check(
		(
			encounter_pool.size() >= 3
			and encounter_pool.has("N01")
			and encounter_pool.has("N02")
			and encounter_pool.has("R3-AC")
		),
		"v3 term-1 encounter pool has multiple encounters",
		failures
	)
	for exam_encounter in ["R3-AC-INDEP", "R3-AC-FIXED", "R3-AC-BOTH"]:
		_check(
			not encounter_pool.has(exam_encounter),
			"v3 term-1 map excludes test encounter " + exam_encounter,
			failures
		)
	var enabled := catalog.get_info().enabled
	_check(
		(
			enabled.task.size() >= 50
			and enabled.encounter.size() >= 40
			and enabled.event.size() == 4
			and enabled.relic.size() >= 8
		),
		"v3 production content pools are populated",
		failures
	)
	var p01_passive: Dictionary = catalog.get_definition("character", "P01").data.passive
	var p04_passive: Dictionary = catalog.get_definition("character", "P04").data.passive
	_check(
		(
			str(p01_passive.id) == "r3_p01_link_replay"
			and str(p04_passive.id) == "r3_p04_teamwork"
			and str(p04_passive.trigger) == "cooperation_card_resolved"
		),
		"v3 character passives are role-specific",
		failures
	)
	var generator := RewardGenerator.new(catalog)
	var run := RunState.new(
		{
			"run_id": "v3_prod",
			"character_id": "P02",
			"ruleset_id": "campus_v1",
			"manifest_id": "campus_v3",
			"term": 1
		}
	)
	var cards := generator.card_candidates(run, 3, _rng(), {"white": 1, "blue": 1, "purple": 1})
	_check(cards.ok and cards.data.size() == 3, "v3 reward candidate generation succeeds", failures)
	if cards.ok:
		for id in cards.data:
			_check(
				str(id).begins_with("R3-") and id not in ["R3-T201", "R3-T202"],
				"v3 reward candidate is permanent R3 card: " + str(id),
				failures
			)
	var shop := generator.generate_shop({"node_id": "n1"}, run, _rng())
	_check(shop.ok, "v3 shop generation succeeds", failures)
	if shop.ok:
		_check(shop.data.stocks.size() > 0, "v3 shop has card stock", failures)
	var eligible: Array[String] = []
	for quality in ["white", "blue", "purple", "gold"]:
		eligible.append_array(generator._eligible_card_pool(run, quality))
	_check(eligible.size() == 50, "v3 P02 reward pool has 50 cards", failures)
	for id in eligible:
		var definition: Dictionary = catalog.get_definition("card", id).data
		_check(
			str(definition.get("owner", "")) in ["C", "P02"],
			"v3 reward pool excludes other characters: " + str(id),
			failures
		)

	var session := GameSession.new(
		SaveStore.new("user://v3-prod-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()])
	)
	var setup := session.get_setup_options()
	_check(
		setup.ok and setup.data.characters.size() == 4, "v3 setup exposes four characters", failures
	)
	if setup.ok:
		var manifest_ids: Array[String] = []
		for manifest in setup.data.manifests:
			manifest_ids.append(str(manifest.id))
		_check(
			manifest_ids == ["campus_v3", "campus_mvp"],
			"setup exposes both production manifests",
			failures
		)
	var started := session.start_run(StartRunRequest.new("P02", &"normal", "campus_v3", "42"))
	_check(started.accepted, "v3 P02 run starts", failures)
	if started.accepted:
		var view := session.get_view()
		_check(
			str(view.run.character_id) == "P02" and str(view.run.manifest_id) == "campus_v3",
			"v3 run records character and manifest",
			failures
		)
		var reachable: Array = view.run.reachable_node_ids
		_check(not reachable.is_empty(), "v3 run has reachable nodes", failures)
		if not reachable.is_empty():
			var entered := session.submit(
				CommandContext.new(view.run_id, view.revision),
				GameAction.new(&"enter_node", {"node_id": str(reachable[0])})
			)
			_check(
				entered.accepted and entered.view.battle != null, "v3 node enters battle", failures
			)
			if entered.accepted and entered.view.battle != null:
				_check(
					not str(entered.view.battle.get("encounter_id", "")).is_empty(),
					"v3 battle has an encounter",
					failures
				)
	session.free()
	var ui_session := GameSession.new(
		SaveStore.new("user://v3-ui-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()])
	)
	var shell := GameShell.new()
	shell.session = ui_session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	if shell.page == null:
		shell._ready()
	shell.refresh()
	_check(shell.press("menu:new"), "v3 setup opens through the real menu", failures)
	_check(
		(
			shell.page != null
			and shell.page.button_uids().has("setup:character:P02")
			and shell.page.button_uids().has("setup:character:P03")
		),
		"v3 setup shows P02 and P03",
		failures
	)
	_check(shell.press("setup:character:P02"), "v3 setup selects P02", failures)
	var seed_input := _line_edit(shell)
	if seed_input != null:
		seed_input.text = "42"
		seed_input.text_changed.emit("42")
	_check(shell.press("setup:start"), "v3 setup starts P02", failures)
	var ui_view := ui_session.get_view()
	_check(
		(
			ui_view.screen == &"map"
			and str(ui_view.run.get("manifest_id", "")) == "campus_v3"
			and str(ui_view.run.get("character_id", "")) == "P02"
		),
		"v3 UI start reaches map with campus_v3 P02",
		failures
	)
	if ui_view.screen == &"map":
		var reachable: Array = ui_view.run.reachable_node_ids
		if not reachable.is_empty() and shell.press("node:" + str(reachable[0])):
			var battle := shell.page as BattleScreen
			_check(battle != null, "v3 UI enters battle", failures)
			if battle != null:
				var battle_state := ui_session._state.battle
				var has_task_card := false
				for card_id in battle_state.zones.hand:
					var def := catalog.get_definition(
						"card", str(battle_state.card_by_id[card_id].definition_id)
					)
					if def.ok and str(def.data.target) == "task":
						has_task_card = true
						break
				if not has_task_card:
					for card_id in battle_state.zones.draw + battle_state.zones.discard:
						var def := catalog.get_definition(
							"card", str(battle_state.card_by_id[card_id].definition_id)
						)
						if def.ok and str(def.data.target) == "task":
							battle_state.zones.draw.erase(card_id)
							battle_state.zones.discard.erase(card_id)
							battle_state.zones.hand.append(card_id)
							shell.refresh()
							battle = shell.page as BattleScreen
							break
				var first_card := ""
				for uid in battle._buttons:
					var value: Variant = battle._buttons[uid]
					if value is BattleCard:
						_check(
							not value.text.begins_with("R3-"),
							"v3 battle card shows a display name",
							failures
						)
						var face: Dictionary = value.card_data.get(
							"face", value.card_data.get("effective_card", {})
						)
						if not value.disabled and str(face.get("target", "")) == "task":
							first_card = str(uid)
							break
						if first_card.is_empty() and not value.disabled:
							first_card = str(uid)
				_check(not first_card.is_empty(), "v3 battle exposes a selectable card", failures)
				if not first_card.is_empty():
					_check(shell.press(first_card), "v3 card selection button responds", failures)
					_check(
						(
							not battle._selected_card_id.is_empty()
							or shell.session.get_view().pending_choice != null
							or shell.last_error == null
						),
						"v3 card selection registers without a code error",
						failures
					)
					var target_uid := ""
					for uid in battle._buttons:
						if str(uid).begins_with("task:") and not battle._buttons[uid].disabled:
							target_uid = str(uid)
							break
					_check(
						not target_uid.is_empty(),
						"v3 target selection exposes a task button",
						failures
					)
					if not target_uid.is_empty():
						_check(shell.press(target_uid), "v3 task target button responds", failures)
					var live: BattleState = ui_session._state.battle
					for index in 2:
						var unit_id := "test_unit_%d" % index
						var unit_def: Dictionary = (
							catalog.get_definition("unit", str(["R3-U01", "R3-U02"][index])).data
						)
						var unit: Dictionary = unit_def.duplicate(true)
						unit["unit_id"] = unit_id
						unit["definition_id"] = str(["R3-U01", "R3-U02"][index])
						unit["max_vitality"] = int(unit.get("vitality", 1))
						unit["entered_order"] = int(live.next_creation_order)
						unit["actions_taken"] = 0
						unit["target_id"] = ""
						live.units.append(unit)
					var unit_card_id := "test_unit_target_card"
					live.card_by_id[unit_card_id] = {
						"card_id": unit_card_id,
						"definition_id": "R3-P04-12",
						"origin_card_id": "",
						"upgrade_level": 0,
						"temporary_modifiers": {},
					}
					live.zones.hand.append(unit_card_id)
					live.player.focus = 10
					shell.refresh()
					var refreshed := shell.page as BattleScreen
					_check(refreshed != null, "v3 unit target battle renders", failures)
					if refreshed != null:
						var unit_card_uid := "card:" + unit_card_id
						_check(
							refreshed._buttons.has(unit_card_uid) and shell.press(unit_card_uid),
							"v3 unit-target card can be selected",
							failures
						)
						var enabled_units := 0
						var chosen_unit := ""
						for uid in refreshed._buttons:
							if (
								str(uid).begins_with("unit:")
								and not refreshed._buttons[uid].disabled
							):
								enabled_units += 1
								chosen_unit = str(uid)
						_check(enabled_units >= 2, "v3 two units are selectable targets", failures)
						if not chosen_unit.is_empty():
							_check(
								shell.press(chosen_unit),
								"v3 unit target selection responds",
								failures
							)
	shell.free()
	if failures.is_empty():
		print("V3_PRODUCTION_INTEGRATION=passed")
	return failures


func _rng() -> RandomSource:
	return RandomSource.new("v3-production")


func _line_edit(node: Node) -> LineEdit:
	if node is LineEdit:
		return node
	for child in node.get_children():
		var found := _line_edit(child)
		if found != null:
			return found
	return null


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("v3 production: " + label)
